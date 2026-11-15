class_name EventChoice extends Resource

## Effect keys understood by MissionState.apply_effects():
##   oxygen, water, food, power, hull, medkits, science  -> add to resource
##   crew_health        -> add to every crew member aboard's health
##   random_crew_health -> add to one random crew member's health
##   crew_stress        -> add to every crew member aboard's stress (negative calms them down)
##   random_crew_stress -> add to one random crew member's stress
##   random_crew_sick   -> (any value) makes one random healthy crew member sick
##   mission_days       -> add days to the mission length (delays / shortcuts)
##   worker_health / worker_stress -> the crew member who handles it (random if radioed)
##   most_stressed_stress -> the most stressed crew member
##   stress_<skill>     -> crew with that skill, e.g. stress_command
##   <condition>_days   -> a ship condition for that many nights (MissionState.CONDITIONS:
##                         blackout, rationing, sluggish, comms_down, cold)
##   break_<domain>     -> a random working module of that domain breaks (needs a repair)
##   lose_<domain>      -> ... is gone for good;  offline_<domain> -> ... is off for the day
##                         (domain: energy, oxygen, ..., "any"; join with "_or_")
##   repair_module      -> repairs that many broken modules
##   gain_mythic        -> that many random Mythic cards join the ship as modules
##   random_resource    -> add to a random one of oxygen, water, food, power
##   sick_all           -> the whole crew gets sick
##   cryosleep          -> the most stressed crew member goes home tonight to recover

@export var label: String = ""
## Only available while a working module of this domain is aboard (-1 = none),
## e.g. "Analyze it with the star tracker" needs Navigation.
@export_enum("None:-1", "Water:0", "Energy:1", "Oxygen:2", "Food:3", "Propulsion:4", "Logistics:5",
    "Communication:6", "Navigation:7", "Fuel:8") var requires_domain: int = -1
## Paid immediately when the choice is picked. The choice is disabled if the cost can't be paid.
@export var cost: Dictionary[String, int] = {}
## Somebody has to go and do it. When false the order is just radioed to the
## ship and resolves right away.
@export var needs_crew: bool = true
## Hours of work on the spot (skilled crew are faster).
@export var work_hours: float = 2.0
## Base chance (0..1) of success; skill, stress and sickness change it.
@export_range(0.0, 1.0) var success_chance: float = 1.0
@export var success_effects: Dictionary[String, int] = {}
@export_multiline var success_text: String = ""
@export var failure_effects: Dictionary[String, int] = {}
@export_multiline var failure_text: String = ""
