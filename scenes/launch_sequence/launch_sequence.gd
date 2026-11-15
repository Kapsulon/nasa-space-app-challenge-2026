extends Control
## Transition between the launch report and the mission: the countdown and
## the launch itself. Whether the rocket reaches orbit is rolled from the
## launch odds of the picked cargo (see LaunchProfile). Nobody gets hurt on a
## failure: the launch is either scrubbed on the pad, or the capsule
## parachutes back into the sea, and the player goes back to planning.

const MISSION_SCENE: String = "res://scenes/mission_phase/mission_phase.tscn"
const PLAN_SCENE: String = "res://scenes/plan_phase/plan_phase.tscn"

const GREEN := "39ff6a"
const DIM := "1f8f3c"
const AMBER := "ffb800"
const RED := "ff3a55"

## Capsule height at which orbit is reached, and where a fuel abort happens.
const ORBIT_ALTITUDE: float = 9000.0
const FUEL_ABORT_ALTITUDE: float = 4200.0
const ORBIT_KM: float = 200.0
const ORBIT_SPEED_KMH: float = 27600.0
## Time scale while the player fast-forwards.
const FAST_FORWARD: float = 4.0

## For testing: -1 rolls the launch normally, otherwise forces the outcome
## (0 = success, 1 = too heavy, 2 = out of fuel, 3 = glitch).
@export_range(-1, 3) var forced_outcome: int = -1

var profile: LaunchProfile
var chance: float
var failure: LaunchProfile.Failure

var _clock: String = "T-10"
var _flight_time: float = -1.0
var _finished: bool = false
var _leaving: bool = false

@onready var view: LaunchView = %LaunchView
@onready var telemetry: TerminalLabel = %Telemetry


func _ready() -> void:
    profile = LaunchProfile.from_instances(TransitionData.selected_augments)
    chance = profile.success_chance()
    failure = profile.roll() if forced_outcome < 0 else forced_outcome as LaunchProfile.Failure
    %ResultPanel.hide()
    %Countdown.text = ""
    %ResultButton.pressed.connect(_on_result_pressed)
    telemetry.clear_terminal()
    telemetry.get_v_scroll_bar().modulate = Color.TRANSPARENT
    _update_hud()
    _run()


func _exit_tree() -> void:
    Engine.time_scale = 1.0


func _input(event: InputEvent) -> void:
    if _finished:
        return
    var pressed: bool = (event is InputEventKey and event.pressed and not event.echo) \
        or (event is InputEventMouseButton and event.pressed)
    if pressed and Engine.time_scale < FAST_FORWARD:
        get_viewport().set_input_as_handled()
        Engine.time_scale = FAST_FORWARD
        %SkipHint.text = ">> FAST-FORWARD x%d" % int(FAST_FORWARD)


func _process(delta: float) -> void:
    if _flight_time >= 0.0 and not _finished:
        _flight_time += delta
        _clock = "T+%02d:%02d" % [floori(_flight_time / 60.0), int(_flight_time) % 60]
    _update_hud()


# --- Sequence -------------------------------------------------------------------

func _run() -> void:
    _log("LAUNCH ODDS: [color=#%s]%d%%[/color]" % [_odds_color(chance), roundi(chance * 100.0)])
    for t in range(10, 0, -1):
        _clock = "T-%02d" % t
        %Countdown.text = "T-%d" % t
        match t:
            10: _log("COUNTDOWN STARTED")
            8: _log("GO/NO-GO POLL: ALL STATIONS GO")
            6:
                _log("FUEL LOADED: %d" % roundi(profile.fuel))
                if profile.fuel_leak > 0.0:
                    _log("[color=#%s]%d FUEL LEAKED OR BOILED OFF, %d LEFT[/color]" % [AMBER, roundi(profile.fuel_leak), roundi(profile.fuel_available())])
            5: _log("CREW STRAPPED IN AND SMILING")
            3:
                _log("IGNITION SEQUENCE START")
                _tween(view, "throttle", 0.45, 2.0)
                _tween(view, "shake", 2.0, 2.0)
            2:
                if failure == LaunchProfile.Failure.GLITCH:
                    await _glitch_hold()
                    return
        await _wait(1.0)

    _clock = "T+00:00"
    if failure == LaunchProfile.Failure.THRUST:
        await _too_heavy()
        return
    await _liftoff()
    if failure == LaunchProfile.Failure.FUEL:
        await _fuel_abort()
    else:
        await _reach_orbit()


func _liftoff() -> void:
    _flight_time = 0.0
    %Countdown.text = "LIFTOFF!"
    _log("[color=#%s]LIFTOFF![/color] THE CREW IS ON ITS WAY" % GREEN)
    _tween(view, "throttle", 1.0, 0.4)
    _tween(view, "shake", 6.0, 0.4)
    var tween := create_tween()
    tween.tween_property(view, "altitude", LaunchView.START_ALTITUDE + 900.0, 5.0) \
        .set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
    await _wait(2.5)
    _log("CLEARED THE TOWER")
    await tween.finished
    %Countdown.text = ""
    _tween(view, "shake", 2.0, 3.0)


