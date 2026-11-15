@tool
extends Control

const TIME_TO_PICK: float = 10.0
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
    var pool := available_augments()
    if pool.is_empty():
        return
    for i in range(3):
        var card: AugmentCard = AUGMENT_CARD_PACKED_SCENE.instantiate()
        card.augment_instance = AugmentInstance.new(pool.pick_random(), "")
        card.connect("picked", func(): card_picked(card.augment_instance))
        card.hover_changed.connect(func(hovering: bool):
            update_launch_odds(card.augment_instance.augment if hovering else null))
        %CardsHolder.add_child(card)
        card.owner = get_tree().edited_scene_root


func gen_slots() -> void:
    for child in %Slots.get_children():
        child.queue_free()
    for i in range(available_augment_slots):
        var slot := SLOT_PACKED_SCENE.instantiate()
        %Slots.add_child(slot)
        slot.owner = get_tree().edited_scene_root
    update_slots()


## Tints filled slots with the rarity color of the augment occupying them.
func update_slots() -> void:
    var colors: Array[Color] = []
    for instance in selected_augments:
        for i in instance.augment.slot_cost():
            colors.append(Augment.RARITY_COLORS[instance.augment.rarity])
    var slots := %Slots.get_children().filter(func(c: Node): return not c.is_queued_for_deletion())
    for i in slots.size():
        slots[i].modulate = colors[i] if i < colors.size() else EMPTY_SLOT_COLOR


func update_manifest() -> void:
    %SlotsLabel.text = "%d / %d slots filled" % [used_slots, available_augment_slots]
    for child in %ManifestList.get_children():
        child.queue_free()

    # Group identical augments: "3x Water capacity".
    var counts: Dictionary[Augment, int] = {}
    for instance in selected_augments:
        counts[instance.augment] = counts.get(instance.augment, 0) + 1
    for augment: Augment in counts.keys():
        var label := Label.new()
        var cost: int = augment.slot_cost()
        label.text = "%dx %s  (%d slot%s each)" % [counts[augment], augment.display_name, cost, "" if cost == 1 else "s"]
        label.add_theme_font_size_override("font_size", 26)
        label.add_theme_color_override("font_color", Augment.RARITY_COLORS[augment.rarity])
        label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
        %ManifestList.add_child(label)


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
