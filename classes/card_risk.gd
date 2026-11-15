class_name CardRisk extends Resource
## Something that can go wrong with a module during the mission. Checked every
## night for each working module; when its condition holds and the dice roll
## succeeds, its effects are applied and its log line is printed.

enum Condition {
    ## Can happen on any day.
    ANY_DAY,
    ## Only when the module sits right next to a card of `domain` in the cargo.
    ADJACENT_DOMAIN,
    ## Only on nights when life support ran short of power.
    POWER_SHORTAGE,
    ## Only when the batteries are completely full (overcharged).
    POWER_FULL,
    ## Only when the water stock is below `threshold` liters.
    WATER_BELOW,
    ## Every `every_days` days, checked in the morning before modules run
    ## (every_days = 1: every morning).
    EVERY_N_DAYS,
    ## Only on the night of day `threshold` (a one-off).
    ON_DAY,
}

@export var condition: Condition = Condition.ANY_DAY
## Chance (0 to 1) that the risk happens when its condition holds.
@export_range(0.0, 1.0, 0.01) var chance: float = 1.0
## For ADJACENT_DOMAIN, and for `adjacent_chance`.
@export var domain: Augment.Domain = Augment.Domain.ENERGY
## When >= 0, the chance used instead of `chance` while the module sits next
## to a card of `domain` (e.g. a radio next to a power module).
@export_range(-1.0, 1.0, 0.01) var adjacent_chance: float = -1.0
## For WATER_BELOW (liters) and ON_DAY (the day).
@export var threshold: int = 0
## For EVERY_N_DAYS.
@export var every_days: int = 3

## Same keys as event effects (MissionState.apply_effects): resource ids,
## "<resource>_percent" (e.g. food_percent: -40 spoils 40% of the food),
## crew_health, crew_stress, random_crew_health, random_crew_stress,
## random_crew_sick.
@export var effects: Dictionary = {}
## The module stops working until a crew member repairs it.
@export var breaks_module: bool = false
## The module is gone for good (cannot be repaired).
@export var permanent: bool = false
## The module produces nothing today (EVERY_N_DAYS risks).
@export var offline_today: bool = false
## Radio contact with Earth is lost for the day: "Call home" does nothing.
@export var cuts_comms: bool = false
## The risk never happens while a working module with this flag is aboard
## (e.g. "pure_water", "stable_power").
@export var blocked_by: StringName = &""
## The chance is halved while a working module with this flag is aboard.
@export var halved_by: StringName = &""
## Hazard alerts become this much more likely for the day (0.1 = +10%).
@export_range(0.0, 1.0, 0.05) var hazard_up: float = 0.0

## Short line for the card face, e.g. "Shorts next to Energy".
@export var short_text: String = ""
## Line for the daily report. {module} is replaced by the module name.
@export_multiline var log_text: String = ""