func _reach_orbit() -> void:
    var tween := create_tween()
    tween.tween_property(view, "altitude", ORBIT_ALTITUDE - 1200.0, 11.0)
    tween.tween_property(view, "altitude", ORBIT_ALTITUDE, 3.5).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
    await _wait(1.5)
    _log("MAX-Q: PEAK PRESSURE, ROCKET HOLDING STEADY")
    await _wait(4.0)
    _log("ABOVE THE CLOUDS, THE SKY IS TURNING BLACK")
    await _wait(4.5)
    _log("MAIN ENGINE CUTOFF IN 3... 2... 1...")
    _tween(view, "throttle", 0.0, 3.5)
    _tween(view, "shake", 0.0, 2.0)
    await tween.finished
    _log("[color=#%s]ORBIT REACHED![/color] %d KM ABOVE EARTH" % [GREEN, roundi(ORBIT_KM)])
    %Countdown.text = "ORBIT!"
    await _wait(1.5)
    _show_result(
        "ORBIT REACHED", GREEN,
        "The rocket carried the crew and [color=#%s]%.1f t[/color] of cargo all the way to orbit.\nNext stop: the International Space Station!" % [AMBER, profile.cargo_tons],
        "> START THE MISSION")


func _fuel_abort() -> void:
    var climb := create_tween()
    climb.tween_property(view, "altitude", FUEL_ABORT_ALTITUDE, 7.0)
    await _wait(1.5)
    _log("MAX-Q: PEAK PRESSURE, ROCKET HOLDING STEADY")
    await climb.finished
    _log("[color=#%s]FUEL RUNNING LOW, ORBIT OUT OF REACH[/color]" % AMBER)
    var coast := create_tween()
    coast.tween_property(view, "altitude", FUEL_ABORT_ALTITUDE + 250.0, 1.6).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_QUAD)
    var sputter := create_tween()
    for level: float in [0.3, 0.9, 0.2, 0.7, 0.1, 0.0]:
        sputter.tween_property(view, "throttle", level, 0.25)
    await coast.finished

    _log("[color=#%s]ABORT![/color] CAPSULE SEPARATING, JUST LIKE IN TRAINING" % AMBER)
    %Countdown.text = "ABORT"
    view.booster_altitude = view.altitude - LaunchView.ROCKET_HEIGHT
    view.separated = true
    view.escape_burn = true
    view.shake = 3.0
    var fall := create_tween().set_parallel()
    fall.tween_property(view, "booster_altitude", view.booster_altitude - 1400.0, 3.0).set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_QUAD)
    fall.tween_property(view, "booster_alpha", 0.0, 2.5)
    var escape := create_tween()
    escape.tween_property(view, "altitude", view.altitude + 260.0, 1.2).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_QUAD)
    await escape.finished
    view.escape_burn = false
    view.show_tower = false
    view.shake = 0.0
    %Countdown.text = ""

    _log("PARACHUTES OPEN")
    _tween(view, "parachute", 1.0, 1.2)
    var descent := create_tween().set_parallel()
    descent.tween_property(view, "altitude", LaunchView.SPLASH_ALTITUDE, 9.0).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_SINE)
    descent.tween_property(view, "drift", 420.0, 9.0).set_ease(Tween.EASE_IN_OUT).set_trans(Tween.TRANS_SINE)
    await _wait(4.0)
    _log("BLUE SKY AGAIN, GENTLE RIDE DOWN")
    await descent.finished
    _tween(view, "splash", 1.0, 1.5)
    _log("[color=#%s]SPLASHDOWN![/color] RECOVERY BOAT ON THE WAY" % GREEN)
    %Countdown.text = "SPLASHDOWN"
    await _wait(2.0)
    _show_result(
        "SPLASHDOWN", AMBER,
        ("The engines ran the tanks dry before reaching orbit: they had [color=#%s]%d fuel[/color], but these engines burn about [color=#%s]%d[/color] on the way up.\n" +
        "The capsule separated and floated down under its parachute. A recovery boat picked up the crew, safe and smiling!\n\n" +
        "[color=#%s]Tip: every engine burns fuel at take-off. Fuel tanks keep them going.[/color]") % [
            RED, roundi(profile.fuel_available()), AMBER, ceili(profile.fuel_needed() * LaunchProfile.FUEL_SAFE), DIM],
        "> BACK TO PLANNING")


