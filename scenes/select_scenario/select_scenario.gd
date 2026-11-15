extends Control
## Main menu, shown after the intro: the title and four arcade buttons, then
## the mission select, the card codex and the options. Built in code, in the
## pixel-panel style of the intro: steel frames with hard drop shadows, a
## colored strip per button and a ▶ cursor on the selected one.
##
## Keys: ↑/↓ select, Enter confirm, Esc back.

const PLAN_SCENE: String = "res://scenes/plan_phase/plan_phase.tscn"
const MenuBackground := preload("res://scenes/select_scenario/menu_background.gd")
const RetroSynth := preload("res://classes/retro_synth.gd")
const GameSettings := preload("res://classes/game_settings.gd")
const CRT_SHADER := preload("res://assets/shaders/crt.gdshader")
const AUGMENT_CARD := preload("res://prefabs/augment_card.tscn")

## The missions on offer. Add entries here for more.
const SCENARIOS: Array[Dictionary] = [
    {"name": "Reach the ISS", "orbit": "LOW EARTH ORBIT", "slots": 40, "days": 10,
        "objective": "Keep the crew alive for 10 days until docking with the International Space Station."},
]

const C_PANEL := Color(0.059, 0.09, 0.165, 0.92)
const C_PANEL_HI := Color("1e293b")
const C_DEEP := Color(0.027, 0.043, 0.078, 0.94)
const C_STEEL := Color("334155")
const C_EDGE := Color("475569")
const C_SHADOW := Color("020617")
const C_WHITE := Color("f8fafc")
const C_TEXT := Color("cbd5e1")
const C_MUTED := Color("94a3b8")
const C_DIM := Color("64748b")
const C_SKY := Color("38bdf8")
const C_ORANGE := Color("f97316")
const C_PURPLE := Color("a855f7")
const C_EMERALD := Color("10b981")
const C_AMBER := Color("fbbf24")

## Codex tiles: [border, background] per rarity.
const RARITY_STYLE: Dictionary = {
    Augment.Rarity.COMMON: [Color("38bdf8"), Color("0c1e3a")],
    Augment.Rarity.RARE: [Color("a855f7"), Color("241038")],
    Augment.Rarity.MYTHIC: [Color("eab308"), Color("3b2506")],
}

var _views: Dictionary[StringName, Control] = {}
var _current: StringName = &""
## First control to focus when a view opens.
var _first_focus: Dictionary[StringName, Control] = {}
## The main menu button that opened the current view.
var _return_focus: Control
var _leaving: bool = false

var _root: Control
var _fade: ColorRect
var _synth: AudioStreamPlayer

var _selected_scenario: int = 0
var _mission_rows: Array[Button] = []
var _start_button: Button

var _codex_grid: GridContainer
var _codex_filters: HFlowContainer
var _codex_card_holder: Control
var _codex_info: HBoxContainer
var _codex_filter: int = -1


func _ready() -> void:
    Augment.preload_library()
    Music.play(&"menu")
    _build()
    _show(&"main")
    _fade.color.a = 1.0
    create_tween().tween_property(_fade, "color:a", 0.0, 0.4)


func _unhandled_input(event: InputEvent) -> void:
    if _leaving or _current == &"main":
        return
    if event.is_action_pressed("ui_cancel"):
        get_viewport().set_input_as_handled()
        _back()


# --- Navigation -----------------------------------------------------------------

func _show(view_name: StringName) -> void:
    _current = view_name
    for key in _views:
        _views[key].visible = key == view_name
    var view := _views[view_name]
    view.offset_transform_enabled = true
    view.offset_transform_pivot_ratio = Vector2(0.5, 0.5)
    view.offset_transform_position = Vector2(0, 14)
    view.offset_transform_scale = Vector2(0.97, 0.97)
    view.modulate.a = 0.0
    var tween := view.create_tween().set_parallel(true).set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_OUT)
    tween.tween_property(view, "offset_transform_position", Vector2.ZERO, 0.22)
    tween.tween_property(view, "offset_transform_scale", Vector2.ONE, 0.22)
    tween.tween_property(view, "modulate:a", 1.0, 0.18)
    var target: Control = _return_focus if view_name == &"main" and _return_focus != null else _first_focus.get(view_name)
    if target != null:
        target.grab_focus.call_deferred()


