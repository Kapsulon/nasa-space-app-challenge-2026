class_name ShipView extends Control
## Side cutaway of the ship. Knows where every room is, draws the ship and
## room highlights, finds walking paths for the crew and reports clicks on
## rooms. Crew sprites and alert bubbles are children of this node.
##
## Positions are in "native" coordinates: the 820x340 map of the ship sprite
## sheet (assets/textures/sprites_vaisseau/manifest.json).

signal room_clicked(room: String)

const SHIP_TEXTURE: Texture2D = preload("res://assets/textures/sprites_vaisseau/x1/vaisseau_complet.png")
## Where the full ship sprite sits in the native map.
const SHIP_ORIGIN := Vector2(11, 2)
const NATIVE_SIZE := Vector2(820, 340)
## The central corridor: crew walk along it with their feet at this height.
const CORRIDOR_FLOOR: float = 183.0
const CORRIDOR_MIN_X: float = 92.0
const CORRIDOR_MAX_X: float = 744.0

## rect: clickable area. floor: feet height when standing inside.
## door: x where crew float between the room and the corridor.
## spots: x range where crew stand. outside: a spacewalk spot.
const ROOMS: Dictionary[String, Dictionary] = {
    "bunks": {"rect": Rect2(203, 108, 72, 44), "floor": 150.0, "door": 240.0, "spots": Vector2(212, 266)},
    "medbay": {"rect": Rect2(298, 108, 72, 44), "floor": 150.0, "door": 334.0, "spots": Vector2(306, 362)},
    "galley": {"rect": Rect2(205, 185, 104, 60), "floor": 242.0, "door": 257.0, "spots": Vector2(214, 300)},
    "engineering": {"rect": Rect2(408, 106, 86, 47), "floor": 151.0, "door": 451.0, "spots": Vector2(416, 486)},
    "comms": {"rect": Rect2(522, 38, 72, 86), "floor": 122.0, "door": 558.0, "spots": Vector2(530, 586)},
    "life_support": {"rect": Rect2(515, 185, 80, 60), "floor": 242.0, "door": 554.0, "spots": Vector2(524, 586)},
    "lab": {"rect": Rect2(627, 108, 85, 45), "floor": 150.0, "door": 669.0, "spots": Vector2(636, 704)},
    "cupola": {"rect": Rect2(711, 116, 40, 106), "floor": CORRIDOR_FLOOR, "door": 730.0, "spots": Vector2(716, 742)},
    "engine_bay": {"rect": Rect2(80, 112, 58, 112), "floor": CORRIDOR_FLOOR, "door": 110.0, "spots": Vector2(94, 128)},
    "hull": {"rect": Rect2(250, 82, 70, 24), "floor": 102.0, "door": 285.0, "spots": Vector2(270, 300), "outside": true},
    "outside": {"rect": Rect2(758, 100, 56, 70), "floor": 160.0, "door": 744.0, "spots": Vector2(770, 800), "outside": true},
}

const ROOM_NAMES: Dictionary[String, String] = {
    "galley": "Galley",
    "engine_bay": "Engine bay",
    "hull": "Outer hull",
    "outside": "Outside the ship",
}

## Game speed multiplier, set by the mission (0 = paused).
var speed: float = 1.0
## 0 = day, 1 = night.
var night: float = 0.0
## Rooms the player can click (stations).
var clickable_rooms: Array[String] = []
## Rooms drawn with a soft highlight (e.g. valid targets for the selection).
var highlight_rooms: Array[String] = []

var _hover_room: String = ""
var _scale: float = 1.0
var _offset := Vector2.ZERO
var _time: float = 0.0


func _ready() -> void:
    texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
    mouse_filter = Control.MOUSE_FILTER_STOP
    resized.connect(_layout)
    _layout()


func _layout() -> void:
    _scale = minf(size.x / NATIVE_SIZE.x, size.y / NATIVE_SIZE.y)
    _offset = (size - NATIVE_SIZE * _scale) * 0.5
    for child in get_children():
        if child.has_method("refresh_position"):
            child.refresh_position()
    queue_redraw()


func view_scale() -> float:
    return _scale


## Native map point -> local position in this control.
func to_view(native: Vector2) -> Vector2:
    return _offset + native * _scale


func to_native(local: Vector2) -> Vector2:
    return (local - _offset) / _scale


static func room_name(room: String) -> String:
    if MissionState.STATIONS.has(room):
        return MissionState.station_name(room)
    return ROOM_NAMES.get(room, room.capitalize())


