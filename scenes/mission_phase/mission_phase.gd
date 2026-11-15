extends Control
## Mission phase (phase 2): a day-by-day survival loop.
## Each day: read the dashboard, set rations / tasks, answer the event, end the day,
## then read the recap of what happened overnight.

const MENU_SCENE: String = "res://scenes/select_scenario/select_scenario.tscn"

const COLOR_GOOD := Color("7be38b")
const COLOR_BAD := Color("ff5a6e")
const COLOR_WARN := Color("ffb35c")
const COLOR_MUTED := Color("8a94a6")

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
    _build_resource_rows()
    state.start_day()
    _refresh_all()
    _show_briefing()


# --- Building / refreshing ----------------------------------------------------

func _refresh_all() -> void:
    %TitleLabel.text = state.scenario_name
    %DayLabel.text = "Day %d / %d" % [state.day, state.mission_days]
    %MissionProgress.max_value = state.mission_days
    %MissionProgress.value = state.day - 1
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

        var bar := ProgressBar.new()
        bar.custom_minimum_size.y = 18
        bar.show_percentage = false
        var fill := StyleBoxFlat.new()
        fill.bg_color = info["color"]
        fill.set_corner_radius_all(4)
        var bg := StyleBoxFlat.new()
        bg.bg_color = Color(1, 1, 1, 0.08)
        bg.set_corner_radius_all(4)
        bar.add_theme_stylebox_override("fill", fill)
        bar.add_theme_stylebox_override("background", bg)

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
    %EndDayButton.disabled = state.needs_decision()
    %EndDayButton.text = "Answer the event first" if state.needs_decision() else "End day %d" % state.day


func _build_crew() -> void:
    for child in %CrewList.get_children():
        child.queue_free()
    for member in state.crew:
        %CrewList.add_child(_make_crew_card(member))


func _make_crew_card(member: CrewMember) -> Control:
    var panel := PanelContainer.new()
    panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
    panel.add_theme_stylebox_override("panel", _card_style(member.is_alive()))
    var box := VBoxContainer.new()
    box.add_theme_constant_override("separation", 8)
    panel.add_child(box)

    var header := HBoxContainer.new()
    var name_label := _label(member.display_name, 32)
    name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    header.add_child(name_label)
    header.add_child(_label(member.role, 22, COLOR_MUTED))
    box.add_child(header)

    if not member.is_alive():
        box.add_child(_label("Deceased", 26, COLOR_BAD))
        panel.modulate = Color(1, 1, 1, 0.5)
        return panel

    var health_bar := ProgressBar.new()
    health_bar.max_value = CrewMember.MAX_HEALTH
    health_bar.value = member.health
    health_bar.custom_minimum_size.y = 16
    health_bar.show_percentage = false
    var fill := StyleBoxFlat.new()
    fill.bg_color = COLOR_GOOD if member.health >= 50 else (COLOR_WARN if member.health >= 25 else COLOR_BAD)
    fill.set_corner_radius_all(4)
    health_bar.add_theme_stylebox_override("fill", fill)
    box.add_child(_label("Health %d / %d" % [member.health, CrewMember.MAX_HEALTH], 22))
    box.add_child(health_bar)

    var status_color := COLOR_GOOD if member.status_text() == "Healthy" else COLOR_WARN
    box.add_child(_label(member.status_text(), 22, status_color))

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
    var task_hint := _label(CrewMember.TASK_HINTS[member.task], 20, COLOR_MUTED)
    task_option.item_selected.connect(func(index: int):
        member.task = task_option.get_item_id(index) as CrewMember.Task
        task_hint.text = CrewMember.TASK_HINTS[member.task]
        _refresh_resources())
    task_row.add_child(task_option)
    box.add_child(task_row)
    box.add_child(task_hint)

    var medkit_button := Button.new()
    medkit_button.text = "Use medkit (+%d hp, cure)" % MissionState.MEDKIT_HEAL
    medkit_button.add_theme_font_size_override("font_size", 20)
    medkit_button.disabled = not state.can_use_medkit(member)
    medkit_button.pressed.connect(func():
        state.use_medkit(member)
        _build_crew.call_deferred()
        _refresh_resources())
    box.add_child(medkit_button)
    return panel


func _build_event() -> void:
    for child in %EventChoices.get_children():
        child.queue_free()

    var event := state.current_event
    if event == null:
        %EventTitle.text = "Quiet day"
        %EventDescription.text = "No incidents reported. Use the time to manage rations and assign the crew."
        return

    %EventTitle.text = event.title
    if state.chosen != null:
        %EventDescription.text = "%s\n\n[color=#%s]Decision: %s[/color]\n[color=#%s]The outcome will be known tomorrow morning.[/color]" % [
            event.description, COLOR_GOOD.to_html(false), state.chosen.label, COLOR_MUTED.to_html(false)]
        return

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
        button.pressed.connect(func():
            state.choose(choice)
            _build_event.call_deferred()
            _refresh_resources())
        %EventChoices.add_child(button)


