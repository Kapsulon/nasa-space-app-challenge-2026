class_name CrewMember extends RefCounted
## One astronaut. Nobody gets hurt for good in this game: when health or
## stress reach their limit, the crew member takes the return capsule home
## and simply leaves the mission.

enum Task {
    REST,
    REPAIR,
    RECYCLE,
    RESEARCH,
    CALL_HOME,
}

const TASK_NAMES: Dictionary[Task, String] = {
    Task.REST: "Rest",
    Task.REPAIR: "Repair hull",
    Task.RECYCLE: "Recycle air & water",
    Task.RESEARCH: "Research",
    Task.CALL_HOME: "Call home",
}

const TASK_HINTS: Dictionary[Task, String] = {
    Task.REST: "+15 health, -10 stress",
    Task.REPAIR: "+8 hull, -1 power, +6 stress",
    Task.RECYCLE: "+2 oxygen, +2 water, -1 power, +6 stress",
    Task.RESEARCH: "+1 science, -1 power, +6 stress",
    Task.CALL_HOME: "-25 stress, -1 power",
}

const MAX_HEALTH: int = 100
const MAX_STRESS: int = 100
const STRESSED: int = 50
const OVERWHELMED: int = 80

var display_name: String
var role: String
var health: int = MAX_HEALTH
var stress: int = 0
var sick: bool = false
## False once the crew member has taken the return capsule home.
var aboard: bool = true
## Why they went home, shown in the UI ("needed medical care", ...).
var left_reason: String = ""
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


func is_aboard() -> bool:
    return aboard


func damage(amount: int) -> void:
    if aboard:
        health = clampi(health - amount, 0, MAX_HEALTH)


func heal(amount: int) -> void:
    if aboard:
        health = clampi(health + amount, 0, MAX_HEALTH)


func add_stress(amount: int) -> void:
    if aboard:
        stress = clampi(stress + amount, 0, MAX_STRESS)


func send_home(reason: String) -> void:
    aboard = false
    left_reason = reason


func is_overwhelmed() -> bool:
    return stress >= OVERWHELMED


func status_text() -> String:
    if not aboard:
        return "Back on Earth"
    var parts: PackedStringArray = []
    if health < 25:
        parts.append("Exhausted")
    elif health < 50:
        parts.append("Tired")
    if stress >= OVERWHELMED:
        parts.append("Overwhelmed")
    elif stress >= STRESSED:
        parts.append("Stressed")
    if sick:
        parts.append("Feeling unwell")
    if days_hungry >= 2:
        parts.append("Very hungry")
    elif days_hungry == 1:
        parts.append("Hungry")
    if days_thirsty >= 1:
        parts.append("Thirsty")
    if parts.is_empty():
        return "Doing great"
    return ", ".join(parts)


func is_doing_great() -> bool:
    return status_text() == "Doing great"
