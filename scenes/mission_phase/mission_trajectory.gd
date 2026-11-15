@tool
class_name MissionTrajectory extends Control
## Mission progress drawn as a journey: Earth on the left, the destination
## station on the right, one tick per day, and the ship sprite travelling
## along the path.

@export var ship_texture: Texture2D:
    set(value):
        ship_texture = value
        if _ship:
            _ship.texture = value
@export var ship_height: float = 56.0
@export var days: int = 10:
    set(value):
        days = maxi(1, value)
        queue_redraw()
@export_range(0.0, 1.0) var progress: float = 0.0:
    set(value):
        progress = clampf(value, 0.0, 1.0)
        if is_node_ready() and not Engine.is_editor_hint():
            var tween := create_tween()
            tween.tween_property(self, "_shown_progress", progress, 1.2).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
        else:
            _shown_progress = progress

const PATH_COLOR := Color(0.39, 0.69, 1.0, 0.35)
const DONE_COLOR := Color("ff3a55")
const EARTH_RADIUS := 30.0
const MARGIN := 70.0

var _shown_progress: float = 0.0
var _ship: TextureRect
var _time: float = 0.0


func _ready() -> void:
    mouse_filter = Control.MOUSE_FILTER_IGNORE
    _ship = TextureRect.new()
    _ship.texture = ship_texture
    _ship.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
    _ship.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
    _ship.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
    _ship.mouse_filter = Control.MOUSE_FILTER_IGNORE
    add_child(_ship, false, Node.INTERNAL_MODE_FRONT)
    _shown_progress = progress


func set_day(day_index: int, total_days: int) -> void:
    days = total_days
    progress = float(day_index) / float(maxi(1, total_days))


func _process(delta: float) -> void:
    _time += delta
    _place_ship()
    queue_redraw()


func _path_start() -> Vector2:
    return Vector2(MARGIN + EARTH_RADIUS, size.y * 0.5)


func _path_end() -> Vector2:
    return Vector2(size.x - MARGIN - 20.0, size.y * 0.5)


func _place_ship() -> void:
    if _ship == null or ship_texture == null:
        return
    var aspect := float(ship_texture.get_width()) / float(ship_texture.get_height())
    _ship.size = Vector2(ship_height * aspect, ship_height)
    var pos := _path_start().lerp(_path_end(), _shown_progress)
    pos.y += sin(_time * 1.6) * 3.0
    _ship.position = pos - _ship.size * 0.5


func _draw() -> void:
    var start := _path_start()
    var end := _path_end()
    var current := start.lerp(end, _shown_progress)

    # Path: dashed for what's left, solid for what's done.
    draw_dashed_line(current, end, PATH_COLOR, 2.0, 10.0)
    draw_line(start, current, DONE_COLOR, 3.0, true)
    for i in range(days + 1):
        var p := start.lerp(end, float(i) / days)
        var reached := float(i) / days <= _shown_progress + 0.001
        draw_circle(p, 4.0, DONE_COLOR if reached else PATH_COLOR, true, -1.0, true)

    # Earth: ocean, a couple of continents, atmosphere glow.
    var earth := Vector2(MARGIN * 0.5 + EARTH_RADIUS * 0.5, size.y * 0.5)
    for k in 4:
        draw_circle(earth, EARTH_RADIUS + 10.0 - k * 2.5, Color(0.4, 0.7, 1.0, 0.06), true, -1.0, true)
    draw_circle(earth, EARTH_RADIUS, Color("1f5fbf"), true, -1.0, true)
    draw_circle(earth + Vector2(-9, -8), 10.0, Color("3fa65a"), true, -1.0, true)
    draw_circle(earth + Vector2(10, 9), 8.0, Color("3fa65a"), true, -1.0, true)
    draw_circle(earth + Vector2(4, -16), 5.0, Color("3fa65a"), true, -1.0, true)
    draw_arc(earth, EARTH_RADIUS, 0.0, TAU, 48, Color(0.75, 0.9, 1.0, 0.6), 1.5, true)

    # Destination station: truss, modules and solar wings.
    var iss := Vector2(size.x - MARGIN * 0.5, size.y * 0.5)
    var blink := 0.5 + 0.5 * sin(_time * 3.0)
    draw_rect(Rect2(iss + Vector2(-22, -1.5), Vector2(44, 3)), Color("c9d1db"))
    draw_rect(Rect2(iss + Vector2(-6, -6), Vector2(12, 12)), Color("e8edf2"))
    for side in [-1, 1]:
        for row in [-1, 1]:
            draw_rect(Rect2(iss + Vector2(side * 16 - 5, row * 7 - (8 if row < 0 else 0)), Vector2(10, 8)), Color("2b5fb8"))
    draw_circle(iss + Vector2(0, -10), 2.0, Color(1.0, 0.3, 0.3, blink), true, -1.0, true)
