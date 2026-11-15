extends Control
## The little pixel-art capsule and module from the title card, drawn on a
## 64x32 grid and scaled to the control's size.

const NATIVE := Vector2(64, 32)

## [x, y, w, h, color] on the 64x32 grid.
const PIXELS: Array[Array] = [
    # Station module.
    [42, 6, 18, 20, "9a3412"], [44, 8, 14, 16, "ea580c"], [47, 6, 8, 2, "f8fafc"],
    # Capsule: engine flame, fins, body, nose, porthole.
    [6, 14, 5, 4, "ea580c"], [9, 15, 2, 2, "facc15"],
    [11, 10, 3, 2, "dc2626"], [11, 20, 3, 2, "dc2626"],
    [11, 12, 12, 8, "f8fafc"],
    [23, 13, 3, 6, "dc2626"], [26, 15, 2, 2, "dc2626"],
    [16, 14, 4, 4, "63b1ff"],
]


func _ready() -> void:
    mouse_filter = Control.MOUSE_FILTER_IGNORE


func _draw() -> void:
    var k := size / NATIVE
    for p in PIXELS:
        draw_rect(Rect2(Vector2(p[0], p[1]) * k, Vector2(p[2], p[3]) * k), Color(p[4]))
