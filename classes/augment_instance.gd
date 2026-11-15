class_name AugmentInstance extends Node

## Country that built this card (a Country id, "" for none, e.g. in the
## codex). Shown as a flag on the card; see Country for the bonuses.
var country: String = ""
var augment: Augment


func _init(_augment: Augment, _country: String) -> void:
    augment = _augment
    country = _country

## Rolled amounts for upgrades with a range ("20-60"), decided once when the
## card is picked so every screen shows the same number.
var rolled: Dictionary[String, int] = {}
## Cargo slots this card takes. -1 = its normal cost. Cards that came out of
## a crate or a lottery take 0 (the crate paid for them).
var slots: int = -1


func slots_taken() -> int:
    return slots if slots >= 0 else augment.slot_cost()


func roll() -> void:
    for key in augment.upgrades.keys():
        var r := Augment.parse_range(augment.upgrades[key])
        if r.x != r.y:
            rolled[key] = randi_range(r.x, r.y)


func upgrade_amount(key: String) -> int:
    if rolled.has(key):
        return rolled[key]
    var r := Augment.parse_range(augment.upgrades[key])
    return floori((r.x + r.y) / 2.0)
