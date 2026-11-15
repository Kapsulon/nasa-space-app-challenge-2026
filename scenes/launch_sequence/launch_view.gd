class_name LaunchView extends Control
## Procedural launch scene, no textures needed: sky, clouds, launch pad, rocket, flame, smoke, and
## the capsule's parachute ride home on an abort. It only draws; the launch
## sequence script animates it by tweening the properties below.
##
## World coordinates: y is height above sea level in pixels (up is positive).
## The camera follows `altitude` once the rocket is high enough.

## Height of the booster from engine bell to the top of the body.
const ROCKET_HEIGHT: float = 352.0
const PAD_TOP: float = 24.0
## `altitude` while the rocket sits on the pad.
const START_ALTITUDE: float = PAD_TOP + ROCKET_HEIGHT
## Altitude (camera height) at which the sky has fully turned to space.
const SPACE_ALTITUDE: float = 6000.0
## Capsule bottom when floating on the sea.
const SPLASH_ALTITUDE: float = 10.0

const SKY_TOP := Color("3d7cc9")
const SKY_HORIZON := Color("a8d8f5")
const SKY_HIGH := Color("0b1a3d")
const LAND := Color("4c6b43")
const LAND_DARK := Color("3a5434")
const SEA := Color("1d5fa8")
const SEA_LIGHT := Color("4b8fd6")
const CONCRETE := Color("8a8f99")
const TOWER := Color("c0392b")
const BODY := Color("e8ecf2")
const BODY_SHADE := Color("c3cbd6")
const BAND := Color("1d5fd1")
const FIN := Color("d23b3b")
const METAL := Color("3a3f4a")
const CAPSULE := Color("9aa3ae")
const CAPSULE_SHADE := Color("7d8691")

## Capsule bottom height above sea level. Before separation the booster sits
## right below it.
var altitude: float = START_ALTITUDE
## Flame size, 0 (off) to 1 (full power).
var throttle: float = 0.0
## Camera shake amplitude in pixels.
var shake: float = 0.0
## True once the capsule has left the booster (abort).
var separated: bool = false
## Booster base height once separated; it falls away and fades out.
var booster_altitude: float = 0.0
var booster_alpha: float = 1.0
## Escape tower on top of the capsule, dropped before the parachute opens.
var show_tower: bool = true
## Escape motor jets on the tower.
var escape_burn: bool = false
## Parachute opening, 0 to 1.
var parachute: float = 0.0
## Sideways drift of the capsule under its parachute, in pixels.
var drift: float = 0.0
## Splash ring animation, 0 to 1.
var splash: float = 0.0

var _time: float = 0.0
var _smoke: Array[Dictionary] = []
var _clouds: Array[Dictionary] = []
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
    mouse_filter = Control.MOUSE_FILTER_IGNORE
    _rng.seed = 7
    for i in 16:
        var puffs: Array[Vector3] = []
        for k in _rng.randi_range(3, 6):
            puffs.append(Vector3(_rng.randf_range(-90, 90), _rng.randf_range(-18, 18), _rng.randf_range(28, 60)))
        _clouds.append({
            "x": _rng.randf(),
            "y": _rng.randf_range(700.0, 4200.0),
            "puffs": puffs,
        })
    _rng.randomize()


func camera() -> float:
    return maxf(0.0, altitude - _ground_y() + size.y * 0.42)


func _ground_y() -> float:
    return size.y * 0.86


func _to_screen(world_y: float) -> float:
    return _ground_y() - world_y + camera()


func _process(delta: float) -> void:
    _time += delta
    _update_smoke(delta)
    queue_redraw()


# --- Smoke ----------------------------------------------------------------------

