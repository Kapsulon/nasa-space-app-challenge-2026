@tool
extends Control
## Phase 1: pick cards for the cargo, three offers at a time, until the slots
## are full. Logistics cards act on the cargo right away (throw a card away,
## swap it, open a crate...). Some of them need a target: the manifest then
## turns into buttons until the player picks one.

const TIME_TO_PICK: float = 60.0
const LAUNCH_REPORT_SCENE: String = "res://scenes/launch_report/launch_report.tscn"
const PROMPT_TEXT: String = "Choose wisely:"

@export_tool_button("Generate cards") var gen = gen_cards

const AUGMENT_CARD_PACKED_SCENE: PackedScene = preload("res://prefabs/augment_card.tscn")
const RetroSynth := preload("res://classes/retro_synth.gd")
const SLOT_PACKED_SCENE: PackedScene = preload("res://scenes/plan_phase/slot.tscn")

const EMPTY_SLOT_COLOR := Color(1, 1, 1, 0.15)
## Background of a cargo row in the manifest.
const CARGO_ROW_COLOR := Color(0.059, 0.09, 0.165, 0.95)

## Actions that need the player to pick card(s) in the manifest.
const TARGETED_ACTIONS: Array[Augment.PlanAction] = [
    Augment.PlanAction.REMOVE, Augment.PlanAction.SWAP, Augment.PlanAction.DUPLICATE, Augment.PlanAction.TRADE_UP,
]

## Launch odds bar colors, from hopeless (red) to safe (green).
static var ODDS_GRADIENT: Gradient = _make_odds_gradient()


static func _make_odds_gradient() -> Gradient:
    var gradient := Gradient.new()
    gradient.offsets = PackedFloat32Array([0.0, 0.5, 0.8, 1.0])
    gradient.colors = PackedColorArray([Color("ff3a55"), Color("ff8a2a"), Color("ffb800"), Color("39ff6a")])
    return gradient

@export var available_augment_slots: int = 40:
    set(n_available_augment_slots):
        available_augment_slots = n_available_augment_slots
        if is_node_ready():
            gen_slots()

var selected_augments: Array[AugmentInstance] = []
## Slots taken by crates and gambles themselves (their cards ride inside).
var overhead_slots: int = 0
## Rarity of each overhead slot, to color it in the slot bar.
var _overhead_rarities: Array[int] = []
## Weight, thrust and fuel of everything picked so far.
var launch: LaunchProfile = LaunchProfile.new()
var finished: bool = false

var time_left: float = TIME_TO_PICK

## A Logistics card waiting for the player to pick its target(s).
var _pending: AugmentInstance = null
var _pending_targets: Array[AugmentInstance] = []
var _message_tween: Tween

# --- Juice ---
## Layer above everything: cards on their way out, the impact flash.
var _fx_layer: Control
var _impact_flash: ColorRect
var _synth: AudioStreamPlayer
var _odds_shown: float = -1.0
var _odds_tween: Tween
## Filled slots after the last update (new ones pop).
var _slots_shown: int = 0
## The card just picked, its slot, and the manifest line to highlight.
var _last_pick: AugmentInstance = null
var _last_pick_slot: int = -1
var _highlight: Augment = null

# --- Countries ---
var _country_chips: Dictionary[String, PanelContainer] = {}
var _country_labels: Dictionary[String, Label] = {}

# --- Target hand ---
## While a Logistics card waits for targets, the cards it can pick are dealt
## as a fanned hand where the offers usually sit.
var _hand: Control
var _hand_cards: Control
var _hand_cancel: Button
## Hand cards in cargo order (hover moves a card to the front of its parent).
var _hand_list: Array[AugmentCard] = []

# --- Reveal ---
## Emitted once the reveal popup is dismissed.
signal reveal_closed
## Popup showing the cards a Logistics card added (or took away).
var _reveal: Control = null
## Seconds before the popup closes on its own (paused while a card is hovered).
var _reveal_time: float = 0.0
var _reveal_hovered: int = 0
var _reveal_age: float = 0.0


func _ready() -> void:
    if not Engine.is_editor_hint():
        Music.play(&"phase_1")
        _build_fx()
        _build_countries()
    if not Engine.is_editor_hint() and TransitionData.scenario_base_slot_count > 0:
        available_augment_slots = TransitionData.scenario_base_slot_count
    gen_cards()
    gen_slots()
    update_manifest()
    update_launch_odds()


func _process(delta: float) -> void:
    if Engine.is_editor_hint() or finished:
        return
    if _reveal != null:
        # The pick timer waits for the player to see what they got.
        _reveal_age += delta
        if _reveal_hovered == 0:
            _reveal_time -= delta
            if _reveal_time <= 0.0:
                _close_reveal()
        return
    time_left -= delta
    if time_left <= 0.0:
        time_left = TIME_TO_PICK
        if _pending != null:
            # Out of time: pick the target(s) at random.
            var targets := _targets_for(_pending.augment).filter(func(t): return not _pending_targets.has(t))
            targets.shuffle()
            while _pending_targets.size() < _targets_needed(_pending.augment) and not targets.is_empty():
                _pending_targets.append(targets.pop_back())
            _resolve_pending()
        else:
            var cards := %CardsHolder.get_children().filter(func(c: Node): return not c.is_queued_for_deletion())
            if not cards.is_empty():
                cards.pick_random().pick()
    _show_timer()


## The pick timer: striped bar going from green to red, seconds on the right.
func _show_timer() -> void:
    var ratio := clampf(time_left / TIME_TO_PICK, 0.0, 1.0)
    var bar := %TimeLeftProgress
    bar.value = ratio
    bar.fill_color = ODDS_GRADIENT.sample(ratio)
    var label: Label = %TimeLeftLabel
    label.text = "%ds" % ceili(time_left)
    # The last seconds blink.
    label.modulate.a = 1.0 if time_left > 10.0 or fmod(time_left, 0.5) > 0.2 else 0.35


func used_slots() -> int:
    var used := overhead_slots
    for instance in selected_augments:
        used += instance.slots_taken()
    return used


func remaining_slots() -> int:
    return available_augment_slots - used_slots()


## Cards that fit in the remaining slots and can do something right now.
func available_augments() -> Array[Augment]:
    var result: Array[Augment] = []
    for augment in _all_augments():
        if augment.slot_cost() <= remaining_slots() and _can_use(augment):
            result.append(augment)
    return result


func _all_augments() -> Array[Augment]:
    return Augment.all_cards()


