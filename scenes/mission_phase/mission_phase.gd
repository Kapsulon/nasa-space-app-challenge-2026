extends Control
## Mission phase (phase 2): a day-by-day survival loop.
## Each day: read the dashboard, set rations / tasks, answer the incoming
## transmission (mission control types the reply), end the day, then read the
## overnight report in the mission-control terminal.

const MENU_SCENE: String = "res://scenes/select_scenario/select_scenario.tscn"

const COLOR_GOOD := Color("7be38b")
const COLOR_BAD := Color("ff5a6e")
const COLOR_WARN := Color("ffb35c")
const COLOR_MUTED := Color("8a94a6")
const COLOR_STRESS := Color("b46cff")

# Terminal palette (hex strings for bbcode).
const T_GREEN := "39ff6a"
const T_DIM := "1f8f3c"
const T_AMBER := "ffb800"
const T_RED := "ff5a6e"
const T_BLUE := "63b1ff"
const PROMPT := "[color=#1f8f3c]houston@mission-control[/color]:[color=#63b1ff]~[/color]$ "
const SHORT_PROMPT := "[color=#1f8f3c]houston[/color]:[color=#63b1ff]~[/color]$ "

var state: MissionState

enum RecapMode { BRIEFING, DAILY, END }
var _recap_mode: RecapMode = RecapMode.BRIEFING

# res_id -> {bar, value, forecast}
var _resource_rows: Dictionary[String, Dictionary] = {}


func _ready() -> void:
    var scenario_name := TransitionData.scenario_name if TransitionData.scenario_name != "" else "Reach the ISS"
    state = MissionState.new(scenario_name, TransitionData.scenario_days, MissionState.load_event_pool(), TransitionData.selected_augments)
    %EndDayButton.pressed.connect(_on_end_day_pressed)
    %RecapButton.pressed.connect(_on_recap_continue)
    %RecapTerminal.output_done.connect(_on_recap_printed)
    %DecisionTerminal.output_done.connect(_refresh_resources)
    _build_resource_rows()
    state.start_day()
    _refresh_all()
    _show_briefing()


func _input(event: InputEvent) -> void:
    # Any key or click while the report is printing reveals it all at once.
    if not %RecapOverlay.visible or not %RecapTerminal.is_busy():
        return
    var pressed: bool = (event is InputEventKey and event.pressed and not event.echo) \
        or (event is InputEventMouseButton and event.pressed)
    if pressed:
        %RecapTerminal.skip()
        get_viewport().set_input_as_handled()


# --- Building / refreshing ----------------------------------------------------

func _refresh_all() -> void:
    %TitleLabel.text = state.scenario_name
    %DayLabel.text = "Day %d / %d" % [state.day, state.mission_days]
    %Trajectory.set_day(state.day - 1, state.mission_days)
    %ScienceLabel.text = "Science: %d" % state.science
    _build_crew()
    _build_event()
    _refresh_resources()


func _build_resource_rows() -> void:
    for child in %ResourceList.get_children():
        child.queue_free()
    for res_id in MissionState.RESOURCE_IDS:
        var info: Dictionary = MissionState.RESOURCE_INFO[res_id]
        var row := VBoxContainer.new()
        row.add_theme_constant_override("separation", 4)

        var header := HBoxContainer.new()
        var name_label := _label(info["name"], 28)
        name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
        var value_label := _label("", 28)
        var forecast_label := _label("", 24)
        forecast_label.custom_minimum_size.x = 70
        forecast_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
        header.add_child(name_label)
        header.add_child(value_label)
        header.add_child(forecast_label)

        var bar := _bar(info["color"], 18)
        row.add_child(header)
        row.add_child(bar)
        %ResourceList.add_child(row)
        _resource_rows[res_id] = {"bar": bar, "value": value_label, "forecast": forecast_label}


