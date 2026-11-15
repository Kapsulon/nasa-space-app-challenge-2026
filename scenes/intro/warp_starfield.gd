extends Control
## Pixel starfield flying towards the camera, drawn at 320x180 and scaled up
## so every star is a crisp block. `warp` sets the speed: from 3.5 the close
## stars stretch into streaks.

const NATIVE := Vector2(320, 180)
const STAR_COUNT: int = 75
const FAR_Z: float = 160.0
const BACKGROUND := Color("050914")
const WHITE := Color("f8fafc")
const BLUE := Color("63b1ff")
const ORANGE := Color("ff7a1a")

## Stars move this many depth units per frame (at 60 fps).
var warp: float = 1.0
## Drift slowly while the intro is paused.
var paused: bool = false

var _stars: Array[Dictionary] = []


func _ready() -> void:
    mouse_filter = Control.MOUSE_FILTER_IGNORE
    for i in STAR_COUNT:
        var star := {"z": randf() * FAR_Z + 10.0}
        _place(star)
        star["color"] = BLUE if randf() > 0.75 else (ORANGE if randf() > 0.9 else WHITE)
        _stars.append(star)


func _place(star: Dictionary) -> void:
    star["x"] = (randf() - 0.5) * NATIVE.x
    star["y"] = (randf() - 0.5) * NATIVE.y


func _process(delta: float) -> void:
    var step := (0.15 if paused else warp) * delta * 60.0
    for star in _stars:
        star["z"] -= step
        if star["z"] <= 2.0:
            _place(star)
            star["z"] = FAR_Z
    queue_redraw()


func _draw() -> void:
    draw_rect(Rect2(Vector2.ZERO, size), BACKGROUND)
    var k := size / NATIVE
    var speed := 0.15 if paused else warp
    for star in _stars:
        var z: float = star["z"]
        var head := _project(star, z)
        if head.x < 0.0 or head.x >= NATIVE.x or head.y < 0.0 or head.y >= NATIVE.y:
            continue
        var block := Vector2(2, 2) if z < 45.0 else Vector2(1, 1)
        if speed >= 3.5 and z < 90.0:
            # Warp streak: a trail of pixels pointing away from the center,
            # from where the star was a few frames ago to where it is now.
            var tail := _project(star, minf(z + speed * 3.0, FAR_Z))
            var steps := maxi(1, roundi(maxf(absf(head.x - tail.x), absf(head.y - tail.y))))
            for i in steps + 1:
                var p := tail.lerp(head, float(i) / steps).round()
                draw_rect(Rect2(p * k, Vector2.ONE * k), star["color"])
        else:
            draw_rect(Rect2(head * k, block * k), star["color"])


## Where a star at depth `z` lands on the 320x180 grid.
func _project(star: Dictionary, z: float) -> Vector2:
    return Vector2(roundf(NATIVE.x * 0.5 + star["x"] / z * 90.0), roundf(NATIVE.y * 0.5 + star["y"] / z * 90.0))
