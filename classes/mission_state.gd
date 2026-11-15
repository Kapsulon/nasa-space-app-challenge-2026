class_name MissionState extends RefCounted
## Pure simulation of the mission phase. The UI reads from it and calls
## start_day() / choose() / use_medkit() / end_day(); no nodes involved.
##
## Family friendly by design: crew members never die. When their health or
## stress hits the limit they board the return capsule and fly home safely,
## which leaves fewer hands aboard for the rest of the mission.

const RESOURCE_IDS: Array[String] = ["oxygen", "water", "food", "power", "hull", "medkits"]

const RESOURCE_INFO: Dictionary[String, Dictionary] = {
    "oxygen": {"name": "Oxygen", "color": Color("63b1ff")},
    "water": {"name": "Water", "color": Color("3ad1c2")},
    "food": {"name": "Food", "color": Color("f2b53a")},
    "power": {"name": "Power", "color": Color("ffe45c")},
    "hull": {"name": "Hull integrity", "color": Color("b8c2cc")},
    "medkits": {"name": "Medkits", "color": Color("ff5a6e")},
}

const DEFAULT_CAPACITIES: Dictionary[String, int] = {
    "oxygen": 24, "water": 20, "food": 20, "power": 15, "hull": 100, "medkits": 5,
}
const DEFAULT_START: Dictionary[String, int] = {
    "oxygen": 20, "water": 14, "food": 14, "power": 10, "hull": 100, "medkits": 2,
}

const DEFAULT_CREW: Array[Array] = [
    ["Cmdr. Okafor", "Commander"],
    ["Dr. Lindqvist", "Flight surgeon"],
    ["Eng. Tanaka", "Engineer"],
    ["Sci. Moreau", "Scientist"],
]

const SOLAR_POWER_PER_DAY: int = 3
const LIFE_SUPPORT_POWER: int = 2
const HULL_DECAY_PER_DAY: int = 2
const HULL_LEAK_THRESHOLD: int = 30
const EVENT_CHANCE: float = 0.7
const REST_HEAL: int = 15
const SICK_REST_HEAL: int = 5
const MEDKIT_HEAL: int = 40
const REPAIR_AMOUNT: int = 8

# Stress tuning.
const WORK_STRESS: int = 6
const REST_STRESS_RELIEF: int = 10
const CALL_HOME_STRESS_RELIEF: int = 25
const HUNGER_STRESS: int = 8
const THIRST_STRESS: int = 8
const SICK_STRESS: int = 5
const HULL_DAMAGE_STRESS: int = 5
const LOW_AIR_STRESS: int = 20
## Chance that an overwhelmed crew member can't focus on their task.
const OVERWHELMED_FAIL_CHANCE: float = 0.4

const TASK_POWER: Dictionary[CrewMember.Task, int] = {
    CrewMember.Task.REST: 0,
    CrewMember.Task.REPAIR: 1,
    CrewMember.Task.RECYCLE: 1,
    CrewMember.Task.RESEARCH: 1,
    CrewMember.Task.CALL_HOME: 1,
}

enum Outcome { ONGOING, WON, LOST }

var scenario_name: String = "Mission"
var day: int = 1
var mission_days: int = 10
var science: int = 0
var resources: Dictionary[String, int] = {}
var capacities: Dictionary[String, int] = {}
var crew: Array[CrewMember] = []
var outcome: Outcome = Outcome.ONGOING
var outcome_text: String = ""
## Human readable lines describing what the augments changed at launch.
var augment_summary: PackedStringArray = []

var current_event: MissionEvent = null
var chosen: EventChoice = null

var _event_pool: Array[MissionEvent] = []
var _day_start_resources: Dictionary[String, int] = {}
var _day_start_science: int = 0
var _day_log: PackedStringArray = []


func _init(_scenario_name: String, _mission_days: int, event_pool: Array[MissionEvent], augments: Array[AugmentInstance]) -> void:
    scenario_name = _scenario_name
    mission_days = _mission_days
    _event_pool = event_pool.duplicate()
    capacities = DEFAULT_CAPACITIES.duplicate()
    resources = DEFAULT_START.duplicate()
    for entry in DEFAULT_CREW:
        crew.append(CrewMember.new(entry[0], entry[1]))
    _apply_augments(augments)


