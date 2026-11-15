extends Control
## Mission phase (phase 2): a real-time view of the ship.
##   - Days run on a clock (08:00 to 20:00); pause and speed up at the top.
##   - Click an astronaut, then a room: mission control radios the order and
##     the astronaut floats over. Crew work their station by the hour.
##   - Alerts pop up as bubbles around the ship. Click one, pick what to do and
##     who goes: skill and stress change the odds and the time it takes.
##   - Everything is narrated in the terminal at the bottom: orders typed by
##     mission control, crew replies, alerts and the nightly report.

const MENU_SCENE: String = "res://scenes/select_scenario/select_scenario.tscn"

## Real seconds per game hour at 1x speed.
const HOUR_SECONDS: float = 5.0
const SPEEDS: Array[float] = [1.0, 2.0, 4.0]

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
const T_ALERT := "ff5a3c"
const PROMPT := "[color=#1f8f3c]houston@mission-control[/color]:[color=#63b1ff]~[/color]$ "
const SHORT_PROMPT := "[color=#1f8f3c]houston[/color]:[color=#63b1ff]~[/color]$ "

const CREW_TINTS: Array[Color] = [Color("ffd27a"), Color("ff9aa2"), Color("8fd3ff"), Color("b6f09c")]

## Cards to fly with when this scene is run on its own (no plan phase before
## it), for testing. Ignored when cards were picked in the plan phase.
@export var test_cargo: Array[Augment] = []

var state: MissionState
## Current time of day, 8.0 to 20.0.
var hour: float = MissionState.DAY_START_HOUR
var speed: float = 1.0
var paused: bool = false
## True between 20:00 and the next morning (night report).
var night: bool = false
var selected: CrewMember = null

var _sprites: Dictionary[CrewMember, CrewSprite] = {}
var _tints: Dictionary[CrewMember, Color] = {}
var _bubbles: Array[EventBubble] = []
## Alerts still to come today: [{hour, event}].
var _schedule: Array[Dictionary] = []
## The alert a crew member is on (walking there or working), if any.
var _jobs: Dictionary[CrewMember, EventBubble] = {}
## Where a crew member is heading (their next station) while walking.
var _heading: Dictionary[CrewMember, String] = {}
var _popup_bubble: EventBubble = null
var _popup_choice: EventChoice = null
var _ui_timer: float = 0.0
var _resource_labels: Dictionary[String, Array] = {}
var _roster_cards: Dictionary[CrewMember, Dictionary] = {}
var _speed_buttons: Array[Button] = []
var _pause_button: Button
var _ending: bool = false


func _ready() -> void:
    var scenario_name := TransitionData.scenario_name if TransitionData.scenario_name != "" else "Reach the ISS"
    var cargo: Array[AugmentInstance] = TransitionData.selected_augments
    if cargo.is_empty():
        for augment in test_cargo:
            var instance := AugmentInstance.new(augment, "")
            instance.roll()
            cargo.append(instance)
    state = MissionState.new(scenario_name, TransitionData.scenario_days, MissionState.load_event_pool(), cargo)

    var view: ShipView = %ShipView
    view.clickable_rooms.assign(MissionState.STATIONS.keys())
    view.room_clicked.connect(_on_room_clicked)
    %PopupClose.pressed.connect(_close_popup)
    %RecapButton.pressed.connect(func(): get_tree().change_scene_to_file(MENU_SCENE))
    %RecapOverlay.hide()
    %EventPopup.hide()
    %Terminal.get_v_scroll_bar().modulate = Color.TRANSPARENT

    _build_speed_controls()
    _build_resource_bar()
    _build_roster()
    _build_modules()
    for i in state.crew.size():
        var member := state.crew[i]
        _tints[member] = CREW_TINTS[i % CREW_TINTS.size()]
        var sprite := CrewSprite.new()
        view.add_child(sprite)
        sprite.setup(member, view, _tints[member], member.station)
        sprite.clicked.connect(_select.bind(member))
        sprite.arrived.connect(_on_arrived.bind(member))
        _sprites[member] = sprite

    %TitleLabel.text = state.scenario_name
    state.start_day()
    _schedule_events()
    _briefing()
    _refresh_ui()


# --- Clock ----------------------------------------------------------------------

func game_speed() -> float:
    if paused or night or _ending or %EventPopup.visible:
        return 0.0
    return speed


func _process(delta: float) -> void:
    var gs := game_speed()
    # The clock stops at night, but the crew still floats to bed.
    %ShipView.speed = 3.0 if night and not _ending else gs
    _flush_log()
    if gs > 0.0:
        _advance(delta * gs / HOUR_SECONDS)
    _ui_timer -= delta
    if _ui_timer <= 0.0:
        _ui_timer = 0.2
        _refresh_ui()


