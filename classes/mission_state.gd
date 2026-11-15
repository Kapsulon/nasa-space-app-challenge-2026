class_name MissionState extends RefCounted
## Pure simulation of the mission phase, no nodes involved. The ship view
## drives it in real time:
##   - start_day() in the morning,
##   - work(member, hours) for every crew member while they stay at a station,
##   - begin_event_choice() / finish_event_choice() / ignore_event() for the
##     alerts that pop up around the ship,
##   - end_day() at night (modules, supplies, risks).
## Everything worth telling the player goes to a live feed: drain_log().
##
## Family friendly by design: crew members never die. When their health or
## stress hits the limit they board the return capsule and fly home safely,
## which leaves fewer hands aboard for the rest of the mission.
##
## The cards picked in the plan phase become ship modules (ShipModule): they
## add stock at launch, then produce / consume every night, can break or
## misbehave (CardRisk), and some react to their neighbours in the cargo.

const RESOURCE_IDS: Array[String] = ["oxygen", "water", "food", "power", "hull", "medkits"]

const RESOURCE_INFO: Dictionary[String, Dictionary] = {
    "oxygen": {"name": "Oxygen", "unit": "kg", "color": Color("63b1ff")},
    "water": {"name": "Water", "unit": "L", "color": Color("3ad1c2")},
    "food": {"name": "Food", "unit": "meals", "color": Color("f2b53a")},
    "power": {"name": "Power", "unit": "kWh", "color": Color("ffe45c")},
    "hull": {"name": "Hull", "unit": "%", "color": Color("b8c2cc")},
    "medkits": {"name": "Medkits", "unit": "", "color": Color("ff5a6e")},
}

## The bare capsule, before any card. Cards add stock and storage on top.
const DEFAULT_CAPACITIES: Dictionary[String, int] = {
    "oxygen": 30, "water": 60, "food": 50, "power": 20, "hull": 100, "medkits": 5,
}
const DEFAULT_START: Dictionary[String, int] = {
    "oxygen": 12, "water": 24, "food": 24, "power": 12, "hull": 100, "medkits": 2,
}

## Daily needs of each crew member (roughly real ISS figures).
const WATER_PER_CREW: int = 3
const OXYGEN_PER_CREW: int = 1
const FOOD_PER_CREW: int = 2

## name, role, skill, starting station.
const DEFAULT_CREW: Array[Array] = [
    ["Cmdr. Okafor", "Commander", "command", "comms"],
    ["Dr. Lindqvist", "Flight surgeon", "medical", "medbay"],
    ["Eng. Tanaka", "Engineer", "engineering", "engineering"],
    ["Sci. Moreau", "Scientist", "science", "lab"],
]

const SKILL_NAMES: Dictionary[String, String] = {
    "command": "Commander",
    "medical": "Flight surgeon",
    "engineering": "Engineer",
    "science": "Scientist",
}

## Fixed rooms of the ship. Effects are per hour spent there during the day.
## "skill": crew with that skill work 50% faster there.
## "power": the station draws 1 kWh at night if anyone used it that day.
const STATIONS: Dictionary[String, Dictionary] = {
    "bunks": {"name": "Sleep pods", "verb": "resting in the sleep pods",
        "hint": "Rest: health back up, stress down", "skill": "", "power": false},
    "medbay": {"name": "Medbay", "verb": "in the medbay",
        "hint": "Faster healing, treats sickness (uses a medkit)", "skill": "medical", "power": false},
    "comms": {"name": "Comms room", "verb": "calling home",
        "hint": "Video calls home: big stress relief (needs the radio)", "skill": "command", "power": true},
    "cupola": {"name": "Cupola", "verb": "watching Earth from the cupola",
        "hint": "Looking at Earth: gentle stress relief", "skill": "", "power": false},
    "lab": {"name": "Greenhouse lab", "verb": "doing research",
        "hint": "Research: science points, a bit tiring", "skill": "science", "power": true},
    "engineering": {"name": "Power core", "verb": "doing repairs",
        "hint": "Repairs broken modules, then the hull", "skill": "engineering", "power": true},
    "life_support": {"name": "Life support", "verb": "recycling air and water",
        "hint": "Manual recycling: water and oxygen", "skill": "engineering", "power": true},
}

## Daytime hours (08:00 to 20:00).
const DAY_START_HOUR: float = 8.0
const DAY_HOURS: float = 12.0

# Station rates, per hour.
const REST_HEAL_PER_HOUR: float = 1.0
const REST_STRESS_PER_HOUR: float = 0.8
const MEDBAY_HEAL_PER_HOUR: float = 1.5
const MEDBAY_CURE_HOURS: float = 4.0
const COMMS_STRESS_PER_HOUR: float = 2.0
const CUPOLA_STRESS_PER_HOUR: float = 1.0
const WORK_STRESS_PER_HOUR: float = 0.6
const SCIENCE_PER_HOUR: float = 0.12
const HULL_REPAIR_PER_HOUR: float = 0.5
const MODULE_REPAIR_HOURS: float = 4.0
const RECYCLE_WATER_PER_HOUR: float = 0.2
const RECYCLE_OXYGEN_PER_HOUR: float = 0.08
## Overwhelmed crew work at this fraction of their speed.
const OVERWHELMED_EFFICIENCY: float = 0.5
const SKILL_BONUS: float = 1.5

# Night.
const SOLAR_POWER_PER_DAY: int = 4
const LIFE_SUPPORT_POWER: int = 3
## Extra oxygen used when life support falls back to backup mode.
const BACKUP_OXYGEN: int = 3
const HULL_DECAY_PER_DAY: int = 3
const HULL_LEAK_THRESHOLD: int = 30
const SLEEP_HEAL: int = 4
const SLEEP_STRESS_RELIEF: int = 4
## The ship can't fly with fewer crew than this: the last ones fly home too.
const MIN_CREW: int = 2
## Being far from home wears on everyone a little every night.
const HOMESICK_STRESS: int = 3
const MEDKIT_HEAL: int = 40