func _open(view_name: StringName) -> void:
    _return_focus = get_viewport().gui_get_focus_owner()
    if view_name == &"codex" and _codex_grid.get_child_count() == 0:
        _fill_codex()
    _show(view_name)


func _back() -> void:
    if _current == &"options":
        GameSettings.save()
    _synth.word_tick(300.0)
    _show(&"main")


func _start_mission() -> void:
    if _leaving:
        return
    _leaving = true
    var scenario: Dictionary = SCENARIOS[_selected_scenario]
    TransitionData.scenario_name = scenario["name"]
    TransitionData.scenario_base_slot_count = scenario["slots"]
    TransitionData.scenario_days = scenario["days"]
    TransitionData.scenario_objective = scenario["objective"]
    TransitionData.selected_augments = []
    _synth.title_chord()
    var tween := create_tween()
    tween.tween_property(_fade, "color:a", 1.0, 0.6)
    tween.tween_callback(func(): get_tree().change_scene_to_file(PLAN_SCENE))


# --- Views ----------------------------------------------------------------------

func _build() -> void:
    var background := MenuBackground.new()
    _full(background)
    add_child(background)

    var crt := ColorRect.new()
    var crt_material := ShaderMaterial.new()
    crt_material.shader = CRT_SHADER
    crt.material = crt_material
    _full(crt)
    add_child(crt)

    _root = Control.new()
    _full(_root)
    add_child(_root)

    _build_main()
    _build_missions()
    _build_codex()
    _build_options()

    _fade = ColorRect.new()
    _fade.color = Color(0, 0, 0, 0)
    _full(_fade)
    add_child(_fade)

    _synth = RetroSynth.new()
    add_child(_synth)


func _build_main() -> void:
    var column := _column(_new_view(&"main"), 860, 20)

    var title := _panel(C_DEEP, C_SKY, Vector2(40, 32))
    column.add_child(title)
    var box := VBoxContainer.new()
    box.add_theme_constant_override("separation", 12)
    title.add_child(box)
    box.add_child(_chip("NASA SPACE APPS 2026", C_SKY, C_ORANGE))
    var name_label := _label("MISSION ISMA", 76, C_WHITE)
    name_label.add_theme_color_override("font_shadow_color", Color("0284c7"))
    name_label.add_theme_constant_override("shadow_offset_x", 0)
    name_label.add_theme_constant_override("shadow_offset_y", 6)
    box.add_child(name_label)
    box.add_child(_label("DRAFT  •  LAUNCH  •  SURVIVE", 42, C_AMBER))

    var buttons := VBoxContainer.new()
    buttons.add_theme_constant_override("separation", 14)
    column.add_child(buttons)
    var play := _menu_button("PLAY", C_ORANGE, "ENTER", _open.bind(&"missions"))
    buttons.add_child(play)
    _first_focus[&"main"] = play
    buttons.add_child(_menu_button("CODEX", C_PURPLE, "%d CARDS" % _card_count(), _open.bind(&"codex")))
    buttons.add_child(_menu_button("OPTIONS", C_SKY, "", _open.bind(&"options")))
    if not OS.has_feature("web"):
        buttons.add_child(_menu_button("QUIT", C_DIM, "", func(): get_tree().quit()))

    var hint := _label("↑↓ SELECT     ENTER CONFIRM     ESC BACK", 34, C_DIM, HORIZONTAL_ALIGNMENT_CENTER)
    column.add_child(hint)


