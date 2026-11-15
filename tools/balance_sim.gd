extends SceneTree
## Headless balance simulation of the whole scenario: plan phase (card offers,
## Logistics actions), launch (a failed launch goes back to planning, as in the
## game) and the real-time mission, played by a bot that acts like a
## reasonable first-time player.
##
## Run (from the project root):
##   $GODOT --headless --path . -s tools/balance_sim.gd -- [runs] [player]
## player: "casual" (default), "careful" or "idle" (never touches anything).
##
## The mission loop mirrors scenes/mission_phase/mission_phase.gd: alerts come
## from MissionState.plan_alerts(), wait EVENT_DEADLINE_HOURS for someone,
## then fall back on their last choice; assigned crew walk there, work, and
## everything unfinished wraps up at 20:00.

const AUGMENTS: Registry = preload("res://data/augments/augments.tres")

## Same as the scenario (select_scenario.gd). Can be overridden: 4th argument.
const SLOTS: int = 27
const MISSION_DAYS: int = 10
const STEP_HOURS: float = 0.25
## Walking between rooms (plus the radio chatter before they move).
const WALK_HOURS: float = 0.6

const HOME_STATIONS: Dictionary[String, String] = {
    "command": "comms", "medical": "medbay", "engineering": "engineering", "science": "lab",
}

## How the bot plays: chance to answer an alert, delay before reacting
## (game hours), chance to pick a random option instead of the best one,
## chance to make a random pick in the plan phase, chance per game hour to
## look at the crew and move people around (0 = never).
##   careful: attentive player who reads everything.
##   casual:  first-time player, the one the balance targets (~60% wins).
##   idle:    clicks nothing: random cards, no alerts, no crew orders.
const PLAYERS: Dictionary[String, Dictionary] = {
    "careful": {"respond": 0.95, "react": [0.2, 1.0], "random_choice": 0.05, "random_pick": 0.1, "manage": 1.0, "toggles": true},
    "casual": {"respond": 0.75, "react": [0.3, 2.5], "random_choice": 0.25, "random_pick": 0.35, "manage": 0.35, "toggles": false},
    "idle": {"respond": 0.0, "react": [0.0, 0.0], "random_choice": 1.0, "random_pick": 1.0, "manage": 0.0, "toggles": false},
}

var player: Dictionary
var all_cards: Array[Augment] = []
var stats: Dictionary = {}
var trace: bool = false
var slots_total: int = SLOTS