func _advance(hours: float) -> void:
    hour += hours
    # Crew at their stations work by the hour.
    for member in state.crew_aboard():
        var sprite := _sprites[member]
        if not _jobs.has(member) and not sprite.is_walking() and not _heading.has(member):
            state.work(member, hours)
    # Alerts: work in progress, or the clock ticking down.
    for bubble in _bubbles.duplicate():
        if bubble.is_assigned():
            if bubble.working:
                bubble.work_done += hours
                if bubble.work_done >= bubble.work_total:
                    _finish_alert(bubble)
        else:
            bubble.hours_left -= hours
            if bubble.hours_left <= 0.0:
                _expire_alert(bubble)
    for entry in _schedule.duplicate():
        if hour >= entry["hour"]:
            _schedule.erase(entry)
            _spawn_alert(entry["event"])
    if hour >= MissionState.DAY_START_HOUR + MissionState.DAY_HOURS:
        _start_night()


func _schedule_events() -> void:
    _schedule.clear()
    if state.day == 1 or randf() < MissionState.EVENT_CHANCE:
        var event := state.draw_event()
        if event != null:
            _schedule.append({"hour": randf_range(9.5, 12.5) if state.day > 1 else 9.5, "event": event})
    if state.day > 1 and randf() < MissionState.SECOND_EVENT_CHANCE:
        var event := state.draw_event()
        if event != null:
            _schedule.append({"hour": randf_range(13.0, 15.5), "event": event})


func _build_speed_controls() -> void:
    _pause_button = _small_button("II")
    _pause_button.tooltip_text = "Pause (Space)"
    _pause_button.toggle_mode = true
    _pause_button.toggled.connect(func(on: bool): paused = on)
    %SpeedBox.add_child(_pause_button)
    for s in SPEEDS:
        var button := _small_button("%dx" % int(s))
        button.toggle_mode = true
        button.button_pressed = s == speed
        button.pressed.connect(_set_speed.bind(s))
        %SpeedBox.add_child(button)
        _speed_buttons.append(button)


func _set_speed(value: float) -> void:
    speed = value
    paused = false
    _pause_button.set_pressed_no_signal(false)
    for i in SPEEDS.size():
        _speed_buttons[i].set_pressed_no_signal(SPEEDS[i] == speed)


func _unhandled_input(event: InputEvent) -> void:
    if event is InputEventKey and event.pressed and not event.echo:
        match event.keycode:
            KEY_SPACE:
                _pause_button.button_pressed = not _pause_button.button_pressed
            KEY_ESCAPE:
                if %EventPopup.visible:
                    _close_popup()
                else:
                    _select(null)
            KEY_1, KEY_2, KEY_3:
                _set_speed(SPEEDS[event.keycode - KEY_1])
    elif event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_RIGHT:
        _select(null)


# --- Orders ---------------------------------------------------------------------

func _select(member: CrewMember) -> void:
    if member != null and not member.is_aboard():
        member = null
    selected = member
    for m in _sprites.keys():
        _sprites[m].selected = m == selected
    var view: ShipView = %ShipView
    if selected == null:
        view.highlight_rooms.clear()
        %ShipHint.text = "Click an astronaut, then a room to send them there. Red bubbles are alerts."
    else:
        view.highlight_rooms.assign(MissionState.STATIONS.keys())
        var where := "on an alert" if _jobs.has(selected) else "in the %s" % ShipView.room_name(_sprites[selected].room)
        %ShipHint.text = "%s (%s) is %s. Click a room to send them there. Right-click to cancel." % [
            selected.display_name, MissionState.SKILL_NAMES.get(selected.skill, selected.role), where]
    _refresh_roster()


func _on_room_clicked(room: String) -> void:
    if night or _ending:
        return
    if selected == null:
        var info: Dictionary = MissionState.STATIONS.get(room, {})
        if not info.is_empty():
            var skilled: String = MissionState.SKILL_NAMES.get(info["skill"], "")
            %ShipHint.text = "%s: %s.%s" % [info["name"], info["hint"], "  Best: %s." % skilled if skilled != "" else ""]
        return
    if not MissionState.STATIONS.has(room):
        return
    _order_move(selected, room)
    _select(null)


func _order_move(member: CrewMember, room: String) -> void:
    if _jobs.has(member):
        _reply(member, "I'm busy with \"%s\" right now. I'll get back to my post after." % _jobs[member].event.title)
        return
    if member.station == room and not _heading.has(member):
        _reply(member, "Already here!")
        return
    _heading[member] = room
    member.station = ""
    _command("order %s --goto %s" % [_slug(member), room])
    var sprite := _sprites[member]
    %Terminal.then(func():
        _reply(member, _move_reply(room))
        if _heading.get(member, "") == room:
            sprite.walk_to(room))


