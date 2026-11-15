extends Control


func _scenario01_pressed() -> void:
    TransitionData.scenario_name = "Reach the ISS"
    TransitionData.scenario_base_slot_count = 30
    get_tree().change_scene_to_file("res://scenes/plan_phase/plan_phase.tscn")
