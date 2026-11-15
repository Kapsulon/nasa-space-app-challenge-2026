@tool
extends Control

const TIME_TO_PICK: float = 10.0
const LAUNCH_REPORT_SCENE: String = "res://scenes/launch_report/launch_report.tscn"

@export_tool_button("Generate cards") var gen = gen_cards

const AUGMENT_CARD_PACKED_SCENE: PackedScene = preload("res://prefabs/augment_card.tscn")
const SLOT_PACKED_SCENE: PackedScene = preload("res://scenes/plan_phase/slot.tscn")

const AUGMENTS: Registry = preload("res://data/augments/augments.tres")

const EMPTY_SLOT_COLOR := Color(1, 1, 1, 0.15)

@export var available_augment_slots: int = 30:
    set(n_available_augment_slots):
        available_augment_slots = n_available_augment_slots
        if is_node_ready():
            gen_slots()

var selected_augments: Array[AugmentInstance] = []
var used_slots: int = 0
var finished: bool = false

var time_left: float = TIME_TO_PICK


func _ready() -> void:
    if not Engine.is_editor_hint() and TransitionData.scenario_base_slot_count > 0:
        available_augment_slots = TransitionData.scenario_base_slot_count
    gen_cards()
    gen_slots()
    update_manifest()


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
    var pool := available_augments()
    if pool.is_empty():
        return
    for i in range(3):
        var card: AugmentCard = AUGMENT_CARD_PACKED_SCENE.instantiate()
        card.augment_instance = AugmentInstance.new(pool.pick_random(), "")
        card.connect("picked", func(): card_picked(card.augment_instance))
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


func card_picked(augment_instance: AugmentInstance) -> void:
    if finished or augment_instance.augment.slot_cost() > remaining_slots():
        return
    time_left = TIME_TO_PICK
    selected_augments.append(augment_instance)
    used_slots += augment_instance.augment.slot_cost()
    update_slots()
    update_manifest()

    if remaining_slots() <= 0 or available_augments().is_empty():
        finish()
    else:
        gen_cards()


## All slots are filled: hand the selection over and go to the launch report.
func finish() -> void:
    finished = true
    for child in %CardsHolder.get_children():
        child.queue_free()
    %TimeLeftProgress.value = 0.0
    TransitionData.selected_augments = selected_augments
    await get_tree().create_timer(1.0).timeout
    get_tree().change_scene_to_file(LAUNCH_REPORT_SCENE)