func _build_missions() -> void:
    var column := _column(_new_view(&"missions"), 1180, 20)
    column.add_child(_header("SELECT MISSION", C_ORANGE))

    for i in SCENARIOS.size():
        var row := _mission_row(SCENARIOS[i], i)
        column.add_child(row)
        _mission_rows.append(row)
    _first_focus[&"missions"] = _mission_rows[0]

    var footer := HBoxContainer.new()
    footer.alignment = BoxContainer.ALIGNMENT_END
    column.add_child(footer)
    _start_button = _action_button("START  ▶", Color("ea580c"), Color("fdba74"))
    _start_button.pressed.connect(_start_mission)
    footer.add_child(_start_button)


func _mission_row(scenario: Dictionary, index: int) -> Button:
    var row := Button.new()
    row.custom_minimum_size = Vector2(0, 290)
    row.focus_mode = Control.FOCUS_ALL
    var strip := _strip(C_ORANGE)
    row.add_child(strip)

    var content := HBoxContainer.new()
    _full(content)
    content.offset_left = 40
    content.offset_right = -32
    content.add_theme_constant_override("separation", 32)
    row.add_child(content)

    var icon_box := _panel(Color("050914"), C_STEEL, Vector2(16, 12), 2, 0)
    icon_box.size_flags_vertical = Control.SIZE_SHRINK_CENTER
    content.add_child(icon_box)
    var icon := TextureRect.new()
    icon.texture = ImageTexture.create_from_image(MenuBackground.station_image())
    icon.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
    icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
    icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
    icon.custom_minimum_size = Vector2(240, 100)
    icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
    icon_box.add_child(icon)

    var text := VBoxContainer.new()
    text.alignment = BoxContainer.ALIGNMENT_CENTER
    text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    text.add_theme_constant_override("separation", 12)
    text.mouse_filter = Control.MOUSE_FILTER_IGNORE
    content.add_child(text)
    text.add_child(_label(String(scenario["name"]).to_upper(), 52, C_WHITE))
    var objective := _label(scenario["objective"], 36, C_TEXT)
    objective.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
    text.add_child(objective)
    var chips := HBoxContainer.new()
    chips.add_theme_constant_override("separation", 10)
    chips.mouse_filter = Control.MOUSE_FILTER_IGNORE
    text.add_child(chips)
    chips.add_child(_chip("%d DAYS" % scenario["days"], C_EMERALD))
    chips.add_child(_chip("%d SLOTS" % scenario["slots"], C_SKY))
    chips.add_child(_chip(scenario["orbit"], C_AMBER))

    var cursor := _label("▶", 51, C_ORANGE)
    cursor.modulate.a = 0.0
    content.add_child(cursor)

    _hook_highlight(row, func(on: bool): cursor.modulate.a = 1.0 if on else 0.0)
    row.pressed.connect(func():
        _selected_scenario = index
        _synth.word_tick(880.0)
        _start_button.grab_focus())
    return row


