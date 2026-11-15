extends Control
## Game intro, shown at start-up: a trailer-style sequence of short beats over
## a warp-speed pixel starfield, then the title card with START MISSION.
## Remade in Godot from cin_matique_d_introduction_mission_isma.html.
##
## Controls: click or Right arrow = next beat, Left arrow = previous beat,
## Space = pause, Esc = skip to the title, Enter = start (on the title).

const MENU_SCENE: String = "res://scenes/select_scenario/select_scenario.tscn"
const WarpStarfield := preload("res://scenes/intro/warp_starfield.gd")
const IntroSynth := preload("res://classes/retro_synth.gd")
const PixelBadge := preload("res://scenes/intro/pixel_badge.gd")
const CRT_SHADER := preload("res://assets/shaders/crt.gdshader")

## Seconds each beat stays on screen.
const BEAT_SECONDS: float = 2.0
## Delay between the words of a word-stack beat.
const WORD_STEP: float = 0.42
const BAR_HEIGHT: float = 72.0

# The game's palette (terminal and card domain colors).
const C_BG := Color("03060d")
const C_WHITE := Color("f8fafc")
const C_MUTED := Color("8a94a6")
const C_DIM := Color("64748b")
const C_GREEN := Color("39ff6a")
const C_AMBER := Color("ffb800")
const C_RED := Color("ff3a55")
const C_BLUE := Color("63b1ff")
const C_LINE := Color("334155")

## The beats. "main" is BBCode. "words" makes a word stack, "final" the title
## card. warp = starfield speed, sound = tick / bass / alert / chord.
const BEATS: Array[Dictionary] = [
    {"kicker": "INCOMING TRANSMISSION // NASA SPACE APPS", "main": "YEAR 2026.", "size": 84,
        "warp": 0.6, "sound": "tick"},
    {"kicker": "COORDINATES LOCKED", "main": "LOW EARTH ORBIT — [color=#63b1ff]NEXT STOP: ISS.[/color]", "size": 64,
        "warp": 1.2, "sound": "bass"},
    {"kicker": "SURVIVAL REPORT", "main": "SPACE FORGIVES [color=#63b1ff]NO MISTAKES.[/color]", "size": 56,
        "warp": 1.8, "sound": "bass"},
    {"words": [["OXYGEN.", "63b1ff"], ["WATER.", "3ad1c2"], ["ENERGY.", "ffe45c"], ["PROPULSION.", "ff7a1a"]],
        "warp": 2.5, "sound": ""},
    {"kicker": "⚠ SYSTEM FAILURE IMMINENT", "main": "ONE GAUGE DROPS TO [color=#ff3a55]0%[/color]",
        "sub": "AND THE STATION IS LOST.", "size": 64, "warp": 4.2, "sound": "alert", "shake": true, "flash": true},
    {"kicker": "CONTROL ROOM • EMERGENCY PROTOCOL", "main": "[color=#ffb800]4 ASTRONAUTS.[/color] ONE ROCKET.",
        "sub": "TO DEFY THE CHAOS.", "size": 84, "warp": 5.5, "sound": "alert", "shake": true},
    {"kicker": "ENGINEERING PHASE", "main": "DRAFT YOUR [color=#63b1ff]CARDS.[/color]",
        "sub": "ASSEMBLE YOUR MODULES.", "size": 64, "warp": 3.5, "sound": "bass"},
    {"kicker": "ULTIMATE DIRECTIVE", "main": "EVERY CHOICE DECIDES YOUR [color=#39ff6a]SURVIVAL.[/color]", "size": 56,
        "warp": 6.5, "sound": "bass"},
    {"final": true, "warp": 1.0, "sound": "chord"},
]

var beat: int = 0
var paused: bool = false

var _beat_time: float = 0.0
## Things to do later in the current beat: [{at, call}].
var _scheduled: Array[Dictionary] = []
var _frame_count: int = 0
var _leaving: bool = false

var _mono: SystemFont
var _frame: Control
var _starfield: Control
var _flash: ColorRect
var _stage: Control
var _fade: ColorRect
var _synth: AudioStreamPlayer
var _counter: Label
var _timecode: Label
var _progress: ProgressBar
var _hint: Label
var _start_button: Button