func gen_cards() -> void:
    _clear_offers()
    update_launch_odds()
    show_details(null)
    var offers := draw_offers(available_augments(), 3)
    for i in offers.size():
        var card: AugmentCard = AUGMENT_CARD_PACKED_SCENE.instantiate()
        card.augment_instance = AugmentInstance.new(offers[i], Country.random_id())
        card.connect("picked", func(): card_picked(card.augment_instance))
        card.hover_changed.connect(func(hovering: bool):
            update_launch_odds(card.augment_instance if hovering else null)
            show_details(card.augment_instance.augment if hovering else null, card.augment_instance.country if hovering else "", true)
            _highlight_country(card.augment_instance.country if hovering else ""))
        %CardsHolder.add_child(card)
        card.owner = get_tree().edited_scene_root
        if not Engine.is_editor_hint():
            # Wait for the previous offers to clear the table.
            var delay := (0.32 if _fx_layer.get_child_count() > 1 else 0.12) + i * 0.09
            card.deal_in(delay)
            _synth.word_tick(560.0 + i * 120.0, delay + 0.05)


## Takes the current offers off the table: the picked one flies into its
## cargo slot, the others drop away. They move to the effects layer so the
## new offers can take their place right away.
func _clear_offers() -> void:
    var cards := %CardsHolder.get_children().filter(func(c: Node): return not c.is_queued_for_deletion())
    if Engine.is_editor_hint() or _fx_layer == null:
        for card in cards:
            card.queue_free()
        return
    var dropped := 0
    for card: AugmentCard in cards:
        var rect := card.get_global_rect()
        card.reparent(_fx_layer, false)
        card.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
        card.global_position = rect.position
        card.size = rect.size
        card.retire()
        if _last_pick != null and card.augment_instance == _last_pick:
            var slots := %Slots.get_children()
            var has_slot := _last_pick_slot >= 0 and _last_pick_slot < slots.size()
            var target: Vector2 = (slots[_last_pick_slot] as Control).get_global_rect().get_center() if has_slot else Vector2.ZERO
            card.fly_to(target, has_slot)
        else:
            card.drop_away(dropped * 0.05)
            dropped += 1
    _last_pick = null


## Up to `count` different cards, rarer cards showing up less often
## (Augment.RARITY_WEIGHTS).
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


func gen_slots() -> void:
    for child in %Slots.get_children():
        child.queue_free()
    for i in range(available_augment_slots):
        var slot := SLOT_PACKED_SCENE.instantiate()
        %Slots.add_child(slot)
        slot.owner = get_tree().edited_scene_root
    update_slots()


## Tints filled slots with the rarity color of the card occupying them.
## Crates and gambles sit at the end, in their own rarity color.
func update_slots() -> void:
    var colors: Array[Color] = []
    for instance in selected_augments:
        for i in instance.slots_taken():
            colors.append(Augment.RARITY_COLORS[instance.augment.rarity])
    for rarity in _overhead_rarities:
        colors.append(Augment.RARITY_COLORS[rarity])
    var slots := %Slots.get_children().filter(func(c: Node): return not c.is_queued_for_deletion())
    for i in slots.size():
        var slot: Control = slots[i]
        var color: Color = colors[i] if i < colors.size() else EMPTY_SLOT_COLOR
        if Engine.is_editor_hint() or i < _slots_shown or i >= colors.size():
            slot.modulate = color
            continue
        # Newly filled: pops in once the flying card gets there.
        slot.pivot_offset = slot.size * 0.5
        var tween := slot.create_tween()
        tween.tween_interval(0.62 + (i - _slots_shown) * 0.04)
        tween.tween_callback(func():
            slot.modulate = Color(2.2, 2.2, 2.2)
            slot.scale = Vector2(1.7, 1.7))
        tween.set_parallel(true)
        tween.chain().tween_property(slot, "scale", Vector2.ONE, 0.4).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
        tween.tween_property(slot, "modulate", color, 0.5)
    _slots_shown = colors.size()


func update_manifest() -> void:
    %SlotsLabel.text = "%d / %d SLOTS" % [used_slots(), available_augment_slots]
    for child in %ManifestList.get_children():
        child.queue_free()
    if _pending != null:
        _build_target_list()
        update_balance()
        return

    # Cargo order matters (neighbours), so list it in order and only merge
    # identical cards picked one after the other: "3x Fuel Tank".
    var runs: Array[Array] = []
    for instance in selected_augments:
        if not runs.is_empty() and runs[-1][0] == instance.augment:
            runs[-1][1] += 1
        else:
            runs.append([instance.augment, 1])
    for run in runs:
        var augment: Augment = run[0]
        var row := PanelContainer.new()
        row.add_theme_stylebox_override("panel", _pill_style(augment, CARGO_ROW_COLOR))
        var line := HBoxContainer.new()
        line.add_theme_constant_override("separation", 10)
        row.add_child(line)
        var label := Label.new()
        label.text = augment.card_name()
        label.add_theme_font_size_override("font_size", 32)
        label.add_theme_color_override("font_color", Augment.RARITY_COLORS[augment.rarity])
        label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
        label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
        line.add_child(label)
        if run[1] > 1:
            line.add_child(_tag("x%d" % run[1], Color("94a3b8")))
        %ManifestList.add_child(row)
        if augment == _highlight and not Engine.is_editor_hint():
            # The line of the card just added flashes, then settles.
            row.modulate = Color(2.5, 2.5, 2.5, 0.0)
            var tween := row.create_tween()
            tween.tween_interval(0.35)
            tween.tween_property(row, "modulate", Color.WHITE, 0.5).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
    _highlight = null
    if overhead_slots > 0:
        var crates := Label.new()
        crates.text = "Crates and gambles: %d slot%s" % [overhead_slots, "" if overhead_slots == 1 else "s"]
        crates.add_theme_font_size_override("font_size", 31)
        crates.add_theme_color_override("font_color", Augment.DOMAIN_COLORS[Augment.Domain.LOGISTICS])
        %ManifestList.add_child(crates)
    update_balance()


## The manifest as buttons, one per card, while a Logistics card waits for
## its target(s).
func _build_target_list() -> void:
    var targets := _targets_for(_pending.augment)
    for instance in selected_augments:
        var augment := instance.augment
        var button := Button.new()
        button.text = augment.card_name()
        button.alignment = HORIZONTAL_ALIGNMENT_LEFT
        button.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
        button.add_theme_font_size_override("font_size", 32)
        var rarity_color: Color = Augment.RARITY_COLORS[augment.rarity]
        for state in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color", "font_hover_pressed_color"]:
            button.add_theme_color_override(state, rarity_color)
        button.add_theme_color_override("font_disabled_color", Color(rarity_color, 0.3))
        var normal := _pill_style(augment, CARGO_ROW_COLOR)
        var hover := _pill_style(augment, Color("1e293b"))
        var picked := _pill_style(augment, Color("0c3b5c"))
        picked.border_color = Color("38bdf8")
        picked.border_width_right = 3
        picked.border_width_top = 3
        picked.border_width_bottom = 3
        var disabled := _pill_style(augment, Color(CARGO_ROW_COLOR, 0.4))
        button.add_theme_stylebox_override("normal", normal)
        button.add_theme_stylebox_override("hover", hover)
        button.add_theme_stylebox_override("pressed", picked)
        button.add_theme_stylebox_override("hover_pressed", picked)
        button.add_theme_stylebox_override("disabled", disabled)
        button.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
        button.toggle_mode = true
        button.button_pressed = _pending_targets.has(instance)
        button.disabled = not targets.has(instance)
        button.pressed.connect(_on_target_pressed.bind(instance))
        %ManifestList.add_child(button)