func _build_codex() -> void:
    var view := _new_view(&"codex")
    var margin := MarginContainer.new()
    _full(margin)
    margin.mouse_filter = Control.MOUSE_FILTER_PASS
    for side in ["left", "right"]:
        margin.add_theme_constant_override("margin_" + side, 72)
    for side in ["top", "bottom"]:
        margin.add_theme_constant_override("margin_" + side, 56)
    view.add_child(margin)
    var column := VBoxContainer.new()
    column.add_theme_constant_override("separation", 18)
    margin.add_child(column)
    column.add_child(_header("CODEX", C_PURPLE))

    _codex_filters = HFlowContainer.new()
    _codex_filters.add_theme_constant_override("h_separation", 10)
    _codex_filters.add_theme_constant_override("v_separation", 10)
    column.add_child(_codex_filters)

    var body := HBoxContainer.new()
    body.size_flags_vertical = Control.SIZE_EXPAND_FILL
    body.add_theme_constant_override("separation", 24)
    column.add_child(body)

    var scroll := ScrollContainer.new()
    scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
    scroll.follow_focus = true
    body.add_child(scroll)
    var grid_margin := MarginContainer.new()
    grid_margin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    for side in ["left", "top", "right", "bottom"]:
        grid_margin.add_theme_constant_override("margin_" + side, 10)
    scroll.add_child(grid_margin)
    _codex_grid = GridContainer.new()
    _codex_grid.columns = 6
    _codex_grid.add_theme_constant_override("h_separation", 14)
    _codex_grid.add_theme_constant_override("v_separation", 14)
    grid_margin.add_child(_codex_grid)

    var detail := _panel(C_DEEP, C_SKY, Vector2(28, 28))
    detail.custom_minimum_size.x = 500
    body.add_child(detail)
    var detail_box := VBoxContainer.new()
    detail_box.alignment = BoxContainer.ALIGNMENT_CENTER
    detail_box.add_theme_constant_override("separation", 18)
    detail.add_child(detail_box)
    _codex_card_holder = Control.new()
    _codex_card_holder.custom_minimum_size = Vector2(430, 606)
    _codex_card_holder.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
    detail_box.add_child(_codex_card_holder)
    _codex_info = HBoxContainer.new()
    _codex_info.alignment = BoxContainer.ALIGNMENT_CENTER
    _codex_info.add_theme_constant_override("separation", 14)
    detail_box.add_child(_codex_info)


## Loads the cards the first time the codex opens.
func _fill_codex() -> void:
    var cards := Augment.all_cards().duplicate()
    cards.sort_custom(func(a: Augment, b: Augment) -> bool:
        if a.domain != b.domain:
            return a.domain < b.domain
        if a.rarity != b.rarity:
            return a.rarity < b.rarity
        return a.card_name() < b.card_name())

    var domains: Array[int] = []
    for augment: Augment in cards:
        if augment.domain not in domains:
            domains.append(augment.domain)
        _codex_grid.add_child(_codex_tile(augment))

    _codex_filters.add_child(_filter_chip("ALL", C_SKY, -1))
    for domain in domains:
        _codex_filters.add_child(_filter_chip(Augment.Domain.keys()[domain], Augment.DOMAIN_COLORS[domain], domain))
    _paint_filters()
    if _codex_grid.get_child_count() > 0:
        _first_focus[&"codex"] = _codex_grid.get_child(0)
        _show_card(cards[0])


func _codex_tile(augment: Augment) -> Button:
    var colors: Array = RARITY_STYLE[augment.rarity]
    var tile := Button.new()
    tile.custom_minimum_size = Vector2(0, 250)
    tile.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    tile.focus_mode = Control.FOCUS_ALL
    tile.set_meta(&"domain", augment.domain)
    var normal := _style(colors[1], colors[0], 3, Vector2.ZERO, 4)
    if augment.rarity == Augment.Rarity.MYTHIC:
        normal.shadow_color = Color(colors[0], 0.35)
        normal.shadow_size = 12
        normal.shadow_offset = Vector2.ZERO
    var lit := normal.duplicate() as StyleBoxFlat
    lit.bg_color = (colors[1] as Color).lightened(0.12)
    lit.border_color = C_WHITE

    var box := VBoxContainer.new()
    _full(box)
    for side in [SIDE_LEFT, SIDE_TOP]:
        box.set_offset(side, 8)
    for side in [SIDE_RIGHT, SIDE_BOTTOM]:
        box.set_offset(side, -8)
    box.add_theme_constant_override("separation", 8)
    tile.add_child(box)
    var image := TextureRect.new()
    image.texture = augment.image
    image.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
    image.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
    image.size_flags_vertical = Control.SIZE_EXPAND_FILL
    image.mouse_filter = Control.MOUSE_FILTER_IGNORE
    box.add_child(image)
    var name_label := _label(augment.card_name().to_upper(), 30, C_WHITE, HORIZONTAL_ALIGNMENT_CENTER)
    name_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
    name_label.max_lines_visible = 2
    name_label.custom_minimum_size.y = 74
    box.add_child(name_label)

    var on_change := func(on: bool):
        if on:
            _show_card(augment)
    _hook_highlight(tile, on_change, normal, lit, Vector2(0, -6))
    return tile