func _ready() -> void:
    Augment.preload_library()
    _mono = SystemFont.new()
    _mono.font_names = PackedStringArray(["Menlo", "Consolas", "DejaVu Sans Mono", "Courier New", "Monospace"])
    _build()
    play_beat(0)


# --- Sequencer ------------------------------------------------------------------

func play_beat(index: int) -> void:
    beat = clampi(index, 0, BEATS.size() - 1)
    _beat_time = 0.0
    _scheduled.clear()
    for child in _stage.get_children():
        child.queue_free()
    var data: Dictionary = BEATS[beat]
    _starfield.warp = data["warp"]
    _counter.text = "BEAT %02d/%02d" % [beat + 1, BEATS.size()]
    _progress.value = float(beat + 1) / BEATS.size() * 100.0
    _hint.text = "ENTER: START  •  ←: BACK" if data.has("final") else "CLICK: NEXT  •  SPACE: PAUSE  •  ESC: SKIP"

    match data.get("sound", ""):
        "tick":
            _synth.word_tick(620.0)
        "bass":
            _synth.bass_hit(95.0, 0.24)
        "alert":
            _synth.red_alert()
        "chord":
            _synth.title_chord()
    if data.get("shake", false):
        _shake()
    if data.get("flash", false):
        _alert_flash()

    if data.has("final"):
        _show_title()
    elif data.has("words"):
        _show_words(data["words"])
    else:
        _show_text(data)


func next_beat() -> void:
    if beat < BEATS.size() - 1:
        play_beat(beat + 1)


func _process(delta: float) -> void:
    _frame_count += 1
    if paused or _leaving:
        return
    _beat_time += delta
    for entry in _scheduled.duplicate():
        if _beat_time >= entry["at"]:
            _scheduled.erase(entry)
            entry["call"].call()
    if beat < BEATS.size() - 1 and _beat_time >= BEAT_SECONDS:
        next_beat()
    if _frame_count % 3 == 0:
        _timecode.text = "TC 00:00:%02d:%02d" % [beat + 1, _frame_count % 24]


func _set_paused(value: bool) -> void:
    paused = value
    _starfield.paused = value
    _counter.text = "PAUSED" if paused else "BEAT %02d/%02d" % [beat + 1, BEATS.size()]


func _gui_input(event: InputEvent) -> void:
    if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
        accept_event()
        if paused:
            _set_paused(false)
        next_beat()


func _input(event: InputEvent) -> void:
    if _leaving or not (event is InputEventKey and event.pressed and not event.echo):
        return
    match event.keycode:
        KEY_ESCAPE:
            play_beat(BEATS.size() - 1)
        KEY_SPACE:
            _set_paused(not paused)
        KEY_RIGHT:
            next_beat()
        KEY_LEFT:
            play_beat(beat - 1)
        KEY_ENTER, KEY_KP_ENTER:
            if beat == BEATS.size() - 1:
                _start_mission()
            else:
                play_beat(BEATS.size() - 1)
        _:
            return
    get_viewport().set_input_as_handled()


func _start_mission() -> void:
    if _leaving:
        return
    _leaving = true
    _synth.title_chord()
    _starfield.warp = 8.0
    var tween := create_tween()
    tween.tween_property(_fade, "color:a", 1.0, 0.8)
    tween.tween_callback(func(): get_tree().change_scene_to_file(MENU_SCENE))


# --- Beats ----------------------------------------------------------------------