# Going without. Damage per night: the first night, then every night after.
const HUNGER_DAMAGE: Array[int] = [5, 12]
const THIRST_DAMAGE: Array[int] = [8, 18]
const NO_AIR_DAMAGE: int = 50

# Stress tuning.
const HUNGER_STRESS: int = 8
const THIRST_STRESS: int = 8
const SICK_STRESS: int = 5
const HULL_DAMAGE_STRESS: int = 5
const LOW_AIR_STRESS: int = 20

# Events.
## Chance of an alert in the morning, and of a second one in the afternoon.
const EVENT_CHANCE: float = 1.0
const SECOND_EVENT_CHANCE: float = 0.7
## Hours an alert waits for someone before the crew falls back on the last
## (passive) option.
const EVENT_DEADLINE_HOURS: float = 4.0
const EVENT_SKILL_BONUS: float = 0.2
const EVENT_STRESS_PENALTY: float = 0.3
const EVENT_SICK_PENALTY: float = 0.15
const EVENT_WORK_STRESS: int = 4
## Stress from homesick alerts with an "isolation_relief" module aboard.
const ISOLATION_RELIEF: float = 0.75

## Ship-wide conditions set by alerts with a "<name>_days" effect. They last
## that many nights, tonight included ("night": effects applied every night).
const CONDITIONS: Dictionary[String, Dictionary] = {
    "blackout": {"name": "Blackout", "start": "Main power is off: modules that need power stay dark and life support runs on backup.",
        "end": "Main power is back on."},
    "rationing": {"name": "Rationing", "start": "Strict rationing: half meals and half water for everyone.",
        "end": "Rationing is over.", "night": {"crew_stress": 2}},
    "sluggish": {"name": "Sluggish crew", "start": "The crew is sluggish: everything takes twice as long.",
        "end": "The crew is back up to speed."},
    "comms_down": {"name": "Radio down", "start": "The radio is down: calls home won't get through.",
        "end": "The radio is working again."},
    "cold": {"name": "Freezing", "start": "The heating is off and the cabin is freezing.",
        "end": "The heating is back on.", "night": {"crew_stress": 3, "crew_health": -3}},
}

## Event effects that pick modules by domain: "break_energy",
## "lose_communication_or_navigation", "offline_navigation", "break_any".
const MODULE_EFFECTS: Array[String] = ["break_", "lose_", "offline_"]

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
## Every card aboard, in cargo order.
var modules: Array[ShipModule] = []
## The radio is down today: calls home don't get through.
var comms_down: bool = false
## Extra hazard chance for today (navigation glitches).
var hazard_up_today: float = 0.0
## Alerts the crew can still redraw (Star tracker).
var rerolls_left: int = 0
## Day from which a bad alert can be cancelled again (AutoNav).
var _cancel_ready_day: int = 1
## Active CONDITIONS: name -> nights left (tonight included).
var conditions: Dictionary[String, int] = {}
## Modules were added or lost during the day (the view rebuilds its list).
var modules_changed: bool = false

## The crew member resolving the current event choice ("worker_*" effects).
var _worker: CrewMember = null
## Crew members going into cryosleep tonight.
var _cryosleep: Array[CrewMember] = []

var _event_pool: Array[MissionEvent] = []
var _all_events: Array[MissionEvent] = []
var _day_start_resources: Dictionary[String, int] = {}
var _day_start_science: int = 0
var _feed: PackedStringArray = []
var _power_short: bool = false
## Stations someone worked at today (they draw power at night).
var _stations_used: Dictionary[String, bool] = {}
## Fractions carried between hours: "water", "science", "<member id>:stress"...
var _accum: Dictionary[String, float] = {}
## Hours spent on a module repair / curing sickness.
var _repair_hours: float = 0.0
var _cure_hours: Dictionary[CrewMember, float] = {}


func _init(_scenario_name: String, _mission_days: int, event_pool: Array[MissionEvent], augments: Array[AugmentInstance]) -> void:
    scenario_name = _scenario_name
    mission_days = _mission_days
    _event_pool = event_pool.duplicate()
    _all_events = event_pool.duplicate()
    capacities = DEFAULT_CAPACITIES.duplicate()
    resources = DEFAULT_START.duplicate()
    for entry in DEFAULT_CREW:
        var member := CrewMember.new(entry[0], entry[1])
        member.skill = entry[2]
        member.station = entry[3]
        crew.append(member)
    _apply_augments(augments)
    for module in modules:
        rerolls_left += module.augment.event_rerolls


static func load_event_pool(dir_path: String = "res://data/events") -> Array[MissionEvent]:
    var pool: Array[MissionEvent] = []
    for file in ResourceLoader.list_directory(dir_path):
        var res := load(dir_path.path_join(file))
        if res is MissionEvent:
            pool.append(res)
    return pool


