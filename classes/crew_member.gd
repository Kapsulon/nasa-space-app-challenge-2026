class_name CrewMember extends RefCounted
## One astronaut. Nobody gets hurt for good in this game: when health or
## stress reach their limit, the crew member takes the return capsule home
## and simply leaves the mission.

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

## What they are good at: "command", "medical", "engineering", "science".
var skill: String = ""
## The station (MissionState.STATIONS) they are assigned to.
var station: String = "bunks"


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
