class_name Augment extends Resource
## A card picked during the plan phase. Once launched it becomes a ship module
## (see MissionState / ShipModule):
##   - `upgrades` apply once, at launch (stock, fuel, engine lift...).
##   - `daily` applies every night while the module works.
##   - `risks` can trigger during the night.
##   - `synergy_*` gives a daily bonus for related cards (optionally only for
##     cards right next to this one in the cargo).
##   - Navigation cards lower the odds of hazard alerts (`hazard_reduction`).
## Propulsion, Fuel and Logistics cards never become modules: they only matter
## for the launch, or act on the deck as soon as they are picked
## (`plan_action`).

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
    LOGISTICS,
    COMMUNICATION,
    NAVIGATION,
    FUEL,
}

enum CardType {
    STOCK,
    RECYCLING,
    TREATMENT,
    PRODUCTION,
    STORAGE,
    CONNECTOR,
    PROPULSION,
    DECK_MANAGEMENT,
    GAMBLE,
    MODULE,
    BOOSTER,
    ENGINE,
    TANK,
}

## What a Logistics card does to the deck the moment it is picked.
enum PlanAction {
    NONE,
    ## Throw away a card of the cargo (up to `action_max_rarity`).
    REMOVE,
    ## Replace a card with a random one of the same rarity.
    SWAP,
    ## 3 random cards, at least one of them Rare.
    CRATE,
    ## Copy a Common card already in the cargo (the copy takes its slots).
    DUPLICATE,
    ## 2 Common cards become 1 random Rare.
    TRADE_UP,
    ## 50%: 2 random Rare cards. 50%: lose 2 random cards.
    DOUBLE_OR_NOTHING,
    ## 1 random Mythic.
    LOTTERY,
}

## Cards that only matter before the mission (never ship modules).
const LAUNCH_ONLY_DOMAINS: Array[Domain] = [Domain.PROPULSION, Domain.FUEL, Domain.LOGISTICS]

## Total hazard reduction allowed from Navigation cards (unless a card
## raises it with `hazard_cap`).
const DEFAULT_HAZARD_CAP: float = 0.75

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
    Domain.LOGISTICS: Color("c9a274"),
    Domain.COMMUNICATION: Color("ff7ac8"),
    Domain.NAVIGATION: Color("7cf08a"),
    Domain.FUEL: Color("ff4f4f"),
}

## Flags a module can carry, and what they mean on the card.
const FLAG_TEXT: Dictionary[StringName, String] = {
    &"pure_water": "No water sickness aboard",
    &"stable_power": "Power never fails",
    &"laser_comms": "Radio never goes down, no comms risks",
    &"morale_floor": "Crew stress never goes above 75",
    &"isolation_relief": "Homesick alerts cost 25% less stress",
    &"comms_relay": "Halves Common comms interference",
    &"infinite_food": "Feeds the whole crew while it runs",
}

## Crew stress can't go above this with a "morale_floor" module aboard.
const MORALE_FLOOR_STRESS: int = 75

