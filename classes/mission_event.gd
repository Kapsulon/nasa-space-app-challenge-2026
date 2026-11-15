class_name MissionEvent extends Resource

@export var title: String = ""
@export_multiline var description: String = ""
## Earliest mission day this event can appear.
@export var min_day: int = 1
## Relative weight when drawing a random event.
@export var weight: float = 1.0
@export var choices: Array[EventChoice] = []
