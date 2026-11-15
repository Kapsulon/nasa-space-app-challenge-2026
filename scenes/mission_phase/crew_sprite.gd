class_name CrewSprite extends Control
## One astronaut walking around the ship view. Uses the 4x4 sheet in
## assets/textures/character.png (columns: front, back, left, right; rows:
## walk frames). Moves in native ship coordinates along a path given by
## ShipView, scaled by the view's game speed.

signal clicked
signal arrived

const SHEET: Texture2D = preload("res://assets/textures/character.png")
const CELL := Vector2(120, 147)
## Height of an astronaut in native ship pixels.
const NATIVE_HEIGHT: float = 25.0
## Walking speed in native pixels per real second at game speed 1.
const WALK_SPEED: float = 60.0

enum Facing { FRONT, BACK, LEFT, RIGHT }

var member: CrewMember
var view: ShipView
var tint: Color = Color.WHITE
## Room the astronaut is in (or heading to once arrived).
var room: String = ""
var native_pos := Vector2.ZERO
var selected: bool = false
## Small text above the head ("zzz", "!", "+").
var badge: String = ""
var badge_color: Color = Color.WHITE

var _path := PackedVector2Array()
var _facing: Facing = Facing.FRONT
var _anim: float = 0.0
var _idle_timer: float = 0.0
## The current path is just idle drifting (no "arrived" signal).
var _wandering: bool = false
var _time: float = randf() * 10.0


func setup(_member: CrewMember, _view: ShipView, _tint: Color, start_room: String) -> void:
    member = _member
    view = _view
    tint = _tint
    room = start_room
    native_pos = view.room_spot(start_room)
    mouse_filter = Control.MOUSE_FILTER_STOP
    mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
    refresh_position()


func is_walking() -> bool:
    return not _path.is_empty()


## Walks to a spot in `target_room`.
func walk_to(target_room: String, target: Vector2 = Vector2.INF) -> void:
    if target == Vector2.INF:
        target = view.room_spot(target_room)
    _path = view.path(native_pos, room, target, target_room)
    room = target_room
    _wandering = false


func refresh_position() -> void:
    if view == null:
        return
    var s := view.view_scale()
    var height := NATIVE_HEIGHT * s
    size = Vector2(height * CELL.x / CELL.y, height)
    position = view.to_view(native_pos) - Vector2(size.x * 0.5, size.y)


func _process(delta: float) -> void:
    if view == null:
        return
    _time += delta
    var game_delta := delta * view.speed
    if not _path.is_empty():
        var step := WALK_SPEED * game_delta
        while step > 0.0 and not _path.is_empty():
            var target := _path[0]
            var to_target := target - native_pos
            var dist := to_target.length()
            if dist < 0.01:
                _path.remove_at(0)
                continue
            if absf(to_target.x) > absf(to_target.y):
                _facing = Facing.RIGHT if to_target.x > 0 else Facing.LEFT
            else:
                _facing = Facing.BACK if to_target.y < 0 else Facing.FRONT
            var move := minf(step, dist)
            native_pos += to_target / dist * move
            step -= move
            if move >= dist:
                _path.remove_at(0)
        _anim += game_delta * 8.0
        if _path.is_empty():
            _facing = Facing.FRONT
            if not _wandering:
                arrived.emit()
            _wandering = false
    elif view.speed > 0.0 and member != null and member.is_aboard() and not view.ROOMS.get(room, {}).get("outside", false):
        # Drift around the room a little now and then.
        _idle_timer -= game_delta
        if _idle_timer <= 0.0:
            _idle_timer = randf_range(4.0, 9.0)
            if randf() < 0.6 and view.ROOMS.has(room):
                var spot := view.room_spot(room)
                _path = PackedVector2Array([Vector2(spot.x, native_pos.y)])
                _wandering = true
    refresh_position()
    queue_redraw()


## Generous click area around the small sprite.
func _has_point(point: Vector2) -> bool:
    return Rect2(Vector2.ZERO, size).grow(12.0).has_point(point)


func _gui_input(event: InputEvent) -> void:
    if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
        clicked.emit()
        accept_event()


func _draw() -> void:
    # Zero-g bob.
    var bob := sin(_time * 2.2) * size.y * 0.03
    if selected:
        var ring_center := Vector2(size.x * 0.5, size.y)
        var pulse := 0.6 + 0.4 * sin(_time * 6.0)
        _draw_ellipse(ring_center, size.x * 0.65, size.x * 0.2, Color(0.39, 0.69, 1.0, pulse))
    var column: int = [0, 1, 2, 3][_facing]
    var row := int(_anim) % 4 if is_walking() else 0
    var src := Rect2(Vector2(column, row) * CELL, CELL)
    draw_texture_rect_region(SHEET, Rect2(Vector2(0, bob), size), src, tint)

    var font := get_theme_default_font()
    var name_size := 15
    var label := member.display_name.get_slice(" ", 1) if member.display_name.contains(" ") else member.display_name
    var w := font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, name_size).x
    var tag_pos := Vector2(size.x * 0.5 - w * 0.5, bob - 6.0)
    draw_rect(Rect2(tag_pos - Vector2(4, 14), Vector2(w + 8, 18)), Color(0, 0, 0, 0.6))
    draw_string(font, tag_pos, label, HORIZONTAL_ALIGNMENT_LEFT, -1, name_size, tint.lerp(Color.WHITE, 0.4))
    if badge != "":
        draw_string(font, Vector2(size.x * 0.5 + w * 0.5 + 6, bob - 6.0 + sin(_time * 3.0) * 2.0), badge, HORIZONTAL_ALIGNMENT_LEFT, -1, 16, badge_color)


func _draw_ellipse(center: Vector2, rx: float, ry: float, color: Color) -> void:
    var points := PackedVector2Array()
    for k in 25:
        var a := TAU * k / 24.0
        points.append(center + Vector2(cos(a) * rx, sin(a) * ry))
    draw_polyline(points, color, 2.0, true)
