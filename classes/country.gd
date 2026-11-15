class_name Country extends RefCounted
## The four (invented) countries that build the cards. Every picked card
## comes from a random country, shown by the flag in its top right corner.
## Each country backs the mission with a passive bonus that grows with the
## number of its cards in the cargo: tier 1 at 6 cards, 2 at 9, 3 at 12.

## Cards of one country needed for each bonus tier.
const TIERS: Array[int] = [6, 9, 12]

## name, what the bonus gives ("key": a resource added every night, or
## "reliability" in launch %), its amount per tier, the text for one tier
## and a short tag for the manifest.
const DATA: Dictionary[String, Dictionary] = {
    "solvara": {
        "name": "Solvara",
        "motto": "Sun-drenched desert republic, world leader in solar farms.",
        "color": Color("ff922b"),
        "key": "power",
        "amounts": [1, 2, 3],
        "text": "+%d kWh power every night",
        "tag": "+%d kWh",
    },
    "glacia": {
        "name": "Glacia",
        "motto": "Icy mountain kingdom that bottles the cleanest water around.",
        "color": Color("74c0fc"),
        "key": "water",
        "amounts": [1, 2, 4],
        "text": "+%d L water every night",
        "tag": "+%d L",
    },
    "verdania": {
        "name": "Verdania",
        "motto": "Forest federation whose greenhouses grow the freshest air.",
        "color": Color("69db7c"),
        "key": "oxygen",
        "amounts": [1, 1, 2],
        "text": "+%d kg oxygen every night",
        "tag": "+%d kg O2",
    },
    "ferrovia": {
        "name": "Ferrovia",
        "motto": "Steel-and-gears union famous for rockets that never miss a launch.",
        "color": Color("ff6b6b"),
        "key": "reliability",
        "amounts": [1, 2, 4],
        "text": "+%d%% launch reliability",
        "tag": "+%d%% LAUNCH",
    },
}

const FLAG_DIR: String = "res://assets/textures/flags"

static var _flags: Dictionary[String, Texture2D] = {}


static func ids() -> Array[String]:
    var result: Array[String] = []
    result.assign(DATA.keys())
    return result


static func random_id() -> String:
    return ids().pick_random()


static func display_name(id: String) -> String:
    return DATA[id]["name"] if DATA.has(id) else ""


static func color(id: String) -> Color:
    return DATA[id]["color"] if DATA.has(id) else Color.WHITE


## The flag texture, or null for no country.
static func flag(id: String) -> Texture2D:
    if not DATA.has(id):
        return null
    if not _flags.has(id):
        _flags[id] = load(FLAG_DIR.path_join(id + ".png"))
    return _flags[id]


## Bonus tier for this many cards: 0 (none) to 3.
static func tier(count: int) -> int:
    var result := 0
    for needed in TIERS:
        if count >= needed:
            result += 1
    return result


## Cards needed for the next tier, or -1 at the top tier.
static func next_tier_at(count: int) -> int:
    for needed in TIERS:
        if count < needed:
            return needed
    return -1


## Bonus amount at a tier (0 below tier 1).
static func amount(id: String, at_tier: int) -> int:
    if at_tier <= 0 or not DATA.has(id):
        return 0
    return DATA[id]["amounts"][at_tier - 1]


static func bonus_text(id: String, at_tier: int) -> String:
    return DATA[id]["text"] % amount(id, at_tier)


static func bonus_tag(id: String, at_tier: int) -> String:
    return DATA[id]["tag"] % amount(id, at_tier)


## Cards per country.
static func count_ids(country_ids: Array) -> Dictionary[String, int]:
    var counts: Dictionary[String, int] = {}
    for id in ids():
        counts[id] = 0
    for id in country_ids:
        if counts.has(id):
            counts[id] += 1
    return counts


static func counts(instances: Array[AugmentInstance]) -> Dictionary[String, int]:
    return count_ids(instances.map(func(i: AugmentInstance): return i.country))


## Everything the countries add, by key: "power", "water", "oxygen" (per
## night) and "reliability" (launch %).
static func bonuses(country_counts: Dictionary[String, int]) -> Dictionary[String, int]:
    var result: Dictionary[String, int] = {}
    for id in ids():
        var key: String = DATA[id]["key"]
        result[key] = result.get(key, 0) + amount(id, tier(country_counts.get(id, 0)))
    return result
