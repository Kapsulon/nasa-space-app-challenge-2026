extends Control


func _scenario01_pressed() -> void:
    TransitionData.scenario_name = "Reach the ISS"
    TransitionData.scenario_base_slot_count = 30
    TransitionData.scenario_days = 10
    TransitionData.scenario_objective = "Keep the crew alive for 10 days until docking with the International Space Station."
    TransitionData.selected_augments = []
    get_tree().change_scene_to_file("res://scenes/plan_phase/plan_phase.tscn")