## Cargo row: dark pill with the card's domain color down its left edge.
func _pill_style(augment: Augment, bg: Color) -> StyleBoxFlat:
    var style := StyleBoxFlat.new()
    style.bg_color = bg
    style.border_color = Augment.DOMAIN_COLORS[augment.domain]
    style.border_width_left = 6
    style.content_margin_left = 16
    style.content_margin_right = 10
    style.content_margin_top = 7
    style.content_margin_bottom = 7
    return style


func _box_style(bg: Color, border: Color, width: int) -> StyleBoxFlat:
    var style := StyleBoxFlat.new()
    style.bg_color = bg
    style.border_color = border
    style.set_border_width_all(width)
    style.content_margin_left = 12
    style.content_margin_right = 12
    style.content_margin_top = 6
    style.content_margin_bottom = 6
    return style


## Small tinted tag: "x3", "STEADY", "2 DAYS"...
func _tag(text: String, color: Color) -> PanelContainer:
    var tag := PanelContainer.new()
    tag.size_flags_vertical = Control.SIZE_SHRINK_CENTER
    tag.size_flags_horizontal = Control.SIZE_SHRINK_END
    var style := _box_style(Color(color, 0.14), color, 2)
    style.content_margin_left = 8
    style.content_margin_right = 8
    style.content_margin_top = 3
    style.content_margin_bottom = 3
    tag.add_theme_stylebox_override("panel", style)
    var label := Label.new()
    label.text = text
    label.add_theme_font_size_override("font_size", 31)
    label.add_theme_color_override("font_color", color)
    tag.add_child(label)
    return tag


func _small_label(text: String, font_size: int, color: Color) -> Label:
    var label := Label.new()
    label.text = text
    label.add_theme_font_size_override("font_size", font_size)
    label.add_theme_color_override("font_color", color)
    label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
    return label


## How long the supplies would last with this cargo, and how the cargo order
## affects the modules.
func update_balance() -> void:
    if Engine.is_editor_hint():
        return
    var preview := MissionState.new("", TransitionData.scenario_days, [], selected_augments)
    var forecast := preview.forecast()
    var grid: GridContainer = %Supplies
    for child in grid.get_children():
        child.queue_free()
    # One row per resource: name, stock, change per day, how long it lasts.
    for res_id in ["water", "oxygen", "food", "power"]:
        var stock: int = preview.resources[res_id]
        var net: int = forecast[res_id]
        var lasts := "STEADY"
        var color := Color("39ff6a")
        if net < 0:
            var days := floori(stock / float(-net))
            lasts = "%d DAY%s" % [days, "" if days == 1 else "S"]
            if days < preview.mission_days:
                color = Color("ff3a55") if days * 2 < preview.mission_days else Color("ffb800")
        var name_label := _small_label(MissionState.resource_name(res_id).to_upper(), 31, Color("cbd5e1"))
        name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
        grid.add_child(name_label)
        grid.add_child(_small_label("%d %s" % [stock, MissionState.unit(res_id)], 31, Color.WHITE))
        grid.add_child(_small_label("%+d/DAY" % net, 31, Color("64748b")))
        grid.add_child(_tag(lasts, color))
    var t := ""
    var hazard := preview.hazard_change()
    if hazard < 0.0:
        t += "Hazard alerts  [color=#39ff6a]%d%% less likely[/color]\n" % roundi(-hazard * 100.0)
    for note in preview.adjacency_notes():
        t += "[color=#ffb800]%s[/color]\n" % note
    %SupplyNotes.text = t.strip_edges()
    %SupplyNotes.visible = t != ""
    _update_countries()


## Fills the details panel with everything about the hovered card.
## `country` is the card's country; `offered` says it isn't in the cargo
## yet (picking it would add one card to that country).
func show_details(augment: Augment, country: String = "", offered: bool = false) -> void:
    if Engine.is_editor_hint():
        return
    if augment == null:
        %CardDetails.text = "[color=#8a94a6]Hover a card to read about it. Cards become modules aboard the ship: they bring supplies, produce or use resources every day, and some can misbehave. Order matters: cards next to each other in the cargo can help or bother each other. Engines, boosters and fuel tanks only matter for the launch, and Logistics cards rearrange the cargo as soon as you pick them.[/color]"
        return
    var t := "[b][color=#%s]%s[/color][/b]\n" % [Augment.RARITY_COLORS[augment.rarity].to_html(false), augment.display_name]
    t += "[color=#%s]%s[/color] [color=#8a94a6]-  %s  -  %s  -  %.1f t  -  %d slot%s[/color]\n" % [
        Augment.DOMAIN_COLORS[augment.domain].to_html(false), augment.domain_name(), augment.card_type_name(),
        augment.rarity_name(), augment.weight, augment.slot_cost(), "" if augment.slot_cost() == 1 else "s"]
    if country != "":
        t += _country_line(country, offered and not augment.is_consumed()) + "\n"
    var rows := [["Gives", augment.gives_text, "7be38b"], ["Costs", augment.costs_text, "ff5a6e"],
        ["Risks", augment.risks_text, "ffb35c"], ["Synergy", augment.synergy_text, "63b1ff"]]
    for row in rows:
        if row[1] != "":
            t += "[color=#%s]%s:[/color] %s\n" % [row[2], row[0], row[1]]
    %CardDetails.text = t
    # The flavor text only shows when there is room: the numbers come first
    # and must stay big enough to read.
    if augment.lore != "":
        var label: RichTextLabel = %CardDetails
        var with_lore := t + "[color=#8a94a6][font_size=31]%s[/font_size][/color]" % augment.lore
        label.text = with_lore
        if label.get_content_height() > label.size.y:
            label.text = t