func _show_card(augment: Augment) -> void:
    for child in _codex_card_holder.get_children():
        child.queue_free()
    var card: AugmentCard = AUGMENT_CARD.instantiate()
    card.augment_instance = AugmentInstance.new(augment, "")
    _codex_card_holder.add_child(card)
    card.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
    card.modulate.a = 0.0
    card.create_tween().tween_property(card, "modulate:a", 1.0, 0.15)

    for child in _codex_info.get_children():
        child.queue_free()
    _codex_info.add_child(_chip(augment.rarity_name().to_upper(), RARITY_STYLE[augment.rarity][0]))
    _codex_info.add_child(_chip(augment.domain_name().to_upper(), Augment.DOMAIN_COLORS[augment.domain]))
    var slots := augment.slot_cost()
    _codex_info.add_child(_chip("%d SLOT%s" % [slots, "" if slots == 1 else "S"], C_MUTED))


func _filter_chip(text: String, color: Color, domain: int) -> Button:
    var button := Button.new()
    button.text = text
    button.focus_mode = Control.FOCUS_ALL
    button.set_meta(&"domain", domain)
    button.set_meta(&"color", color)
    button.add_theme_font_size_override("font_size", 34)
    button.pressed.connect(func():
        _codex_filter = domain
        _synth.word_tick(620.0)
        _paint_filters()
        for tile in _codex_grid.get_children():
            tile.visible = domain == -1 or tile.get_meta(&"domain") == domain)
    return button


func _paint_filters() -> void:
    for button: Button in _codex_filters.get_children():
        var color: Color = button.get_meta(&"color")
        var active: bool = button.get_meta(&"domain") == _codex_filter
        var normal := _style(color.darkened(0.72) if active else C_PANEL_HI, color if active else C_EDGE, 2, Vector2(14, 8), 3)
        var hover := normal.duplicate() as StyleBoxFlat
        hover.border_color = C_SKY
        button.add_theme_stylebox_override("normal", normal)
        button.add_theme_stylebox_override("hover", hover)
        button.add_theme_stylebox_override("pressed", hover)
        button.add_theme_stylebox_override("focus", _outline())
        for state in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color"]:
            button.add_theme_color_override(state, color if active else C_MUTED)


func _build_options() -> void:
    var column := _column(_new_view(&"options"), 900, 20)
    column.add_child(_header("OPTIONS", C_SKY))
    var panel := _panel(C_PANEL, C_STEEL, Vector2(36, 16))
    column.add_child(panel)
    var rows := VBoxContainer.new()
    panel.add_child(rows)

    var volume := _slider(GameSettings.volume, func(value: float):
        GameSettings.volume = value
        GameSettings.apply()
        _synth.word_tick(660.0))
    rows.add_child(_option_row("VOLUME", volume, true))
    _first_focus[&"options"] = volume
    var music := _slider(GameSettings.music, func(value: float):
        GameSettings.music = value
        GameSettings.apply())
    rows.add_child(_option_row("MUSIC", music, true))

    var fullscreen := Button.new()
    fullscreen.custom_minimum_size = Vector2(150, 0)
    fullscreen.focus_mode = Control.FOCUS_ALL
    fullscreen.add_theme_font_size_override("font_size", 39)
    fullscreen.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
    _paint_toggle(fullscreen, GameSettings.fullscreen)
    fullscreen.pressed.connect(func():
        GameSettings.fullscreen = not GameSettings.fullscreen
        GameSettings.apply()
        _paint_toggle(fullscreen, GameSettings.fullscreen)
        _synth.word_tick(880.0 if GameSettings.fullscreen else 440.0))
    rows.add_child(_option_row("FULLSCREEN", fullscreen, false))