func _refresh_resources() -> void:
    var forecast := state.forecast()
    for res_id in MissionState.RESOURCE_IDS:
        var row: Dictionary = _resource_rows[res_id]
        var amount: int = state.resources[res_id]
        var cap: int = state.capacities[res_id]
        row["bar"].max_value = cap
        row["bar"].value = amount
        row["value"].text = "%d / %d" % [amount, cap]
        var delta: int = forecast[res_id]
        var forecast_label: Label = row["forecast"]
        forecast_label.text = "%+d" % delta if delta != 0 else "0"
        forecast_label.add_theme_color_override("font_color", COLOR_GOOD if delta > 0 else (COLOR_BAD if delta < 0 else COLOR_MUTED))
        # Warn when tonight would empty the stock.
        row["value"].add_theme_color_override("font_color", COLOR_BAD if amount + delta < 0 or amount == 0 else Color.WHITE)
    %ScienceLabel.text = "Science: %d" % state.science

    var transmitting: bool = %DecisionTerminal.is_busy()
    %EndDayButton.disabled = state.needs_decision() or transmitting
    if state.needs_decision():
        %EndDayButton.text = "Answer the transmission first"
    elif transmitting:
        %EndDayButton.text = "Transmitting..."
    else:
        %EndDayButton.text = "End day %d" % state.day


func _build_crew() -> void:
    for child in %CrewList.get_children():
        child.queue_free()
    for member in state.crew:
        %CrewList.add_child(_make_crew_card(member))


func _make_crew_card(member: CrewMember) -> Control:
    var panel := PanelContainer.new()
    panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
    panel.add_theme_stylebox_override("panel", _card_style(member.is_aboard()))
    var box := VBoxContainer.new()
    box.add_theme_constant_override("separation", 8)
    panel.add_child(box)

    var header := HBoxContainer.new()
    var name_label := _label(member.display_name, 30)
    name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    header.add_child(name_label)
    header.add_child(_label(member.role, 20, COLOR_MUTED))
    box.add_child(header)

    if not member.is_aboard():
        box.add_child(_label("Back on Earth", 26, COLOR_GOOD))
        var reason := _label("Took the return capsule home because they %s. Safe and sound!" % member.left_reason, 20, COLOR_MUTED)
        reason.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
        box.add_child(reason)
        panel.modulate = Color(1, 1, 1, 0.6)
        return panel

    var health_color := COLOR_GOOD if member.health >= 50 else (COLOR_WARN if member.health >= 25 else COLOR_BAD)
    box.add_child(_stat_row("Health", member.health, CrewMember.MAX_HEALTH, health_color))
    var stress_color := COLOR_STRESS if member.stress < CrewMember.STRESSED else (COLOR_WARN if member.stress < CrewMember.OVERWHELMED else COLOR_BAD)
    box.add_child(_stat_row("Stress", member.stress, CrewMember.MAX_STRESS, stress_color))

    box.add_child(_label(member.status_text(), 22, COLOR_GOOD if member.is_doing_great() else COLOR_WARN))

    var rations := HBoxContainer.new()
    rations.add_theme_constant_override("separation", 16)
    var food_check := CheckBox.new()
    food_check.text = "Food ration"
    food_check.button_pressed = member.give_food
    food_check.add_theme_font_size_override("font_size", 22)
    food_check.toggled.connect(func(on: bool):
        member.give_food = on
        _refresh_resources())
    var water_check := CheckBox.new()
    water_check.text = "Water ration"
    water_check.button_pressed = member.give_water
    water_check.add_theme_font_size_override("font_size", 22)
    water_check.toggled.connect(func(on: bool):
        member.give_water = on
        _refresh_resources())
    rations.add_child(food_check)
    rations.add_child(water_check)
    box.add_child(rations)

    var task_row := HBoxContainer.new()
    task_row.add_child(_label("Task:", 22))
    var task_option := OptionButton.new()
    task_option.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    task_option.add_theme_font_size_override("font_size", 22)
    task_option.clip_text = true
    task_option.custom_minimum_size.x = 120
    for task in CrewMember.TASK_NAMES.keys():
        task_option.add_item(CrewMember.TASK_NAMES[task], task)
    task_option.select(task_option.get_item_index(member.task))
    var task_hint := _label(CrewMember.TASK_HINTS[member.task], 18, COLOR_MUTED)
    task_option.item_selected.connect(func(index: int):
        member.task = task_option.get_item_id(index) as CrewMember.Task
        task_hint.text = CrewMember.TASK_HINTS[member.task]
        _refresh_resources())
    task_row.add_child(task_option)
    box.add_child(task_row)
    box.add_child(task_hint)

    var medkit_button := Button.new()
    medkit_button.text = "Use medkit (+%d health)" % MissionState.MEDKIT_HEAL
    medkit_button.add_theme_font_size_override("font_size", 20)
    medkit_button.disabled = not state.can_use_medkit(member)
    medkit_button.pressed.connect(func():
        state.use_medkit(member)
        _build_crew.call_deferred()
        _refresh_resources())
    box.add_child(medkit_button)
    return panel