func _move_reply(room: String) -> String:
    var lines := {
        "bunks": "Copy. Going to get some rest.",
        "medbay": "Heading to the medbay.",
        "comms": "On my way to the comms room. Time to call home!",
        "cupola": "Going to look at Earth for a bit.",
        "lab": "Heading to the lab. Science time!",
        "engineering": "Copy, going to the power core to fix things up.",
        "life_support": "On it, heading to life support.",
    }
    return lines.get(room, "Copy that.")


func _on_arrived(member: CrewMember) -> void:
    if _jobs.has(member):
        _jobs[member].working = true
        return
    if _heading.has(member):
        member.station = _heading[member]
        _heading.erase(member)


# --- Alerts ---------------------------------------------------------------------

func _spawn_alert(event: MissionEvent) -> void:
    var bubble := EventBubble.new()
    %ShipView.add_child(bubble)
    bubble.setup(event, %ShipView)
    bubble.clicked.connect(_open_popup.bind(bubble))
    bubble.tooltip_text = ""
    _bubbles.append(bubble)
    _alert("%s  [color=#%s](%s)[/color]" % [event.title, T_DIM, ShipView.room_name(bubble.room)])


func _open_popup(bubble: EventBubble) -> void:
    _popup_bubble = bubble
    _popup_choice = null
    _fill_popup()
    %EventPopup.show()


func _close_popup() -> void:
    %EventPopup.hide()
    _popup_bubble = null
    _popup_choice = null


func _fill_popup() -> void:
    var bubble := _popup_bubble
    var event := bubble.event
    %PopupTitle.text = event.title
    %PopupDesc.text = event.description
    for child in %PopupChoices.get_children():
        child.queue_free()

    var skill_name: String = MissionState.SKILL_NAMES.get(event.skill, "anyone")
    if bubble.is_assigned():
        %PopupKicker.text = "IN PROGRESS"
        %PopupInfo.text = "%s is on it: \"%s\" (%d%% done)." % [
            bubble.worker.display_name, bubble.choice.label, int(100.0 * bubble.work_done / maxf(bubble.work_total, 0.01))]
        return
    %PopupKicker.text = "ALERT  -  %s" % ShipView.room_name(bubble.room).to_upper()
    %PopupInfo.text = "Best handled by: [color=#%s]%s[/color]   -   Time left: [color=#%s]%.1f h[/color]   -   If nobody goes: \"%s\"" % [
        T_BLUE, skill_name, T_AMBER, bubble.hours_left, event.choices[-1].label]

    if _popup_choice == null:
        for choice in event.choices:
            var button := Button.new()
            button.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
            button.custom_minimum_size = Vector2(0, 54)
            button.add_theme_font_size_override("font_size", 22)
            var parts: PackedStringArray = []
            if not choice.cost.is_empty():
                parts.append(_format_cost(choice.cost))
            if choice.needs_crew:
                parts.append("send someone, ~%.1f h" % choice.work_hours)
            else:
                parts.append("radio order")
            if choice.success_chance < 1.0:
                parts.append("risky")
            button.text = "%s   (%s)" % [choice.label, ", ".join(parts)]
            button.disabled = not state.can_afford(choice.cost)
            button.pressed.connect(_pick_choice.bind(choice))
            %PopupChoices.add_child(button)
        _add_navigation_buttons(event)
        return

    # Second step: who goes?
    var header := _label("\"%s\": who should go?" % _popup_choice.label, 22, COLOR_WARN)
    header.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
    %PopupChoices.add_child(header)
    for member in state.crew_aboard():
        var button := Button.new()
        button.custom_minimum_size = Vector2(0, 50)
        button.add_theme_font_size_override("font_size", 22)
        button.alignment = HORIZONTAL_ALIGNMENT_LEFT
        var chance := state.event_chance(event, _popup_choice, member)
        var hours := state.event_hours(event, _popup_choice, member)
        var notes: PackedStringArray = []
        if state.is_skilled_for(member, event):
            notes.append("skilled")
        if member.is_overwhelmed():
            notes.append("overwhelmed")
        elif member.stress >= CrewMember.STRESSED:
            notes.append("stressed")
        if member.sick:
            notes.append("unwell")
        button.text = "%s  -  %d%% success, %.1f h%s" % [member.display_name, roundi(chance * 100.0), hours,
            ("   [%s]" % ", ".join(notes)) if not notes.is_empty() else ""]
        button.add_theme_color_override("font_color", _tints[member])
        if _jobs.has(member):
            button.disabled = true
            button.text += "   (busy)"
        button.pressed.connect(_dispatch.bind(member))
        %PopupChoices.add_child(button)
    var back := Button.new()
    back.text = "Back"
    back.add_theme_font_size_override("font_size", 20)
    back.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
    back.pressed.connect(func():
        _popup_choice = null
        _fill_popup())
    %PopupChoices.add_child(back)