func _update_smoke(delta: float) -> void:
    if throttle > 0.05 and not separated:
        var base := altitude - ROCKET_HEIGHT
        var near_ground := base < PAD_TOP + 160.0
        var count := int(throttle * (5 if near_ground else 2))
        for i in count:
            var vel: Vector2
            if near_ground:
                vel = Vector2(_rng.randf_range(-260, 260), _rng.randf_range(-10, 50))
            else:
                vel = Vector2(_rng.randf_range(-25, 25), _rng.randf_range(-40, 0))
            _smoke.append({
                "pos": Vector2(size.x * 0.5 + _rng.randf_range(-20, 20), base - 20.0),
                "vel": vel,
                "radius": _rng.randf_range(14, 26),
                "grow": _rng.randf_range(18, 40),
                "life": 0.0,
                "max_life": _rng.randf_range(1.8, 3.2),
            })
    for i in range(_smoke.size() - 1, -1, -1):
        var p: Dictionary = _smoke[i]
        p["life"] += delta
        if p["life"] >= p["max_life"]:
            _smoke.remove_at(i)
            continue
        p["pos"] += p["vel"] * delta
        p["vel"] *= 1.0 - 1.2 * delta
        p["radius"] += p["grow"] * delta
    while _smoke.size() > 320:
        _smoke.pop_front()


# --- Drawing --------------------------------------------------------------------

func _draw() -> void:
    var offset := Vector2(_rng.randf_range(-shake, shake), _rng.randf_range(-shake, shake))
    draw_set_transform(offset)
    _draw_sky()
    _draw_clouds()
    _draw_ground()
    for p in _smoke:
        var t: float = p["life"] / p["max_life"]
        var pos: Vector2 = p["pos"]
        draw_circle(Vector2(pos.x, _to_screen(pos.y)), p["radius"], Color(0.92, 0.92, 0.95, 0.55 * (1.0 - t)))

    var cx := size.x * 0.5
    if separated:
        if booster_alpha > 0.0:
            _draw_booster(cx, _to_screen(booster_altitude), booster_alpha, false)
        _draw_capsule(cx + drift, _to_screen(altitude))
    else:
        _draw_booster(cx, _to_screen(altitude - ROCKET_HEIGHT), 1.0, true)
        _draw_capsule(cx, _to_screen(altitude))
    if splash > 0.0:
        _draw_splash(cx + drift, _to_screen(0.0))
    draw_set_transform(Vector2.ZERO)


func _draw_sky() -> void:
    var t := clampf(camera() / SPACE_ALTITUDE, 0.0, 1.0)
    var top := SKY_TOP.lerp(SKY_HIGH, clampf(t * 2.0, 0.0, 1.0))
    var bottom := SKY_HORIZON.lerp(SKY_TOP, clampf(t * 2.0, 0.0, 1.0))
    var alpha := 1.0 - smoothstep(0.4, 1.0, t)
    if alpha <= 0.0:
        return
    top.a = alpha
    bottom.a = alpha
    var pad := 40.0 # covers the camera shake
    draw_polygon(
        PackedVector2Array([Vector2(-pad, -pad), Vector2(size.x + pad, -pad), Vector2(size.x + pad, size.y + pad), Vector2(-pad, size.y + pad)]),
        PackedColorArray([top, top, bottom, bottom]))


func _draw_clouds() -> void:
    var fade := 1.0 - clampf(camera() / SPACE_ALTITUDE, 0.0, 1.0)
    for cloud in _clouds:
        var y := _to_screen(cloud["y"])
        if y < -150.0 or y > size.y + 150.0:
            continue
        var x: float = cloud["x"] * size.x
        for puff: Vector3 in cloud["puffs"]:
            draw_circle(Vector2(x + puff.x, y + puff.y), puff.z, Color(1, 1, 1, 0.8 * fade))


