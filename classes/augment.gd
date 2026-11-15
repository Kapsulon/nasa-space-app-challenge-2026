class_name Augment extends Resource

enum Type {
    VITAL,
    TECHNICAL,
    SPECIAL
}

enum Rarity {
    COMMON,
    EPIC,
    MYTHIC
}

static var RARITY_CARDS: Dictionary[Rarity, CompressedTexture2D] = {
    Rarity.COMMON: load("res://assets/textures/card_common.png"),
    Rarity.EPIC: load("res://assets/textures/card_epic.png"),
    Rarity.MYTHIC: load("res://assets/textures/card_mythic.png")
}

static var TYPE_ICONS: Dictionary[Type, CompressedTexture2D] = {
    Type.VITAL: load("res://assets/textures/type_vital.png"),
    Type.TECHNICAL: load("res://assets/textures/type_technical.png"),
    Type.SPECIAL: load("res://assets/textures/type_special.png")
}

static var RARITY_SLOTS: Dictionary[Rarity, int] = {
    Rarity.COMMON: 1,
    Rarity.EPIC: 2,
    Rarity.MYTHIC: 5
}

static var RARITY_COLORS: Dictionary[Rarity, Color] = {
    Rarity.COMMON: Color("b8c2cc"),
    Rarity.EPIC: Color("b46cff"),
    Rarity.MYTHIC: Color("ffb800")
}


func slot_cost() -> int:
    return RARITY_SLOTS[rarity]


func rarity_name() -> String:
    return Rarity.keys()[rarity].capitalize()

@export var display_name: String = ""
@export_multiline var description: String = ""
@export var upgrades: Dictionary[String, String] = {}
@export var image: CompressedTexture2D
## Launch mass in tons. Heavier cargo lowers the launch odds (see LaunchProfile).
@export_range(0.0, 50.0, 0.1, "or_greater", "suffix:t") var weight: float = 0.0

@export var type: Type
@export var rarity: Rarity
