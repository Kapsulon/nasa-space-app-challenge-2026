class_name Augment extends Resource
## A card picked during the plan phase. Once launched it becomes a ship module
## (see MissionState / ShipModule):
##   - `upgrades` apply once, at launch (stock, fuel, engine lift...).
##   - `daily` applies every night while the module works.
##   - `risks` can trigger during the night.
##   - `synergy_*` gives a daily bonus for related cards (optionally only for
##     cards right next to this one in the cargo).

enum Type {
    VITAL,
    TECHNICAL,
    SPECIAL
}

enum Rarity {
    COMMON,
    RARE,
    MYTHIC
}

## What the card is about.
enum Domain {
    WATER,
    ENERGY,
    OXYGEN,
    FOOD,
    PROPULSION,
}

enum CardType {
    STOCK,
    RECYCLING,
    TREATMENT,
    PRODUCTION,
    STORAGE,
    CONNECTOR,
    PROPULSION,
}

static var RARITY_CARDS: Dictionary[Rarity, CompressedTexture2D] = {
    Rarity.COMMON: load("res://assets/textures/card_common.png"),
    Rarity.RARE: load("res://assets/textures/card_epic.png"),
    Rarity.MYTHIC: load("res://assets/textures/card_mythic.png")
}

static var TYPE_ICONS: Dictionary[Type, CompressedTexture2D] = {
    Type.VITAL: load("res://assets/textures/type_vital.png"),
    Type.TECHNICAL: load("res://assets/textures/type_technical.png"),
    Type.SPECIAL: load("res://assets/textures/type_special.png")
}

static var RARITY_SLOTS: Dictionary[Rarity, int] = {
    Rarity.COMMON: 1,
    Rarity.RARE: 2,
    Rarity.MYTHIC: 5
}

static var RARITY_COLORS: Dictionary[Rarity, Color] = {
    Rarity.COMMON: Color("b8c2cc"),
    Rarity.RARE: Color("b46cff"),
    Rarity.MYTHIC: Color("ffb800")
}

## How often each rarity shows up in the card offers (relative weights).
static var RARITY_WEIGHTS: Dictionary[Rarity, float] = {
    Rarity.COMMON: 55.0,
    Rarity.RARE: 32.0,
    Rarity.MYTHIC: 13.0,
}

static var DOMAIN_COLORS: Dictionary[Domain, Color] = {
    Domain.WATER: Color("3ad1c2"),
    Domain.ENERGY: Color("ffe45c"),
    Domain.OXYGEN: Color("63b1ff"),
    Domain.FOOD: Color("f2b53a"),
    Domain.PROPULSION: Color("ff7a1a"),
}

## Flags a module can carry, and what they mean on the card.
const FLAG_TEXT: Dictionary[StringName, String] = {
    &"pure_water": "No water sickness aboard",
    &"stable_power": "Power never fails",
}

@export var display_name: String = ""
## Shorter name for the card face and lists. Empty = display_name.
@export var short_name: String = ""
## Optional card face text. When empty, the face is generated from the data.
@export_multiline var description: String = ""
@export var image: CompressedTexture2D
## Launch mass in tons. Heavier cargo lowers the launch odds (see LaunchProfile).
@export_range(0.0, 50.0, 0.1, "or_greater", "suffix:t") var weight: float = 0.0

@export var type: Type
@export var rarity: Rarity
@export var domain: Domain
@export var card_type: CardType
## Slots taken in the cargo. 0 = depends on rarity.
@export var slot_override: int = 0

@export_group("Effects")
## Applied once at launch. Resource ids (water, oxygen, food, power) add
## that much stock and the storage to hold it ("20-60" rolls a random
## amount; negative values are a one-time cost). "<id>_capacity" adds empty
## storage. "fuel" and "engine_thrust" are used by the launch, "mission_days"
## changes the mission length.
@export var upgrades: Dictionary[String, String] = {}
## Applied every night while the module works. Resource ids, plus
## crew_stress (each crew member) and crew_water (extra liters each crew
## member drinks).
@export var daily: Dictionary[String, int] = {}
## The crew can switch this module off for the night (no output, no costs).
@export var toggleable: bool = false
@export var risks: Array[CardRisk] = []
## See FLAG_TEXT.
@export var flags: Array[StringName] = []

