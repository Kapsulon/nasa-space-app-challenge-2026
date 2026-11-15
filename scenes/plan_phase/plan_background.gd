extends Control
## Plan phase backdrop, drawn on a 320x180 pixel grid and scaled up: the wall
## of a mission control room with a big world-map screen behind the cards.
## The ship's ground track waves across the map with a blinking dot running
## along it, and a console desk with status lights sits at the bottom.

const NATIVE := Vector2(320, 180)
## The big wall screen, on the grid.
const SCREEN := Rect2i(5, 3, 225, 104)
## Ground track: two waves across the screen.
const TRACK_AMPLITUDE: float = 30.0
const TRACK_WAVES: float = 2.0
## Seconds for the dot to cross the screen.
const LAP_SECONDS: float = 26.0
const DESK_Y: int = 150

const C_WALL := Color("0a0f1c")
const C_SEAM := Color("111a2e")
const C_RIVET := Color("1e293b")
const C_FRAME := Color("334155")
const C_SCREEN := Color("04101f")
const C_GRID := Color("0b2440")
const C_LAND := Color("0f3a5a")
const C_TRACK := Color("1d6fa3")
const C_DOT := Color("7dd3fc")

## Ground stations on the map: blinking amber dots.
const STATIONS: Array[Vector2i] = [Vector2i(52, 40), Vector2i(118, 30), Vector2i(176, 62), Vector2i(90, 78)]
## Console lights along the desk: [x, color, blink period].
const LIGHTS: Array[Array] = [
    [24, "39ff6a", 1.3], [30, "39ff6a", 0.0], [36, "ffb800", 0.9], [70, "39ff6a", 0.0], [76, "ff3a55", 1.7],
    [120, "39ff6a", 1.1], [126, "38bdf8", 0.0], [170, "ffb800", 2.1], [176, "39ff6a", 0.0], [214, "38bdf8", 1.5],
    [262, "39ff6a", 0.0], [268, "ffb800", 1.2], [300, "ff3a55", 2.4],
]

var _time: float = 0.0
var _static: ImageTexture


func _ready() -> void:
    mouse_filter = Control.MOUSE_FILTER_IGNORE
    texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
    _static = ImageTexture.create_from_image(_paint())


func _process(delta: float) -> void:
    _time += delta
    queue_redraw()


func _draw() -> void:
    var k := size / NATIVE
    draw_texture_rect(_static, Rect2(Vector2.ZERO, size), false)

    # The ship running along its ground track, with a fading trail.
    var head := fmod(_time / LAP_SECONDS, 1.0) * SCREEN.size.x
    for i in 28:
        var x := head - i
        if x < 0.0:
            x += SCREEN.size.x
        var alpha := 1.0 - i / 28.0
        _px(k, Vector2(SCREEN.position.x + floorf(x), _track_y(x)), Vector2.ONE, Color(C_DOT, alpha * 0.8))
    var dot := Vector2(SCREEN.position.x + floorf(head), _track_y(head))
    _px(k, dot - Vector2(1, 1), Vector2(3, 3), Color(C_DOT, 0.35 + 0.35 * sin(_time * 6.0)))
    _px(k, dot, Vector2.ONE, Color.WHITE)

    for i in STATIONS.size():
        if int(_time * 1.2 + i * 0.7) % 3 != 0:
            _px(k, Vector2(SCREEN.position) + Vector2(STATIONS[i]), Vector2(2, 2), Color("ffb800"))

    # Slow scan line sweeping down the screen.
    var scan := fmod(_time * 14.0, SCREEN.size.y + 20.0) - 10.0
    if scan >= 0.0 and scan < SCREEN.size.y:
        _px(k, Vector2(SCREEN.position.x, SCREEN.position.y + floorf(scan)), Vector2(SCREEN.size.x, 1), Color(C_DOT, 0.08))

    for light in LIGHTS:
        var period: float = light[2]
        if period > 0.0 and fmod(_time, period) > period * 0.6:
            continue
        _px(k, Vector2(light[0], DESK_Y + 4), Vector2(3, 2), Color(light[1]))


func _px(k: Vector2, pos: Vector2, rect_size: Vector2, color: Color) -> void:
    draw_rect(Rect2(pos * k, rect_size * k), color)


func _track_y(x: float) -> float:
    var t := x / SCREEN.size.x * TRACK_WAVES * TAU
    return roundf(SCREEN.position.y + SCREEN.size.y * 0.5 - sin(t) * TRACK_AMPLITUDE)


## Wall, screen (frame, grid, continents, track) and desk, painted once.
func _paint() -> Image:
    var img := Image.create(int(NATIVE.x), int(NATIVE.y), false, Image.FORMAT_RGBA8)
    img.fill(C_WALL)
    # Wall panels: seams and rivets.
    for x in range(0, int(NATIVE.x), 40):
        img.fill_rect(Rect2i(x, 0, 1, DESK_Y), C_SEAM)
        for y in [6, 60, 120, 144]:
            img.fill_rect(Rect2i(x + 3, y, 1, 1), C_RIVET)
            img.fill_rect(Rect2i(x + 36, y, 1, 1), C_RIVET)
    img.fill_rect(Rect2i(0, 128, int(NATIVE.x), 1), C_SEAM)

    # Screen frame and face.
    img.fill_rect(SCREEN.grow(3), Color("1e293b"))
    img.fill_rect(SCREEN.grow(2), C_FRAME)
    img.fill_rect(SCREEN.grow(1), Color("020617"))
    img.fill_rect(SCREEN, C_SCREEN)
    var noise := FastNoiseLite.new()
    noise.seed = 3
    noise.frequency = 0.035
    noise.fractal_octaves = 3
    for y in SCREEN.size.y:
        for x in SCREEN.size.x:
            var color := C_SCREEN
            # Continents, thinning out towards the poles.
            var lat := absf(y / float(SCREEN.size.y) - 0.5) * 2.0
            if noise.get_noise_2d(x, y * 1.4) > 0.08 + lat * lat * 0.4:
                color = C_LAND
            if x % 15 == 0 or y % 13 == 0:
                color = C_GRID if color == C_SCREEN else color.lightened(0.08)
            img.set_pixel(SCREEN.position.x + x, SCREEN.position.y + y, color)
    # Ground track, dotted.
    for x in SCREEN.size.x:
        if x % 3 != 2:
            img.set_pixel(SCREEN.position.x + x, int(_track_y(x)), C_TRACK)
    # Mounting brackets under the screen.
    for x in [40, 190]:
        img.fill_rect(Rect2i(SCREEN.position.x + x, SCREEN.end.y + 3, 6, 8), C_FRAME)

    # Console desk along the bottom.
    img.fill_rect(Rect2i(0, DESK_Y, int(NATIVE.x), int(NATIVE.y) - DESK_Y), Color("0b1220"))
    img.fill_rect(Rect2i(0, DESK_Y, int(NATIVE.x), 2), Color("1e293b"))
    img.fill_rect(Rect2i(0, DESK_Y + 2, int(NATIVE.x), 1), Color("020617"))
    for x in range(10, int(NATIVE.x), 52):
        img.fill_rect(Rect2i(x, DESK_Y + 10, 34, 16), Color("020617"))
        img.fill_rect(Rect2i(x + 1, DESK_Y + 11, 32, 14), Color("06243a"))
    return img