## Refreshes the launch odds bar. While a card is hovered, `preview` is that
## card and the hint shows how picking it would change the odds.
func update_launch_odds(preview: AugmentInstance = null) -> void:
    if Engine.is_editor_hint():
        return
    var chance := launch.success_chance()
    if _odds_shown < 0.0:
        _show_odds(chance)
    elif not is_equal_approx(chance, _odds_shown):
        # Slide and count to the new odds.
        if _odds_tween != null:
            _odds_tween.kill()
        _odds_tween = create_tween()
        _odds_tween.tween_method(_show_odds, _odds_shown, chance, 0.6).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
        var label: Label = %OddsLabel
        label.pivot_offset = label.size * 0.5
        label.scale = Vector2(1.25, 1.25)
        _odds_tween.parallel().tween_property(label, "scale", Vector2.ONE, 0.4).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

    var hint: Label = %OddsHint
    var shown := launch
    if preview != null and not preview.augment.is_consumed():
        shown = launch.with_augment(preview.augment, preview.country)
        var after := shown.success_chance()
        var delta := roundi(after * 100.0) - roundi(chance * 100.0)
        hint.text = "If picked: %d%% (%s)" % [roundi(after * 100.0), "no change" if delta == 0 else "%+d" % delta]
        hint.add_theme_color_override("font_color", Color("39ff6a") if delta > 0 else (Color("ff3a55") if delta < 0 else Color.WHITE))
        # White tick on the bar where the odds would land.
        %OddsBar.marker = after
    else:
        hint.text = launch.advice()
        hint.add_theme_color_override("font_color", ODDS_GRADIENT.sample(chance))
        %OddsBar.marker = -1.0

    # Thrust and fuel against what the launch needs (the marker); while a card
    # is hovered they show the cargo with that card.
    _show_need(%ThrustBar, %ThrustValue, shown.thrust, shown.thrust_needed())
    _show_need(%FuelBar, %FuelValue, shown.fuel_available(), shown.fuel_needed())
    %WeightLabel.text = "WEIGHT %.1f T" % shown.total_weight()


## A stat bar scaled so the need sits at 80%: green past it, red short of it.
func _show_need(bar: Control, label: Label, have: float, need: float) -> void:
    var scale_max := maxf(need / 0.8, 1.0)
    bar.value = have / scale_max
    bar.marker = need / scale_max if need > 0.0 else -1.0
    bar.fill_color = Color("39ff6a") if have >= need else Color("ff3a55")
    label.text = "%d / %d" % [roundi(have), roundi(need)]
    label.add_theme_color_override("font_color", Color.WHITE if have >= need else Color("ff7a8a"))


func _show_odds(chance: float) -> void:
    _odds_shown = chance
    var bar := %OddsBar
    bar.value = chance
    bar.fill_color = ODDS_GRADIENT.sample(chance)
    %OddsLabel.text = "%d%%" % roundi(chance * 100.0)
    %OddsLabel.add_theme_color_override("font_color", ODDS_GRADIENT.sample(chance).lerp(Color.WHITE, 0.35))


func card_picked(augment_instance: AugmentInstance) -> void:
    var augment := augment_instance.augment
    if finished or _pending != null or _reveal != null or augment.slot_cost() > remaining_slots():
        return
    time_left = TIME_TO_PICK
    if augment.plan_action in TARGETED_ACTIONS:
        _pending = augment_instance
        _pending_targets.clear()
        %CardsHolder.hide()
        _set_prompt(_target_prompt(augment), 31)
        update_manifest()
        _open_hand()
        return
    _apply_card(augment_instance, [])


# --- Logistics ------------------------------------------------------------------

## Whether a card can be picked now (Logistics cards need something to act on).
func _can_use(augment: Augment) -> bool:
    match augment.plan_action:
        Augment.PlanAction.REMOVE, Augment.PlanAction.SWAP, Augment.PlanAction.DUPLICATE:
            return not _targets_for(augment).is_empty()
        Augment.PlanAction.TRADE_UP:
            return _targets_for(augment).size() >= 2
    return true


## Cards in the cargo the action can pick.
func _targets_for(augment: Augment) -> Array[AugmentInstance]:
    var result: Array[AugmentInstance] = []
    for instance in selected_augments:
        var target := instance.augment
        if target.domain == Augment.Domain.LOGISTICS:
            continue
        match augment.plan_action:
            Augment.PlanAction.REMOVE:
                if target.rarity <= augment.action_max_rarity:
                    result.append(instance)
            Augment.PlanAction.SWAP:
                result.append(instance)
            Augment.PlanAction.DUPLICATE:
                if target.rarity == Augment.Rarity.COMMON and target.slot_cost() <= remaining_slots() - augment.slot_cost():
                    result.append(instance)
            Augment.PlanAction.TRADE_UP:
                if target.rarity == Augment.Rarity.COMMON:
                    result.append(instance)
    return result


func _targets_needed(augment: Augment) -> int:
    return 2 if augment.plan_action == Augment.PlanAction.TRADE_UP else 1


func _target_prompt(augment: Augment) -> String:
    match augment.plan_action:
        Augment.PlanAction.REMOVE:
            return "%s: pick a card to throw away" % augment.card_name()
        Augment.PlanAction.SWAP:
            return "%s: pick a card to swap" % augment.card_name()
        Augment.PlanAction.DUPLICATE:
            return "%s: pick a Common card to print a copy of" % augment.card_name()
        Augment.PlanAction.TRADE_UP:
            return "%s: pick 2 Common cards to trade" % augment.card_name()
    return PROMPT_TEXT


func _on_target_pressed(instance: AugmentInstance) -> void:
    if _pending == null or not _targets_for(_pending.augment).has(instance):
        return
    if _pending_targets.has(instance):
        _pending_targets.erase(instance)
    else:
        _pending_targets.append(instance)
    if _pending_targets.size() >= _targets_needed(_pending.augment):
        _resolve_pending()
    else:
        update_manifest()
        _update_hand_marks()


func _cancel_pending() -> void:
    _pending = null
    _pending_targets.clear()
    _close_hand([])
    %CardsHolder.show()
    _set_prompt(PROMPT_TEXT)
    update_manifest()


func _resolve_pending() -> void:
    var instance := _pending
    var targets := _pending_targets.duplicate()
    _pending = null
    _pending_targets.clear()
    _close_hand(targets)
    %CardsHolder.show()
    _set_prompt(PROMPT_TEXT)
    if instance != null and targets.size() >= _targets_needed(instance.augment):
        _apply_card(instance, targets)
    else:
        update_manifest()


