extends Control
## Menu backdrop drawn on a 320x180 pixel grid and scaled up: twinkling stars
## drifting slowly, the Earth rising in a corner, the Moon, and the ISS
## bobbing in the dark.

const NATIVE := Vector2(320, 180)
const BACKGROUND := Color("050914")
const STAR_COUNT: int = 70
## Where the station sits on the grid (top-left of its sprite).
const STATION_AT := Vector2(-10, 110)

var _stars: Array[Dictionary] = []
var _time: float = 0.0
var _planets: ImageTexture
var _station: ImageTexture


func _ready() -> void:
    mouse_filter = Control.MOUSE_FILTER_IGNORE
    texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
    for i in STAR_COUNT:
        _stars.append({
            "pos": Vector2(randf() * NATIVE.x, randf() * NATIVE.y),
            "size": 2.0 if randf() > 0.85 else 1.0,
            "speed": randf_range(0.5, 3.0),
            "color": Color("38bdf8") if randf() > 0.7 else Color("e2e8f0"),
            "blink": i % 5 == 0,
        })
    _planets = ImageTexture.create_from_image(_paint_planets())
    _station = ImageTexture.create_from_image(station_image())


func _process(delta: float) -> void:
    _time += delta
    for star in _stars:
        var pos: Vector2 = star["pos"]
        pos.x -= star["speed"] * delta
        if pos.x < -2.0:
            pos = Vector2(NATIVE.x + 1.0, randf() * NATIVE.y)
        star["pos"] = pos
    queue_redraw()


func _draw() -> void:
    draw_rect(Rect2(Vector2.ZERO, size), BACKGROUND)
    var k := size / NATIVE
    var blink_off := int(_time * 2.0) % 2 == 0
    for star in _stars:
        if star["blink"] and blink_off:
            continue
        draw_rect(Rect2(star["pos"].floor() * k, Vector2.ONE * star["size"] * k), star["color"])
    draw_texture_rect(_planets, Rect2(Vector2.ZERO, size), false)

    var bob := roundf(sin(_time * 1.8) * 2.0)
    var at := STATION_AT + Vector2(0, bob)
    draw_texture_rect(_station, Rect2(at * k, Vector2(_station.get_size()) * k), false)
    # Blinking beacon at the end of the truss.
    if int(_time * 1.5) % 2 == 0:
        draw_rect(Rect2((at + Vector2(93, 19)) * k, Vector2(2, 2) * k), Color("f43f5e"))


## The ISS on a 96x40 grid: truss, solar wings, modules, radiators. Also used
## as the mission icon in the menu.
static func station_image() -> Image:
    var img := Image.create(96, 40, false, Image.FORMAT_RGBA8)
    var frame := Color("334155")
    var panel := Color("1e3a8a")
    var cell := Color("2563eb")
    # Solar wings, above and below the truss.
    for x in [6, 18, 70, 82]:
        for y0 in [2, 23]:
            img.fill_rect(Rect2i(x, y0, 9, 15), frame)
            img.fill_rect(Rect2i(x + 1, y0 + 1, 7, 13), panel)
            for row in range(y0 + 2, y0 + 14, 3):
                img.fill_rect(Rect2i(x + 1, row, 7, 1), cell)
    # Truss.
    img.fill_rect(Rect2i(4, 19, 90, 3), Color("64748b"))
    img.fill_rect(Rect2i(4, 19, 90, 1), Color("94a3b8"))
    # Radiators.
    img.fill_rect(Rect2i(30, 23, 5, 8), Color("e2e8f0"))
    img.fill_rect(Rect2i(61, 10, 5, 8), Color("e2e8f0"))
    # Modules: a long cylinder and a node across it.
    img.fill_rect(Rect2i(36, 16, 25, 8), Color("cbd5e1"))
    img.fill_rect(Rect2i(36, 22, 25, 2), Color("94a3b8"))
    img.fill_rect(Rect2i(45, 11, 7, 18), Color("f1f5f9"))
    img.fill_rect(Rect2i(45, 26, 7, 3), Color("94a3b8"))
    img.fill_rect(Rect2i(47, 14, 3, 3), Color("38bdf8"))
    return img


## Earth rising in the bottom-right corner and the Moon up top, painted once.
func _paint_planets() -> Image:
    var img := Image.create(int(NATIVE.x), int(NATIVE.y), false, Image.FORMAT_RGBA8)
    var noise := FastNoiseLite.new()
    noise.seed = 7
    noise.frequency = 0.045
    var clouds := FastNoiseLite.new()
    clouds.seed = 31
    clouds.frequency = 0.08
    var light := Vector2(-0.7, -0.7).normalized()

    var center := Vector2(262, 236)
    var radius := 104.0
    for y in range(110, int(NATIVE.y)):
        for x in range(140, int(NATIVE.x)):
            var d := Vector2(x + 0.5, y + 0.5) - center
            var dist := d.length()
            if dist > radius + 2.0:
                continue
            if dist > radius:
                img.set_pixel(x, y, Color("38bdf8", 0.55))
                continue
            var color := Color("1d4ed8")
            if noise.get_noise_2d(x, y) > 0.12:
                color = Color("15803d")
            if clouds.get_noise_2d(x, y) > 0.35:
                color = Color("e2e8f0")
            # Day side towards the top-left, night side darker.
            var lit := (d / radius).dot(light)
            if lit < -0.1:
                color = color.darkened(0.55)
            elif lit < 0.25:
                color = color.darkened(0.25)
            if dist > radius - 2.0:
                color = color.lerp(Color("7dd3fc"), 0.5)
            img.set_pixel(x, y, color)

    var moon := Vector2(268, 34)
    for y in range(20, 48):
        for x in range(254, 282):
            var d := Vector2(x + 0.5, y + 0.5) - moon
            if d.length() > 12.0:
                continue
            var color := Color("cbd5e1")
            if noise.get_noise_2d(x * 3, y * 3) > 0.25:
                color = Color("94a3b8")
            if (d / 12.0).dot(light) < -0.2:
                color = color.darkened(0.45)
            img.set_pixel(x, y, color)
    return img