func _apply_augments(augments: Array[AugmentInstance]) -> void:
    var cargo: Array[Augment] = []
    for i in augments.size():
        modules.append(ShipModule.new(augments[i].augment, i))
        cargo.append(augments[i].augment)
    # [key, amount] pairs: the upgrades, plus the launch synergies of cards
    # whose partner is in the cargo (same rule as LaunchProfile).
    var changes: Array[Array] = []
    for instance in augments:
        var augment := instance.augment
        for key in augment.upgrades.keys():
            changes.append([key, instance.upgrade_amount(key)])
        if not augment.launch_synergy.is_empty() and cargo.any(func(a: Augment): return a != augment and augment.is_synergy_partner(a)):
            for key in augment.launch_synergy.keys():
                changes.append([key, Augment.parse_range(augment.launch_synergy[key]).x])
    # Stock first, one-time costs after, so the order of the cards
    # doesn't matter.
    for pass_costs: bool in [false, true]:
        for change in changes:
            var key: String = change[0]
            var amount: int = change[1]
            if (amount < 0) != pass_costs:
                continue
            if key.ends_with("_capacity") and capacities.has(key.trim_suffix("_capacity")):
                capacities[key.trim_suffix("_capacity")] += amount
            elif resources.has(key):
                if amount > 0:
                    capacities[key] += amount
                resources[key] = maxi(0, resources[key] + amount)
            elif key == "mission_days":
                mission_days = maxi(1, mission_days + amount)
            # "fuel" / "engine_thrust" only matter for the launch.


static func resource_name(res_id: String) -> String:
    return RESOURCE_INFO.get(res_id, {}).get("name", res_id.capitalize())


static func unit(res_id: String) -> String:
    return RESOURCE_INFO.get(res_id, {}).get("unit", "")


## "+5 L water", "-1 kWh", "+1 meal", "-3 % hull".
static func amount_text(res_id: String, amount: int) -> String:
    match res_id:
        "water":
            return "%+d L water" % amount
        "oxygen":
            return "%+d kg oxygen" % amount
        "food":
            return "%+d meal%s" % [amount, "" if absi(amount) == 1 else "s"]
        "power":
            return "%+d kWh" % amount
        "hull":
            return "%+d%% hull" % amount
    return "%+d %s" % [amount, resource_name(res_id).to_lower()]


# --- Modules --------------------------------------------------------------------

func neighbours(module: ShipModule) -> Array[ShipModule]:
    var result: Array[ShipModule] = []
    for other in modules:
        if absi(other.index - module.index) == 1:
            result.append(other)
    return result


## A working module aboard carries this flag (see Augment.FLAG_TEXT).
func has_flag(flag: StringName) -> bool:
    for module in modules:
        if module.enabled and not module.broken and not module.lost and module.augment.has_flag(flag):
            return true
    return false


## How many related cards count for the module's synergy bonus.
func synergy_count(module: ShipModule) -> int:
    var augment := module.augment
    if augment.synergy_daily.is_empty():
        return 0
    var pool: Array[ShipModule] = neighbours(module) if augment.synergy_adjacent else modules
    var count := 0
    for other in pool:
        if other != module and not other.lost and augment.is_synergy_partner(other.augment):
            count += 1
    return mini(count, augment.synergy_max)


## What the module does tonight if it works: its daily effects plus synergy
## (nothing once its `daily_days` are over).
func module_daily(module: ShipModule) -> Dictionary[String, int]:
    if module.augment.daily_days > 0 and day > module.augment.daily_days:
        return {}
    var effects: Dictionary[String, int] = module.augment.daily.duplicate()
    var bonus := synergy_count(module)
    for key in module.augment.synergy_daily.keys():
        effects[key] = effects.get(key, 0) + module.augment.synergy_daily[key] * bonus
    return effects


func extra_water_per_crew() -> int:
    var extra := 0
    for module in modules:
        if module.working():
            extra += module_daily(module).get("crew_water", 0)
    return extra


## A working, powered "infinite_food" module feeds the crew: no meals are
## taken from the pantry.
func feeds_crew() -> bool:
    return modules.any(func(m: ShipModule): return m.working() and not m.unpowered and m.augment.has_flag(&"infinite_food"))


func water_need(member: CrewMember) -> int:
    var need := WATER_PER_CREW + extra_water_per_crew() + (WATER_PER_CREW if member.sick else 0)
    return ceili(need / 2.0) if has_condition("rationing") else need


func _risk_blocked(risk: CardRisk) -> bool:
    return risk.blocked_by != &"" and has_flag(risk.blocked_by)


func _trigger_risk(module: ShipModule, risk: CardRisk) -> void:
    if risk.log_text != "":
        _log("[color=#ffb35c]%s[/color]" % risk.log_text.replace("{module}", module.augment.card_name()))
    apply_effects(risk.effects)
    if risk.permanent:
        module.lost = true
    elif risk.breaks_module:
        module.broken = true
    if risk.offline_today:
        module.offline_today = true
    if risk.cuts_comms and not has_flag(&"laser_comms"):
        comms_down = true
    hazard_up_today += risk.hazard_up


## Chance of a risk for this module, after neighbours and modules that
## soften it.
func risk_chance(module: ShipModule, risk: CardRisk) -> float:
    var chance := risk.chance
    if risk.adjacent_chance >= 0.0 and _next_to_domain(module, risk.domain):
        chance = risk.adjacent_chance
    if risk.halved_by != &"" and has_flag(risk.halved_by):
        chance *= 0.5
    return chance


func _next_to_domain(module: ShipModule, domain: Augment.Domain) -> bool:
    return neighbours(module).any(func(n: ShipModule): return not n.lost and n.augment.domain == domain)


## Morning checks: modules that misbehave on a schedule.
func _morning_risks() -> void:
    for module in modules:
        if module.lost or module.broken or not module.enabled:
            continue
        for risk in module.augment.risks:
            if risk.condition == CardRisk.Condition.EVERY_N_DAYS and risk.every_days > 0 \
                    and day % risk.every_days == 0 and not _risk_blocked(risk) and randf() < risk_chance(module, risk):
                _trigger_risk(module, risk)