func room_at(local: Vector2) -> String:
    var p := to_native(local)
    for room in ROOMS.keys():
        if (ROOMS[room]["rect"] as Rect2).grow(3).has_point(p):
            return room
    return ""


## A random standing spot inside the room (native).
func room_spot(room: String) -> Vector2:
    var info: Dictionary = ROOMS[room]
    var spots: Vector2 = info["spots"]
    return Vector2(randf_range(spots.x, spots.y), info["floor"])


## Where an alert bubble floats for a room (native).
func bubble_point(room: String) -> Vector2:
    var rect: Rect2 = ROOMS[room]["rect"]
    if ROOMS[room].get("outside", false):
        return rect.get_center()
    return Vector2(rect.get_center().x, rect.position.y - 4.0)


## Path from `from` (inside `from_room`, or "" for the corridor) to `to`
## inside `to_room`, through the doors and the corridor.
func path(from: Vector2, from_room: String, to: Vector2, to_room: String) -> PackedVector2Array:
    var points := PackedVector2Array()
    if from_room == to_room and from_room != "":
        points.append(Vector2(to.x, from.y))
        points.append(to)
        return points
    if from_room != "" and absf(from.y - CORRIDOR_FLOOR) > 0.5:
        var door: float = ROOMS[from_room]["door"]
        points.append(Vector2(door, from.y))
        points.append(Vector2(door, CORRIDOR_FLOOR))
    if to_room != "" and absf(to.y - CORRIDOR_FLOOR) > 0.5:
        var door: float = ROOMS[to_room]["door"]
        points.append(Vector2(clampf(door, CORRIDOR_MIN_X, CORRIDOR_MAX_X), CORRIDOR_FLOOR))
        points.append(Vector2(door, to.y) if not ROOMS[to_room].get("outside", false) else Vector2(door, CORRIDOR_FLOOR))
    else:
        points.append(Vector2(clampf(to.x, CORRIDOR_MIN_X, CORRIDOR_MAX_X), CORRIDOR_FLOOR))
    points.append(to)
    return points


func _process(delta: float) -> void:
    _time += delta
    var hover := room_at(get_local_mouse_position()) if get_global_rect().has_point(get_global_mouse_position()) else ""
    if hover != _hover_room:
        _hover_room = hover
        tooltip_text = ""
    queue_redraw()


func _gui_input(event: InputEvent) -> void:
    if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
        var room := room_at(event.position)
        if room != "":
            room_clicked.emit(room)
            accept_event()


func _draw() -> void:
    var ship_rect := Rect2(to_view(SHIP_ORIGIN), SHIP_TEXTURE.get_size() * _scale)
    draw_texture_rect(SHIP_TEXTURE, ship_rect, false)

    # Soft highlight on rooms the selected crew member can go to.
    var pulse := 0.5 + 0.5 * sin(_time * 4.0)
    for room in highlight_rooms:
        var r := _room_view_rect(room)
        draw_rect(r, Color(0.39, 0.69, 1.0, 0.06 + 0.06 * pulse))
        draw_rect(r, Color(0.39, 0.69, 1.0, 0.35 + 0.3 * pulse), false, 2.0)

    if _hover_room != "" and (_hover_room in clickable_rooms):
        var r := _room_view_rect(_hover_room)
        draw_rect(r, Color(1, 1, 1, 0.08))
        draw_rect(r, Color(1, 1, 1, 0.8), false, 2.0)
        _draw_tag(room_name(_hover_room), Vector2(r.get_center().x, r.position.y - 6.0))

    if night > 0.0:
        draw_rect(Rect2(Vector2.ZERO, size), Color(0.02, 0.03, 0.1, 0.55 * night))


func _room_view_rect(room: String) -> Rect2:
    var rect: Rect2 = ROOMS[room]["rect"]
    return Rect2(to_view(rect.position), rect.size * _scale)


func _draw_tag(text: String, bottom_center: Vector2) -> void:
    var font := get_theme_default_font()
    var font_size := 20
    var text_size := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size)
    var box := Rect2(bottom_center - Vector2(text_size.x * 0.5 + 8, text_size.y + 6), text_size + Vector2(16, 6))
    draw_rect(box, Color(0.04, 0.06, 0.1, 0.85))
    draw_rect(box, Color(1, 1, 1, 0.5), false, 1.0)
    draw_string(font, Vector2(box.position.x + 8, box.end.y - 6), text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, Color.WHITE)
