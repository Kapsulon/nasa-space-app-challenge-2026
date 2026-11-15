class_name EventChoice extends Resource

## Effect keys understood by MissionState.apply_effects():
##   oxygen, water, food, power, hull, medkits, science  -> add to resource
##   crew_health        -> add to every living crew member's health
##   random_crew_health -> add to one random living crew member's health
##   random_crew_sick   -> (any value) makes one random healthy crew member sick
##   mission_days       -> add days to the mission length (delays / shortcuts)

@export var label: String = ""
## Paid immediately when the choice is picked. The choice is disabled if the cost can't be paid.
@export var cost: Dictionary[String, int] = {}
## Chance (0..1) that the success outcome happens during the night.
@export_range(0.0, 1.0) var success_chance: float = 1.0
@export var success_effects: Dictionary[String, int] = {}
@export_multiline var success_text: String = ""
@export var failure_effects: Dictionary[String, int] = {}
@export_multiline var failure_text: String = ""
