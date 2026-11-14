@tool
extends Control

@export_tool_button("Generate cards") var gen = gen_cards

const AUGMENT_CARD_PACKED_SCENE: PackedScene = preload("res://prefabs/augment_card.tscn")
const SLOT_PACKED_SCENE: PackedScene = preload("res://scenes/plan_phase/slot.tscn")

const AUGMENTS: Registry = preload("res://data/augments/augments.tres")

@export var available_augment_slots: int = 30:
    set(n_available_augment_slots):
        available_augment_slots = n_available_augment_slots
        gen_slots()

var selected_augments: Array[AugmentInstance] = []


func _ready() -> void:
    gen_cards()
    gen_slots()


func gen_cards() -> void:
    for child in %CardsHolder.get_children():
        child.queue_free()
    for i in range(3):
        var rand: Augment = AUGMENTS.load_entry(AUGMENTS.get_all_string_ids().pick_random())
        var card: AugmentCard = AUGMENT_CARD_PACKED_SCENE.instantiate()
        card.augment = rand
        %CardsHolder.add_child(card)
        card.owner = get_tree().edited_scene_root


func gen_slots() -> void:
    for child in %Slots.get_children():
        child.queue_free()
    for i in range(available_augment_slots):
        var slot := SLOT_PACKED_SCENE.instantiate()
        %Slots.add_child(slot)
        slot.owner = get_tree().edited_scene_root