## Star tracker (redraw the alert) and AutoNav (cancel a bad one).
func _add_navigation_buttons(event: MissionEvent) -> void:
    var row := HBoxContainer.new()
    row.add_theme_constant_override("separation", 10)
    if state.can_reroll():
        var reroll := Button.new()
        reroll.text = "Redraw this alert (star tracker, %d left)" % state.rerolls_left
        reroll.add_theme_font_size_override("font_size", 19)
        reroll.add_theme_color_override("font_color", Augment.DOMAIN_COLORS[Augment.Domain.NAVIGATION])
        reroll.pressed.connect(_reroll_alert)
        row.add_child(reroll)
    if state.cancel_cooldown() > 0 and not event.tags.has(&"good"):
        var cancel := Button.new()
        var wait := state.cancel_wait()
        cancel.text = "Cancel it (AutoNav)" if wait == 0 else "AutoNav recharging: %d day%s" % [wait, "" if wait == 1 else "s"]
        cancel.disabled = not state.can_cancel(event)
        cancel.add_theme_font_size_override("font_size", 19)
        cancel.add_theme_color_override("font_color", Augment.DOMAIN_COLORS[Augment.Domain.NAVIGATION])
        cancel.pressed.connect(_cancel_alert)
        row.add_child(cancel)
    if row.get_child_count() > 0:
        %PopupChoices.add_child(row)
    else:
        row.free()


func _reroll_alert() -> void:
    var bubble := _popup_bubble
    if bubble == null:
        return
    var other := state.reroll_event(bubble.event)
    if other == null:
        return
    _command("nav --star-tracker --reroll \"%s\"" % bubble.event.title.to_lower())
    _info("The star tracker found a better path: \"%s\" is gone, but there's something else." % bubble.event.title)
    bubble.set_event(other)
    _alert("%s  [color=#%s](%s)[/color]" % [other.title, T_DIM, ShipView.room_name(bubble.room)])
    _fill_popup()


func _cancel_alert() -> void:
    var bubble := _popup_bubble
    if bubble == null or not state.cancel_event(bubble.event):
        return
    _close_popup()
    _remove_bubble(bubble)
    _command("nav --autonav --avoid \"%s\"" % bubble.event.title.to_lower())
    %Terminal.then(func(): _info("AutoNav re-planned the route: \"%s\" is no longer a problem." % bubble.event.title))


func _pick_choice(choice: EventChoice) -> void:
    if choice.needs_crew:
        _popup_choice = choice
        _fill_popup()
        return
    # Radio order: resolved right away.
    var bubble := _popup_bubble
    _close_popup()
    if not state.begin_event_choice(choice):
        return
    _remove_bubble(bubble)
    _command("transmit --to crew \"%s\"" % choice.label)
    %Terminal.then(func():
        var result := state.finish_event_choice(bubble.event, choice, null)
        _crew_says(state.crew_aboard().pick_random() if not state.crew_aboard().is_empty() else null,
            "Copy. %s" % result["text"], result["success"]))


func _dispatch(member: CrewMember) -> void:
    var bubble := _popup_bubble
    var choice := _popup_choice
    _close_popup()
    if bubble == null or choice == null or _jobs.has(member) or not state.begin_event_choice(choice):
        return
    bubble.worker = member
    bubble.choice = choice
    bubble.work_total = state.event_hours(bubble.event, choice, member)
    _jobs[member] = bubble
    var previous: String = member.station if member.station != "" else _heading.get(member, "bunks")
    _heading[member] = previous
    member.station = ""
    _command("dispatch %s --to %s --task \"%s\"" % [_slug(member), bubble.room, choice.label.to_lower()])
    var sprite := _sprites[member]
    var target := %ShipView.room_spot(bubble.room) as Vector2
    %Terminal.then(func():
        _reply(member, "On my way to the %s!" % ShipView.room_name(bubble.room).to_lower())
        if _jobs.get(member) == bubble:
            sprite.walk_to(bubble.room, target))


func _finish_alert(bubble: EventBubble) -> void:
    var member := bubble.worker
    var result := state.finish_event_choice(bubble.event, bubble.choice, member)
    _jobs.erase(member)
    _remove_bubble(bubble)
    _crew_says(member, result["text"] if result["text"] != "" else "Done!", result["success"])
    if member.is_aboard() and not night:
        var back: String = _heading.get(member, "bunks")
        _sprites[member].walk_to(back)


func _expire_alert(bubble: EventBubble) -> void:
    _remove_bubble(bubble)
    var result := state.ignore_event(bubble.event)
    _alert("Nobody answered \"%s\". The crew went with: %s" % [bubble.event.title, bubble.event.choices[-1].label.to_lower()])
    if result["text"] != "":
        _info(result["text"])