## Puts a picked card in the cargo, or carries out its Logistics action.
func _apply_card(instance: AugmentInstance, targets: Array) -> void:
    var augment := instance.augment
    var message := ""
    _last_pick = instance
    # Cargo cards fill the bar first, crates and gambles sit at its end.
    _last_pick_slot = -1 if augment.is_consumed() else used_slots() - overhead_slots
    _highlight = augment
    _impact(augment)
    if augment.is_consumed():
        overhead_slots += augment.slot_cost()
        for i in augment.slot_cost():
            _overhead_rarities.append(augment.rarity)
    else:
        instance.roll()
        selected_augments.append(instance)
    if augment.bonus_slots != 0:
        available_augment_slots += augment.bonus_slots
        message = "+%d cargo slots!" % augment.bonus_slots

    # Cards the action brought in or took out, shown in the reveal popup.
    var gained: Array[AugmentInstance] = []
    var lost: Array[AugmentInstance] = []
    var reveal_title := ""
    match augment.plan_action:
        Augment.PlanAction.REMOVE:
            var target: AugmentInstance = targets[0]
            selected_augments.erase(target)
            message = "Threw away the %s. %s" % [target.augment.card_name(), message]
        Augment.PlanAction.SWAP:
            var target: AugmentInstance = targets[0]
            var other := _random_card(target.augment.rarity, target.augment)
            if other != null:
                other.slots = target.slots_taken()
                selected_augments[selected_augments.find(target)] = other
                message = "Swapped the %s for: %s" % [target.augment.card_name(), other.augment.card_name()]
                lost.append(target)
                gained.append(other)
                reveal_title = "SWAPPED!"
        Augment.PlanAction.DUPLICATE:
            var target: AugmentInstance = targets[0]
            var copy := AugmentInstance.new(target.augment, target.country)
            copy.roll()
            selected_augments.insert(selected_augments.find(target) + 1, copy)
            message = "Printed a second %s!" % target.augment.card_name()
            gained.append(copy)
            reveal_title = "PRINTED A COPY!"
        Augment.PlanAction.TRADE_UP:
            var index := selected_augments.find(targets[0])
            var freed := 0
            for target: AugmentInstance in targets:
                freed += target.slots_taken()
                selected_augments.erase(target)
            var rare := _random_card(Augment.Rarity.RARE)
            if rare != null:
                rare.slots = freed
                selected_augments.insert(mini(index, selected_augments.size()), rare)
                message = "Traded up for: %s" % rare.augment.card_name()
                for target: AugmentInstance in targets:
                    lost.append(target)
                gained.append(rare)
                reveal_title = "TRADED UP!"
        Augment.PlanAction.CRATE:
            var found: Array[AugmentInstance] = [_random_card(Augment.Rarity.RARE), _random_card(-1), _random_card(-1)]
            message = "Inside the crate: %s" % _add_free_cards(found)
            gained = _non_null(found)
            reveal_title = "INSIDE THE CRATE"
        Augment.PlanAction.DOUBLE_OR_NOTHING:
            if randf() < 0.5:
                var won: Array[AugmentInstance] = [_random_card(Augment.Rarity.RARE), _random_card(Augment.Rarity.RARE)]
                message = "Double! You won: %s" % _add_free_cards(won)
                gained = _non_null(won)
                reveal_title = "DOUBLE!"
            else:
                var pool := selected_augments.filter(func(i: AugmentInstance): return i.augment.domain != Augment.Domain.LOGISTICS)
                pool.shuffle()
                var names: PackedStringArray = []
                for target: AugmentInstance in pool.slice(0, 2):
                    selected_augments.erase(target)
                    names.append(target.augment.card_name())
                    lost.append(target)
                message = "Nothing! You lost: %s" % (", ".join(names) if not names.is_empty() else "nothing, the cargo was empty")
                reveal_title = "NOTHING!"
        Augment.PlanAction.LOTTERY:
            var found: Array[AugmentInstance] = [_random_card(Augment.Rarity.MYTHIC)]
            message = "The prototype is: %s" % _add_free_cards(found)
            gained = _non_null(found)
            reveal_title = "THE PROTOTYPE IS..."

    launch = LaunchProfile.from_instances(selected_augments)
    update_slots()
    update_manifest()
    update_launch_odds()
    if message.strip_edges() != "":
        _flash(message.strip_edges())

    if not gained.is_empty() or not lost.is_empty():
        # Clear the table, show what changed, then deal the next offers.
        _clear_offers()
        _show_reveal(reveal_title, gained, lost)
        await reveal_closed
        if finished:
            return

    if remaining_slots() <= 0 or available_augments().is_empty():
        finish()
    else:
        gen_cards()


## Adds cards that ride for free (inside a crate). Returns their names.
func _add_free_cards(instances: Array[AugmentInstance]) -> String:
    var names: PackedStringArray = []
    for instance in instances:
        if instance == null:
            continue
        instance.slots = 0
        selected_augments.append(instance)
        names.append(instance.augment.card_name())
    return ", ".join(names)


func _non_null(instances: Array[AugmentInstance]) -> Array[AugmentInstance]:
    var result: Array[AugmentInstance] = []
    for instance in instances:
        if instance != null:
            result.append(instance)
    return result


## A random card that can fly (no Logistics), of `rarity` (-1 = any, rarer
## ones less often), other than `exclude`.
func _random_card(rarity: int, exclude: Augment = null) -> AugmentInstance:
    var pool: Array[Augment] = []
    for augment in _all_augments():
        if augment.domain != Augment.Domain.LOGISTICS and augment != exclude and (rarity < 0 or augment.rarity == rarity):
            pool.append(augment)
    if pool.is_empty():
        return null
    var picked: Augment = pool.pick_random() if rarity >= 0 else draw_offers(pool, 1)[0]
    var instance := AugmentInstance.new(picked, Country.random_id())
    instance.roll()
    return instance


func _set_prompt(text: String, font_size: int = 58) -> void:
    if _message_tween != null:
        _message_tween.kill()
    %PromptLabel.text = text
    %PromptLabel.add_theme_font_size_override("font_size", font_size)
    %PromptLabel.modulate = Color.WHITE


## Shows what a Logistics card did for a few seconds.
func _flash(text: String) -> void:
    _set_prompt(text, 31)
    %PromptLabel.modulate = Color("ffb800")
    _message_tween = create_tween()
    _message_tween.tween_interval(3.5)
    _message_tween.tween_callback(func():
        if _pending == null:
            _set_prompt(PROMPT_TEXT))


## All slots are filled: hand the selection over and go to the launch report.
func finish() -> void:
    finished = true
    _clear_offers()
    update_launch_odds()
    time_left = 0.0
    _show_timer()
    TransitionData.selected_augments = selected_augments
    TransitionData.cargo_slots_total = available_augment_slots
    TransitionData.cargo_overhead_slots = overhead_slots
    await get_tree().create_timer(1.0).timeout
    get_tree().change_scene_to_file(LAUNCH_REPORT_SCENE)


# --- Countries ------------------------------------------------------------------

## One chip per country under the supplies: flag and "cards / next tier".
## Lit in the country color while its bonus is active. Hovering a chip shows
## the country's bonus tiers in the details panel.
func _build_countries() -> void:
    var row := HBoxContainer.new()
    row.add_theme_constant_override("separation", 8)
    var vbox := %SupplyNotes.get_parent()
    vbox.add_child(row)
    vbox.move_child(row, %SupplyNotes.get_index() + 1)
    for id in Country.ids():
        var chip := PanelContainer.new()
        chip.size_flags_horizontal = Control.SIZE_EXPAND_FILL
        chip.mouse_filter = Control.MOUSE_FILTER_STOP
        chip.mouse_entered.connect(_show_country_details.bind(id))
        chip.mouse_exited.connect(show_details.bind(null))
        var line := HBoxContainer.new()
        line.add_theme_constant_override("separation", 8)
        line.alignment = BoxContainer.ALIGNMENT_CENTER
        line.mouse_filter = Control.MOUSE_FILTER_IGNORE
        chip.add_child(line)
        var flag := TextureRect.new()
        flag.texture = Country.flag(id)
        flag.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
        flag.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
        flag.custom_minimum_size = Vector2(42, 28)
        flag.mouse_filter = Control.MOUSE_FILTER_IGNORE
        line.add_child(flag)
        var label := Label.new()
        label.add_theme_font_size_override("font_size", 25)
        label.mouse_filter = Control.MOUSE_FILTER_IGNORE
        line.add_child(label)
        row.add_child(chip)
        _country_chips[id] = chip
        _country_labels[id] = label
    _update_countries()