func _paint_toggle(button: Button, on: bool) -> void:
    button.text = "ON" if on else "OFF"
    var color := C_EMERALD if on else C_DIM
    var normal := _style(color.darkened(0.6), color, 2, Vector2(18, 10), 3)
    for state in ["normal", "hover", "pressed"]:
        button.add_theme_stylebox_override(state, normal)
    for state in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color"]:
        button.add_theme_color_override(state, C_WHITE if on else C_MUTED)


## A labeled settings row; the label lights up with a ▶ while `control` has focus.
func _option_row(text: String, control: Control, show_value: bool) -> Control:
    var row := HBoxContainer.new()
    row.custom_minimum_size.y = 84
    row.add_theme_constant_override("separation", 18)
    var cursor := _label("▶", 39, C_SKY)
    cursor.modulate.a = 0.0
    row.add_child(cursor)
    var label := _label(text, 44, C_WHITE)
    label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    row.add_child(label)
    control.size_flags_vertical = Control.SIZE_SHRINK_CENTER
    row.add_child(control)
    if show_value:
        var value := _label("", 39, C_SKY, HORIZONTAL_ALIGNMENT_RIGHT)
        value.custom_minimum_size.x = 72
        row.add_child(value)
        var slider := control as Range
        var update := func(v: float): value.text = "%d%%" % roundi(v * 100.0)
        update.call(slider.value)
        slider.value_changed.connect(update)
    control.mouse_entered.connect(control.grab_focus)
    control.focus_entered.connect(func():
        cursor.modulate.a = 1.0
        label.add_theme_color_override("font_color", C_SKY))
    control.focus_exited.connect(func():
        cursor.modulate.a = 0.0
        label.add_theme_color_override("font_color", C_WHITE))
    return row


func _slider(value: float, on_change: Callable) -> HSlider:
    var slider := HSlider.new()
    slider.min_value = 0.0
    slider.max_value = 1.0
    slider.step = 0.05
    slider.value = value
    slider.custom_minimum_size = Vector2(380, 30)
    slider.focus_mode = Control.FOCUS_ALL
    var track := _style(Color("0f172a"), C_STEEL, 2, Vector2(0, 6), 0)
    var fill := _style(C_SKY, C_SKY, 0, Vector2(0, 6), 0)
    slider.add_theme_stylebox_override("slider", track)
    slider.add_theme_stylebox_override("grabber_area", fill)
    slider.add_theme_stylebox_override("grabber_area_highlight", fill)
    slider.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
    slider.add_theme_icon_override("grabber", _block_icon(C_WHITE))
    slider.add_theme_icon_override("grabber_highlight", _block_icon(C_AMBER))
    slider.value_changed.connect(on_change)
    return slider


# --- Widgets --------------------------------------------------------------------

func _new_view(view_name: StringName) -> Control:
    var view := Control.new()
    _full(view)
    _root.add_child(view)
    _views[view_name] = view
    return view


## A centered column `width` wide inside `view`.
func _column(view: Control, width: float, separation: int) -> VBoxContainer:
    var center := CenterContainer.new()
    _full(center)
    view.add_child(center)
    var column := VBoxContainer.new()
    column.custom_minimum_size.x = width
    column.add_theme_constant_override("separation", separation)
    center.add_child(column)
    return column