func _remove_bubble(bubble: EventBubble) -> void:
    _bubbles.erase(bubble)
    if _popup_bubble == bubble:
        _close_popup()
    bubble.queue_free()


# --- Night ----------------------------------------------------------------------

func _start_night() -> void:
    night = true
    hour = MissionState.DAY_START_HOUR + MissionState.DAY_HOURS
    _select(null)
    # Unfinished work wraps up, unanswered alerts fall back to the default.
    for bubble in _bubbles.duplicate():
        if bubble.is_assigned():
            _finish_alert(bubble)
        else:
            _expire_alert(bubble)
    _schedule.clear()
    create_tween().tween_property(%ShipView, "night", 1.0, 1.0)
    for member in state.crew_aboard():
        _sprites[member].walk_to("bunks")
    _flush_log()

    var recap := state.end_day()
    var term: TerminalLabel = %Terminal
    term.print_text("\n[color=#%s]==== NIGHT %d REPORT ====[/color]\n" % [T_AMBER, recap["day"]], 0.2)
    var parts: PackedStringArray = []
    for res_id in MissionState.RESOURCE_IDS:
        var before: int = recap["resources"][res_id][0]
        var after: int = recap["resources"][res_id][1]
        var delta := after - before
        var color := T_GREEN if delta > 0 else (T_RED if delta < 0 else T_DIM)
        parts.append("%s %d%s [color=#%s](%s)[/color]" % [MissionState.resource_name(res_id).to_lower(), after,
            MissionState.unit(res_id) if MissionState.unit(res_id) in ["L", "kg", "%"] else "", color, "%+d" % delta if delta != 0 else "="])
    term.print_text("  " + "  ".join(parts) + "\n")
    for line in state.drain_log():
        term.print_text("  * %s\n" % line)
    for entry in recap["sent_home"]:
        term.print_text("  [color=#%s]%s %s and took the return capsule home. They landed safely![/color]\n" % [T_AMBER, entry["name"], entry["reason"]])
    for member in state.crew:
        if not member.is_aboard() and _sprites.has(member):
            var sprite := _sprites[member]
            _sprites.erase(member)
            var tween := create_tween()
            tween.tween_property(sprite, "modulate:a", 0.0, 1.5)
            tween.tween_callback(sprite.queue_free)
    term.wait(1.5)
    term.then(_morning)


func _morning() -> void:
    if state.outcome != MissionState.Outcome.ONGOING:
        _show_end()
        return
    night = false
    hour = MissionState.DAY_START_HOUR
    state.start_day()
    _schedule_events()
    create_tween().tween_property(%ShipView, "night", 0.0, 1.0)
    for member in state.crew_aboard():
        var station: String = member.station if member.station != "" else _heading.get(member, "bunks")
        member.station = ""
        _heading[member] = station
        _sprites[member].walk_to(station)
    _build_modules()
    %Terminal.print_text("\n[color=#%s]==== DAY %d / %d  -  08:00 ====[/color]\n" % [T_AMBER, state.day, state.mission_days])
    _flush_log()


# --- Terminal -------------------------------------------------------------------

func _briefing() -> void:
    var term: TerminalLabel = %Terminal
    term.clear_terminal()
    term.print_text(PROMPT, 0.3)
    term.type_text("./open_channel --crew\n", 0.3)
    term.print_text("[color=#%s]uplink ........ [/color][color=#%s][OK][/color]\n" % [T_DIM, T_GREEN])
    term.print_text("Mission: [color=#%s]%s[/color] in [color=#%s]%d days[/color]. %d crew aboard, %d modules running.\n" % [
        T_BLUE, state.scenario_name, T_BLUE, state.mission_days, state.crew.size(), state.ship_modules().size()])
    term.print_text("[color=#%s]Click an astronaut, then a room to send them there. Red bubbles are alerts: click them to send help. Space pauses.[/color]\n" % T_DIM)
    term.print_text("\n[color=#%s]==== DAY 1 / %d  -  08:00 ====[/color]\n" % [T_AMBER, state.mission_days])


func _command(text: String) -> void:
    %Terminal.print_text(SHORT_PROMPT)
    %Terminal.type_text(text + "\n", 0.1)


func _reply(member: CrewMember, text: String) -> void:
    %Terminal.print_text("[color=#%s][%s][/color] %s\n" % [_tints[member].to_html(false), _short_name(member).to_upper(), text])


func _crew_says(member: CrewMember, text: String, good: bool) -> void:
    var color := T_GREEN if good else T_AMBER
    if member == null:
        %Terminal.print_text("[color=#%s]%s[/color]\n" % [color, text])
        return
    %Terminal.print_text("[color=#%s][%s][/color] [color=#%s]%s[/color]\n" % [_tints[member].to_html(false), _short_name(member).to_upper(), color, text])