func _show_text(data: Dictionary) -> void:
    var box := _centered_box(12)
    if data.has("kicker"):
        box.add_child(_label(data["kicker"], 42, C_MUTED, _mono))
    var main := RichTextLabel.new()
    main.bbcode_enabled = true
    main.fit_content = true
    main.scroll_active = false
    main.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
    main.custom_minimum_size.x = 1500
    main.mouse_filter = Control.MOUSE_FILTER_IGNORE
    main.add_theme_font_size_override("normal_font_size", data["size"])
    main.add_theme_color_override("default_color", C_WHITE)
    main.add_theme_color_override("font_shadow_color", Color(1, 1, 1, 0.18))
    main.add_theme_constant_override("shadow_offset_y", 4)
    main.add_theme_constant_override("shadow_outline_size", 12)
    main.add_theme_constant_override("line_separation", 18)
    main.text = "[center]%s[/center]" % data["main"]
    box.add_child(main)
    if data.has("sub"):
        box.add_child(_label(data["sub"], 58, Color("cbd5e1")))
    _slam(box)


func _show_words(words: Array) -> void:
    var center := CenterContainer.new()
    center.set_anchors_preset(Control.PRESET_FULL_RECT)
    center.mouse_filter = Control.MOUSE_FILTER_IGNORE
    _stage.add_child(center)
    var grid := GridContainer.new()
    grid.columns = 2
    grid.add_theme_constant_override("h_separation", 32)
    grid.add_theme_constant_override("v_separation", 32)
    grid.mouse_filter = Control.MOUSE_FILTER_IGNORE
    center.add_child(grid)
    for i in words.size():
        var word: String = words[i][0]
        var color := Color(words[i][1])
        _scheduled.append({"at": i * WORD_STEP, "call": func():
            _synth.word_tick(480.0 + i * 110.0)
            var panel := PanelContainer.new()
            panel.custom_minimum_size = Vector2(560, 0)
            panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
            panel.add_theme_stylebox_override("panel", _box_style(Color("020617", 0.9), color, 3, 10, Vector2(28, 22)))
            var label := _label(word, 61, color)
            panel.add_child(label)
            grid.add_child(panel)
            _slam(panel)})


func _show_title() -> void:
    var box := _centered_box(22)
    var badge := PixelBadge.new()
    badge.custom_minimum_size = Vector2(256, 128)
    badge.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
    box.add_child(badge)

    var chip := PanelContainer.new()
    chip.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
    chip.mouse_filter = Control.MOUSE_FILTER_IGNORE
    chip.add_theme_stylebox_override("panel", _box_style(Color(C_BLUE, 0.15), C_BLUE, 2, 0, Vector2(16, 6)))
    chip.add_child(_label("NASA SPACE APPS CHALLENGE • PITCH INTRO", 35, C_BLUE, _mono))
    box.add_child(chip)

    var title := _label("MISSION ISMA", 104, C_WHITE)
    title.add_theme_color_override("font_shadow_color", Color("0284c7"))
    title.add_theme_constant_override("shadow_offset_x", 0)
    title.add_theme_constant_override("shadow_offset_y", 5)
    box.add_child(title)
    box.add_child(_label("PACK THE ROCKET. BRING EVERYONE HOME.", 48, C_AMBER))

    var buttons := HBoxContainer.new()
    buttons.alignment = BoxContainer.ALIGNMENT_CENTER
    buttons.add_theme_constant_override("separation", 24)
    var spacer := Control.new()
    spacer.custom_minimum_size.y = 12
    box.add_child(spacer)
    box.add_child(buttons)
    _start_button = _arcade_button("▶  START MISSION", Color("059669"), Color("6ee7b7"), Color.WHITE)
    _start_button.pressed.connect(_start_mission)
    buttons.add_child(_start_button)
    var replay := _arcade_button("↺  REPLAY TEASER", Color("1e293b"), Color("475569"), Color("e2e8f0"))
    replay.pressed.connect(func():
        _set_paused(false)
        play_beat(0))
    buttons.add_child(replay)
    _slam(box)
    _start_button.grab_focus.call_deferred()


# --- Effects --------------------------------------------------------------------

## Trailer "slam": the node punches in big and bright, then settles.
func _slam(node: Control) -> void:
    node.modulate = Color(2.5, 2.5, 2.5, 0.0)
    node.scale = Vector2(1.35, 1.35)
    await get_tree().process_frame
    if not is_instance_valid(node):
        return
    node.pivot_offset = node.size * 0.5
    var tween := node.create_tween()
    tween.set_parallel(true)
    tween.tween_property(node, "scale", Vector2(0.98, 0.98), 0.15).set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_OUT)
    tween.tween_property(node, "modulate", Color(1.2, 1.2, 1.2, 1.0), 0.15)
    tween.chain().tween_property(node, "scale", Vector2.ONE, 0.1)
    tween.tween_property(node, "modulate", Color.WHITE, 0.1)
    tween.chain().tween_property(node, "scale", Vector2(1.03, 1.03), 1.6).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)