func _update_countries() -> void:
    if _country_chips.is_empty():
        return
    var counts := Country.counts(selected_augments)
    for id in Country.ids():
        var count: int = counts[id]
        var next := Country.next_tier_at(count)
        var active := Country.tier(count) > 0
        var color := Country.color(id)
        var label: Label = _country_labels[id]
        label.text = "%d/%d" % [count, next] if next > 0 else "%d MAX" % count
        label.add_theme_color_override("font_color", color if active else Color("94a3b8"))
        var style := _box_style(Color(color, 0.18) if active else CARGO_ROW_COLOR, color if active else Color("334155"), 2 + Country.tier(count))
        style.content_margin_left = 8
        style.content_margin_right = 8
        style.content_margin_top = 4
        style.content_margin_bottom = 4
        _country_chips[id].add_theme_stylebox_override("panel", style)


## While an offer is hovered, its country's chip stands out.
func _highlight_country(id: String) -> void:
    for chip_id in _country_chips.keys():
        var chip: PanelContainer = _country_chips[chip_id]
        chip.modulate.a = 1.0 if id == "" or chip_id == id else 0.35
        if chip_id == id:
            chip.pivot_offset = chip.size * 0.5
            chip.scale = Vector2(1.15, 1.15)
            chip.create_tween().tween_property(chip, "scale", Vector2.ONE, 0.3).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


func _flag_bbcode(id: String) -> String:
    return "[img=42x28]%s[/img]" % Country.flag(id).resource_path


## "Made in Solvara" plus where its bonus stands. `adding`: the card isn't in
## the cargo yet, so show what picking it would change.
func _country_line(id: String, adding: bool) -> String:
    var count: int = Country.counts(selected_augments)[id]
    var color := Country.color(id).to_html(false)
    var t := "%s [color=#%s]Made in %s[/color]  " % [_flag_bbcode(id), color, Country.display_name(id)]
    var now := Country.tier(count)
    if adding:
        var after := Country.tier(count + 1)
        if after > now:
            return t + "[color=#39ff6a]Picking it unlocks: %s![/color]" % Country.bonus_text(id, after)
        var next := Country.next_tier_at(count + 1)
        if next > 0:
            return t + "[color=#8a94a6]%d/%d cards for: %s[/color]" % [count + 1, next, Country.bonus_text(id, Country.tier(next))]
        return t + "[color=#8a94a6]%s (max)[/color]" % Country.bonus_text(id, now)
    if now > 0:
        return t + "[color=#%s]%s[/color]" % [color, Country.bonus_text(id, now)]
    return t + "[color=#8a94a6]%d/%d cards for: %s[/color]" % [count, Country.TIERS[0], Country.bonus_text(id, 1)]


## The details panel tells everything about a country's bonus.
func _show_country_details(id: String) -> void:
    var count: int = Country.counts(selected_augments)[id]
    var color := Country.color(id).to_html(false)
    var t := "%s [b][color=#%s]%s[/color][/b]\n" % [_flag_bbcode(id), color, Country.display_name(id).to_upper()]
    t += "[color=#8a94a6]%s[/color]\n" % Country.DATA[id]["motto"]
    t += "Cards from %s in the cargo: [color=#%s]%d[/color]\n" % [Country.display_name(id), color, count]
    for i in Country.TIERS.size():
        var reached := count >= Country.TIERS[i]
        t += "[color=#%s]%s %d cards: %s[/color]\n" % [
            color if reached else "64748b", "[lb]x[rb]" if reached else "[lb] [rb]", Country.TIERS[i], Country.bonus_text(id, i + 1)]
    %CardDetails.text = t.strip_edges()


# --- Target hand ----------------------------------------------------------------

## Badge text and color on the cards a Logistics action has picked.
func _target_mark(augment: Augment) -> Array:
    match augment.plan_action:
        Augment.PlanAction.REMOVE:
            return ["THROW AWAY", Color("ff3a55")]
        Augment.PlanAction.SWAP:
            return ["SWAP", Color("38bdf8")]
        Augment.PlanAction.DUPLICATE:
            return ["COPY", Color("39ff6a")]
        Augment.PlanAction.TRADE_UP:
            return ["TRADE", Color("ffb800")]
    return ["PICKED", Color.WHITE]


## The hand sits over the offer row, in the same container.
func _build_hand() -> void:
    _hand = Control.new()
    _hand.mouse_filter = Control.MOUSE_FILTER_IGNORE
    %CardsHolder.get_parent().add_child(_hand)
    _hand_cards = Control.new()
    _hand_cards.mouse_filter = Control.MOUSE_FILTER_IGNORE
    _hand_cards.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
    _hand.add_child(_hand_cards)
    _hand_cancel = Button.new()
    _hand_cancel.text = "CANCEL: PICK ANOTHER CARD"
    _hand_cancel.add_theme_font_size_override("font_size", 31)
    var cancel_style := _box_style(Color("1e293b"), Color("475569"), 2)
    var cancel_hover := _box_style(Color("1e293b"), Color("38bdf8"), 2)
    cancel_style.content_margin_left = 20
    cancel_style.content_margin_right = 20
    cancel_hover.content_margin_left = 20
    cancel_hover.content_margin_right = 20
    _hand_cancel.add_theme_stylebox_override("normal", cancel_style)
    _hand_cancel.add_theme_stylebox_override("hover", cancel_hover)
    _hand_cancel.add_theme_stylebox_override("pressed", cancel_hover)
    _hand_cancel.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
    _hand_cancel.pressed.connect(_cancel_pending)
    _hand_cancel.hide()
    _hand.add_child(_hand_cancel)
    _hand_cancel.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM, Control.PRESET_MODE_MINSIZE)
    _hand_cancel.grow_horizontal = Control.GROW_DIRECTION_BOTH
    _hand_cancel.grow_vertical = Control.GROW_DIRECTION_BEGIN
    _hand.resized.connect(_layout_hand.bind(false))