func _alert(text: String) -> void:
    %Terminal.print_text("[color=#%s][ALERT][/color] %s\n" % [T_ALERT, text])


func _info(text: String) -> void:
    %Terminal.print_text("[color=#%s]%s[/color]\n" % [T_DIM, text])


## Prints whatever the simulation reported (repairs, risks, discoveries...).
func _flush_log() -> void:
    if night:
        return
    for line in state.drain_log():
        %Terminal.print_text("[color=#%s]*[/color] %s\n" % [T_DIM, line])


func _slug(member: CrewMember) -> String:
    return _short_name(member).to_lower()


func _short_name(member: CrewMember) -> String:
    return member.display_name.get_slice(" ", 1) if member.display_name.contains(" ") else member.display_name


# --- UI -------------------------------------------------------------------------

func _refresh_ui() -> void:
    %ClockLabel.text = "Day %d/%d  %02d:%02d" % [state.day, state.mission_days, floori(hour), int(fmod(hour, 1.0) * 60.0)] \
        if not night else "Day %d/%d  Night" % [state.day - 1, state.mission_days]
    %Trajectory.set_day(state.day - 1, state.mission_days)
    %ScienceLabel.text = "Science %d" % state.science
    var forecast := state.forecast()
    for res_id in MissionState.RESOURCE_IDS:
        var labels: Array = _resource_labels[res_id]
        var amount: int = state.resources[res_id]
        var delta: int = forecast[res_id]
        labels[0].text = "%d%s" % [amount, MissionState.unit(res_id) if MissionState.unit(res_id) in ["L", "kg", "%"] else ""]
        labels[0].add_theme_color_override("font_color", COLOR_BAD if amount + delta < 0 or (amount == 0 and res_id != "medkits") else Color.WHITE)
        labels[1].text = ("%+d" % delta) if delta != 0 else ""
        labels[1].add_theme_color_override("font_color", COLOR_GOOD if delta > 0 else COLOR_BAD)
    for member in _sprites.keys():
        var sprite := _sprites[member]
        sprite.badge = ""
        if _jobs.has(member):
            sprite.badge = "..."
            sprite.badge_color = Color("63b1ff")
        elif member.sick:
            sprite.badge = "+"
            sprite.badge_color = COLOR_BAD
        elif member.is_overwhelmed():
            sprite.badge = "!"
            sprite.badge_color = COLOR_WARN
        elif member.station == "bunks" or night:
            sprite.badge = "z"
            sprite.badge_color = Color("8fd3ff")
    if %EventPopup.visible and _popup_bubble != null and _popup_bubble.is_assigned():
        _fill_popup()
    _refresh_roster()


func _build_resource_bar() -> void:
    for res_id in MissionState.RESOURCE_IDS:
        var info: Dictionary = MissionState.RESOURCE_INFO[res_id]
        var chip := HBoxContainer.new()
        chip.add_theme_constant_override("separation", 6)
        chip.tooltip_text = "%s. Small number: expected change tonight." % info["name"]
        var swatch := ColorRect.new()
        swatch.color = info["color"]
        swatch.custom_minimum_size = Vector2(6, 26)
        swatch.size_flags_vertical = Control.SIZE_SHRINK_CENTER
        chip.add_child(swatch)
        var name_label := _label(info["name"], 18, COLOR_MUTED)
        name_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
        chip.add_child(name_label)
        var value := _label("", 24)
        value.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
        chip.add_child(value)
        var delta := _label("", 18)
        delta.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
        chip.add_child(delta)
        %ResourceBar.add_child(chip)
        _resource_labels[res_id] = [value, delta]


func _build_roster() -> void:
    for child in %Roster.get_children():
        child.queue_free()
    _roster_cards.clear()
    for i in state.crew.size():
        var member := state.crew[i]
        var tint := CREW_TINTS[i % CREW_TINTS.size()]
        var panel := PanelContainer.new()
        panel.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
        panel.gui_input.connect(func(e: InputEvent):
            if e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT:
                _select(null if selected == member else member))
        var box := VBoxContainer.new()
        box.add_theme_constant_override("separation", 4)
        box.mouse_filter = Control.MOUSE_FILTER_IGNORE
        panel.add_child(box)
        var header := HBoxContainer.new()
        header.mouse_filter = Control.MOUSE_FILTER_IGNORE
        var name_label := _label(member.display_name, 26, tint)
        name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
        header.add_child(name_label)
        header.add_child(_label(member.role, 18, COLOR_MUTED))
        box.add_child(header)
        var health := _stat_row("Health")
        var stress := _stat_row("Stress")
        box.add_child(health["row"])
        box.add_child(stress["row"])
        var activity := _label("", 18, COLOR_MUTED)
        activity.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
        box.add_child(activity)
        var medkit := Button.new()
        medkit.text = "Use medkit (+%d health)" % MissionState.MEDKIT_HEAL
        medkit.add_theme_font_size_override("font_size", 16)
        medkit.pressed.connect(func():
            state.use_medkit(member)
            _refresh_ui())
        box.add_child(medkit)
        %Roster.add_child(panel)
        _roster_cards[member] = {"panel": panel, "health": health, "stress": stress, "activity": activity, "medkit": medkit}


