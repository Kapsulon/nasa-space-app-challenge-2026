class_name CrewMember extends RefCounted

enum Task {
    REST,
    REPAIR,
    RECYCLE,
    RESEARCH,
}

const TASK_NAMES: Dictionary[Task, String] = {
    Task.REST: "Rest",
    Task.REPAIR: "Repair hull",
    Task.RECYCLE: "Recycle air & water",
    Task.RESEARCH: "Research",
}

const TASK_HINTS: Dictionary[Task, String] = {
    Task.REST: "+15 health",
    Task.REPAIR: "+8 hull, -1 power",
    Task.RECYCLE: "+2 oxygen, +2 water, -1 power",
    Task.RESEARCH: "+1 science, -1 power",
}

const MAX_HEALTH: int = 100

var display_name: String
var role: String
var health: int = MAX_HEALTH
var sick: bool = false
## Days in a row without food / water.
var days_hungry: int = 0
var days_thirsty: int = 0

# Per-day decisions, reset every morning.
var task: Task = Task.REST
var give_food: bool = true
var give_water: bool = true


func _init(_name: String, _role: String) -> void:
    display_name = _name
    role = _role


func is_alive() -> bool:
    return health > 0


func damage(amount: int) -> void:
    health = clampi(health - amount, 0, MAX_HEALTH)


func heal(amount: int) -> void:
    if is_alive():
        health = clampi(health + amount, 0, MAX_HEALTH)


func status_text() -> String:
    if not is_alive():
        return "Dead"
    var parts: PackedStringArray = []
    if health < 25:
        parts.append("Critical")
    elif health < 50:
        parts.append("Weak")
    else:
        parts.append("Healthy")
    if sick:
        parts.append("Sick")
    if days_hungry >= 2:
        parts.append("Starving")
    elif days_hungry == 1:
        parts.append("Hungry")
    if days_thirsty >= 1:
        parts.append("Thirsty")
    return ", ".join(parts)
