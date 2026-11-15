@tool class_name AugmentCard extends Control

signal picked

@export var augment_instance: AugmentInstance:
    set(new_augment_instance):
        augment_instance = new_augment_instance
        update_display()

@export var country: String


func update_display() -> void:
    if augment_instance == null:
        return
    %NameLabel.text = augment_instance.augment.display_name

    var sb := %Card.get_theme_stylebox("panel").duplicate() as StyleBoxTexture
    sb.texture = Augment.RARITY_CARDS[augment_instance.augment.rarity]
    %Card.add_theme_stylebox_override("panel", sb)

    %FamilyImage.texture = Augment.TYPE_ICONS[augment_instance.augment.type]
    %AugmentImage.texture = augment_instance.augment.image

    var desc: String = augment_instance.augment.description
    for stat in augment_instance.augment.upgrades.keys():
        desc = desc.replace("{%s}" % stat, augment_instance.augment.upgrades[stat])
    %AugmentDescription.text = desc


func pick() -> void:
    %Button.emit_signal("pressed")


func _on_button_pressed() -> void:
    picked.emit()


func _on_button_mouse_entered() -> void:
    var tween: Tween = create_tween()
    tween.tween_property(%Card, "offset_transform_scale", Vector2(1.1, 1.1), 0.5).set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_OUT)


func _on_button_mouse_exited() -> void:
    var tween: Tween = create_tween()
    tween.tween_property(%Card, "offset_transform_scale", Vector2(1, 1), 0.5).set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_OUT)
