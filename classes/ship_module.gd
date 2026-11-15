class_name ShipModule extends RefCounted
## A card once it is aboard the ship. Its position in the cargo (`index`)
## decides its neighbours, which some cards care about.

var augment: Augment
var index: int = 0
## Switched on by the crew (only toggleable modules can be switched off).
var enabled: bool = true
## Needs a repair before it works again.
var broken: bool = false
## Gone for good (e.g. the ficus dried out).
var lost: bool = false
## Not producing today (e.g. the bargain solar panel blacked out).
var offline_today: bool = false


func _init(_augment: Augment, _index: int) -> void:
    augment = _augment
    index = _index


func working() -> bool:
    return enabled and not broken and not lost and not offline_today


func has_daily_effect() -> bool:
    return not augment.daily.is_empty() or not augment.synergy_daily.is_empty()


func status_text() -> String:
    if lost:
        return "Lost"
    if broken:
        return "Broken: needs repair"
    if not enabled:
        return "Switched off"
    if offline_today:
        return "Offline today"
    return "Working"
