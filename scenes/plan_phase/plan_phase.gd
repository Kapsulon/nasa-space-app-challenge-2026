@tool
extends Control

const TIME_TO_PICK: float = 60.0
const LAUNCH_REPORT_SCENE: String = "res://scenes/launch_report/launch_report.tscn"

@export_tool_button("Generate cards") var gen = gen_cards

const AUGMENT_CARD_PACKED_SCENE: PackedScene = preload("res://prefabs/augment_card.tscn")
const SLOT_PACKED_SCENE: PackedScene = preload("res://scenes/plan_phase/slot.tscn")

const AUGMENTS: Registry = preload("res://data/augments/augments.tres")

const EMPTY_SLOT_COLOR := Color(1, 1, 1, 0.15)

## Launch odds bar colors, from hopeless (red) to safe (green).
static var ODDS_GRADIENT: Gradient = _make_odds_gradient()


static func _make_odds_gradient() -> Gradient:
    var gradient := Gradient.new()
    gradient.offsets = PackedFloat32Array([0.0, 0.5, 0.8, 1.0])
    gradient.colors = PackedColorArray([Color("ff3a55"), Color("ff8a2a"), Color("ffb800"), Color("39ff6a")])
    return gradient

@export var available_augment_slots: int = 30:
    set(n_available_augment_slots):
        available_augment_slots = n_available_augment_slots
        if is_node_ready():
            gen_slots()

var selected_augments: Array[AugmentInstance] = []
var used_slots: int = 0
## Weight, engine lift and fuel of everything picked so far.
var launch: LaunchProfile = LaunchProfile.new()
var finished: bool = false

var time_left: float = TIME_TO_PICK


func _ready() -> void:
    if not Engine.is_editor_hint() and TransitionData.scenario_base_slot_count > 0:
        available_augment_slots = TransitionData.scenario_base_slot_count
    gen_cards()
    gen_slots()
    update_manifest()
    update_launch_odds()


func _process(delta: float) -> void:
    if Engine.is_editor_hint() or finished:
        return
    time_left -= delta
    if time_left <= 0.0:
        time_left = TIME_TO_PICK
        var cards := %CardsHolder.get_children().filter(func(c: Node): return not c.is_queued_for_deletion())
        if not cards.is_empty():
            cards.pick_random().pick()
    %TimeLeftProgress.value = time_left / TIME_TO_PICK * 100.0


func remaining_slots() -> int:
    return available_augment_slots - used_slots


## Augments whose rarity still fits in the remaining slots.
func available_augments() -> Array[Augment]:
    var result: Array[Augment] = []
    for id in AUGMENTS.get_all_string_ids():
        var augment: Augment = AUGMENTS.load_entry(id)
        if augment != null and augment.slot_cost() <= remaining_slots():
            result.append(augment)
    return result


func gen_cards() -> void:
    for child in %CardsHolder.get_children():
        child.queue_free()
    update_launch_odds()
    show_details(null)
    for augment in draw_offers(available_augments(), 3):
        var card: AugmentCard = AUGMENT_CARD_PACKED_SCENE.instantiate()
        card.augment_instance = AugmentInstance.new(augment, "")
        card.connect("picked", func(): card_picked(card.augment_instance))
        card.hover_changed.connect(func(hovering: bool):
            update_launch_odds(card.augment_instance.augment if hovering else null)
            show_details(card.augment_instance.augment if hovering else null))
        %CardsHolder.add_child(card)
        card.owner = get_tree().edited_scene_root


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


## Tints filled slots with the domain color of the card occupying them, so
## neighbours in the cargo are easy to spot.
func update_slots() -> void:
    var colors: Array[Color] = []
    for instance in selected_augments:
        for i in instance.augment.slot_cost():
            colors.append(Augment.DOMAIN_COLORS[instance.augment.domain])
    var slots := %Slots.get_children().filter(func(c: Node): return not c.is_queued_for_deletion())
    for i in slots.size():
        slots[i].modulate = colors[i] if i < colors.size() else EMPTY_SLOT_COLOR


func update_manifest() -> void:
    %SlotsLabel.text = "%d / %d slots filled" % [used_slots, available_augment_slots]
    for child in %ManifestList.get_children():
        child.queue_free()

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
        var row := HBoxContainer.new()
        row.add_theme_constant_override("separation", 10)
        var swatch := ColorRect.new()
        swatch.color = Augment.DOMAIN_COLORS[augment.domain]
        swatch.custom_minimum_size = Vector2(10, 22)
        swatch.size_flags_vertical = Control.SIZE_SHRINK_CENTER
        row.add_child(swatch)
        var label := Label.new()
        label.text = ("%dx " % run[1] if run[1] > 1 else "") + augment.card_name()
        label.add_theme_font_size_override("font_size", 22)
        label.add_theme_color_override("font_color", Augment.RARITY_COLORS[augment.rarity])
        label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
        label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
        row.add_child(label)
        %ManifestList.add_child(row)
    update_balance()


