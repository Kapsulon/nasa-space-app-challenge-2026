extends Node

var scenario_name: String = ""
var scenario_base_slot_count: int = -1
var scenario_days: int = 10
var scenario_objective: String = ""
var selected_augments: Array[AugmentInstance] = []
## Cargo slots after Logistics cards (bonus slots), and slots used by the
## crates / gambles themselves. -1 = not set (plan phase skipped).
var cargo_slots_total: int = -1
var cargo_overhead_slots: int = 0