@export_group("Synergy")
## Daily bonus for each related card aboard (or next to this one).
@export var synergy_daily: Dictionary[String, int] = {}
@export var synergy_domain: Domain = Domain.ENERGY
## Only cards right next to this one in the cargo count.
@export var synergy_adjacent: bool = false
## Maximum number of related cards that count.
@export var synergy_max: int = 1

@export_group("Card text")
@export_multiline var gives_text: String = ""
@export_multiline var costs_text: String = ""
@export_multiline var risks_text: String = ""
@export_multiline var synergy_text: String = ""
@export_multiline var lore: String = ""


func card_name() -> String:
    return short_name if short_name != "" else display_name


func slot_cost() -> int:
    return slot_override if slot_override > 0 else RARITY_SLOTS[rarity]


func rarity_name() -> String:
    return Rarity.keys()[rarity].capitalize()


func domain_name() -> String:
    return Domain.keys()[domain].capitalize()


func card_type_name() -> String:
    return CardType.keys()[card_type].capitalize()


func has_flag(flag: StringName) -> bool:
    return flags.has(flag)


## Parses an upgrade value: "10" -> [10, 10], "20-60" -> [20, 60].
static func parse_range(value: String) -> Vector2i:
    var dash := value.find("-", 1)
    if dash > 0:
        return Vector2i(int(value.substr(0, dash)), int(value.substr(dash + 1)))
    return Vector2i(int(value), int(value))


## Short mechanical summary, one effect per line (plain text). Used in the
## launch report and the mission.
func summary_lines() -> PackedStringArray:
    var lines: PackedStringArray = []
    for entry in summary_entries():
        lines.append(entry["text"])
    return lines


## Like summary_lines(), with a "kind" per line for coloring:
## "good", "bad", "risk" or "info".
func summary_entries() -> Array[Dictionary]:
    var entries: Array[Dictionary] = []
    for key in upgrades.keys():
        var r := parse_range(upgrades[key])
        var amount := "%+d" % r.x if r.x == r.y else "+%d-%d" % [r.x, r.y]
        var kind := "bad" if r.y < 0 else "good"
        var text := ""
        match key:
            "fuel":
                text = "%s t rocket fuel" % amount
            "engine_thrust":
                text = "Engines lift %s t" % amount
            "mission_days":
                text = "%s mission days" % amount
            "power":
                text = "%s %s battery" % [amount, MissionState.unit("power")]
            _:
                if key.ends_with("_capacity"):
                    var res: String = key.trim_suffix("_capacity")
                    text = "%s %s %s storage" % [amount, MissionState.unit(res), MissionState.resource_name(res).to_lower()]
                elif r.x == r.y:
                    text = MissionState.amount_text(key, r.x) + (" (once)" if r.x < 0 else "")
                else:
                    text = MissionState.amount_text(key, r.x).replace("%+d" % r.x, amount)
        entries.append({"text": text, "kind": kind})
    for key in daily.keys():
        var amount: int = daily[key]
        var good := amount < 0 if key in ["crew_stress", "crew_water"] else amount > 0
        entries.append({"text": daily_line(key, amount) + " / day", "kind": "good" if good else "bad"})
    if not synergy_daily.is_empty():
        var parts: PackedStringArray = []
        for key in synergy_daily.keys():
            parts.append(daily_line(key, synergy_daily[key]))
        entries.append({"text": "%s / day per %s%s card" % [", ".join(parts), "adjacent " if synergy_adjacent else "",
            Domain.keys()[synergy_domain].capitalize()], "kind": "good"})
    for flag in flags:
        entries.append({"text": FLAG_TEXT.get(flag, String(flag)), "kind": "good"})
    for risk in risks:
        if risk.short_text != "":
            entries.append({"text": "Risk: " + risk.short_text, "kind": "risk"})
    return entries


static func daily_line(key: String, amount: int) -> String:
    match key:
        "crew_stress":
            return "%+d crew stress" % amount
        "crew_water":
            return "crew drink %+d %s" % [amount, MissionState.unit("water")]
        _:
            return MissionState.amount_text(key, amount)