func _stat_row(title: String, value: int, max_value: int, color: Color) -> Control:
    var row := HBoxContainer.new()
    row.add_theme_constant_override("separation", 12)
    var label := _label("%s %d" % [title, value], 22)
    label.custom_minimum_size.x = 130
    row.add_child(label)
    var bar := _bar(color, 14)
    bar.max_value = max_value
    bar.value = value
    bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
    row.add_child(bar)
    return row


func _build_event() -> void:
    for child in %EventChoices.get_children():
        child.queue_free()
    %DecisionBox.hide()
    %DecisionTerminal.clear_terminal()

    var event := state.current_event
    if event == null:
        %EventTitle.text = "Quiet day"
        %EventDescription.text = "No incidents reported. Use the time to look after the crew and plan the day."
        return

    %EventTitle.text = event.title
    %EventDescription.text = event.description
    for choice in event.choices:
        var button := Button.new()
        button.add_theme_font_size_override("font_size", 24)
        button.custom_minimum_size.y = 56
        button.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
        button.text = choice.label
        if not choice.cost.is_empty():
            button.text += "  (%s)" % _format_cost(choice.cost)
        button.disabled = not state.can_afford(choice.cost)
        button.pressed.connect(_on_choice_pressed.bind(choice))
        %EventChoices.add_child(button)


func _on_choice_pressed(choice: EventChoice) -> void:
    if state.chosen != null:
        return
    state.choose(choice)
    for child in %EventChoices.get_children():
        child.queue_free()
    _transmit_decision(choice)
    _refresh_resources()


## Mission control types the reply to the crew in a little terminal.
func _transmit_decision(choice: EventChoice) -> void:
    var term: TerminalLabel = %DecisionTerminal
    %DecisionBox.show()
    term.clear_terminal()
    term.print_text(SHORT_PROMPT, 0.35)
    term.type_text("transmit --to crew \"%s\"\n" % choice.label, 0.4)
    term.print_text("[color=#%s]uplink .......... [/color][color=#%s][OK][/color]\n" % [T_DIM, T_GREEN], 0.2)
    term.print_text("[color=#%s]Crew acknowledged. Outcome expected tomorrow morning.[/color]" % T_DIM)


# --- Day flow -----------------------------------------------------------------

func _on_end_day_pressed() -> void:
    if state.needs_decision() or %DecisionTerminal.is_busy():
        return
    var recap := state.end_day()
    _show_recap(recap)


func _on_recap_continue() -> void:
    match _recap_mode:
        RecapMode.END:
            get_tree().change_scene_to_file(MENU_SCENE)
            return
        RecapMode.DAILY:
            if state.outcome != MissionState.Outcome.ONGOING:
                _show_end()
                return
            state.start_day()
            _refresh_all()
    %RecapOverlay.hide()


func _on_recap_printed() -> void:
    %RecapButton.show()
    %RecapButton.grab_focus()


# --- Terminal reports ---------------------------------------------------------