static func load_event_pool(dir_path: String = "res://data/events") -> Array[MissionEvent]:
    var pool: Array[MissionEvent] = []
    for file in ResourceLoader.list_directory(dir_path):
        var res := load(dir_path.path_join(file))
        if res is MissionEvent:
            pool.append(res)
    return pool


func _apply_augments(augments: Array[AugmentInstance]) -> void:
    for instance in augments:
        for key in instance.augment.upgrades.keys():
            var amount := int(instance.augment.upgrades[key])
            if key.ends_with("_capacity") and capacities.has(key.trim_suffix("_capacity")):
                var res_id: String = key.trim_suffix("_capacity")
                capacities[res_id] += amount
                resources[res_id] += amount
                augment_summary.append("%s: +%d %s capacity" % [instance.augment.display_name, amount, resource_name(res_id)])
            elif resources.has(key):
                resources[key] = mini(resources[key] + amount, capacities[key])
                augment_summary.append("%s: +%d %s" % [instance.augment.display_name, amount, resource_name(key)])
            elif key == "mission_days":
                mission_days = maxi(1, mission_days + amount)
                augment_summary.append("%s: %+d mission days" % [instance.augment.display_name, amount])


static func resource_name(res_id: String) -> String:
    return RESOURCE_INFO.get(res_id, {}).get("name", res_id.capitalize())


func crew_aboard() -> Array[CrewMember]:
    return crew.filter(func(c: CrewMember): return c.is_aboard())


# --- Day flow -----------------------------------------------------------------

func start_day() -> void:
    _day_start_resources = resources.duplicate()
    _day_start_science = science
    _day_log = []
    chosen = null
    current_event = null
    for member in crew:
        member.give_food = member.is_aboard()
        member.give_water = member.is_aboard()
        if not member.is_aboard():
            member.task = CrewMember.Task.REST
    if day > 1 and randf() < EVENT_CHANCE:
        current_event = _draw_event()


func _draw_event() -> MissionEvent:
    var candidates := _event_pool.filter(func(e: MissionEvent): return e.min_day <= day)
    if candidates.is_empty():
        return null
    var total := 0.0
    for e in candidates:
        total += e.weight
    var roll := randf() * total
    for e in candidates:
        roll -= e.weight
        if roll <= 0.0:
            _event_pool.erase(e)
            return e
    _event_pool.erase(candidates[-1])
    return candidates[-1]


func needs_decision() -> bool:
    return current_event != null and chosen == null


func can_afford(cost: Dictionary) -> bool:
    for key in cost.keys():
        if resources.get(key, 0) < cost[key]:
            return false
    return true


func choose(choice: EventChoice) -> void:
    if chosen != null or not can_afford(choice.cost):
        return
    chosen = choice
    for key in choice.cost.keys():
        resources[key] -= choice.cost[key]


func can_use_medkit(member: CrewMember) -> bool:
    return member.is_aboard() and resources["medkits"] > 0 and (member.sick or member.health < CrewMember.MAX_HEALTH)


func use_medkit(member: CrewMember) -> void:
    if not can_use_medkit(member):
        return
    resources["medkits"] -= 1
    member.heal(MEDKIT_HEAL)
    member.sick = false
    _day_log.append("%s was patched up with a medkit." % member.display_name)


## Expected resource change for tonight given the current decisions
## (ignores random event outcomes).
func forecast() -> Dictionary[String, int]:
    var delta: Dictionary[String, int] = {}
    for res_id in RESOURCE_IDS:
        delta[res_id] = 0
    var aboard := crew_aboard()
    delta["power"] += SOLAR_POWER_PER_DAY - LIFE_SUPPORT_POWER
    delta["oxygen"] -= aboard.size()
    delta["hull"] -= HULL_DECAY_PER_DAY
    if resources["hull"] < HULL_LEAK_THRESHOLD:
        delta["oxygen"] -= 1
    for member in aboard:
        if member.give_food:
            delta["food"] -= 1
        if member.give_water:
            delta["water"] -= 1
        delta["power"] -= TASK_POWER[member.task]
        match member.task:
            CrewMember.Task.REPAIR:
                delta["hull"] += REPAIR_AMOUNT
            CrewMember.Task.RECYCLE:
                delta["oxygen"] += 2
                delta["water"] += 2
    return delta