func _init() -> void:
    var args := OS.get_cmdline_user_args()
    var runs := int(args[0]) if args.size() > 0 else 300
    var player_name: String = args[1] if args.size() > 1 else "casual"
    player = PLAYERS[player_name]
    trace = args.size() > 2 and args[2] == "trace"
    if args.size() > 3:
        slots_total = int(args[3])
    for id in AUGMENTS.get_all_string_ids():
        var augment: Augment = AUGMENTS.load_entry(id)
        if augment != null:
            all_cards.append(augment)
    var events := MissionState.load_event_pool()
    stats = {"won": 0, "lost_crew": 0, "lost_hull": 0, "launch_tries": 0, "crew_end": 0, "home_health": 0,
        "home_stress": 0, "home_cryo": 0, "events": 0, "answered": 0, "fallback": 0, "days": 0, "event_seen": {}}
    for i in runs:
        var cargo: Array[AugmentInstance] = []
        while true:
            stats["launch_tries"] += 1
            cargo = plan()
            if LaunchProfile.from_instances(cargo).roll() == LaunchProfile.Failure.NONE:
                break
        var state := MissionState.new("Reach the ISS", MISSION_DAYS, events, cargo)
        if trace:
            var names: PackedStringArray = []
            for instance in cargo:
                names.append(instance.augment.card_name())
            print("run %d cargo: %s" % [i, ", ".join(names)])
        play(state)
        for res_id in ["oxygen", "water", "food", "power"]:
            if state.get_meta("ran_out_" + res_id, false):
                stats["ran_out_" + res_id] = stats.get("ran_out_" + res_id, 0) + 1
                if state.outcome != MissionState.Outcome.WON:
                    stats["lost_out_" + res_id] = stats.get("lost_out_" + res_id, 0) + 1
        stats["days"] += state.day - 1
        if state.outcome == MissionState.Outcome.WON:
            stats["won"] += 1
            stats["crew_end"] += state.crew_aboard().size()
        elif state.resources["hull"] <= 0:
            stats["lost_hull"] += 1
        else:
            stats["lost_crew"] += 1
        for member in state.crew:
            if not member.is_aboard():
                var key := "home_cryo" if member.left_reason.contains("cryo") else ("home_health" if member.left_reason.contains("doctor") else "home_stress")
                stats[key] += 1
    var won: int = stats["won"]
    print("player=%s runs=%d" % [player_name, runs])
    print("  WIN RATE %.1f%%  (lost: %d crew all home, %d hull)" % [100.0 * won / runs, stats["lost_crew"], stats["lost_hull"]])
    print("  launch attempts per mission %.2f" % (float(stats["launch_tries"]) / runs))
    print("  crew aboard at the end of a win %.2f / 4" % (float(stats["crew_end"]) / maxi(won, 1)))
    print("  sent home per run: health %.2f, stress %.2f, cryosleep %.2f" % [
        float(stats["home_health"]) / runs, float(stats["home_stress"]) / runs, float(stats["home_cryo"]) / runs])
    print("  alerts per run %.1f, answered %.0f%%, fallback %.0f%%, days flown %.1f" % [
        float(stats["events"]) / runs, 100.0 * stats["answered"] / maxi(stats["events"], 1),
        100.0 * stats["fallback"] / maxi(stats["events"], 1), float(stats["days"]) / runs])
    var out: PackedStringArray = []
    for res_id in ["oxygen", "water", "food", "power"]:
        out.append("%s %d%% (%d losses)" % [res_id, 100 * stats.get("ran_out_" + res_id, 0) / runs, stats.get("lost_out_" + res_id, 0)])
    print("  ran out at some point: ", ", ".join(out))
    quit()


# --- Plan phase -----------------------------------------------------------------

func plan() -> Array[AugmentInstance]:
    var cargo: Array[AugmentInstance] = []
    var slots := slots_total
    var overhead := 0
    while true:
        var used := overhead
        for instance in cargo:
            used += instance.slots_taken()
        var room := slots - used
        var pool: Array[Augment] = []
        for augment in all_cards:
            if augment.slot_cost() <= room and _can_use(augment, cargo, room):
                pool.append(augment)
        if room <= 0 or pool.is_empty():
            break
        var offers: Array[Augment] = draw_offers(pool, 3)
        var pick: Augment = offers.pick_random()
        if randf() >= player["random_pick"]:
            var best := -INF
            var base := cargo_value(cargo)
            for augment in offers:
                var v := pick_value(augment, cargo, base)
                if v > best:
                    best = v
                    pick = augment
        var instance := AugmentInstance.new(pick, "")
        if pick.is_consumed():
            overhead += pick.slot_cost()
        else:
            instance.roll()
            cargo.append(instance)
        slots += pick.bonus_slots
        _plan_action(pick, cargo, room - pick.slot_cost())
    return cargo


## Same as plan_phase.gd draw_offers() (that script needs the TransitionData
## autoload, which doesn't exist in -s mode).
static func draw_offers(pool: Array[Augment], count: int) -> Array[Augment]:
    var remaining := pool.duplicate()
    var offers: Array[Augment] = []
    while offers.size() < count and not remaining.is_empty():
        var total := 0.0
        for augment: Augment in remaining:
            total += Augment.RARITY_WEIGHTS[augment.rarity]
        var roll := randf() * total
        var picked: Augment = remaining[-1]
        for augment: Augment in remaining:
            roll -= Augment.RARITY_WEIGHTS[augment.rarity]
            if roll <= 0.0:
                picked = augment
                break
        remaining.erase(picked)
        offers.append(picked)
    return offers