## View title bar: accent block, title, BACK button.
func _header(text: String, accent: Color) -> PanelContainer:
    var panel := _panel(C_PANEL, C_STEEL, Vector2(28, 18))
    var row := HBoxContainer.new()
    row.add_theme_constant_override("separation", 18)
    panel.add_child(row)
    var block := ColorRect.new()
    block.color = accent
    block.custom_minimum_size = Vector2(14, 14)
    block.size_flags_vertical = Control.SIZE_SHRINK_CENTER
    row.add_child(block)
    var title := _label(text, 58, C_WHITE)
    title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    row.add_child(title)
    var back := Button.new()
    back.text = "◀ BACK"
    back.focus_mode = Control.FOCUS_ALL
    back.add_theme_font_size_override("font_size", 34)
    var normal := _style(C_PANEL_HI, C_EDGE, 2, Vector2(18, 10), 3)
    var hover := normal.duplicate() as StyleBoxFlat
    hover.border_color = C_SKY
    back.add_theme_stylebox_override("normal", normal)
    back.add_theme_stylebox_override("hover", hover)
    back.add_theme_stylebox_override("pressed", hover)
    back.add_theme_stylebox_override("focus", _outline())
    for state in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color"]:
        back.add_theme_color_override(state, C_TEXT)
    back.pressed.connect(_back)
    row.add_child(back)
    return panel


## Big main-menu button: accent strip on the left, ▶ cursor and a small hint.
func _menu_button(text: String, accent: Color, hint: String, action: Callable) -> Button:
    var button := Button.new()
    button.custom_minimum_size = Vector2(0, 86)
    button.focus_mode = Control.FOCUS_ALL
    button.add_child(_strip(accent))
    var row := HBoxContainer.new()
    _full(row)
    row.offset_left = 36
    row.offset_right = -28
    row.add_theme_constant_override("separation", 18)
    button.add_child(row)
    var cursor := _label("▶", 44, accent)
    cursor.modulate.a = 0.0
    row.add_child(cursor)
    var label := _label(text, 53, C_WHITE)
    label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    row.add_child(label)
    if hint != "":
        row.add_child(_label(hint, 34, accent))
    _hook_highlight(button, func(on: bool): cursor.modulate.a = 1.0 if on else 0.0)
    button.pressed.connect(func():
        _synth.word_tick(880.0)
        action.call())
    return button


## Hover follows focus, so the mouse and the keys share one highlight: the
## button lights up (`lit` style), nudges by `nudge` and calls `on_change`.
func _hook_highlight(button: Button, on_change: Callable, normal: StyleBoxFlat = null,
        lit: StyleBoxFlat = null, nudge: Vector2 = Vector2(8, 0)) -> void:
    if normal == null:
        normal = _style(C_PANEL, C_STEEL, 3, Vector2.ZERO)
    if lit == null:
        lit = _style(C_PANEL_HI, C_SKY, 3, Vector2.ZERO)
    var paint := func(style: StyleBoxFlat):
        for state in ["normal", "hover", "pressed"]:
            button.add_theme_stylebox_override(state, style)
    paint.call(normal)
    button.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
    button.offset_transform_enabled = true
    button.mouse_entered.connect(button.grab_focus)
    button.focus_entered.connect(func():
        paint.call(lit)
        _synth.word_tick(520.0)
        button.create_tween().tween_property(button, "offset_transform_position", nudge, 0.08)
        on_change.call(true))
    button.focus_exited.connect(func():
        paint.call(normal)
        button.create_tween().tween_property(button, "offset_transform_position", Vector2.ZERO, 0.08)
        on_change.call(false))


## Chunky arcade button with a hard drop shadow; it sinks when pressed.
func _action_button(text: String, bg_color: Color, border: Color) -> Button:
    var button := Button.new()
    button.text = text
    button.focus_mode = Control.FOCUS_ALL
    button.add_theme_font_size_override("font_size", 51)
    for state in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color"]:
        button.add_theme_color_override(state, C_WHITE)
    var normal := _style(bg_color, border, 3, Vector2(44, 22))
    var hover := normal.duplicate() as StyleBoxFlat
    hover.bg_color = bg_color.lightened(0.15)
    var pressed := hover.duplicate() as StyleBoxFlat
    pressed.shadow_offset = Vector2(0, 2)
    pressed.content_margin_top += 4
    pressed.content_margin_bottom -= 4
    button.add_theme_stylebox_override("normal", normal)
    button.add_theme_stylebox_override("hover", hover)
    button.add_theme_stylebox_override("pressed", pressed)
    button.add_theme_stylebox_override("focus", _outline())
    button.mouse_entered.connect(button.grab_focus)
    return button