# --- Day flow -----------------------------------------------------------------

func _on_end_day_pressed() -> void:
    if state.needs_decision():
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


func _show_briefing() -> void:
    _recap_mode = RecapMode.BRIEFING
    var text := "Your crew of %d has launched. Keep them alive for [b]%d days[/b] until the mission is complete.\n\n" % [state.crew.size(), state.mission_days]
    text += "[b]Each day[/b]\n"
    text += "• Choose who gets food and water rations.\n"
    text += "• Assign a task to every crew member. Tasks other than resting cost power.\n"
    text += "• Respond to unexpected events. Their outcome is revealed the next morning.\n\n"
    text += "[b]Every night[/b] the ship produces %d power, life support uses %d, each crew member breathes 1 oxygen and the hull loses %d integrity.\n\n" % [
        MissionState.SOLAR_POWER_PER_DAY, MissionState.LIFE_SUPPORT_POWER, MissionState.HULL_DECAY_PER_DAY]
    text += "[b]Launch bonuses from your augments[/b]\n"
    if state.augment_summary.is_empty():
        text += "[color=#%s]None.[/color]\n" % COLOR_MUTED.to_html(false)
    for line in state.augment_summary:
        text += "• %s\n" % line
    _open_overlay("Mission briefing", text, "Begin day 1")


func _show_recap(recap: Dictionary) -> void:
    _recap_mode = RecapMode.DAILY
    var text := ""

    if recap["event_title"] != "":
        text += "[b]%s[/b]\n" % recap["event_title"]
        text += "You chose: %s\n" % recap["decision"]
        if recap["event_result"] != "":
            text += "[i]%s[/i]\n" % recap["event_result"]
        text += "\n"

    text += "[b]Ship status[/b]\n[table=4]"
    for res_id in MissionState.RESOURCE_IDS:
        var before: int = recap["resources"][res_id][0]
        var after: int = recap["resources"][res_id][1]
        text += _recap_row(MissionState.resource_name(res_id), before, after)
    text += _recap_row("Science", recap["science"][0], recap["science"][1])
    text += "[/table]\n\n"

    text += "[b]Crew[/b]\n"
    for member in state.crew:
        if member.display_name in recap["deaths"]:
            text += "[color=#%s]%s died during the night.[/color]\n" % [COLOR_BAD.to_html(false), member.display_name]
        elif member.is_alive():
            text += "• %s: %d health, %s\n" % [member.display_name, member.health, member.status_text().to_lower()]

    if not recap["log"].is_empty():
        text += "\n[b]Log[/b]\n"
        for line in recap["log"]:
            text += "• %s\n" % line

    var button_text := "Start day %d" % state.day
    if state.outcome != MissionState.Outcome.ONGOING:
        button_text = "Continue"
    _open_overlay("Day %d report" % recap["day"], text, button_text)


func _show_end() -> void:
    _recap_mode = RecapMode.END
    var won := state.outcome == MissionState.Outcome.WON
    var color := COLOR_GOOD if won else COLOR_BAD
    var text := "[color=#%s]%s[/color]\n\n" % [color.to_html(false), state.outcome_text]
    text += "Days survived: %d\nCrew alive: %d / %d\nScience collected: %d\n" % [
        state.day - 1, state.living_crew().size(), state.crew.size(), state.science]
    _open_overlay("Mission complete" if won else "Mission failed", text, "Back to menu")


func _open_overlay(title: String, body: String, button_text: String) -> void:
    %RecapTitle.text = title
    %RecapBody.text = body
    %RecapBody.scroll_to_line(0)
    %RecapButton.text = button_text
    %RecapOverlay.show()


# --- Helpers ------------------------------------------------------------------

func _recap_row(label: String, before: int, after: int) -> String:
    var delta := after - before
    var color := COLOR_GOOD if delta > 0 else (COLOR_BAD if delta < 0 else COLOR_MUTED)
    return "[cell]%s[/cell][cell]  %d[/cell][cell]  -> %d[/cell][cell]  [color=#%s]%s[/color][/cell]" % [
        label, before, after, color.to_html(false), ("%+d" % delta) if delta != 0 else "0"]


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


func _card_style(alive: bool) -> StyleBoxFlat:
    var sb := StyleBoxFlat.new()
    sb.bg_color = Color("16202e") if alive else Color("1a1a1a")
    sb.border_color = Color("2c3e57")
    sb.set_border_width_all(2)
    sb.set_corner_radius_all(8)
    sb.set_content_margin_all(16)
    return sb
