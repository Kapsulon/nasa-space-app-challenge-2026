class_name Augment extends Resource

enum Type {
    VITAL,
    TECHNICAL,
    POLITICAL
}

enum Rarity {
    COMMON,
    EPIC,
    MYTHIC
}

static var RARITY_SLOTS: Dictionary[Rarity, int] = {
    Rarity.COMMON: 1,
    Rarity.EPIC: 2,
    Rarity.MYTHIC: 5
}

@export var display_name: String = ""
@export_multiline var description: String = ""
@export var upgrades: Dictionary[String, String] = {}

@export var type: Type
@export var rarity: Rarity