func _shake() -> void:
    var tween := _frame.create_tween()
    for offset in [Vector2(-10, 5), Vector2(10, -7), Vector2(-8, -3), Vector2(8, 7), Vector2(-5, 3), Vector2.ZERO]:
        tween.tween_property(_frame, "position", offset, 0.058)


func _alert_flash() -> void:
    var tween := _flash.create_tween()
    for i in 2:
        tween.tween_property(_flash, "color:a", 0.18, 0.22)
        tween.tween_property(_flash, "color:a", 0.0, 0.22)


# --- Layout ---------------------------------------------------------------------

func _build() -> void:
    mouse_filter = Control.MOUSE_FILTER_STOP
    var bg := ColorRect.new()
    bg.color = C_BG
    _full(bg)
    add_child(bg)

    _frame = Control.new()
    _full(_frame)
    add_child(_frame)

    _starfield = WarpStarfield.new()
    _full(_starfield)
    _frame.add_child(_starfield)

    _flash = ColorRect.new()
    _flash.color = Color(C_RED, 0.0)
    _full(_flash)
    _frame.add_child(_flash)

    var crt := ColorRect.new()
    var material := ShaderMaterial.new()
    material.shader = CRT_SHADER
    crt.material = material
    _full(crt)
    _frame.add_child(crt)

    _stage = Control.new()
    _full(_stage)
    _stage.offset_top = BAR_HEIGHT
    _stage.offset_bottom = -BAR_HEIGHT
    _frame.add_child(_stage)

    # Top letterbox: REC, camera, beat counter, timecode.
    var top := _bar(true)
    var left := HBoxContainer.new()
    left.add_theme_constant_override("separation", 18)
    left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    left.add_child(_label("● REC", 35, Color("f43f5e"), _mono))
    left.add_child(_label("CAM-ISMA-01", 35, C_DIM, _mono))
    _counter = _label("", 35, C_GREEN, _mono)
    left.add_child(_counter)
    top.add_child(left)
    _timecode = _label("TC 00:00:01:00", 35, C_MUTED, _mono)
    _timecode.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    top.add_child(_timecode)
    var right := _label("NASA SPACE APPS // PITCH INTRO", 35, Color(C_BLUE, 0.8), _mono)
    right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    right.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
    top.add_child(right)

    # Bottom letterbox: progress through the beats, controls.
    var bottom := _bar(false)
    bottom.add_theme_constant_override("separation", 28)
    bottom.add_child(_label("INTRO SEQUENCE", 35, C_DIM, _mono))
    _progress = ProgressBar.new()
    _progress.show_percentage = false
    _progress.custom_minimum_size = Vector2(0, 10)
    _progress.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    _progress.size_flags_vertical = Control.SIZE_SHRINK_CENTER
    _progress.mouse_filter = Control.MOUSE_FILTER_IGNORE
    _progress.add_theme_stylebox_override("background", _box_style(Color("0f172a"), C_LINE, 1, 3, Vector2.ZERO))
    _progress.add_theme_stylebox_override("fill", _box_style(C_WHITE, C_WHITE, 0, 3, Vector2.ZERO))
    bottom.add_child(_progress)
    _hint = _label("", 35, C_AMBER, _mono)
    bottom.add_child(_hint)

    _fade = ColorRect.new()
    _fade.color = Color(0, 0, 0, 0)
    _full(_fade)
    add_child(_fade)

    _synth = IntroSynth.new()
    add_child(_synth)