func _can_use(augment: Augment, cargo: Array[AugmentInstance], room: int) -> bool:
    var commons := cargo.filter(func(i: AugmentInstance): return i.augment.rarity == Augment.Rarity.COMMON and i.augment.domain != Augment.Domain.LOGISTICS)
    match augment.plan_action:
        Augment.PlanAction.REMOVE, Augment.PlanAction.SWAP:
            return not cargo.is_empty()
        Augment.PlanAction.DUPLICATE:
            return commons.any(func(i: AugmentInstance): return i.augment.slot_cost() <= room - augment.slot_cost())
        Augment.PlanAction.TRADE_UP:
            return commons.size() >= 2
    return true


## Logistics actions, played the way a player would: throw away / swap /
## trade the least useful cards, copy the most useful Common.
func _plan_action(augment: Augment, cargo: Array[AugmentInstance], room: int) -> void:
    match augment.plan_action:
        Augment.PlanAction.REMOVE:
            var target := _worst(cargo, augment.action_max_rarity)
            if target:
                cargo.erase(target)
        Augment.PlanAction.SWAP:
            var target := _worst(cargo, Augment.Rarity.MYTHIC)
            if target:
                var other := _random_card(target.augment.rarity, target.augment)
                other.slots = target.slots_taken()
                cargo[cargo.find(target)] = other
        Augment.PlanAction.DUPLICATE:
            var best: AugmentInstance = null
            var best_v := -INF
            var base := cargo_value(cargo)
            for instance in cargo:
                if instance.augment.rarity == Augment.Rarity.COMMON and instance.augment.slot_cost() <= room:
                    var v := pick_value(instance.augment, cargo, base)
                    if v > best_v:
                        best_v = v
                        best = instance
            if best:
                var copy := AugmentInstance.new(best.augment, "")
                copy.roll()
                cargo.insert(cargo.find(best) + 1, copy)
        Augment.PlanAction.TRADE_UP:
            var freed := 0
            for i in 2:
                var target := _worst(cargo, Augment.Rarity.COMMON)
                if target:
                    freed += target.slots_taken()
                    cargo.erase(target)
            var rare := _random_card(Augment.Rarity.RARE)
            rare.slots = freed
            cargo.append(rare)
        Augment.PlanAction.CRATE:
            _add_free(cargo, [_random_card(Augment.Rarity.RARE), _random_card(-1), _random_card(-1)])
        Augment.PlanAction.DOUBLE_OR_NOTHING:
            if randf() < 0.5:
                _add_free(cargo, [_random_card(Augment.Rarity.RARE), _random_card(Augment.Rarity.RARE)])
            else:
                var pool := cargo.duplicate()
                pool.shuffle()
                for target in pool.slice(0, 2):
                    cargo.erase(target)
        Augment.PlanAction.LOTTERY:
            _add_free(cargo, [_random_card(Augment.Rarity.MYTHIC)])


func _add_free(cargo: Array[AugmentInstance], found: Array) -> void:
    for instance: AugmentInstance in found:
        instance.slots = 0
        cargo.append(instance)


func _worst(cargo: Array[AugmentInstance], max_rarity: int) -> AugmentInstance:
    var worst: AugmentInstance = null
    var worst_v := INF
    var full := cargo_value(cargo)
    for instance in cargo:
        if instance.augment.rarity > max_rarity:
            continue
        var without := cargo.duplicate()
        without.erase(instance)
        var v := full - cargo_value(without)
        if v < worst_v:
            worst_v = v
            worst = instance
    return worst


func _random_card(rarity: int, exclude: Augment = null) -> AugmentInstance:
    var pool: Array[Augment] = []
    for augment in all_cards:
        if augment.domain != Augment.Domain.LOGISTICS and augment != exclude and (rarity < 0 or augment.rarity == rarity):
            pool.append(augment)
    var picked: Augment = pool.pick_random() if rarity >= 0 else draw_offers(pool, 1)[0]
    var instance := AugmentInstance.new(picked, "")
    instance.roll()
    return instance