## Night checks for every other kind of risk.
func _night_risks() -> void:
    for module in modules:
        if module.lost or module.broken or not module.enabled:
            continue
        for risk in module.augment.risks:
            if _risk_blocked(risk):
                continue
            var condition_met := false
            match risk.condition:
                CardRisk.Condition.ANY_DAY:
                    condition_met = true
                CardRisk.Condition.ADJACENT_DOMAIN:
                    condition_met = _next_to_domain(module, risk.domain)
                CardRisk.Condition.POWER_SHORTAGE:
                    condition_met = _power_short
                CardRisk.Condition.POWER_FULL:
                    condition_met = resources["power"] >= capacities["power"]
                CardRisk.Condition.WATER_BELOW:
                    condition_met = resources["water"] < risk.threshold
                CardRisk.Condition.ON_DAY:
                    condition_met = day == risk.threshold
            if condition_met and randf() < risk_chance(module, risk):
                _trigger_risk(module, risk)
                if module.lost or module.broken:
                    break


## Notes about how the cargo order affects the modules, for the plan phase.
func adjacency_notes() -> PackedStringArray:
    var notes: PackedStringArray = []
    for module in modules:
        for risk in module.augment.risks:
            if risk.condition == CardRisk.Condition.ADJACENT_DOMAIN \
                    and neighbours(module).any(func(n: ShipModule): return n.augment.domain == risk.domain):
                notes.append("%s is next to an %s card. Risk: %s" % [module.augment.card_name(), Augment.Domain.keys()[risk.domain].capitalize(), risk.short_text.to_lower()])
            elif risk.adjacent_chance >= 0.0 and neighbours(module).any(func(n: ShipModule): return n.augment.domain == risk.domain):
                notes.append("%s is next to an %s card: %d%% risk instead of %d%%" % [module.augment.card_name(),
                    Augment.Domain.keys()[risk.domain].capitalize(), roundi(risk.adjacent_chance * 100.0), roundi(risk.chance * 100.0)])
        if module.augment.synergy_adjacent and not module.augment.synergy_daily.is_empty():
            notes.append("%s links %d %s card%s" % [module.augment.card_name(), synergy_count(module),
                Augment.Domain.keys()[module.augment.synergy_domain].capitalize(), "" if synergy_count(module) == 1 else "s"])
    return notes


# --- Live feed ------------------------------------------------------------------

func _log(line: String) -> void:
    _feed.append(line)


## Everything that happened since the last call (BBCode lines).
func drain_log() -> PackedStringArray:
    var lines := _feed
    _feed = []
    return lines


func crew_aboard() -> Array[CrewMember]:
    return crew.filter(func(c: CrewMember): return c.is_aboard())


## Modules that do something aboard (launch hardware and deck cards left
## out).
func ship_modules() -> Array[ShipModule]:
    return modules.filter(func(m: ShipModule): return not m.augment.is_launch_only())


func _update_stress_cap() -> void:
    var cap := Augment.MORALE_FLOOR_STRESS if has_flag(&"morale_floor") else CrewMember.MAX_STRESS
    for member in crew:
        member.stress_cap = cap
        member.stress = mini(member.stress, cap)


# --- Day flow -----------------------------------------------------------------

func start_day() -> void:
    _day_start_resources = resources.duplicate()
    _day_start_science = science
    _stations_used.clear()
    comms_down = has_condition("comms_down") or has_condition("blackout")
    hazard_up_today = 0.0
    for module in modules:
        module.offline_today = false
    _morning_risks()
    _update_stress_cap()


## Today's alerts: [{hour, event}]. Always one on day 1, then a morning one
## (EVENT_CHANCE) and an afternoon one (SECOND_EVENT_CHANCE).
func plan_alerts() -> Array[Dictionary]:
    var schedule: Array[Dictionary] = []
    if day == 1 or randf() < EVENT_CHANCE:
        var event := draw_event()
        if event != null:
            schedule.append({"hour": randf_range(9.5, 12.5) if day > 1 else 9.5, "event": event})
    if day > 1 and randf() < SECOND_EVENT_CHANCE:
        var event := draw_event()
        if event != null:
            schedule.append({"hour": randf_range(13.0, 15.5), "event": event})
    return schedule


## Picks a random alert for today, or null. Events don't repeat until every
## available one has happened. Navigation cards can steer the ship clear of a
## hazard (null), glitching ones can lead it into one.
func draw_event() -> MissionEvent:
    var event := _draw(func(_e: MissionEvent): return true)
    if event == null:
        return null
    var change := hazard_change()
    if event.tags.has(&"hazard") and change < 0.0 and randf() < -change:
        _log("[color=#7cf08a]Navigation spotted trouble early and steered around it: \"%s\" avoided.[/color]" % event.title)
        return null
    if not event.tags.has(&"hazard") and change > 0.0 and randf() < change:
        var hazard := _draw(func(e: MissionEvent): return e.tags.has(&"hazard"))
        if hazard != null:
            _event_pool.append(event)
            return hazard
    return event


func _draw(filter: Callable) -> MissionEvent:
    var candidates := _event_pool.filter(func(e: MissionEvent): return e.min_day <= day and filter.call(e))
    if candidates.is_empty() and not _all_events.is_empty():
        for e in _all_events:
            if not _event_pool.has(e):
                _event_pool.append(e)
        candidates = _event_pool.filter(func(e: MissionEvent): return e.min_day <= day and filter.call(e))
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


## How much more (positive) or less (negative) likely hazard alerts are
## today, from the Navigation cards.
func hazard_change() -> float:
    var reduction := 0.0
    var cap := Augment.DEFAULT_HAZARD_CAP
    for module in modules:
        if module.working() and not module.unpowered and module.augment.hazard_reduction > 0.0:
            reduction += module.augment.hazard_reduction
            cap = maxf(cap, module.augment.hazard_cap)
    return hazard_up_today - minf(reduction, cap)