func _refresh_roster() -> void:
    for member in _roster_cards.keys():
        var card: Dictionary = _roster_cards[member]
        var panel: PanelContainer = card["panel"]
        panel.add_theme_stylebox_override("panel", _card_style(member.is_aboard(), member == selected))
        var activity: Label = card["activity"]
        var medkit: Button = card["medkit"]
        if not member.is_aboard():
            panel.modulate = Color(1, 1, 1, 0.55)
            activity.text = "Back on Earth: %s. Safe and sound!" % member.left_reason
            activity.add_theme_color_override("font_color", COLOR_GOOD)
            card["health"]["row"].hide()
            card["stress"]["row"].hide()
            medkit.hide()
            continue
        _set_stat(card["health"], member.health, COLOR_GOOD if member.health >= 50 else (COLOR_WARN if member.health >= 25 else COLOR_BAD))
        _set_stat(card["stress"], member.stress, COLOR_STRESS if member.stress < CrewMember.STRESSED else (COLOR_WARN if member.stress < CrewMember.OVERWHELMED else COLOR_BAD))
        activity.text = _activity_text(member)
        activity.add_theme_color_override("font_color", COLOR_MUTED if member.is_doing_great() else COLOR_WARN)
        medkit.visible = member.sick or member.health < 50
        medkit.disabled = not state.can_use_medkit(member)


func _activity_text(member: CrewMember) -> String:
    var sprite := _sprites.get(member) as CrewSprite
    var status := ""
    if night:
        status = "Sleeping"
    elif _jobs.has(member):
        var bubble := _jobs[member]
        status = ("Working on \"%s\" (%d%%)" % [bubble.event.title, int(100.0 * bubble.work_done / maxf(bubble.work_total, 0.01))]) \
            if bubble.working else "On the way: %s" % bubble.event.title
    elif _heading.has(member) or (sprite != null and sprite.is_walking() and member.station == ""):
        status = "Heading to the %s" % ShipView.room_name(_heading.get(member, "bunks")).to_lower()
    elif MissionState.STATIONS.has(member.station):
        var info: Dictionary = MissionState.STATIONS[member.station]
        var verb: String = info["verb"]
        status = verb.left(1).to_upper() + verb.substr(1)
        if member.station == "comms" and state.comms_down:
            status += " (radio down!)"
        elif state.is_skilled_at(member, member.station):
            status += " (expert)"
    var condition := member.status_text()
    return status + ("" if member.is_doing_great() else "  -  " + condition)


func _stat_row(title: String) -> Dictionary:
    var row := HBoxContainer.new()
    row.add_theme_constant_override("separation", 10)
    row.mouse_filter = Control.MOUSE_FILTER_IGNORE
    var label := _label(title, 18)
    label.custom_minimum_size.x = 110
    row.add_child(label)
    var bar := _bar(Color.WHITE, 12)
    bar.max_value = 100
    bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
    bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
    row.add_child(bar)
    return {"row": row, "label": label, "bar": bar, "title": title}


func _set_stat(stat: Dictionary, value: int, color: Color) -> void:
    stat["label"].text = "%s %d" % [stat["title"], value]
    var bar: ProgressBar = stat["bar"]
    bar.value = value
    (bar.get_theme_stylebox("fill") as StyleBoxFlat).bg_color = color


func _build_modules() -> void:
    for child in %ModuleList.get_children():
        child.queue_free()
    var ship_modules := state.ship_modules()
    %ModulesHeader.text = "Modules (%d)" % ship_modules.size()
    if ship_modules.is_empty():
        var empty := _label("No modules aboard: the crew relies on the capsule's own supplies.", 18, COLOR_MUTED)
        empty.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
        %ModuleList.add_child(empty)
    for module in ship_modules:
        %ModuleList.add_child(_make_module_row(module))