func pick_value(augment: Augment, cargo: Array[AugmentInstance], base: float) -> float:
    match augment.plan_action:
        Augment.PlanAction.CRATE, Augment.PlanAction.LOTTERY:
            return 6.0
        Augment.PlanAction.DOUBLE_OR_NOTHING:
            return 1.0
        Augment.PlanAction.NONE:
            pass
        _:
            return 2.0 + 2.0 * augment.bonus_slots
    var instance := AugmentInstance.new(augment, "")
    var with := cargo.duplicate()
    with.append(instance)
    return cargo_value(with) - base + 2.0 * augment.bonus_slots


## What a player reads on the planning screen: the launch odds bar and how
## many days each supply lasts.
func cargo_value(cargo: Array[AugmentInstance]) -> float:
    var launch := LaunchProfile.from_instances(cargo).success_chance()
    var preview := MissionState.new("", MISSION_DAYS, [], cargo)
    var forecast := preview.forecast()
    var value := 60.0 * launch * launch
    for res_id in ["water", "oxygen", "food", "power"]:
        var net: int = forecast[res_id]
        var lasts := float(MISSION_DAYS + 3) if net >= 0 else minf(preview.resources[res_id] / float(-net), MISSION_DAYS + 3)
        value += 12.0 * lasts / MISSION_DAYS
    var calm := 0
    for module in preview.ship_modules():
        calm -= preview.module_daily(module).get("crew_stress", 0)
    value += 1.5 * calm + 15.0 * -minf(preview.hazard_change(), 0.0)
    return value


# --- Mission --------------------------------------------------------------------

class Alert:
    var event: MissionEvent
    var hours_left: float = MissionState.EVENT_DEADLINE_HOURS
    var react_at: float = INF
    var worker: CrewMember = null
    var choice: EventChoice = null
    var work_total: float = 0.0
    var work_done: float = 0.0
    var walk_left: float = 0.0


func play(state: MissionState) -> void:
    var busy_until: Dictionary[CrewMember, float] = {}
    while state.outcome == MissionState.Outcome.ONGOING:
        state.start_day()
        var schedule := state.plan_alerts()
        var alerts: Array[Alert] = []
        var jobs: Dictionary[CrewMember, Alert] = {}
        var hour := MissionState.DAY_START_HOUR
        for member in state.crew_aboard():
            busy_until[member] = hour + WALK_HOURS
        while hour < MissionState.DAY_START_HOUR + MissionState.DAY_HOURS:
            for entry in schedule.duplicate():
                if hour >= entry["hour"]:
                    schedule.erase(entry)
                    var alert := Alert.new()
                    alert.event = entry["event"]
                    stats["events"] += 1
                    stats["event_seen"][alert.event.title] = stats["event_seen"].get(alert.event.title, 0) + 1
                    if randf() < player["respond"]:
                        alert.react_at = hour + randf_range(player["react"][0], player["react"][1])
                    alerts.append(alert)
            if fmod(hour, 1.0) < 0.01 and randf() < player["manage"]:
                _manage_crew(state, jobs, busy_until, hour)
            for member in state.crew_aboard():
                if not jobs.has(member) and busy_until.get(member, 0.0) <= hour:
                    state.work(member, STEP_HOURS)
            for alert in alerts.duplicate():
                if alert.worker != null:
                    if alert.walk_left > 0.0:
                        alert.walk_left -= STEP_HOURS
                    else:
                        alert.work_done += STEP_HOURS
                        if alert.work_done >= alert.work_total:
                            _finish(state, alert, jobs, busy_until, hour)
                            alerts.erase(alert)
                    continue
                if hour >= alert.react_at:
                    alert.react_at = INF
                    if _answer(state, alert, jobs):
                        stats["answered"] += 1
                        if alert.worker == null:
                            alerts.erase(alert)
                        continue
                alert.hours_left -= STEP_HOURS
                if alert.hours_left <= 0.0:
                    stats["fallback"] += 1
                    state.ignore_event(alert.event)
                    alerts.erase(alert)
            hour += STEP_HOURS
        if player["toggles"]:
            _manage_power(state)
        for alert in alerts:
            if alert.worker != null:
                _finish(state, alert, jobs, busy_until, hour)
            else:
                stats["fallback"] += 1
                state.ignore_event(alert.event)
        state.end_day()
        for res_id in ["oxygen", "water", "food", "power"]:
            if state.resources[res_id] == 0:
                state.set_meta("ran_out_" + res_id, true)
        var log := state.drain_log()
        if trace:
            var crew_text: PackedStringArray = []
            for member in state.crew:
                crew_text.append("%s h%d s%d%s" % [member.display_name.get_slice(" ", 1).left(4), member.health, member.stress,
                    "" if member.is_aboard() else " HOME"])
            print("  day %2d  O2 %3d  H2O %3d  food %3d  pwr %3d  hull %3d  med %d | %s" % [state.day - 1, state.resources["oxygen"],
                state.resources["water"], state.resources["food"], state.resources["power"], state.resources["hull"],
                state.resources["medkits"], ", ".join(crew_text)])