## Small tag: tinted fill, colored border and text, optional square dot.
func _chip(text: String, color: Color, dot: Color = Color.TRANSPARENT) -> PanelContainer:
    var chip := _panel(Color(color, 0.14), color, Vector2(12, 6), 2, 0)
    chip.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
    var row := HBoxContainer.new()
    row.add_theme_constant_override("separation", 10)
    row.mouse_filter = Control.MOUSE_FILTER_IGNORE
    chip.add_child(row)
    if dot.a > 0.0:
        var square := ColorRect.new()
        square.color = dot
        square.custom_minimum_size = Vector2(10, 10)
        square.size_flags_vertical = Control.SIZE_SHRINK_CENTER
        square.mouse_filter = Control.MOUSE_FILTER_IGNORE
        row.add_child(square)
    row.add_child(_label(text, 34, color))
    return chip


func _panel(bg_color: Color, border: Color, margin: Vector2, width: int = 3, drop: int = 6) -> PanelContainer:
    var panel := PanelContainer.new()
    panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
    panel.add_theme_stylebox_override("panel", _style(bg_color, border, width, margin, drop))
    return panel


## Square pixel frame with a hard shadow `drop` pixels below.
func _style(bg_color: Color, border: Color, width: int, margin: Vector2, drop: int = 6) -> StyleBoxFlat:
    var style := StyleBoxFlat.new()
    style.bg_color = bg_color
    style.border_color = border
    style.set_border_width_all(width)
    style.content_margin_left = margin.x
    style.content_margin_right = margin.x
    style.content_margin_top = margin.y
    style.content_margin_bottom = margin.y
    if drop > 0:
        style.shadow_color = C_SHADOW
        style.shadow_size = 1
        style.shadow_offset = Vector2(0, drop)
    return style


func _outline() -> StyleBoxFlat:
    var style := StyleBoxFlat.new()
    style.draw_center = false
    style.border_color = Color(C_WHITE, 0.7)
    style.set_border_width_all(2)
    style.set_expand_margin_all(5)
    return style


## The colored strip down the left edge of a button.
func _strip(color: Color) -> ColorRect:
    var strip := ColorRect.new()
    strip.color = color
    strip.set_anchors_preset(Control.PRESET_LEFT_WIDE)
    strip.offset_right = 10
    strip.mouse_filter = Control.MOUSE_FILTER_IGNORE
    return strip


func _block_icon(color: Color) -> ImageTexture:
    var img := Image.create(16, 30, false, Image.FORMAT_RGBA8)
    img.fill(C_SHADOW)
    img.fill_rect(Rect2i(2, 2, 12, 26), color)
    return ImageTexture.create_from_image(img)


func _label(text: String, font_size: int, color: Color,
        align: HorizontalAlignment = HORIZONTAL_ALIGNMENT_LEFT) -> Label:
    var label := Label.new()
    label.text = text
    label.horizontal_alignment = align
    label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
    label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
    label.mouse_filter = Control.MOUSE_FILTER_IGNORE
    label.add_theme_font_size_override("font_size", font_size)
    label.add_theme_color_override("font_color", color)
    return label


func _card_count() -> int:
    var registry := load(Augment.REGISTRY_PATH) as Registry
    return registry.get_all_string_ids().size() if registry != null else 0


func _full(control: Control) -> void:
    control.set_anchors_preset(Control.PRESET_FULL_RECT)
    control.mouse_filter = Control.MOUSE_FILTER_IGNORE
