@tool
extends Control
## Pixel-art progress bar: a steel frame around chunky segments, or one fill
## with diagonal stripes that can scroll. Each block has a light top edge and
## a dark bottom edge. An optional white marker shows a target or a preview.

@export_range(0.0, 1.0) var value: float = 0.5:
    set(v):
        value = clampf(v, 0.0, 1.0)
        queue_redraw()
@export var fill_color: Color = Color("38bdf8"):
    set(c):
        fill_color = c
        queue_redraw()
## Number of blocks; 0 draws one continuous fill.
@export var segments: int = 0:
    set(n):
        segments = n
        queue_redraw()
## Diagonal stripes on the continuous fill.
@export var striped: bool = false:
    set(on):
        striped = on
        queue_redraw()
## Stripes scroll sideways.
@export var animate_stripes: bool = false
## Marker position (0..1); negative hides it.
@export var marker: float = -1.0:
    set(v):
        marker = v
        queue_redraw()
@export var frame_color: Color = Color("334155")
@export var back_color: Color = Color("070b14")
@export var frame_width: int = 2
@export var padding: int = 3

const STRIPE_PERIOD: float = 18.0
const SEGMENT_GAP: float = 3.0
const STRIPE_STEP: float = 3.0

var _scroll: float = 0.0


func _process(delta: float) -> void:
    if animate_stripes and striped and value > 0.0:
        _scroll = fmod(_scroll + delta * 26.0, STRIPE_PERIOD)
        queue_redraw()


func _draw() -> void:
    draw_rect(Rect2(Vector2.ZERO, size), frame_color)
    var inner := Rect2(Vector2.ZERO, size).grow(-frame_width)
    draw_rect(inner, back_color)
    var area := inner.grow(-padding)
    if area.size.x <= 0.0 or area.size.y <= 0.0:
        return
    if segments > 0:
        var width := (area.size.x - SEGMENT_GAP * (segments - 1)) / segments
        var filled := value * segments
        for i in segments:
            var x0 := roundf(area.position.x + i * (width + SEGMENT_GAP))
            var x1 := roundf(area.position.x + i * (width + SEGMENT_GAP) + width)
            var seg := Rect2(x0, area.position.y, x1 - x0, area.size.y)
            draw_rect(seg, Color(fill_color, 0.1))
            var amount := clampf(filled - i, 0.0, 1.0)
            if amount > 0.0:
                _block(Rect2(seg.position, Vector2(roundf(seg.size.x * amount), seg.size.y)))
    else:
        var fill := Rect2(area.position, Vector2(roundf(area.size.x * value), area.size.y))
        if fill.size.x > 0.0:
            _block(fill)
    if marker >= 0.0:
        var x := roundf(area.position.x + area.size.x * clampf(marker, 0.0, 1.0))
        draw_rect(Rect2(x - 2, 0, 4, size.y), Color("020617"))
        draw_rect(Rect2(x - 1, 0, 2, size.y), Color.WHITE)


func _block(rect: Rect2) -> void:
    draw_rect(rect, fill_color)
    if striped:
        _stripes(rect)
    var edge := maxf(2.0, roundf(rect.size.y * 0.18))
    draw_rect(Rect2(rect.position, Vector2(rect.size.x, edge)), fill_color.lightened(0.35))
    draw_rect(Rect2(rect.position.x, rect.end.y - edge, rect.size.x, edge), fill_color.darkened(0.35))


## Diagonal stripes drawn as a staircase of STRIPE_STEP-pixel rows, so the
## slant looks like pixel art.
func _stripes(rect: Rect2) -> void:
    var dark := fill_color.darkened(0.28)
    var half := STRIPE_PERIOD * 0.5
    var y := rect.position.y
    while y < rect.end.y:
        var row_h := minf(STRIPE_STEP, rect.end.y - y)
        # Each row is shifted right as it goes up: a "/" slant.
        var shift := fmod(_scroll + (rect.end.y - y), STRIPE_PERIOD)
        var x := rect.position.x - STRIPE_PERIOD + shift
        while x < rect.end.x:
            var x0 := maxf(x, rect.position.x)
            var x1 := minf(x + half, rect.end.x)
            if x1 > x0:
                draw_rect(Rect2(x0, y, x1 - x0, row_h), dark)
            x += STRIPE_PERIOD
        y += STRIPE_STEP