func _finish(state: MissionState, alert: Alert, jobs: Dictionary[CrewMember, Alert], busy_until: Dictionary[CrewMember, float], hour: float) -> void:
    state.finish_event_choice(alert.event, alert.choice, alert.worker)
    jobs.erase(alert.worker)
    busy_until[alert.worker] = hour + WALK_HOURS
    alert.worker.station = alert.worker.get_meta("back", "bunks")


## Picks an option like a player reading the popup. False if nothing was done.
func _answer(state: MissionState, alert: Alert, jobs: Dictionary[CrewMember, Alert]) -> bool:
    var event := alert.event
    var free := state.crew_aboard().filter(func(m: CrewMember): return not jobs.has(m))
    var options: Array[EventChoice] = []
    for choice in event.choices:
        if state.can_choose(choice) and (not choice.needs_crew or not free.is_empty()):
            options.append(choice)
    if options.is_empty():
        return false
    var pick: EventChoice = options.pick_random()
    var member: CrewMember = null
    if randf() >= player["random_choice"]:
        var best := -INF
        for choice in options:
            var who := _best_member(state, event, choice, free) if choice.needs_crew else null
            var p := state.event_chance(event, choice, who)
            var v := p * effect_value(state, choice.success_effects) + (1.0 - p) * effect_value(state, choice.failure_effects) \
                - effect_value(state, negate(choice.cost))
            if choice.needs_crew:
                v -= 0.5 * state.event_hours(event, choice, who)
            if v > best:
                best = v
                pick = choice
    if pick == event.choices[-1] and not pick.needs_crew:
        return false
    if pick.needs_crew:
        member = _best_member(state, event, pick, free)
    if not state.begin_event_choice(pick):
        return false
    if member == null:
        state.finish_event_choice(event, pick, null)
        return true
    alert.worker = member
    alert.choice = pick
    alert.work_total = state.event_hours(event, pick, member)
    alert.walk_left = WALK_HOURS
    jobs[member] = alert
    member.set_meta("back", member.station)
    return true


func _best_member(state: MissionState, event: MissionEvent, choice: EventChoice, free: Array) -> CrewMember:
    var best: CrewMember = null
    var best_v := -INF
    for member: CrewMember in free:
        var v := state.event_chance(event, choice, member) * 10.0 - state.event_hours(event, choice, member)
        if v > best_v:
            best_v = v
            best = member
    return best


static func negate(cost: Dictionary) -> Dictionary:
    var result := {}
    for key in cost.keys():
        result[key] = -cost[key]
    return result


func effect_value(state: MissionState, effects: Dictionary) -> float:
    return effect_value_static(state, effects)