## How long the supplies would last with this cargo, and how the cargo order
## affects the modules.
func update_balance() -> void:
    if Engine.is_editor_hint():
        return
    var preview := MissionState.new("", TransitionData.scenario_days, [], selected_augments)
    var forecast := preview.forecast()
    var t := ""
    for res_id in ["water", "oxygen", "food", "power"]:
        var stock: int = preview.resources[res_id]
        var net: int = forecast[res_id]
        var lasts := ""
        var color := "7be38b"
        if net >= 0:
            lasts = "steady"
        else:
            var days := floori(stock / float(-net))
            lasts = "lasts %d day%s" % [days, "" if days == 1 else "s"]
            if days < preview.mission_days:
                color = "ff5a6e" if days * 2 < preview.mission_days else "ffb35c"
        t += "%s %d %s  [color=#8a94a6]%+d/day[/color]  [color=#%s]%s[/color]\n" % [
            MissionState.resource_name(res_id), stock, MissionState.unit(res_id), net, color, lasts]
    for note in preview.adjacency_notes():
        t += "[color=#ffb35c][font_size=18]%s[/font_size][/color]\n" % note
    %Balance.text = t.strip_edges()


## Fills the details panel with everything about the hovered card.
func show_details(augment: Augment) -> void:
    if Engine.is_editor_hint():
        return
    if augment == null:
        %CardDetails.text = "[color=#8a94a6]Hover a card to read about it. Cards become modules aboard the ship: they bring supplies, produce or use resources every day, and some can misbehave. Order matters: cards next to each other in the cargo can help or bother each other.[/color]"
        return
    var t := "[b][color=#%s]%s[/color][/b]\n" % [Augment.RARITY_COLORS[augment.rarity].to_html(false), augment.display_name]
    t += "[color=#%s]%s[/color] [color=#8a94a6]-  %s  -  %s  -  %.1f t  -  %d slot%s[/color]\n" % [
        Augment.DOMAIN_COLORS[augment.domain].to_html(false), augment.domain_name(), augment.card_type_name(),
        augment.rarity_name(), augment.weight, augment.slot_cost(), "" if augment.slot_cost() == 1 else "s"]
    var rows := [["Gives", augment.gives_text, "7be38b"], ["Costs", augment.costs_text, "ff5a6e"],
        ["Risks", augment.risks_text, "ffb35c"], ["Synergy", augment.synergy_text, "63b1ff"]]
    for row in rows:
        if row[1] != "":
            t += "[color=#%s]%s:[/color] %s\n" % [row[2], row[0], row[1]]
    if augment.lore != "":
        t += "[color=#8a94a6][font_size=18]%s[/font_size][/color]" % augment.lore
    %CardDetails.text = t


## Refreshes the launch odds bar. While a card is hovered, `preview` is its
## augment and the hint shows how picking it would change the odds.
func update_launch_odds(preview: Augment = null) -> void:
    if Engine.is_editor_hint():
        return
    var chance := launch.success_chance()
    var bar: ProgressBar = %OddsBar
    bar.value = chance * 100.0
    var fill := bar.get_theme_stylebox("fill").duplicate() as StyleBoxFlat
    fill.bg_color = ODDS_GRADIENT.sample(chance)
    bar.add_theme_stylebox_override("fill", fill)
    %OddsLabel.text = "%d%%" % roundi(chance * 100.0)

    var hint: Label = %OddsHint
    if preview != null:
        var after := launch.with_augment(preview).success_chance()
        var delta := roundi(after * 100.0) - roundi(chance * 100.0)
        hint.text = "If picked: %d%% (%s)" % [roundi(after * 100.0), "no change" if delta == 0 else "%+d" % delta]
        hint.add_theme_color_override("font_color", Color("39ff6a") if delta > 0 else (Color("ff3a55") if delta < 0 else Color.WHITE))
    else:
        hint.text = launch.advice()
        hint.add_theme_color_override("font_color", ODDS_GRADIENT.sample(chance))

    %LaunchStats.text = "Weight %.1f t / engines lift %.1f t\nFuel %d t / needs %d t" % [
        launch.total_weight(), launch.lift_tons, roundi(launch.fuel_tons), roundi(launch.fuel_needed())]


func card_picked(augment_instance: AugmentInstance) -> void:
    if finished or augment_instance.augment.slot_cost() > remaining_slots():
        return
    time_left = TIME_TO_PICK
    augment_instance.roll()
    selected_augments.append(augment_instance)
    used_slots += augment_instance.augment.slot_cost()
    launch.add(augment_instance.augment)
    update_slots()
    update_manifest()
    update_launch_odds()

    if remaining_slots() <= 0 or available_augments().is_empty():
        finish()
    else:
        gen_cards()


## All slots are filled: hand the selection over and go to the launch report.
func finish() -> void:
    finished = true
    for child in %CardsHolder.get_children():
        child.queue_free()
    update_launch_odds()
    %TimeLeftProgress.value = 0.0
    TransitionData.selected_augments = selected_augments
    await get_tree().create_timer(1.0).timeout
    get_tree().change_scene_to_file(LAUNCH_REPORT_SCENE)
