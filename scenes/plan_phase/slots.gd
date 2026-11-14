@tool
extends Control

func _ready() -> void:
    child_order_changed.connect(arrange)
    arrange()

func arrange() -> void:
    var cards := get_children()
    var n := cards.size()
    for i in n:
        var card: Control = cards[i]
        card.position.x = i * 32