func _draw_ground() -> void:
    var gy := _to_screen(0.0)
    if gy > size.y + 50.0:
        return
    var cx := size.x * 0.5
    var land_end := cx + 260.0
    var depth := size.y + 100.0
    # Sea on the right, with a few wave lines.
    draw_rect(Rect2(land_end, gy, size.x - land_end + 50.0, depth), SEA)
    for i in 6:
        var wy := gy + 14.0 + i * 22.0
        var wx := land_end + fposmod(_time * 30.0 + i * 97.0, 160.0)
        while wx < size.x + 40.0:
            draw_line(Vector2(wx, wy), Vector2(wx + 50.0, wy), SEA_LIGHT, 3.0)
            wx += 160.0
    # Land with the launch site.
    draw_rect(Rect2(-50.0, gy, land_end + 50.0, depth), LAND)
    draw_rect(Rect2(-50.0, gy, land_end + 50.0, 10.0), LAND_DARK)
    var pad_y := _to_screen(PAD_TOP)
    draw_rect(Rect2(cx - 120.0, pad_y, 240.0, PAD_TOP), CONCRETE)
    draw_rect(Rect2(cx - 50.0, pad_y, 100.0, PAD_TOP), METAL) # flame trench
    # Launch tower: a red lattice with an access arm.
    var tx := cx - 150.0
    var tower_top := _to_screen(PAD_TOP + 420.0)
    draw_line(Vector2(tx, pad_y), Vector2(tx, tower_top), TOWER, 5.0)
    draw_line(Vector2(tx + 40.0, pad_y), Vector2(tx + 40.0, tower_top), TOWER, 5.0)
    var y := pad_y
    while y > tower_top + 1.0:
        var next := maxf(y - 40.0, tower_top)
        draw_line(Vector2(tx, y), Vector2(tx + 40.0, next), TOWER, 3.0)
        draw_line(Vector2(tx, next), Vector2(tx + 40.0, next), TOWER, 3.0)
        y = next
    var arm_y := _to_screen(PAD_TOP + 330.0)
    draw_rect(Rect2(tx + 40.0, arm_y, 64.0, 10.0), TOWER)


func _draw_booster(cx: float, base: float, alpha: float, with_flame: bool) -> void:
    var mod := Color(1, 1, 1, alpha)
    if with_flame and throttle > 0.01:
        _draw_flame(cx, base)
    # Engine bell.
    draw_colored_polygon(PackedVector2Array([
        Vector2(cx - 22, base - 22), Vector2(cx + 22, base - 22),
        Vector2(cx + 30, base), Vector2(cx - 30, base)]), METAL * mod)
    var body_bottom := base - 22.0
    var body_top := base - ROCKET_HEIGHT
    # Fins.
    draw_colored_polygon(PackedVector2Array([
        Vector2(cx - 34, body_bottom - 90), Vector2(cx - 34, body_bottom), Vector2(cx - 74, body_bottom + 6)]), FIN * mod)
    draw_colored_polygon(PackedVector2Array([
        Vector2(cx + 34, body_bottom - 90), Vector2(cx + 74, body_bottom + 6), Vector2(cx + 34, body_bottom)]), FIN * mod)
    # Body with shading and bands.
    draw_rect(Rect2(cx - 34, body_top, 68, body_bottom - body_top), BODY * mod)
    draw_rect(Rect2(cx + 12, body_top, 22, body_bottom - body_top), BODY_SHADE * mod)
    draw_rect(Rect2(cx - 34, body_bottom - 130, 68, 14), METAL * mod)
    draw_rect(Rect2(cx - 34, body_bottom - 220, 68, 20), BAND * mod)
    draw_rect(Rect2(cx - 34, body_top + 14, 68, 8), METAL * mod)