func _too_heavy() -> void:
    %Countdown.text = "IGNITION"
    _tween(view, "throttle", 1.0, 0.4)
    _tween(view, "shake", 9.0, 0.4)
    var strain := create_tween()
    strain.tween_property(view, "altitude", LaunchView.START_ALTITUDE + 14.0, 1.5).set_ease(Tween.EASE_OUT)
    await _wait(1.8)
    _log("[color=#%s]THRUST TOO LOW: THE ROCKET IS TOO HEAVY TO CLIMB[/color]" % AMBER)
    await _wait(1.5)
    _log("SHUTTING THE ENGINES DOWN SAFELY")
    %Countdown.text = "HOLD"
    _tween(view, "throttle", 0.0, 1.2)
    _tween(view, "shake", 0.0, 1.2)
    _tween(view, "altitude", LaunchView.START_ALTITUDE, 0.8)
    await _wait(2.0)
    _log("CREW CLIMBING OUT, EVERYONE IS FINE")
    await _wait(1.5)
    _show_result(
        "LAUNCH SCRUBBED", AMBER,
        ("The rocket weighed [color=#%s]%.1f t[/color]: it needs about [color=#%s]%d thrust[/color] to climb safely, but its engines only make [color=#%s]%d[/color]. " +
        "The flight computer shut the engines down safely and the crew climbed out with a wave.\n\n" +
        "[color=#%s]Tip: engine and booster cards add thrust, and every card shows its weight.[/color]") % [
            RED, profile.total_weight(), AMBER, ceili(profile.thrust_needed() * LaunchProfile.THRUST_SAFE), RED, roundi(profile.thrust), DIM],
        "> BACK TO PLANNING")


func _glitch_hold() -> void:
    %Countdown.text = "HOLD"
    _log("[color=#%s]SENSOR GLITCH DETECTED: HOLD, HOLD, HOLD[/color]" % AMBER)
    _tween(view, "throttle", 0.0, 1.0)
    _tween(view, "shake", 0.0, 1.0)
    await _wait(2.0)
    _log("SAFETY FIRST: LAUNCH SCRUBBED FOR TODAY")
    await _wait(1.5)
    _show_result(
        "LAUNCH SCRUBBED", AMBER,
        ("A sensor glitched during the countdown, so mission control stopped the launch. Safety first! " +
        "The crew is fine, and the rocket will try again another day.\n\n" +
        "[color=#%s]Tip: more thrust also makes the rocket a bit more reliable.[/color]") % DIM,
        "> BACK TO PLANNING")


# --- UI -------------------------------------------------------------------------

func _show_result(title: String, color: String, body: String, button_text: String) -> void:
    _finished = true
    Engine.time_scale = 1.0
    %SkipHint.hide()
    %ResultTitle.text = title
    %ResultTitle.add_theme_color_override("font_color", Color(color))
    %ResultBody.text = body + "\n\n[color=#%s]Launch odds were %d%%.[/color]" % [DIM, roundi(chance * 100.0)]
    %ResultButton.text = button_text
    %ResultPanel.modulate.a = 0.0
    %ResultPanel.show()
    _tween(%ResultPanel, "modulate:a", 1.0, 0.4)
    %ResultButton.grab_focus()


func _on_result_pressed() -> void:
    if _leaving:
        return
    _leaving = true
    var next := MISSION_SCENE
    if failure != LaunchProfile.Failure.NONE:
        # Back to the drawing board: a fresh pick of cargo.
        TransitionData.selected_augments = []
        next = PLAN_SCENE
    var tween := create_tween()
    tween.tween_property(self, "modulate", Color.BLACK, 0.6)
    tween.tween_callback(func(): get_tree().change_scene_to_file(next))


func _update_hud() -> void:
    var span := ORBIT_ALTITUDE - LaunchView.START_ALTITUDE
    var height := clampf((view.altitude - LaunchView.START_ALTITUDE) / span, 0.0, 1.0)
    var speed: float
    if view.separated:
        speed = 25.0 if view.parachute > 0.5 else 900.0
        if view.altitude <= LaunchView.SPLASH_ALTITUDE + 1.0:
            speed = 0.0
    else:
        speed = ORBIT_SPEED_KMH * pow(height, 1.3)
    # Fuel burns as the rocket climbs. On a fuel abort it runs dry right at
    # the abort point; otherwise what is left matches the fuel margin.
    var burn_span := (FUEL_ABORT_ALTITUDE + 250.0 - LaunchView.START_ALTITUDE) / span \
        if failure == LaunchProfile.Failure.FUEL else maxf(profile.fuel_ratio(), 1.02)
    var fuel_left := 0.0 if view.separated else clampf(1.0 - height / burn_span, 0.0, 1.0)
    %Hud.text = "%s\nALTITUDE %6.1f KM\nSPEED    %6d KM/H\nFUEL     %6d %%" % [
        _clock, maxf(0.0, (view.altitude - LaunchView.START_ALTITUDE) / span * ORBIT_KM), roundi(speed), roundi(fuel_left * 100.0)]


func _log(text: String) -> void:
    telemetry.print_text("[color=#%s]%s[/color]  %s\n" % [DIM, _clock, text])


func _wait(seconds: float) -> void:
    await get_tree().create_timer(seconds).timeout


func _tween(target: Object, property: String, value: Variant, duration: float) -> void:
    create_tween().tween_property(target, property, value, duration)


func _odds_color(odds: float) -> String:
    if odds >= 0.8:
        return GREEN
    if odds >= 0.4:
        return AMBER
    return RED
