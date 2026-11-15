class_name MissionEvent extends Resource

@export var title: String = ""
@export_multiline var description: String = ""
## Earliest mission day this event can appear.
@export var min_day: int = 1
## Relative weight when drawing a random event.
@export var weight: float = 1.0
## Who is best at handling it: "command", "medical", "engineering",
## "science" (see MissionState.SKILL_NAMES). Skilled crew are faster and more
## likely to succeed.
@export var skill: String = ""
## Where the alert shows up on the ship: a station id (MissionState.STATIONS)
## or one of the extra spots in ShipView ("galley", "engine_bay", "hull",
## "outside").
@export var location: String = "galley"
## "hazard": debris, meteoroids, flares (Navigation cards make them rarer).
## "isolation": homesickness and crew tension (some Communication cards
## soften them). "good": a nice surprise (can't be cancelled, nobody wants to).
@export var tags: Array[StringName] = []
## The last choice is what the crew falls back on when nobody answers the
## alert in time, so it should be the passive option.
@export var choices: Array[EventChoice] = []
