extends Control
## Transition between the plan phase and the mission phase: a mission-control
## terminal printout recapping the cargo manifest, the resulting launch
## configuration, the launch odds and the objective. Click / press a key to
## skip the typing, then again to go to the launch.

const LAUNCH_SCENE: String = "res://scenes/launch_sequence/launch_sequence.tscn"

const GREEN := "39ff6a"
const DIM := "1f8f3c"
const AMBER := "ffb800"
const RED := "ff3a55"
const PROMPT := "[color=#1f8f3c]houston@mission-control[/color]:[color=#63b1ff]~[/color]$ "

var _launching: bool = false


func _ready() -> void:
    var terminal: TerminalLabel = %Terminal
    terminal.clear_terminal()
    terminal.print_text(PROMPT, 0.4)
    terminal.type_text("./launch_readiness --mission %s\n" % _mission_slug(), 0.3)
    terminal.print_text(_build_report())
    terminal.output_done.connect(_on_report_done)
    %LaunchButton.hide()
    %LaunchButton.pressed.connect(_launch)


func _mission_slug() -> String:
    var scenario_name: String = TransitionData.scenario_name if TransitionData.scenario_name != "" else "Reach the ISS"
    return scenario_name.to_lower().replace(" ", "_")


func _input(event: InputEvent) -> void:
    var pressed: bool = (event is InputEventKey and event.pressed and not event.echo) \
        or (event is InputEventMouseButton and event.pressed)
    if not pressed:
        return
    get_viewport().set_input_as_handled()
    if %Terminal.is_busy():
        %Terminal.skip()
    else:
        _launch()


func _on_report_done() -> void:
    %LaunchButton.show()
    %LaunchButton.grab_focus()


func _launch() -> void:
    if _launching:
        return
    _launching = true
    var tween := create_tween()
    tween.tween_property(self, "modulate", Color.BLACK, 0.6)
    tween.tween_callback(func(): get_tree().change_scene_to_file(LAUNCH_SCENE))


# --- Report -------------------------------------------------------------------

func _build_report() -> String:
    var scenario_name: String = TransitionData.scenario_name if TransitionData.scenario_name != "" else "Reach the ISS"
    var objective: String = TransitionData.scenario_objective
    if objective == "":
        objective = "Keep the crew alive for %d days until the mission is complete." % TransitionData.scenario_days
    var augments: Array[AugmentInstance] = TransitionData.selected_augments
    # Reuse the mission simulation to compute exactly what the crew launches with.
    var preview := MissionState.new(scenario_name, TransitionData.scenario_days, [], augments)

    var t := ""
    t += _dim("NASA MISSION CONTROL // LAUNCH READINESS REPORT") + "\n"
    t += _dim("=".repeat(64)) + "\n"
    t += "> ESTABLISHING UPLINK ............... " + _ok() + "\n"
    t += "> VERIFYING CARGO MANIFEST .......... " + _ok() + "\n\n"

    t += _header("MISSION")
    t += "  NAME ........ %s\n" % scenario_name.to_upper()
    t += "  DURATION .... %d DAYS\n" % preview.mission_days
    t += "  CREW ........ %d\n" % preview.crew.size()
    for member in preview.crew:
        t += _dim("    - %s, %s" % [member.display_name.to_upper(), member.role.to_upper()]) + "\n"
    t += "\n"

    t += _header("CARGO MANIFEST")
    var slots_used := 0
    var counts: Dictionary[Augment, int] = {}
    var order: Array[Augment] = []
    for instance in augments:
        slots_used += instance.augment.slot_cost()
        if not counts.has(instance.augment):
            order.append(instance.augment)
        counts[instance.augment] = counts.get(instance.augment, 0) + 1
    if order.is_empty():
        t += _dim("  (EMPTY)") + "\n"
    for augment in order:
        var n: int = counts[augment]
        t += "  [color=#%s][%s][/color] %s x%d ... %d SLOT%s\n" % [
            Augment.RARITY_COLORS[augment.rarity].to_html(false),
            augment.rarity_name().to_upper(), augment.display_name.to_upper(), n,
            augment.slot_cost() * n, "" if augment.slot_cost() * n == 1 else "S"]
        for key in augment.upgrades.keys():
            var amount := int(augment.upgrades[key])
            t += _dim("      %+d %s" % [amount * n, key.replace("_", " ").to_upper()]) + "\n"
    var total_slots: int = TransitionData.scenario_base_slot_count if TransitionData.scenario_base_slot_count > 0 else slots_used
    t += "  TOTAL ....... %d / %d SLOTS\n\n" % [slots_used, total_slots]

    t += _header("LAUNCH CONFIGURATION")
    for res_id in MissionState.RESOURCE_IDS:
        var res_label := MissionState.resource_name(res_id).to_upper()
        var amount: int = preview.resources[res_id]
        var cap: int = preview.capacities[res_id]
        var base_cap: int = MissionState.DEFAULT_CAPACITIES[res_id]
        var line := "  %s %s %3d / %-3d" % [res_label, ".".repeat(maxi(2, 16 - res_label.length())), amount, cap]
        if cap != base_cap:
            line += "  [color=#%s](%+d CAP)[/color]" % [AMBER, cap - base_cap]
        t += line + "\n"
    t += "\n"

    var launch := LaunchProfile.from_instances(augments)
    var chance := launch.success_chance()
    t += _header("VEHICLE")
    t += "  TOTAL WEIGHT .... %5.1f T" % launch.total_weight() + _dim("  (CAPSULE %.1f + CARGO %.1f)" % [LaunchProfile.CAPSULE_TONS, launch.cargo_tons]) + "\n"
    t += "  ENGINE LIFT ..... %5.1f T" % launch.lift_tons + ("  [color=#%s]OVERWEIGHT[/color]" % RED if launch.is_overweight() else "") + "\n"
    t += "  FUEL ............ %5.0f T" % launch.fuel_tons + _dim("  (NEEDS %.0f T)" % launch.fuel_needed()) + "\n"
    t += "  LAUNCH ODDS ..... [color=#%s]%d%%[/color]\n\n" % [_odds_color(chance), roundi(chance * 100.0)]

    t += _header("OBJECTIVE")
    t += "  %s\n\n" % objective.to_upper()

    if chance >= 0.8:
        t += "> ALL SYSTEMS NOMINAL. GO FOR LAUNCH.\n"
    elif chance >= 0.4:
        t += "> [color=#%s]CAUTION: %s.[/color] GO FOR LAUNCH.\n" % [AMBER, launch.main_problem().to_upper()]
    else:
        t += "> [color=#%s]WARNING: %s.[/color] LAUNCHING ANYWAY.\n" % [RED, launch.main_problem().to_upper()]
    t += _dim("> PRESS ANY KEY TO LAUNCH")
    return t


func _odds_color(chance: float) -> String:
    if chance >= 0.8:
        return GREEN
    if chance >= 0.4:
        return AMBER
    return RED


func _header(title: String) -> String:
    return "[color=#%s]## %s[/color]\n" % [AMBER, title]


func _dim(text: String) -> String:
    return "[color=#%s]%s[/color]" % [DIM, text]


func _ok() -> String:
    return "[color=#%s][OK][/color]" % GREEN