const PLAN_ACTION_TEXT: Dictionary[PlanAction, String] = {
    PlanAction.REMOVE: "Throw away a card",
    PlanAction.SWAP: "Swap a card for a random one of the same rarity",
    PlanAction.CRATE: "3 random cards (at least 1 Rare)",
    PlanAction.DUPLICATE: "Copy a Common card",
    PlanAction.TRADE_UP: "Trade 2 Commons for a random Rare",
    PlanAction.DOUBLE_OR_NOTHING: "50%: 2 random Rares. 50%: lose 2 cards",
    PlanAction.LOTTERY: "1 random Mythic",
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
## Slots taken in the cargo. -1 = depends on rarity.
@export var slot_override: int = -1

@export_group("Effects")
## Applied once at launch. Resource ids (water, oxygen, food, power) add
## that much stock and the storage to hold it ("20-60" rolls a random
## amount; negative values are a one-time cost). "<id>_capacity" adds empty
## storage. "fuel" and "engine_thrust" are used by the launch, "mission_days"
## changes the mission length.
## Launch keys (see LaunchProfile): "thrust", "fuel", "fuel_burn" (fuel the
## engine burns at take-off), "fuel_leak" (fuel lost before take-off),
## "reliability" (launch reliability, in %).
@export var upgrades: Dictionary[String, String] = {}
## Applied every night while the module works. Resource ids, plus
## crew_stress (each crew member) and crew_water (extra liters each crew
## member drinks).
@export var daily: Dictionary[String, int] = {}
## The daily effects (and synergy) stop after this many days of mission
## (0 = the whole mission), e.g. a care package that cheers the crew up for
## the first 2 days.
@export var daily_days: int = 0
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
## Only related cards of at least this rarity count.
@export var synergy_min_rarity: Rarity = Rarity.COMMON
## Keys (like `upgrades`) added at launch when a related card is in the
## cargo: launch keys, and resource ids for extra stock.
@export var launch_synergy: Dictionary[String, String] = {}

@export_group("Navigation")
## Lowers the chance of hazard alerts (0.3 = 30% less likely).
@export_range(0.0, 1.0, 0.05) var hazard_reduction: float = 0.0
## Raises the cap on the total hazard reduction (0 = DEFAULT_HAZARD_CAP).
@export_range(0.0, 1.0, 0.05) var hazard_cap: float = 0.0
## The crew can redraw this many alerts during the mission.
@export var event_rerolls: int = 0
## The crew can cancel a bad alert, once every this many days (0 = never).
@export var cancel_every_days: int = 0

@export_group("Plan phase")
@export var plan_action: PlanAction = PlanAction.NONE
## Highest rarity the action can target (REMOVE).
@export var action_max_rarity: Rarity = Rarity.MYTHIC
## Extra cargo slots, as soon as the card is picked.
@export var bonus_slots: int = 0

@export_group("Card text")
@export_multiline var gives_text: String = ""
@export_multiline var costs_text: String = ""
@export_multiline var risks_text: String = ""
@export_multiline var synergy_text: String = ""
@export_multiline var lore: String = ""


func card_name() -> String:
    return short_name if short_name != "" else display_name


func slot_cost() -> int:
    return slot_override if slot_override >= 0 else RARITY_SLOTS[rarity]


## Only matters before the mission: launch hardware or a deck action.
func is_launch_only() -> bool:
    return domain in LAUNCH_ONLY_DOMAINS


## Used up when picked: it acts on the deck and doesn't fly.
func is_consumed() -> bool:
    return plan_action != PlanAction.NONE


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
    if plan_action != PlanAction.NONE:
        var text: String = PLAN_ACTION_TEXT[plan_action]
        if plan_action == PlanAction.REMOVE and action_max_rarity == Rarity.RARE:
            text += " (not a Mythic)"
        entries.append({"text": text, "kind": "info"})
    if bonus_slots != 0:
        entries.append({"text": "%+d cargo slot%s" % [bonus_slots, "" if absi(bonus_slots) == 1 else "s"], "kind": "good"})
    for key in upgrades.keys():
        var r := parse_range(upgrades[key])
        var amount := "%+d" % r.x if r.x == r.y else "+%d-%d" % [r.x, r.y]
        var kind := "bad" if r.y < 0 else "good"
        var text := ""
        match key:
            "thrust":
                text = "%s thrust" % amount
            "fuel":
                text = "%s fuel" % amount
            "fuel_burn":
                text = "Burns %d fuel at take-off" % r.x
                kind = "bad"
            "fuel_leak":
                text = "Loses %d fuel before take-off" % r.x
                kind = "bad"
            "reliability":
                text = "%s%% launch reliability" % amount
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
        var per_day := " / day" if daily_days <= 0 else " / day (first %d day%s)" % [daily_days, "" if daily_days == 1 else "s"]
        entries.append({"text": daily_line(key, amount) + per_day, "kind": "good" if good else "bad"})
    if hazard_reduction > 0.0:
        entries.append({"text": "Hazard alerts %d%% less likely" % roundi(hazard_reduction * 100.0), "kind": "good"})
    if event_rerolls > 0:
        entries.append({"text": "Redraw %d alert%s per mission" % [event_rerolls, "" if event_rerolls == 1 else "s"], "kind": "good"})
    if cancel_every_days > 0:
        entries.append({"text": "Cancel a bad alert every %d days" % cancel_every_days, "kind": "good"})
    var related := "%s%s%s card" % ["adjacent " if synergy_adjacent else "",
        "Mythic " if synergy_min_rarity == Rarity.MYTHIC else ("Rare+ " if synergy_min_rarity == Rarity.RARE else ""),
        Domain.keys()[synergy_domain].capitalize()]
    if not synergy_daily.is_empty():
        var parts: PackedStringArray = []
        for key in synergy_daily.keys():
            parts.append(daily_line(key, synergy_daily[key]))
        entries.append({"text": "%s / day per %s" % [", ".join(parts), related], "kind": "good"})
    if not launch_synergy.is_empty():
        var parts: PackedStringArray = []
        for key in launch_synergy.keys():
            if MissionState.RESOURCE_INFO.has(key):
                parts.append(MissionState.amount_text(key, int(launch_synergy[key])))
            else:
                parts.append("%+d %s" % [int(launch_synergy[key]), key.replace("_", " ")])
        entries.append({"text": "%s with a %s" % [", ".join(parts), related], "kind": "good"})
    for flag in flags:
        entries.append({"text": FLAG_TEXT.get(flag, String(flag)), "kind": "good"})
    for risk in risks:
        if risk.short_text != "":
            entries.append({"text": "Risk: " + risk.short_text, "kind": "risk"})
    return entries


## A related card for the synergy bonuses.
func is_synergy_partner(other: Augment) -> bool:
    return other.domain == synergy_domain and other.rarity >= synergy_min_rarity


static func daily_line(key: String, amount: int) -> String:
    match key:
        "crew_stress":
            return "%+d crew stress" % amount
        "crew_water":
            return "crew drink %+d %s" % [amount, MissionState.unit("water")]
        _:
            return MissionState.amount_text(key, amount)