func _make_module_row(module: ShipModule) -> Control:
    var augment := module.augment
    var row := HBoxContainer.new()
    row.add_theme_constant_override("separation", 8)
    var swatch := ColorRect.new()
    swatch.color = Augment.DOMAIN_COLORS[augment.domain]
    swatch.custom_minimum_size = Vector2(6, 0)
    row.add_child(swatch)

    var box := VBoxContainer.new()
    box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    box.add_theme_constant_override("separation", 0)
    box.add_child(_label(augment.card_name(), 18, Augment.RARITY_COLORS[augment.rarity]))
    var effects := state.module_daily(module)
    var parts: PackedStringArray = []
    for key in effects.keys():
        if effects[key] != 0:
            parts.append(Augment.daily_line(key, effects[key]))
    if augment.hazard_reduction > 0.0:
        parts.append("hazards -%d%%" % roundi(augment.hazard_reduction * 100.0))
    var detail := ", ".join(parts) + " / night" if not parts.is_empty() else "Supplies loaded at launch"
    var status_color := COLOR_MUTED
    if not module.working() or module.unpowered:
        detail = module.status_text()
        status_color = COLOR_BAD if module.broken or module.lost else COLOR_WARN
    var detail_label := _label(detail, 15, status_color)
    detail_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
    box.add_child(detail_label)
    row.add_child(box)

    if augment.toggleable and not module.lost:
        var toggle := CheckButton.new()
        toggle.button_pressed = module.enabled
        toggle.tooltip_text = "Switch this module on or off for tonight"
        toggle.size_flags_vertical = Control.SIZE_SHRINK_CENTER
        toggle.toggled.connect(func(on: bool):
            module.enabled = on
            _command("%s %s" % ["power_on" if on else "power_off", augment.card_name().to_lower().replace(" ", "_")])
            _build_modules.call_deferred()
            _refresh_ui())
        row.add_child(toggle)
    if module.lost:
        row.modulate = Color(1, 1, 1, 0.5)
    return row


# --- End of mission -------------------------------------------------------------

func _show_end() -> void:
    _ending = true
    var won := state.outcome == MissionState.Outcome.WON
    var t := _title_line("MISSION COMPLETE" if won else "MISSION CALLED OFF")
    t += "[color=#%s]%s[/color]\n\n" % [T_GREEN if won else T_AMBER, state.outcome_text]
    t += "[color=#%s][FINAL STATS][/color]\n" % T_AMBER
    t += "  days in space ..... %d\n" % (state.day - 1)
    t += "  crew aboard ....... %d / %d\n" % [state.crew_aboard().size(), state.crew.size()]
    t += "  science ........... %d\n\n" % state.science
    t += "[color=#%s][CREW][/color]\n" % T_AMBER
    for member in state.crew:
        var where := "made it to the station" if member.is_aboard() and won else ("back on Earth, safe and sound" if not member.is_aboard() or not won else "aboard")
        t += "  %-16s %s\n" % [member.display_name, where]
    t += "\n[color=#%s]Everyone is safe. Thanks for flying with mission control![/color]\n" % T_DIM
    %WindowTitle.text = "houston@mission-control: ~"
    %RecapButton.text = "> BACK TO MENU"
    %RecapButton.hide()
    var term: TerminalLabel = %RecapTerminal
    term.clear_terminal()
    term.print_text(PROMPT, 0.3)
    term.type_text("./mission_status --final\n", 0.3)
    for chunk in t.split("\n\n", false):
        term.print_text(chunk + "\n\n", 0.08)
    term.then(func():
        %RecapButton.show()
        %RecapButton.grab_focus())
    %RecapOverlay.show()


func _title_line(title: String) -> String:
    var bar := "=".repeat(mini(72, title.length() + 8))
    return "[color=#%s]%s\n    %s\n%s[/color]\n\n" % [T_DIM, bar, title, bar]


# --- Helpers --------------------------------------------------------------------

func _format_cost(cost: Dictionary) -> String:
    var parts: PackedStringArray = []
    for key in cost.keys():
        parts.append(MissionState.amount_text(key, -cost[key]))
    return ", ".join(parts)


func _small_button(text: String) -> Button:
    var button := Button.new()
    button.text = text
    button.custom_minimum_size = Vector2(52, 44)
    button.add_theme_font_size_override("font_size", 20)
    button.focus_mode = Control.FOCUS_NONE
    return button


func _label(text: String, font_size: int, color: Color = Color.WHITE) -> Label:
    var label := Label.new()
    label.text = text
    label.add_theme_font_size_override("font_size", font_size)
    label.add_theme_color_override("font_color", color)
    label.mouse_filter = Control.MOUSE_FILTER_IGNORE
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


func _card_style(aboard: bool, is_selected: bool) -> StyleBoxFlat:
    var sb := StyleBoxFlat.new()
    sb.bg_color = Color(0.086, 0.125, 0.18, 0.92) if aboard else Color(0.1, 0.1, 0.1, 0.85)
    sb.border_color = Color("63b1ff") if is_selected else Color("2c3e57")
    sb.set_border_width_all(3 if is_selected else 2)
    sb.set_corner_radius_all(8)
    sb.set_content_margin_all(12)
    return sb