func _draw_flame(cx: float, base: float) -> void:
    var flicker := 0.85 + 0.15 * sin(_time * 47.0) + _rng.randf_range(-0.06, 0.06)
    var length := throttle * 190.0 * flicker
    var w := 26.0
    draw_colored_polygon(PackedVector2Array([
        Vector2(cx - w, base), Vector2(cx + w, base), Vector2(cx + w * 0.45, base + length * 0.6),
        Vector2(cx, base + length), Vector2(cx - w * 0.45, base + length * 0.6)]), Color("ff7a1a", 0.9))
    draw_colored_polygon(PackedVector2Array([
        Vector2(cx - w * 0.65, base), Vector2(cx + w * 0.65, base), Vector2(cx + w * 0.25, base + length * 0.45),
        Vector2(cx, base + length * 0.7), Vector2(cx - w * 0.25, base + length * 0.45)]), Color("ffd23f"))
    draw_colored_polygon(PackedVector2Array([
        Vector2(cx - w * 0.3, base), Vector2(cx + w * 0.3, base), Vector2(cx, base + length * 0.3)]), Color("fff8e0"))


func _draw_capsule(cx: float, bottom: float) -> void:
    var top := bottom - 60.0
    if parachute > 0.0:
        _draw_parachute(cx, top)
    draw_colored_polygon(PackedVector2Array([
        Vector2(cx - 34, bottom), Vector2(cx + 34, bottom), Vector2(cx + 15, top), Vector2(cx - 15, top)]), CAPSULE)
    draw_colored_polygon(PackedVector2Array([
        Vector2(cx + 10, bottom), Vector2(cx + 34, bottom), Vector2(cx + 15, top), Vector2(cx + 6, top)]), CAPSULE_SHADE)
    draw_rect(Rect2(cx - 9, bottom - 38, 12, 10), Color("63b1ff"))
    draw_rect(Rect2(cx - 36, bottom - 6, 72, 6), METAL)
    if show_tower:
        draw_line(Vector2(cx, top), Vector2(cx, top - 54), METAL, 4.0)
        draw_line(Vector2(cx - 10, top), Vector2(cx, top - 30), METAL, 2.0)
        draw_line(Vector2(cx + 10, top), Vector2(cx, top - 30), METAL, 2.0)
        draw_rect(Rect2(cx - 6, top - 74, 12, 22), FIN)
        if escape_burn:
            var flick := _rng.randf_range(0.8, 1.2)
            for side: float in [-1.0, 1.0]:
                draw_colored_polygon(PackedVector2Array([
                    Vector2(cx + side * 6, top - 56), Vector2(cx + side * 6, top - 64),
                    Vector2(cx + side * 40 * flick, top - 34)]), Color("ffb800"))


func _draw_parachute(cx: float, capsule_top: float) -> void:
    var r := 95.0 * parachute
    var center := Vector2(cx, capsule_top - 60.0 - 110.0 * parachute)
    var segments := 6
    for i in segments:
        var a0 := PI + PI * i / segments
        var a1 := PI + PI * (i + 1) / segments
        var points := PackedVector2Array([center])
        for k in 5:
            var a := lerpf(a0, a1, k / 4.0)
            points.append(center + Vector2(cos(a) * r, sin(a) * r * 0.75))
        draw_colored_polygon(points, Color("ff6b3d") if i % 2 == 0 else Color("fff4e6"))
    for side: float in [-1.0, -0.4, 0.4, 1.0]:
        draw_line(center + Vector2(side * r, 0), Vector2(cx + side * 12.0, capsule_top), Color(1, 1, 1, 0.8), 1.5)


func _draw_splash(cx: float, sea_y: float) -> void:
    for i in 3:
        var t := clampf(splash * 1.4 - i * 0.2, 0.0, 1.0)
        if t <= 0.0:
            continue
        var r := lerpf(40.0, 160.0, t)
        _draw_ellipse(Vector2(cx, sea_y + 4.0), r, r * 0.22, Color(1, 1, 1, 0.8 * (1.0 - t)))


func _draw_ellipse(center: Vector2, rx: float, ry: float, color: Color) -> void:
    var points := PackedVector2Array()
    for k in 33:
        var a := TAU * k / 32.0
        points.append(center + Vector2(cos(a) * rx, sin(a) * ry))
    draw_polyline(points, color, 3.0, true)
