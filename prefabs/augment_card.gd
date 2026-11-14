@tool class_name AugmentCard extends Control

@export var augment: Augment:
    set(new_augment):
        augment = new_augment
        update_display()

@export var country: String


func update_display() -> void:
    if augment == null:
        return
    %NameLabel.text = augment.display_name

    var sb := %Card.get_theme_stylebox("panel").duplicate() as StyleBoxTexture
    sb.texture = Augment.RARITY_CARDS[augment.rarity]
    %Card.add_theme_stylebox_override("panel", sb)

    var desc: String = augment.description
    for stat in augment.upgrades.keys():
        desc = desc.replace("{%s}" % stat, augment.upgrades[stat])
    %AugmentDescription.text = desc


func _on_button_pressed() -> void:
    pass


func _on_button_mouse_entered() -> void:
    var tween: Tween = create_tween()
    tween.tween_property(%Card, "offset_transform_scale", Vector2(1.1, 1.1), 0.5).set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_OUT)


func _on_button_mouse_exited() -> void:
    var tween: Tween = create_tween()
    tween.tween_property(%Card, "offset_transform_scale", Vector2(1, 1), 0.5).set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_OUT)