## Star tracker: swap an alert for another one.
func can_reroll() -> bool:
    return rerolls_left > 0 and modules.any(func(m: ShipModule): return m.augment.event_rerolls > 0 and m.working())


func reroll_event(event: MissionEvent) -> MissionEvent:
    if not can_reroll():
        return null
    var other := _draw(func(e: MissionEvent): return e != event)
    if other == null:
        return null
    rerolls_left -= 1
    return other


## AutoNav: wave a bad alert away, once every few days.
func cancel_cooldown() -> int:
    var every := 0
    for module in modules:
        if module.working() and not module.unpowered and module.augment.cancel_every_days > 0:
            every = module.augment.cancel_every_days if every == 0 else mini(every, module.augment.cancel_every_days)
    return every


func can_cancel(event: MissionEvent) -> bool:
    return cancel_cooldown() > 0 and day >= _cancel_ready_day and not event.tags.has(&"good")


## Days until the AutoNav can cancel again (0 = ready).
func cancel_wait() -> int:
    return maxi(0, _cancel_ready_day - day)


func cancel_event(event: MissionEvent) -> bool:
    if not can_cancel(event):
        return false
    _cancel_ready_day = day + cancel_cooldown()
    return true


func can_afford(cost: Dictionary) -> bool:
    for key in cost.keys():
        if resources.get(key, 0) < cost[key]:
            return false
    return true


## The choice can be picked: its cost can be paid and the module it needs
## (if any) is working.
func can_choose(choice: EventChoice) -> bool:
    return can_afford(choice.cost) and (choice.requires_domain < 0 or has_working_domain(choice.requires_domain))


func has_working_domain(domain: int) -> bool:
    return modules.any(func(m: ShipModule): return m.working() and m.augment.domain == domain)


func has_condition(name: String) -> bool:
    return conditions.get(name, 0) > 0


func can_use_medkit(member: CrewMember) -> bool:
    return member.is_aboard() and resources["medkits"] > 0 and (member.sick or member.health < CrewMember.MAX_HEALTH)


func use_medkit(member: CrewMember) -> void:
    if not can_use_medkit(member):
        return
    resources["medkits"] -= 1
    member.heal(MEDKIT_HEAL)
    member.sick = false
    _cure_hours.erase(member)
    _log("%s was patched up with a medkit." % member.display_name)


# --- Stations -------------------------------------------------------------------

static func station_name(station: String) -> String:
    return STATIONS.get(station, {}).get("name", "corridor")


func is_skilled_at(member: CrewMember, station: String) -> bool:
    return member.skill != "" and STATIONS.get(station, {}).get("skill", "") == member.skill


## How fast the member works at a station (1.0 = normal).
func work_rate(member: CrewMember, station: String) -> float:
    var rate := SKILL_BONUS if is_skilled_at(member, station) else 1.0
    if member.is_overwhelmed():
        rate *= OVERWHELMED_EFFICIENCY
    if has_condition("sluggish"):
        rate *= 0.5
    return rate


## Adds a fractional amount; returns the whole part to apply now.
func _accumulate(key: String, amount: float) -> int:
    var total: float = _accum.get(key, 0.0) + amount
    var whole := int(total)
    _accum[key] = total - whole
    return whole


func _member_key(member: CrewMember, what: String) -> String:
    return "%d:%s" % [crew.find(member), what]


func _stress(member: CrewMember, per_hour: float, hours: float) -> void:
    member.add_stress(_accumulate(_member_key(member, "stress"), per_hour * hours))


func _health(member: CrewMember, per_hour: float, hours: float) -> void:
    var amount := _accumulate(_member_key(member, "health"), per_hour * hours)
    if amount > 0:
        member.heal(amount)
    elif amount < 0:
        member.damage(-amount)


## Time spent by a crew member at their current station during the day.
func work(member: CrewMember, hours: float) -> void:
    if not member.is_aboard() or hours <= 0.0:
        return
    var station := member.station
    if not STATIONS.has(station):
        return
    _stations_used[station] = true
    var rate := work_rate(member, station)
    match station:
        "bunks":
            _health(member, REST_HEAL_PER_HOUR * (0.4 if member.sick else 1.0), hours)
            _stress(member, -REST_STRESS_PER_HOUR, hours)
        "medbay":
            var medic_present := crew.any(func(c: CrewMember): return c.is_aboard() and c.station == "medbay" and c.skill == "medical")
            _health(member, MEDBAY_HEAL_PER_HOUR * (SKILL_BONUS if medic_present else 1.0), hours)
            _stress(member, -REST_STRESS_PER_HOUR * 0.5, hours)
            if member.sick:
                if resources["medkits"] > 0:
                    use_medkit(member)
                else:
                    _cure_hours[member] = _cure_hours.get(member, 0.0) + hours * (SKILL_BONUS if medic_present else 1.0)
                    if _cure_hours[member] >= MEDBAY_CURE_HOURS * 2.0:
                        member.sick = false
                        _cure_hours.erase(member)
                        _log("%s feels much better after a long rest in the medbay." % member.display_name)
        "comms":
            if comms_down:
                _stress(member, -CUPOLA_STRESS_PER_HOUR * 0.3, hours)
            else:
                _stress(member, -COMMS_STRESS_PER_HOUR, hours)
        "cupola":
            _stress(member, -CUPOLA_STRESS_PER_HOUR, hours)
        "lab":
            var gained := _accumulate("science", SCIENCE_PER_HOUR * rate * hours)
            if gained > 0:
                science += gained
                _log("%s made a discovery in the lab! [color=#b46cff]+%d science[/color]" % [member.display_name, gained])
            _stress(member, WORK_STRESS_PER_HOUR, hours)
        "engineering":
            var broken := _broken_module()
            if broken != null:
                _repair_hours += rate * hours
                if _repair_hours >= MODULE_REPAIR_HOURS:
                    _repair_hours = 0.0
                    broken.broken = false
                    _log("%s repaired the %s. It's working again!" % [member.display_name, broken.augment.card_name()])
            elif resources["hull"] < capacities["hull"]:
                resources["hull"] = mini(capacities["hull"], resources["hull"] + _accumulate("hull", HULL_REPAIR_PER_HOUR * rate * hours))
            _stress(member, WORK_STRESS_PER_HOUR, hours)
        "life_support":
            resources["water"] += _accumulate("water", RECYCLE_WATER_PER_HOUR * rate * hours)
            resources["oxygen"] += _accumulate("oxygen", RECYCLE_OXYGEN_PER_HOUR * rate * hours)
            _clamp_resources()
            _stress(member, WORK_STRESS_PER_HOUR, hours)