## A black letterbox bar along the top or bottom edge; returns its row.
func _bar(at_top: bool) -> HBoxContainer:
    var panel := PanelContainer.new()
    panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
    panel.set_anchors_preset(Control.PRESET_TOP_WIDE if at_top else Control.PRESET_BOTTOM_WIDE)
    if at_top:
        panel.offset_bottom = BAR_HEIGHT
    else:
        panel.offset_top = -BAR_HEIGHT
    var style := StyleBoxFlat.new()
    style.bg_color = Color(0, 0, 0, 0.9)
    style.border_color = Color("1e293b")
    if at_top:
        style.border_width_bottom = 2
    else:
        style.border_width_top = 2
    style.content_margin_left = 32
    style.content_margin_right = 32
    panel.add_theme_stylebox_override("panel", style)
    var row := HBoxContainer.new()
    row.mouse_filter = Control.MOUSE_FILTER_IGNORE
    row.alignment = BoxContainer.ALIGNMENT_CENTER
    panel.add_child(row)
    _frame.add_child(panel)
    return row


func _centered_box(separation: int) -> VBoxContainer:
    var box := VBoxContainer.new()
    box.mouse_filter = Control.MOUSE_FILTER_IGNORE
    box.alignment = BoxContainer.ALIGNMENT_CENTER
    box.add_theme_constant_override("separation", separation)
    _stage.add_child(box)
    box.set_anchors_and_offsets_preset(Control.PRESET_CENTER, Control.PRESET_MODE_MINSIZE)
    box.grow_horizontal = Control.GROW_DIRECTION_BOTH
    box.grow_vertical = Control.GROW_DIRECTION_BOTH
    return box


func _label(text: String, font_size: int, color: Color, font: Font = null) -> Label:
    var label := Label.new()
    label.text = text
    label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
    label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
    label.mouse_filter = Control.MOUSE_FILTER_IGNORE
    label.add_theme_font_size_override("font_size", font_size)
    label.add_theme_color_override("font_color", color)
    if font != null:
        label.add_theme_font_override("font", font)
    return label


func _box_style(bg_color: Color, border: Color, border_width: int, radius: int, margin: Vector2) -> StyleBoxFlat:
    var style := StyleBoxFlat.new()
    style.bg_color = bg_color
    style.border_color = border
    style.set_border_width_all(border_width)
    style.set_corner_radius_all(radius)
    style.content_margin_left = margin.x
    style.content_margin_right = margin.x
    style.content_margin_top = margin.y
    style.content_margin_bottom = margin.y
    return style


## Chunky arcade button with a hard drop shadow; it sinks when pressed.
func _arcade_button(text: String, bg_color: Color, border: Color, font_color: Color) -> Button:
    var button := Button.new()
    button.text = text
    button.focus_mode = Control.FOCUS_ALL
    button.add_theme_font_size_override("font_size", 51)
    for state in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color"]:
        button.add_theme_color_override(state, font_color)
    var normal := _box_style(bg_color, border, 3, 10, Vector2(36, 20))
    normal.shadow_color = Color("020617")
    normal.shadow_size = 1
    normal.shadow_offset = Vector2(0, 6)
    var hover := normal.duplicate() as StyleBoxFlat
    hover.bg_color = bg_color.lightened(0.15)
    var pressed := normal.duplicate() as StyleBoxFlat
    pressed.shadow_offset = Vector2(0, 2)
    pressed.content_margin_top += 4
    pressed.content_margin_bottom -= 4
    var focus := StyleBoxFlat.new()
    focus.draw_center = false
    focus.border_color = Color(C_WHITE, 0.6)
    focus.set_border_width_all(2)
    focus.set_corner_radius_all(12)
    focus.expand_margin_left = 6
    focus.expand_margin_right = 6
    focus.expand_margin_top = 6
    focus.expand_margin_bottom = 6
    button.add_theme_stylebox_override("normal", normal)
    button.add_theme_stylebox_override("hover", hover)
    button.add_theme_stylebox_override("pressed", pressed)
    button.add_theme_stylebox_override("focus", focus)
    return button


func _full(control: Control) -> void:
    control.set_anchors_preset(Control.PRESET_FULL_RECT)
    control.mouse_filter = Control.MOUSE_FILTER_IGNORE