## Rough worth of a set of effects for the player, like reading the popup.
static func effect_value_static(state: MissionState, effects: Dictionary) -> float:
    var crew := state.crew_aboard().size()
    var v := 0.0
    var weights := {"oxygen": 2.0, "water": 0.7, "food": 1.0, "power": 0.6, "hull": 0.6, "medkits": 4.0, "science": 0.3}
    for key: String in effects.keys():
        var amount: int = effects[key]
        if weights.has(key):
            var change := amount
            if state.resources.has(key):
                change = maxi(amount, -state.resources[key])
            v += weights[key] * change
        elif key == "crew_stress":
            v -= 0.25 * crew * amount
        elif key == "crew_health":
            v += 0.3 * crew * amount
        elif key in ["random_crew_stress", "worker_stress", "most_stressed_stress", "stress_command"]:
            v -= 0.3 * amount
        elif key in ["random_crew_health", "worker_health"]:
            v += 0.3 * amount
        elif key == "random_crew_sick":
            v -= 8.0
        elif key == "sick_all":
            v -= 8.0 * crew
        elif key == "mission_days":
            v -= 20.0 * amount
        elif key.begins_with("break_"):
            v -= 8.0
        elif key.begins_with("lose_"):
            v -= 20.0
        elif key.begins_with("offline_"):
            v -= 1.0
        elif key == "gain_mythic":
            v += 25.0
        elif key == "repair_module":
            v += 6.0
        elif key == "random_resource":
            v += amount
        elif key == "cryosleep":
            v -= 15.0
        elif key.ends_with("_days"):
            var nights := mini(amount, state.mission_days - state.day + 1)
            match key.trim_suffix("_days"):
                "blackout":
                    v -= 6.0 * nights
                "cold":
                    v -= 5.0 * nights
                "sluggish":
                    v -= 4.0 * nights
                "comms_down":
                    v -= 2.0 * nights
                "rationing":
                    var food_days := state.resources["food"] / maxf(crew, 1.0)
                    v += (3.0 if food_days < nights else -2.0) * nights
    return v


## Before the night: switch off power-hungry modules that don't keep the crew
## breathing or drinking while the batteries can't cover everything.
func _manage_power(state: MissionState) -> void:
    for module in state.modules:
        if module.augment.toggleable and not module.lost:
            module.enabled = true
    var needed := 0
    for module in state.modules:
        if module.working():
            needed -= mini(0, state.module_daily(module).get("power", 0))
    var available: int = state.resources["power"] + MissionState.SOLAR_POWER_PER_DAY - MissionState.LIFE_SUPPORT_POWER
    for module in state.modules:
        if needed <= available:
            break
        var daily := state.module_daily(module)
        if module.augment.toggleable and module.working() and daily.get("power", 0) < 0 \
                and daily.get("oxygen", 0) <= 0 and daily.get("water", 0) <= 0 and not module.augment.has_flag(&"infinite_food"):
            module.enabled = false
            needed += daily["power"]


## Rest when tired or stressed, medbay when sick, an engineer on repairs,
## otherwise everyone back to their job.
func _manage_crew(state: MissionState, jobs: Dictionary[CrewMember, Alert], busy_until: Dictionary[CrewMember, float], hour: float) -> void:
    var broken := state.modules.any(func(m: ShipModule): return m.broken and not m.lost)
    var low_air := state.resources["oxygen"] + state.forecast()["oxygen"] * 2 < 0 or state.resources["water"] + state.forecast()["water"] * 2 < 0
    for member in state.crew_aboard():
        if jobs.has(member) or busy_until.get(member, 0.0) > hour:
            continue
        if member.health < 35 and state.resources["medkits"] > 0:
            state.use_medkit(member)
        var target: String = HOME_STATIONS[member.skill]
        if member.sick:
            target = "medbay"
        elif member.health < 40:
            target = "bunks"
        elif member.stress >= 55:
            target = "comms" if not state.comms_down else "cupola"
        elif member.skill == "engineering" and broken:
            target = "engineering"
        elif low_air and member.skill in ["engineering", "science"]:
            target = "life_support"
        elif member.skill == "command" and member.stress < 20:
            target = "engineering" if state.resources["hull"] < 70 else "lab"
        if target != member.station:
            member.station = target
            busy_until[member] = hour + WALK_HOURS