func _show_briefing() -> void:
    _recap_mode = RecapMode.BRIEFING
    var t := _title_line("MISSION BRIEFING :: %s" % state.scenario_name.to_upper())
    t += "Your crew of %d has launched. Get them safely to the station in %s.\n\n" % [
        state.crew.size(), _hl("%d days" % state.mission_days)]
    t += _section("EACH DAY")
    t += "  * choose who gets food and water rations\n"
    t += "  * give every crew member a task (work uses power and adds stress)\n"
    t += "  * answer incoming transmissions; the outcome arrives next morning\n\n"
    t += _section("EVERY NIGHT")
    t += "  * the solar panels make %d power, life support uses %d\n" % [MissionState.SOLAR_POWER_PER_DAY, MissionState.LIFE_SUPPORT_POWER]
    t += "  * each crew member breathes 1 oxygen\n"
    t += "  * the hull wears down by %d\n\n" % MissionState.HULL_DECAY_PER_DAY
    t += _section("CREW WELLBEING")
    t += "  * health drops when the crew is hungry, thirsty or unwell\n"
    t += "  * stress rises with hard work, worries and empty stomachs\n"
    t += "  * resting and calling home help everyone recharge\n"
    t += "  * at 0 health or 100 stress, a crew member takes the return\n"
    t += "    capsule home safely and leaves the mission\n\n"
    t += _section("LAUNCH BONUSES")
    if state.augment_summary.is_empty():
        t += _dim("  none") + "\n"
    else:
        # Group identical lines: "Water capacity: +10 Water capacity  x3".
        var counts: Dictionary[String, int] = {}
        for line in state.augment_summary:
            counts[line] = counts.get(line, 0) + 1
        for line in counts.keys():
            t += "  * %s%s\n" % [line, ("  x%d" % counts[line]) if counts[line] > 1 else ""]
    _open_terminal("~/missions", "cat briefing.txt", t, "> BEGIN DAY 1")


func _show_recap(recap: Dictionary) -> void:
    _recap_mode = RecapMode.DAILY
    var t := _title_line("DAILY REPORT :: %s :: DAY %02d/%02d" % [state.scenario_name.to_upper(), recap["day"], state.mission_days])

    if recap["event_title"] != "":
        t += _section("TRANSMISSION")
        t += "  %s\n" % _hl(recap["event_title"])
        t += "  decision : %s\n" % recap["decision"]
        if recap["event_result"] != "":
            t += "  result   : %s\n" % recap["event_result"]
        t += "\n"

    t += _section("SHIP")
    t += _dim("  %-16s %7s %7s %8s" % ["RESOURCE", "BEFORE", "AFTER", "CHANGE"]) + "\n"
    for res_id in MissionState.RESOURCE_IDS:
        t += _resource_line(MissionState.resource_name(res_id).to_lower(), recap["resources"][res_id][0], recap["resources"][res_id][1])
    t += _resource_line("science", recap["science"][0], recap["science"][1])
    t += "\n"

    t += _section("CREW")
    t += _dim("  %-16s %7s %7s   %s" % ["NAME", "HEALTH", "STRESS", "STATUS"]) + "\n"
    for member in state.crew:
        t += _crew_line(member)
    for entry in recap["sent_home"]:
        t += "\n  [color=#%s]%s %s and took the return capsule home.\n  They landed safely and are having a well-deserved rest![/color]\n" % [
            T_AMBER, entry["name"], entry["reason"]]
    t += "\n"

    if not recap["log"].is_empty():
        t += _section("LOG")
        for line in recap["log"]:
            t += "  * %s\n" % line

    var button_text := "> START DAY %d" % state.day
    if state.outcome != MissionState.Outcome.ONGOING:
        button_text = "> CONTINUE"
    _open_terminal("~/reports", "cat day_%02d.log" % recap["day"], t, button_text)


func _show_end() -> void:
    _recap_mode = RecapMode.END
    var won := state.outcome == MissionState.Outcome.WON
    var t := _title_line("MISSION COMPLETE" if won else "MISSION CALLED OFF")
    t += "[color=#%s]%s[/color]\n\n" % [T_GREEN if won else T_AMBER, state.outcome_text]
    t += _section("FINAL STATS")
    t += "  days in space ..... %d\n" % (state.day - 1)
    t += "  crew aboard ....... %d / %d\n" % [state.crew_aboard().size(), state.crew.size()]
    t += "  science ........... %d\n\n" % state.science
    t += _section("CREW")
    for member in state.crew:
        var where := "made it to the station" if member.is_aboard() and won else ("back on Earth, safe and sound" if not member.is_aboard() or not won else "aboard")
        t += "  %-16s %s\n" % [member.display_name, where]
    t += "\n" + _dim("Everyone is safe. Thanks for flying with mission control!") + "\n"
    _open_terminal("~", "./mission_status --final", t, "> BACK TO MENU")