## Deals the cards the pending Logistics card can pick, in cargo order.
func _open_hand() -> void:
    if _hand == null:
        return
    for card in _hand_list:
        card.queue_free()
    _hand_list.clear()
    var targets := _targets_for(_pending.augment)
    for i in targets.size():
        var instance := targets[i]
        var card: AugmentCard = AUGMENT_CARD_PACKED_SCENE.instantiate()
        card.augment_instance = instance
        _hand_cards.add_child(card)
        card.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
        card.picked.connect(_on_target_pressed.bind(instance))
        card.hover_changed.connect(_on_hand_hover.bind(card))
        _hand_list.append(card)
    _layout_hand(false)
    for i in _hand_list.size():
        var delay := 0.05 + i * minf(0.06, 0.6 / _hand_list.size())
        _hand_list[i].deal_in(delay)
        if i < 8:
            _synth.word_tick(480.0 + i * 70.0, delay + 0.05)
    _hand_cancel.show()


## Fans the hand out: cards overlap when there are many, tilt away from the
## middle and sit a little lower towards the edges. Picked ones rise.
func _layout_hand(animate: bool = true) -> void:
    var n := _hand_list.size()
    if n == 0 or _hand == null:
        return
    var area := _hand_cards.size
    var bottom_room := _hand_cancel.get_combined_minimum_size().y + 24.0
    var card_h := clampf(area.y - bottom_room - 70.0, 160.0, 440.0)
    var card_w := card_h * 0.71
    var spread := minf(n * 2.5, 18.0)
    # The outer cards tilt outwards: keep their corners on screen.
    var usable := area.x - 2.0 * (card_h * sin(deg_to_rad(spread * 0.5)) + 8.0)
    var step := card_w + 18.0
    if n > 1 and step * (n - 1) + card_w > usable:
        step = (usable - card_w) / (n - 1)
    var total := step * (n - 1) + card_w
    var x0 := (area.x - total) * 0.5
    for i in n:
        var card := _hand_list[i]
        var t := 0.0 if n == 1 else i / float(n - 1) * 2.0 - 1.0
        var picked := _pending_targets.has(card.augment_instance)
        var pos := Vector2(x0 + i * step, 46.0 + t * t * spread * 1.8 - (40.0 if picked else 0.0))
        var rot := deg_to_rad(t * spread * 0.5)
        card.size = Vector2(card_w, card_h)
        card.pivot_offset = Vector2(card_w * 0.5, card_h)
        if animate:
            var tween := card.create_tween().set_parallel(true).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
            tween.tween_property(card, "position", pos, 0.28)
            tween.tween_property(card, "rotation", rot, 0.28)
        else:
            card.position = pos
            card.rotation = rot


func _update_hand_marks() -> void:
    if _pending == null:
        return
    var mark := _target_mark(_pending.augment)
    for card in _hand_list:
        card.set_mark(mark[0] if _pending_targets.has(card.augment_instance) else "", mark[1])
    _layout_hand()
    _synth.word_tick(900.0)


## The hovered card comes to the front so it can be read in full, and fills
## the details panel.
func _on_hand_hover(hovering: bool, card: AugmentCard) -> void:
    if not _hand_list.has(card):
        return
    if hovering:
        _hand_cards.move_child(card, -1)
        show_details(card.augment_instance.augment, card.augment_instance.country)
    else:
        _hand_cards.move_child(card, _hand_list.find(card))
        show_details(null)


## Puts the hand away: the cards the action used burst, the others drop.
func _close_hand(used: Array) -> void:
    if _hand == null:
        return
    var dropped := 0
    for card in _hand_list:
        card.retire()
        if used.has(card.augment_instance):
            card.set_mark("")
            card.fly_to(Vector2.ZERO, false)
        else:
            card.drop_away(minf(dropped * 0.02, 0.3))
            dropped += 1
    _hand_list.clear()
    _hand_cancel.hide()
    show_details(null)


# --- Reveal ---------------------------------------------------------------------

## Pops the cards a Logistics card added (and the ones it took away) in the
## middle of the screen so the player sees what happened. Closes on a click,
## or by itself after a few seconds; emits `reveal_closed` then.
func _show_reveal(title: String, gained: Array[AugmentInstance], lost: Array[AugmentInstance]) -> void:
    _reveal = Control.new()
    _reveal.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
    _reveal.mouse_filter = Control.MOUSE_FILTER_STOP
    _reveal.gui_input.connect(func(event: InputEvent):
        if event is InputEventMouseButton and event.pressed:
            _close_reveal())
    add_child(_reveal)
    _reveal_hovered = 0
    _reveal_age = 0.0
    _reveal_time = 2.4 + 0.5 * (gained.size() + lost.size())

    var dim := ColorRect.new()
    dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
    dim.color = Color(0.008, 0.016, 0.04, 0.0)
    dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
    _reveal.add_child(dim)
    dim.create_tween().tween_property(dim, "color:a", 0.78, 0.25)

    var screen := size
    var card_h := minf(screen.y * 0.44, 470.0)
    var card_w := card_h * 0.71
    var gap := 44.0
    var arrow_w := 70.0 if not gained.is_empty() and not lost.is_empty() else 0.0
    var count := gained.size() + lost.size()
    var total := count * card_w + (count - 1) * gap + arrow_w
    var x := (screen.x - total) * 0.5
    var y := (screen.y - card_h) * 0.5 + 30.0

    var title_label := Label.new()
    title_label.text = title
    title_label.add_theme_font_size_override("font_size", 86)
    var title_color := Color("ff3a55") if gained.is_empty() else Color("ffb800")
    title_label.add_theme_color_override("font_color", title_color)
    title_label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.8))
    title_label.add_theme_constant_override("shadow_offset_y", 6)
    title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
    title_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
    title_label.size = Vector2(screen.x, 130.0)
    title_label.position = Vector2(0.0, y - 180.0)
    title_label.pivot_offset = title_label.size * 0.5
    title_label.scale = Vector2(0.4, 0.4)
    title_label.modulate.a = 0.0
    _reveal.add_child(title_label)
    var title_tween := title_label.create_tween().set_parallel(true)
    title_tween.tween_property(title_label, "scale", Vector2.ONE, 0.4).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
    title_tween.tween_property(title_label, "modulate:a", 1.0, 0.15)

    var hint := Label.new()
    hint.text = "CLICK TO CONTINUE"
    hint.add_theme_font_size_override("font_size", 31)
    hint.add_theme_color_override("font_color", Color("8a94a6"))
    hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
    hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
    hint.size = Vector2(screen.x, 56.0)
    hint.position = Vector2(0.0, y + card_h + 60.0)
    hint.modulate.a = 0.0
    _reveal.add_child(hint)
    var hint_tween := hint.create_tween().set_loops()
    hint_tween.tween_property(hint, "modulate:a", 1.0, 0.6).set_delay(0.3)
    hint_tween.tween_property(hint, "modulate:a", 0.3, 0.6)

    var entries: Array = []
    for instance in lost:
        entries.append([instance, false])
    for instance in gained:
        entries.append([instance, true])
    for i in entries.size():
        var instance: AugmentInstance = entries[i][0]
        var is_new: bool = entries[i][1]
        if is_new and i > 0 and not entries[i - 1][1]:
            var arrow := Label.new()
            arrow.text = ">>"
            arrow.add_theme_font_size_override("font_size", 72)
            arrow.add_theme_color_override("font_color", Color("cbd5e1"))
            arrow.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
            arrow.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
            arrow.mouse_filter = Control.MOUSE_FILTER_IGNORE
            arrow.size = Vector2(arrow_w + gap, card_h)
            arrow.position = Vector2(x - gap, y)
            _reveal.add_child(arrow)
            x += arrow_w
        _reveal_card(instance, is_new, Rect2(x, y, card_w, card_h), 0.2 + i * 0.3)
        x += card_w + gap