# --- Alerts ---------------------------------------------------------------------

func is_skilled_for(member: CrewMember, event: MissionEvent) -> bool:
    return event.skill != "" and member.skill == event.skill


## Chance that `member` pulls off `choice`.
func event_chance(event: MissionEvent, choice: EventChoice, member: CrewMember) -> float:
    if choice.success_chance >= 1.0:
        return 1.0
    var chance := choice.success_chance
    if member != null:
        if is_skilled_for(member, event):
            chance += EVENT_SKILL_BONUS
        chance -= member.stress / 100.0 * EVENT_STRESS_PENALTY
        if member.sick:
            chance -= EVENT_SICK_PENALTY
    return clampf(chance, 0.05, 0.98)


## Hours of work the choice takes for `member`.
func event_hours(event: MissionEvent, choice: EventChoice, member: CrewMember) -> float:
    var hours := choice.work_hours
    if is_skilled_for(member, event):
        hours /= SKILL_BONUS
    if member.is_overwhelmed():
        hours /= OVERWHELMED_EFFICIENCY
    if has_condition("sluggish"):
        hours *= 2.0
    return hours


## Pays the choice's cost. False if the ship can't afford it.
func begin_event_choice(choice: EventChoice) -> bool:
    if not can_choose(choice):
        return false
    for key in choice.cost.keys():
        resources[key] -= choice.cost[key]
    return true


## Rolls and applies the outcome. Returns {success: bool, text: String}.
func finish_event_choice(event: MissionEvent, choice: EventChoice, member: CrewMember) -> Dictionary:
    var success := randf() < event_chance(event, choice, member)
    var effects: Dictionary = (choice.success_effects if success else choice.failure_effects).duplicate()
    if event.tags.has(&"isolation") and has_flag(&"isolation_relief"):
        for key in ["crew_stress", "random_crew_stress"]:
            if effects.get(key, 0) > 0:
                effects[key] = roundi(effects[key] * ISOLATION_RELIEF)
    _worker = member
    apply_effects(effects)
    _worker = null
    if member != null:
        member.add_stress(EVENT_WORK_STRESS)
    _clamp_resources()
    return {"success": success, "text": choice.success_text if success else choice.failure_text}


## Nobody answered the alert in time: the crew falls back on its last option.
func ignore_event(event: MissionEvent) -> Dictionary:
    var fallback: EventChoice = event.choices[-1]
    if not begin_event_choice(fallback):
        return {"success": false, "text": ""}
    return finish_event_choice(event, fallback, null)


## Expected resource change for tonight (ignores alerts and module risks).
func forecast() -> Dictionary[String, int]:
    var delta: Dictionary[String, int] = {}
    for res_id in RESOURCE_IDS:
        delta[res_id] = 0
    var aboard := crew_aboard()
    for module in modules:
        if module.working():
            var effects := module_daily(module)
            for key in effects.keys():
                if delta.has(key):
                    delta[key] += effects[key]
    delta["power"] += SOLAR_POWER_PER_DAY - LIFE_SUPPORT_POWER - _powered_stations_used()
    delta["oxygen"] -= aboard.size() * OXYGEN_PER_CREW
    delta["hull"] -= HULL_DECAY_PER_DAY
    if resources["hull"] < HULL_LEAK_THRESHOLD:
        delta["oxygen"] -= 1
    var fed := feeds_crew()
    for member in aboard:
        delta["water"] -= water_need(member)
    if not fed:
        var meals := aboard.size() * FOOD_PER_CREW
        delta["food"] -= ceili(meals / 2.0) if has_condition("rationing") else meals
    if has_condition("blackout"):
        delta["power"] = -resources["power"]
    return delta


func _powered_stations_used() -> int:
    var count := 0
    for station in _stations_used.keys():
        if STATIONS[station]["power"]:
            count += 1
    return count


func _broken_module() -> ShipModule:
    for module in modules:
        if module.broken and not module.lost:
            return module
    return null


## Runs the modules for the night. Modules without costs go first; a module
## whose costs can't be paid shuts down for the night.
func _run_modules() -> void:
    var aboard := crew_aboard()
    var running := modules.filter(func(m: ShipModule): return m.working())
    running.sort_custom(func(a: ShipModule, b: ShipModule): return _cost_count(a) < _cost_count(b))
    for module: ShipModule in running:
        var effects := module_daily(module)
        if has_condition("blackout") and effects.get("power", 0) < 0:
            module.unpowered = true
            continue
        var missing := ""
        for key in effects.keys():
            if resources.has(key) and effects[key] < 0 and resources[key] < -effects[key]:
                missing = resource_name(key).to_lower()
                break
        if missing != "":
            _log("The %s stayed off tonight: not enough %s." % [module.augment.card_name(), missing])
            module.unpowered = true
            continue
        module.unpowered = false
        for key in effects.keys():
            if resources.has(key):
                resources[key] += effects[key]
            elif key == "crew_stress":
                for member in aboard:
                    member.add_stress(effects[key])
        _clamp_resources()