func _open_terminal(directory: String, command: String, body: String, button_text: String) -> void:
    %WindowTitle.text = "houston@mission-control: %s" % directory
    %RecapButton.text = button_text
    %RecapButton.hide()
    var term: TerminalLabel = %RecapTerminal
    term.clear_terminal()
    term.print_text(PROMPT.replace("~", directory), 0.3)
    term.type_text(command + "\n", 0.3)
    # Print section by section so the terminal scrolls as it goes.
    for chunk in body.split("\n\n", false):
        term.print_text(chunk + "\n\n", 0.08)
    term.print_text(PROMPT.replace("~", directory))
    %RecapOverlay.show()


func _title_line(title: String) -> String:
    var bar := "=".repeat(mini(72, title.length() + 8))
    return "[color=#%s]%s\n    %s\n%s[/color]\n\n" % [T_DIM, bar, title, bar]


func _section(title: String) -> String:
    return "[color=#%s][%s][/color]\n" % [T_AMBER, title]


func _hl(text: String) -> String:
    return "[color=#%s]%s[/color]" % [T_BLUE, text]


func _dim(text: String) -> String:
    return "[color=#%s]%s[/color]" % [T_DIM, text]


func _resource_line(label: String, before: int, after: int) -> String:
    var delta := after - before
    var change := ("%+d" % delta) if delta != 0 else "0"
    var color := T_GREEN if delta > 0 else (T_RED if delta < 0 else T_DIM)
    return "  %-16s %7d %7d [color=#%s]%8s[/color]\n" % [label, before, after, color, change]


func _crew_line(member: CrewMember) -> String:
    if not member.is_aboard():
        return _dim("  %-16s %7s %7s   back on earth" % [member.display_name, "-", "-"]) + "\n"
    var health_color := T_GREEN if member.health >= 50 else (T_AMBER if member.health >= 25 else T_RED)
    var stress_color := T_GREEN if member.stress < CrewMember.STRESSED else (T_AMBER if member.stress < CrewMember.OVERWHELMED else T_RED)
    return "  %-16s [color=#%s]%7d[/color] [color=#%s]%7d[/color]   %s\n" % [
        member.display_name, health_color, member.health, stress_color, member.stress, member.status_text().to_lower()]


# --- Helpers ------------------------------------------------------------------

func _format_cost(cost: Dictionary) -> String:
    var parts: PackedStringArray = []
    for key in cost.keys():
        parts.append("-%d %s" % [cost[key], MissionState.resource_name(key).to_lower()])
    return ", ".join(parts)


func _label(text: String, font_size: int, color: Color = Color.WHITE) -> Label:
    var label := Label.new()
    label.text = text
    label.add_theme_font_size_override("font_size", font_size)
    label.add_theme_color_override("font_color", color)
    return label


func _bar(color: Color, height: float) -> ProgressBar:
    var bar := ProgressBar.new()
    bar.custom_minimum_size.y = height
    bar.show_percentage = false
    var fill := StyleBoxFlat.new()
    fill.bg_color = color
    fill.set_corner_radius_all(4)
    var bg := StyleBoxFlat.new()
    bg.bg_color = Color(1, 1, 1, 0.08)
    bg.set_corner_radius_all(4)
    bar.add_theme_stylebox_override("fill", fill)
    bar.add_theme_stylebox_override("background", bg)
    return bar


func _card_style(aboard: bool) -> StyleBoxFlat:
    var sb := StyleBoxFlat.new()
    sb.bg_color = Color(0.086, 0.125, 0.18, 0.92) if aboard else Color(0.1, 0.1, 0.1, 0.85)
    sb.border_color = Color("2c3e57")
    sb.set_border_width_all(2)
    sb.set_corner_radius_all(8)
    sb.set_content_margin_all(14)
    return sb
