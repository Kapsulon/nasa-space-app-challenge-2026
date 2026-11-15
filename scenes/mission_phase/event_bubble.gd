class_name EventBubble extends Control
## Alert bubble floating over the ship where an event happens. Pulses while
## it waits for someone (the ring shows the time left), turns blue with a
## progress ring once a crew member is working on it.

signal clicked

const RADIUS: float = 22.0
const ALERT_COLOR := Color("ff5a3c")
const WORK_COLOR := Color("63b1ff")

var event: MissionEvent
var view: ShipView
var room: String = ""
## Hours left before the crew falls back on the passive option.
var hours_left: float = MissionState.EVENT_DEADLINE_HOURS
## Set once somebody is on it.
var worker: CrewMember = null
var choice: EventChoice = null
var work_total: float = 0.0
var work_done: float = 0.0
## The worker reached the spot and the work clock is running.
var working: bool = false

var _time: float = 0.0


func setup(_event: MissionEvent, _view: ShipView) -> void:
    view = _view
    mouse_filter = Control.MOUSE_FILTER_STOP
    mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
    set_event(_event)


## Shows another alert in this bubble (the clock starts over).
func set_event(_event: MissionEvent) -> void:
    event = _event
    room = event.location if ShipView.ROOMS.has(event.location) else "galley"
    hours_left = MissionState.EVENT_DEADLINE_HOURS
    refresh_position()


func is_assigned() -> bool:
    return worker != null


func refresh_position() -> void:
    if view == null:
        return
    var center := view.to_view(view.bubble_point(room))
    size = Vector2(RADIUS * 2.0, RADIUS * 2.0)
    position = center - size * 0.5


func _process(delta: float) -> void:
    _time += delta
    refresh_position()
    queue_redraw()


func _gui_input(input: InputEvent) -> void:
    if input is InputEventMouseButton and input.pressed and input.button_index == MOUSE_BUTTON_LEFT:
        clicked.emit()
        accept_event()


func _draw() -> void:
    var center := size * 0.5
    var assigned := is_assigned()
    var color := WORK_COLOR if assigned else ALERT_COLOR
    var pulse := 1.0 if assigned else 1.0 + 0.12 * sin(_time * 7.0)
    var r := RADIUS * pulse
    # Glow and bubble with a little tail pointing at the spot.
    draw_circle(center, r * 1.5, Color(color, 0.15 + (0.0 if assigned else 0.1 * sin(_time * 7.0))))
    draw_colored_polygon(PackedVector2Array([center + Vector2(-7, r - 4), center + Vector2(7, r - 4), center + Vector2(0, r + 10)]), color)
    draw_circle(center, r, color)
    draw_circle(center, r * 0.78, Color(0.05, 0.07, 0.12))

    # Ring: time left (alert) or work progress (assigned).
    var ratio := clampf(work_done / maxf(work_total, 0.001), 0.0, 1.0) if assigned \
        else clampf(hours_left / MissionState.EVENT_DEADLINE_HOURS, 0.0, 1.0)
    if ratio > 0.0:
        draw_arc(center, r * 0.9, -PI / 2.0, -PI / 2.0 + TAU * ratio, 32, color, 3.0, true)

    var font := get_theme_default_font()
    var glyph := "..." if assigned else "!"
    var font_size := 40 if not assigned else 30
    var w := font.get_string_size(glyph, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size)
    draw_string(font, center + Vector2(-w.x * 0.5, w.y * 0.3), glyph, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, color.lerp(Color.WHITE, 0.3))

    # Title under the bubble.
    var title_size := 26
    var tw := font.get_string_size(event.title, HORIZONTAL_ALIGNMENT_LEFT, -1, title_size).x
    var title_pos := Vector2(center.x - tw * 0.5, center.y + r + 34)
    draw_rect(Rect2(title_pos - Vector2(8, 25), Vector2(tw + 16, 34)), Color(0, 0, 0, 0.8))
    draw_string(font, title_pos, event.title, HORIZONTAL_ALIGNMENT_LEFT, -1, title_size, Color.WHITE)
