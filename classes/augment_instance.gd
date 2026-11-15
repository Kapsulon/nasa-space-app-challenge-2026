class_name AugmentInstance extends Node

var country: String = ""
var augment: Augment


func _init(_augment: Augment, _country: String) -> void:
    augment = _augment
    country = _country