func _cost_count(module: ShipModule) -> int:
    var count := 0
    for value in module.augment.daily.values():
        if value < 0:
            count += 1
    return count


## Resolves the night and returns a recap dictionary for the UI:
## { day, resources: {id: [before, after]}, science: [before, after],
##   sent_home: Array[{name, reason}], outcome }
## Night events go to the live feed (drain_log()).
func end_day() -> Dictionary:
    var recap := {"day": day}
    var aboard := crew_aboard()

    # 1. Ship modules, then the capsule's own solar wings and life support.
    _run_modules()
    if has_condition("blackout"):
        resources["power"] = 0
        _power_short = true
    else:
        resources["power"] += SOLAR_POWER_PER_DAY
        var station_power := _powered_stations_used()
        resources["power"] = maxi(0, resources["power"] - station_power)
        _power_short = resources["power"] < LIFE_SUPPORT_POWER and not has_flag(&"stable_power")
        resources["power"] = maxi(0, resources["power"] - LIFE_SUPPORT_POWER)
    if _power_short:
        _log("[color=#ffb35c]Not enough power: life support switched to backup mode and used extra oxygen.[/color]")

    # 2. Meals and water, then a night's sleep.
    var fed := feeds_crew()
    for member in aboard:
        var meal := FOOD_PER_CREW
        if has_condition("rationing"):
            meal = _accumulate("ration_meal", FOOD_PER_CREW * 0.5)
        if fed or meal == 0:
            member.days_hungry = 0
        elif resources["food"] >= meal:
            resources["food"] -= meal
            member.days_hungry = 0
        else:
            _log("The pantry ran out before %s got a meal." % member.display_name)
            member.days_hungry += 1
            member.add_stress(HUNGER_STRESS)
        var need := water_need(member)
        if resources["water"] >= need:
            resources["water"] -= need
            member.days_thirsty = 0
        else:
            _log("The water tank ran dry before %s got a drink." % member.display_name)
            member.days_thirsty += 1
            member.add_stress(THIRST_STRESS)
        # Nobody sleeps well hungry, thirsty or sick.
        if not member.sick and member.days_hungry == 0 and member.days_thirsty == 0:
            member.heal(SLEEP_HEAL)
            member.add_stress(-SLEEP_STRESS_RELIEF)

    # 3. Breathing, hull wear.
    var oxygen_needed := aboard.size() * OXYGEN_PER_CREW + (BACKUP_OXYGEN if _power_short else 0)
    if resources["hull"] < HULL_LEAK_THRESHOLD:
        oxygen_needed += 1
        _log("[color=#ffb35c]The worn-out hull is leaking a little air. The crew is getting nervous.[/color]")
        for member in aboard:
            member.add_stress(HULL_DAMAGE_STRESS)
    resources["oxygen"] -= oxygen_needed
    if resources["oxygen"] < 0:
        resources["oxygen"] = 0
        _log("[color=#ff5a6e]The oxygen tanks ran low! The air feels thin and everyone is short of breath.[/color]")
        for member in aboard:
            member.damage(NO_AIR_DAMAGE)
            member.add_stress(LOW_AIR_STRESS)
    resources["hull"] -= HULL_DECAY_PER_DAY
    _clamp_resources()

    # 4. Things that can go wrong with the modules.
    _night_risks()

    # 5. Body condition.
    for member in aboard:
        if member.days_hungry > 0:
            member.damage(HUNGER_DAMAGE[mini(member.days_hungry, 2) - 1])
        if member.days_thirsty > 0:
            member.damage(THIRST_DAMAGE[mini(member.days_thirsty, 2) - 1])
        if member.sick:
            member.damage(6)
            member.add_stress(SICK_STRESS)
        elif member.health < 50 and randf() < 0.15:
            member.sick = true
            _log("%s is feeling unwell." % member.display_name)
    _clamp_resources()

    for member in aboard:
        member.add_stress(HOMESICK_STRESS)

    # Conditions that weigh on the crew every night.
    for name in conditions.keys():
        if conditions[name] > 0 and CONDITIONS[name].has("night"):
            apply_effects(CONDITIONS[name]["night"])

    # 6. Anyone at their limit flies home safely.
    var sent_home: Array[Dictionary] = []
    for member in aboard:
        var reason := ""
        if _cryosleep.has(member):
            reason = "went into cryosleep to recover"
        elif member.health <= 0:
            reason = "needed to see a doctor back on Earth"
        elif member.stress >= CrewMember.MAX_STRESS:
            reason = "needed a break from space"
        if reason != "":
            member.send_home(reason)
            sent_home.append({"name": member.display_name, "reason": reason})

    _cryosleep.clear()
    for name in conditions.keys():
        conditions[name] -= 1
        if conditions[name] <= 0:
            conditions.erase(name)
            _log(CONDITIONS[name]["end"])

    # 7. Mission state.
    if crew_aboard().size() < MIN_CREW:
        for member in crew_aboard():
            member.send_home("couldn't fly the ship alone")
            sent_home.append({"name": member.display_name, "reason": "couldn't fly the ship alone"})
        outcome = Outcome.LOST
        outcome_text = "On day %d there weren't enough hands left to fly the ship, so the last of the crew flew home in the return capsule. The mission was called off, but everyone is safe and sound back on Earth." % day
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
    recap["sent_home"] = sent_home
    recap["outcome"] = outcome

    day += 1
    return recap


