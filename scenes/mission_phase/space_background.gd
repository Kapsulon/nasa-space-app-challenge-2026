@tool
class_name SpaceBackground extends Control
## Procedural space backdrop: a slowly drifting, twinkling multi-depth
## starfield over soft nebula clouds. No textures needed.

@export var star_count: int = 280
## Horizontal drift in pixels per second for the nearest stars.
@export var drift_speed: float = 8.0
@export var background_color: Color = Color("04060d")
@export var nebula_colors: Array[Color] = [Color("5b3bd6"), Color("1d7fd1"), Color("16a3a0"), Color("b0337a")]
@export var random_seed: int = 2026

const STAR_COLORS: Array[Color] = [Color("ffffff"), Color("cfe3ff"), Color("ffeccc"), Color("bcd2ff")]

var _stars: Array[Dictionary] = []
var _nebulae: Array[Dictionary] = []
var _time: float = 0.0


func _ready() -> void:
    mouse_filter = Control.MOUSE_FILTER_IGNORE
    resized.connect(_generate)
    _generate()


func _generate() -> void:
    var rng := RandomNumberGenerator.new()
    rng.seed = random_seed
    _stars.clear()
    for i in star_count:
        var depth := rng.randf() # 0 = far away, 1 = close
        _stars.append({
            "pos": Vector2(rng.randf() * size.x, rng.randf() * size.y),
            "depth": depth,
            "radius": lerpf(0.6, 2.4, depth * depth),
            "phase": rng.randf() * TAU,
            "twinkle": rng.randf_range(0.6, 2.8),
            "color": STAR_COLORS[rng.randi() % STAR_COLORS.size()],
        })
    _nebulae.clear()
    for i in 5:
        _nebulae.append({
            "pos": Vector2(rng.randf() * size.x, rng.randf() * size.y),
            "radius": rng.randf_range(220.0, 520.0),
            "color": nebula_colors[i % nebula_colors.size()] if not nebula_colors.is_empty() else Color.PURPLE,
        })
    queue_redraw()


func _process(delta: float) -> void:
    _time += delta
    queue_redraw()


func _draw() -> void:
    draw_rect(Rect2(Vector2.ZERO, size), background_color)

    # Nebulae: stacked translucent discs give a cheap soft glow.
    for nebula in _nebulae:
        var col: Color = nebula["color"]
        var steps := 7
        for k in steps:
            var r: float = nebula["radius"] * (1.0 - float(k) / steps)
            draw_circle(nebula["pos"], r, Color(col, 0.018))

    for star in _stars:
        var depth: float = star["depth"]
        var pos: Vector2 = star["pos"]
        pos.x = fposmod(pos.x - _time * drift_speed * (0.1 + depth), size.x)
        var twinkle := 0.6 + 0.4 * sin(_time * star["twinkle"] + star["phase"])
        var col := Color(star["color"], twinkle * lerpf(0.35, 1.0, depth))
        draw_circle(pos, star["radius"], col, true, -1.0, true)
        # The closest stars get a little cross-shaped glint.
        if depth > 0.94:
            var glint: float = star["radius"] * 3.5 * twinkle
            var glint_col := Color(col, col.a * 0.5)
            draw_line(pos - Vector2(glint, 0), pos + Vector2(glint, 0), glint_col, 1.0, true)
            draw_line(pos - Vector2(0, glint), pos + Vector2(0, glint), glint_col, 1.0, true)
