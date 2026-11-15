extends Control
## Transition between the plan phase and the mission phase: a mission-control
## terminal printout recapping the cargo manifest, the resulting launch
## configuration and the objective. Click / press a key to skip the typing,
## then again to launch.

const MISSION_SCENE: String = "res://scenes/mission_phase/mission_phase.tscn"

const CHARS_PER_SECOND: float = 260.0
## Pause in seconds at the end of each line, for a "printing" feel.
const LINE_PAUSE: float = 0.04

const GREEN := "39ff6a"
const DIM := "1f8f3c"
const AMBER := "ffb800"

var _typed: float = 0.0
var _line_pause: float = 0.0
var _parsed: String = ""
var _done: bool = false
var _launching: bool = false
var _cursor_time: float = 0.0


func _ready() -> void:
    %Terminal.text = _build_report()
    %Terminal.visible_characters = 0
    %LaunchButton.hide()
    %LaunchButton.pressed.connect(_launch)


func _process(delta: float) -> void:
    _cursor_time += delta
    if _done:
        %LaunchButton.text = "> LAUNCH" + ("_" if fmod(_cursor_time, 1.0) < 0.5 else " ")
        return
    if _line_pause > 0.0:
        _line_pause -= delta
        return
    if _parsed.is_empty():
        _parsed = %Terminal.get_parsed_text()
    var before := int(_typed)
    _typed = minf(_typed + CHARS_PER_SECOND * delta, _parsed.length())
    # Stop at the end of each printed line for a short "printer" pause.
    var newline := _parsed.find("\n", before)
    if newline != -1 and newline < int(_typed):
        _typed = newline + 1
        _line_pause = LINE_PAUSE
    %Terminal.visible_characters = int(_typed)
    if int(_typed) >= _parsed.length():
        _finish_typing()


func _input(event: InputEvent) -> void:
    var pressed: bool = (event is InputEventKey and event.pressed and not event.echo) \
        or (event is InputEventMouseButton and event.pressed)
    if not pressed:
        return
    get_viewport().set_input_as_handled()
    if not _done:
        _finish_typing()
    else:
        _launch()


func _finish_typing() -> void:
    _done = true
    %Terminal.visible_characters = -1
    %LaunchButton.show()
    %LaunchButton.grab_focus()


func _launch() -> void:
    if _launching:
        return
    _launching = true
    var tween := create_tween()
    tween.tween_property(self, "modulate", Color.BLACK, 0.6)
    tween.tween_callback(func(): get_tree().change_scene_to_file(MISSION_SCENE))


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

    t += _header("OBJECTIVE")
    t += "  %s\n\n" % objective.to_upper()

    t += "> ALL SYSTEMS NOMINAL. GO FOR LAUNCH.\n"
    t += _dim("> PRESS ANY KEY TO LAUNCH")
    return t


func _header(title: String) -> String:
    return "[color=#%s]## %s[/color]\n" % [AMBER, title]


func _dim(text: String) -> String:
    return "[color=#%s]%s[/color]" % [DIM, text]


func _ok() -> String:
    return "[color=#%s][OK][/color]" % GREEN