func apply_effects(effects: Dictionary) -> void:
    for key in effects.keys():
        var amount: int = effects[key]
        if resources.has(key):
            resources[key] += amount
        elif key.ends_with("_days") and CONDITIONS.has(key.trim_suffix("_days")):
            var name: String = key.trim_suffix("_days")
            if not has_condition(name):
                _log("[color=#ffb35c]%s[/color]" % CONDITIONS[name]["start"])
            conditions[name] = maxi(conditions.get(name, 0), amount)
            if name in ["comms_down", "blackout"]:
                comms_down = true
        elif MODULE_EFFECTS.any(func(prefix: String): return key.begins_with(prefix)):
            _module_effect(key, amount)
        elif key == "repair_module":
            for i in amount:
                var broken := _broken_module()
                if broken == null:
                    break
                broken.broken = false
                _log("The %s is fixed and working again." % broken.augment.card_name())
        elif key == "gain_mythic":
            for i in amount:
                _gain_random_card(Augment.Rarity.MYTHIC)
        elif key == "random_resource":
            var res_id: String = ["oxygen", "water", "food", "power"].pick_random()
            resources[res_id] += amount
            _log("%s: %s." % [resource_name(res_id), amount_text(res_id, amount)])
        elif key == "sick_all":
            for member in crew_aboard():
                if not member.sick:
                    member.sick = true
            _log("[color=#ff5a6e]The whole crew is feeling unwell.[/color]")
        elif key == "cryosleep":
            var member := _most_stressed()
            if member != null and not _cryosleep.has(member):
                _cryosleep.append(member)
                _log("%s will go into cryosleep tonight." % member.display_name)
        elif key == "worker_health" or key == "worker_stress":
            var member := _worker if _worker != null and _worker.is_aboard() else _random_aboard()
            if member:
                if key == "worker_health":
                    _change_health(member, amount)
                else:
                    member.add_stress(amount)
        elif key == "most_stressed_stress":
            var member := _most_stressed()
            if member:
                member.add_stress(amount)
        elif key.begins_with("stress_") and SKILL_NAMES.has(key.trim_prefix("stress_")):
            for member in crew_aboard():
                if member.skill == key.trim_prefix("stress_"):
                    member.add_stress(amount)
        elif key.ends_with("_percent") and resources.has(key.trim_suffix("_percent")):
            var res_id: String = key.trim_suffix("_percent")
            resources[res_id] += roundi(resources[res_id] * amount / 100.0)
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
                _log("%s %s." % [member.display_name, "feels better" if amount > 0 else "is worn out"])
        elif key == "random_crew_stress":
            var member := _random_aboard()
            if member:
                member.add_stress(amount)
                _log("%s %s." % [member.display_name, "is feeling more relaxed" if amount < 0 else "is feeling stressed"])
        elif key == "random_crew_sick":
            var healthy := crew_aboard().filter(func(c: CrewMember): return not c.sick)
            if not healthy.is_empty():
                var member: CrewMember = healthy.pick_random()
                member.sick = true
                _log("%s is feeling unwell." % member.display_name)
        else:
            push_warning("Unknown event effect key: %s" % key)
    _clamp_resources()


func _most_stressed() -> CrewMember:
    var best: CrewMember = null
    for member in crew_aboard():
        if not _cryosleep.has(member) and (best == null or member.stress > best.stress):
            best = member
    return best


## "break_energy" (needs a repair), "lose_any" (gone for good),
## "offline_navigation" (no output today). Domains can be joined with "_or_".
func _module_effect(key: String, count: int) -> void:
    var prefix := ""
    for p in MODULE_EFFECTS:
        if key.begins_with(p):
            prefix = p
    var domains: Array[int] = []
    var any := false
    for part in key.trim_prefix(prefix).split("_or_"):
        if part == "any":
            any = true
        elif Augment.Domain.has(part.to_upper()):
            domains.append(Augment.Domain[part.to_upper()])
        else:
            push_warning("Unknown domain in event effect: %s" % key)
    for i in maxi(count, 1):
        var targets := ship_modules().filter(func(m: ShipModule): return m.working() and (any or domains.has(m.augment.domain)))
        if targets.is_empty():
            return
        var module: ShipModule = targets.pick_random()
        var name := module.augment.card_name()
        match prefix:
            "break_":
                module.broken = true
                _log("[color=#ffb35c]The %s broke down. Someone needs to repair it at the power core.[/color]" % name)
            "lose_":
                module.lost = true
                _log("[color=#ff5a6e]The %s is gone for good.[/color]" % name)
            "offline_":
                module.offline_today = true
                _log("The %s is busy and offline for the rest of the day." % name)
        modules_changed = true


## A random card (not launch-only) joins the ship as a new module, with its
## supplies.
func _gain_random_card(rarity: Augment.Rarity) -> void:
    var pool: Array[Augment] = []
    for augment in Augment.all_cards():
        if augment.rarity == rarity and not augment.is_launch_only():
            pool.append(augment)
    if pool.is_empty():
        return
    var instance := AugmentInstance.new(pool.pick_random(), "")
    instance.roll()
    var module := ShipModule.new(instance.augment, modules.size())
    modules.append(module)
    for key in instance.augment.upgrades.keys():
        var amount := instance.upgrade_amount(key)
        if resources.has(key):
            if amount > 0:
                capacities[key] += amount
            resources[key] = maxi(0, resources[key] + amount)
        elif key.ends_with("_capacity") and capacities.has(key.trim_suffix("_capacity")):
            capacities[key.trim_suffix("_capacity")] += amount
    rerolls_left += instance.augment.event_rerolls
    modules_changed = true
    _log("[color=#ffb800]New module aboard: %s![/color]" % instance.augment.card_name())


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