## Resolves the night and returns a recap dictionary for the UI:
## { day, event_title, decision, event_result, resources: {id: [before, after]},
##   science: [before, after], log: PackedStringArray,
##   sent_home: Array[{name, reason}], outcome }
func end_day() -> Dictionary:
    var recap := {
        "day": day,
        "event_title": current_event.title if current_event else "",
        "decision": chosen.label if chosen else "",
        "event_result": "",
    }

    # 1. Event outcome, revealed during the night.
    if chosen != null:
        if randf() <= chosen.success_chance:
            apply_effects(chosen.success_effects)
            recap["event_result"] = chosen.success_text
        else:
            apply_effects(chosen.failure_effects)
            recap["event_result"] = chosen.failure_text

    var aboard := crew_aboard()

    # 2. Power: solar in, life support out.
    resources["power"] += SOLAR_POWER_PER_DAY
    var life_support_ok := resources["power"] >= LIFE_SUPPORT_POWER
    if life_support_ok:
        resources["power"] -= LIFE_SUPPORT_POWER
    else:
        _day_log.append("[color=#ffb35c]Not enough power: life support switched to backup mode and used extra oxygen.[/color]")

    # 3. Rations.
    for member in aboard:
        if member.give_food and resources["food"] > 0:
            resources["food"] -= 1
            member.days_hungry = 0
        else:
            if member.give_food:
                _day_log.append("The pantry ran out before %s got a meal." % member.display_name)
            member.days_hungry += 1
            member.add_stress(HUNGER_STRESS)
        if member.give_water and resources["water"] > 0:
            resources["water"] -= 1
            member.days_thirsty = 0
        else:
            if member.give_water:
                _day_log.append("The water tank ran dry before %s got a drink." % member.display_name)
            member.days_thirsty += 1
            member.add_stress(THIRST_STRESS)

    # 4. Crew tasks.
    for member in aboard:
        var task_name := CrewMember.TASK_NAMES[member.task].to_lower()
        var power_needed: int = TASK_POWER[member.task]
        if power_needed > resources["power"]:
            _day_log.append("%s couldn't %s: not enough power." % [member.display_name, task_name])
            continue
        if member.task != CrewMember.Task.REST and member.task != CrewMember.Task.CALL_HOME \
                and member.is_overwhelmed() and randf() < OVERWHELMED_FAIL_CHANCE:
            _day_log.append("%s felt too overwhelmed to focus on \"%s\" today." % [member.display_name, task_name])
            continue
        resources["power"] -= power_needed
        match member.task:
            CrewMember.Task.REST:
                member.heal(REST_HEAL if not member.sick else SICK_REST_HEAL)
                member.add_stress(-REST_STRESS_RELIEF)
            CrewMember.Task.REPAIR:
                resources["hull"] += REPAIR_AMOUNT
                member.add_stress(WORK_STRESS)
            CrewMember.Task.RECYCLE:
                resources["oxygen"] += 2
                resources["water"] += 2
                member.add_stress(WORK_STRESS)
            CrewMember.Task.RESEARCH:
                science += 1
                member.add_stress(WORK_STRESS)
            CrewMember.Task.CALL_HOME:
                member.add_stress(-CALL_HOME_STRESS_RELIEF)
                _day_log.append("%s had a lovely video call with their family." % member.display_name)

    # 5. Breathing, hull wear.
    var oxygen_needed := aboard.size() + (0 if life_support_ok else 2)
    if resources["hull"] < HULL_LEAK_THRESHOLD:
        oxygen_needed += 1
        _day_log.append("[color=#ffb35c]The worn-out hull is leaking a little air. The crew is getting nervous.[/color]")
        for member in aboard:
            member.add_stress(HULL_DAMAGE_STRESS)
    resources["oxygen"] -= oxygen_needed
    if resources["oxygen"] < 0:
        resources["oxygen"] = 0
        _day_log.append("[color=#ff5a6e]The oxygen tanks ran low! The air feels thin and everyone is short of breath.[/color]")
        for member in aboard:
            member.damage(15)
            member.add_stress(LOW_AIR_STRESS)
    resources["hull"] -= HULL_DECAY_PER_DAY

    # 6. Body condition.
    for member in aboard:
        if member.days_hungry >= 2:
            member.damage(10)
        if member.days_thirsty >= 2:
            member.damage(15)
        elif member.days_thirsty == 1:
            member.damage(5)
        if member.sick:
            member.damage(6)
            member.add_stress(SICK_STRESS)
        elif member.health < 50 and randf() < 0.15:
            member.sick = true
            _day_log.append("%s is feeling unwell." % member.display_name)

    _clamp_resources()

    # 7. Anyone at their limit flies home safely.
    var sent_home: Array[Dictionary] = []
    for member in aboard:
        var reason := ""
        if member.health <= 0:
            reason = "needed to see a doctor back on Earth"
        elif member.stress >= CrewMember.MAX_STRESS:
            reason = "needed a break from space"
        if reason != "":
            member.send_home(reason)
            sent_home.append({"name": member.display_name, "reason": reason})

    # 8. Mission state.
    if crew_aboard().is_empty():
        outcome = Outcome.LOST
        outcome_text = "The whole crew flew home in the return capsule on day %d. The mission was called off, but everyone is safe and sound back on Earth." % day
    elif resources["hull"] <= 0:
        outcome = Outcome.LOST
        outcome_text = "On day %d the ship became too damaged to continue. The crew climbed into the return capsule and splashed down safely in the ocean." % day
    elif day >= mission_days:
        outcome = Outcome.WON
        outcome_text = "%s complete! %d of %d crew members made it all the way, with %d science collected." % [
            scenario_name, crew_aboard().size(), crew.size(), science]

    var res_changes := {}
    for res_id in RESOURCE_IDS:
        res_changes[res_id] = [_day_start_resources[res_id], resources[res_id]]
    recap["resources"] = res_changes
    recap["science"] = [_day_start_science, science]
    recap["log"] = _day_log
    recap["sent_home"] = sent_home
    recap["outcome"] = outcome

    day += 1
    return recap