## One card of the reveal: a glow in its rarity color, then the card pops in.
func _reveal_card(instance: AugmentInstance, is_new: bool, rect: Rect2, delay: float) -> void:
    var augment := instance.augment
    var color: Color = Augment.RARITY_COLORS[augment.rarity] if is_new else Color("ff3a55")

    var glow := Panel.new()
    glow.mouse_filter = Control.MOUSE_FILTER_IGNORE
    var glow_style := StyleBoxFlat.new()
    glow_style.bg_color = Color(color, 0.18)
    glow_style.set_corner_radius_all(26)
    glow_style.shadow_color = Color(color, 0.5)
    glow_style.shadow_size = 46
    glow.add_theme_stylebox_override("panel", glow_style)
    glow.position = rect.position - Vector2(10, 10)
    glow.size = rect.size + Vector2(20, 20)
    glow.pivot_offset = glow.size * 0.5
    glow.modulate.a = 0.0
    glow.scale = Vector2(0.6, 0.6)
    _reveal.add_child(glow)
    var glow_tween := glow.create_tween().set_parallel(true)
    glow_tween.tween_property(glow, "modulate:a", 1.0, 0.3).set_delay(delay)
    glow_tween.tween_property(glow, "scale", Vector2.ONE, 0.5).set_delay(delay).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
    glow_tween.chain().tween_property(glow, "modulate:a", 0.55, 0.9).set_trans(Tween.TRANS_SINE)

    var card: AugmentCard = AUGMENT_CARD_PACKED_SCENE.instantiate()
    card.augment_instance = instance
    _reveal.add_child(card)
    card.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
    card.size = rect.size
    card.position = rect.position
    card.pivot_offset = rect.size * 0.5
    card.set_mark("NEW" if is_new else "LOST", color)
    card.scale = Vector2(0.15, 0.15)
    card.rotation = deg_to_rad(randf_range(-30.0, 30.0))
    card.modulate = Color(3.0, 3.0, 3.0, 0.0)
    var final_tint := Color.WHITE if is_new else Color(0.75, 0.55, 0.58)
    var tween := card.create_tween().set_parallel(true)
    tween.tween_property(card, "scale", Vector2.ONE, 0.5).set_delay(delay).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
    tween.tween_property(card, "rotation", 0.0, 0.5).set_delay(delay).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
    tween.tween_property(card, "modulate", final_tint, 0.45).set_delay(delay)
    card.set_meta(&"tween", tween)
    card.set_meta(&"new", is_new)
    card.set_meta(&"tint", final_tint)
    card.picked.connect(_close_reveal)
    card.hover_changed.connect(func(hovering: bool): _reveal_hovered += 1 if hovering else -1)

    if is_new:
        _synth.word_tick(560.0 + rect.position.x * 0.2, delay + 0.05)
        _synth.bass_hit(110.0, 0.2, delay)
        if augment.rarity == Augment.Rarity.MYTHIC:
            get_tree().create_timer(delay).timeout.connect(_synth.title_chord)
        elif augment.rarity == Augment.Rarity.RARE:
            _synth.word_tick(880.0, delay + 0.12)
    else:
        _synth.bass_hit(70.0, 0.3, delay)


## Dismisses the reveal: new cards fly into the manifest, lost ones drop.
func _close_reveal() -> void:
    if _reveal == null or _reveal_age < 0.35:
        return
    var reveal := _reveal
    _reveal = null
    reveal.mouse_filter = Control.MOUSE_FILTER_IGNORE
    var manifest: Control = $MarginContainer/HBoxContainer/Manifest
    var target := manifest.get_global_rect().get_center()
    var dropped := 0
    for child in reveal.get_children():
        if child is AugmentCard:
            var card: AugmentCard = child
            var entry: Tween = card.get_meta(&"tween")
            if entry != null and entry.is_valid():
                entry.kill()
            card.scale = Vector2.ONE
            card.rotation = 0.0
            card.modulate = card.get_meta(&"tint")
            card.retire()
            if card.get_meta(&"new"):
                card.fly_to(target, true)
            else:
                card.drop_away(dropped * 0.06)
                dropped += 1
        else:
            (child as CanvasItem).create_tween().tween_property(child, "modulate:a", 0.0, 0.25)
    _synth.word_tick(700.0)
    var tween := reveal.create_tween()
    tween.tween_interval(0.3)
    tween.tween_callback(reveal_closed.emit)
    tween.tween_interval(0.6)
    tween.tween_callback(reveal.queue_free)


# --- Juice ----------------------------------------------------------------------

func _build_fx() -> void:
    _fx_layer = Control.new()
    _fx_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
    _fx_layer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
    add_child(_fx_layer)
    _impact_flash = ColorRect.new()
    _impact_flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
    _impact_flash.color = Color(1, 1, 1, 0)
    _impact_flash.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
    _fx_layer.add_child(_impact_flash)
    _synth = RetroSynth.new()
    _synth.volume_db = -4.0
    add_child(_synth)
    $MarginContainer.offset_transform_enabled = true
    _build_hand()


## The weight of a pick: a thump for Commons, a flash for Rares, a flash,
## chord and screen shake for Mythics.
func _impact(augment: Augment) -> void:
    var color: Color = Augment.RARITY_COLORS[augment.rarity]
    match augment.rarity:
        Augment.Rarity.COMMON:
            _synth.bass_hit(120.0, 0.18)
        Augment.Rarity.RARE:
            _synth.bass_hit(100.0, 0.26)
            _synth.word_tick(660.0, 0.05)
            _synth.word_tick(880.0, 0.11)
            _flash_screen(color, 0.12)
        Augment.Rarity.MYTHIC:
            _synth.title_chord()
            _flash_screen(color, 0.25)
            _shake(14.0)


func _flash_screen(color: Color, strength: float) -> void:
    _impact_flash.color = Color(color, strength)
    var tween := _impact_flash.create_tween()
    tween.tween_property(_impact_flash, "color:a", 0.0, 0.45).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)


func _shake(strength: float) -> void:
    var root: Control = $MarginContainer
    var tween := root.create_tween()
    for i in 6:
        var falloff := strength * (1.0 - i / 6.0)
        tween.tween_property(root, "offset_transform_position", Vector2(randf_range(-1, 1), randf_range(-1, 1)) * falloff, 0.045)
    tween.tween_property(root, "offset_transform_position", Vector2.ZERO, 0.06)
