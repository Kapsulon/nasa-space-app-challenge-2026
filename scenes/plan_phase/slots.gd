@tool
extends Control
## The cargo slots, overlapping in a row. They squeeze closer together when
## there are too many to fit at the normal spacing.

const STEP: float = 32.0


func _ready() -> void:
    child_order_changed.connect(arrange)
    resized.connect(arrange)
    arrange()


func arrange() -> void:
    var slots := get_children().filter(func(c: Node): return c is Control and not c.is_queued_for_deletion())
    var n := slots.size()
    if n == 0:
        return
    var step := STEP
    var slot_width: float = (slots[0] as Control).size.x
    if n > 1 and size.x > 0.0:
        step = minf(STEP, (size.x - slot_width) / (n - 1))
    for i in n:
        var slot: Control = slots[i]
        slot.position.x = i * step