func apply_effects(effects: Dictionary) -> void:
    for key in effects.keys():
        var amount: int = effects[key]
        if resources.has(key):
            resources[key] += amount
        elif key == "science":
            science = maxi(0, science + amount)
        elif key == "mission_days":
            mission_days = maxi(day, mission_days + amount)
        elif key == "crew_health":
            for member in crew_aboard():
                _change_health(member, amount)
        elif key == "crew_stress":
            for member in crew_aboard():
                member.add_stress(amount)
        elif key == "random_crew_health":
            var member := _random_aboard()
            if member:
                _change_health(member, amount)
                _day_log.append("%s %s." % [member.display_name, "feels better" if amount > 0 else "is worn out"])
        elif key == "random_crew_stress":
            var member := _random_aboard()
            if member:
                member.add_stress(amount)
                _day_log.append("%s %s." % [member.display_name, "is feeling more relaxed" if amount < 0 else "is feeling stressed"])
        elif key == "random_crew_sick":
            var healthy := crew_aboard().filter(func(c: CrewMember): return not c.sick)
            if not healthy.is_empty():
                var member: CrewMember = healthy.pick_random()
                member.sick = true
                _day_log.append("%s is feeling unwell." % member.display_name)
        else:
            push_warning("Unknown event effect key: %s" % key)
    _clamp_resources()


func _random_aboard() -> CrewMember:
    var aboard := crew_aboard()
    return null if aboard.is_empty() else aboard.pick_random()


func _change_health(member: CrewMember, amount: int) -> void:
    if amount > 0:
        member.heal(amount)
    else:
        member.damage(-amount)


func _clamp_resources() -> void:
    for res_id in RESOURCE_IDS:
        resources[res_id] = clampi(resources[res_id], 0, capacities[res_id])
