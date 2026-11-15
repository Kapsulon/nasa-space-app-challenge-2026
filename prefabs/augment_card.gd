@tool class_name AugmentCard extends Control

signal picked
## Emitted when the mouse enters / leaves the card, for previews.
signal hover_changed(hovering: bool)

@export var augment_instance: AugmentInstance:
    set(new_augment_instance):
        augment_instance = new_augment_instance
        update_display()

@export var country: String


## Card face colors (dark, readable on the parchment).
const FACE_COLORS: Dictionary[String, String] = {
    "good": "1b7a2e",
    "bad": "b3261e",
    "risk": "a35c00",
    "info": "4a4a4a",
}


func _ready() -> void:
    %NameLabel.resized.connect(_fit_name)


func update_display() -> void:
    if augment_instance == null:
        return
    var augment := augment_instance.augment
    %NameLabel.text = augment.card_name()
    _fit_name.call_deferred()

    var sb := %Card.get_theme_stylebox("panel").duplicate() as StyleBoxTexture
    sb.texture = Augment.RARITY_CARDS[augment.rarity]
    %Card.add_theme_stylebox_override("panel", sb)

    %FamilyImage.texture = Augment.TYPE_ICONS[augment.type]
    %AugmentImage.texture = augment.image
    %Foil.visible = augment.rarity == Augment.Rarity.MYTHIC

    var desc: String = augment.description
    if desc == "":
        var lines: PackedStringArray = []
        for entry in augment.summary_entries():
            lines.append("[color=#%s]%s[/color]" % [FACE_COLORS[entry["kind"]], entry["text"]])
        desc = "[font_size=19]%s[/font_size]" % "\n".join(lines)
    var footer := "%.1f t" % augment.weight
    if augment.slot_cost() != Augment.RARITY_SLOTS[augment.rarity]:
        footer += "  -  %d slots" % augment.slot_cost()
    desc += "\n[font_size=17][color=#%s]%s  -  %s[/color][/font_size]" % [FACE_COLORS["info"], augment.card_type_name(), footer]
    %AugmentDescription.text = desc


## Shrinks the name until it fits on (at most) two lines.
func _fit_name() -> void:
    var label: Label = %NameLabel
    if label.size.x <= 0.0:
        return
    label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
    label.clip_text = true
    var font := label.get_theme_font("font")
    for font_size in range(36, 11, -2):
        var height := font.get_multiline_string_size(label.text, HORIZONTAL_ALIGNMENT_CENTER, label.size.x, font_size).y
        if height <= label.size.y:
            label.add_theme_font_size_override("font_size", font_size)
            return
    label.add_theme_font_size_override("font_size", 12)


func pick() -> void:
    %Button.emit_signal("pressed")


func _on_button_pressed() -> void:
    picked.emit()


func _on_button_mouse_entered() -> void:
    if not is_inside_tree() or is_queued_for_deletion():
        return
    hover_changed.emit(true)
    var tween: Tween = create_tween()
    tween.tween_property(%Card, "offset_transform_scale", Vector2(1.1, 1.1), 0.5).set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_OUT)


func _on_button_mouse_exited() -> void:
    if not is_inside_tree() or is_queued_for_deletion():
        return
    hover_changed.emit(false)
    var tween: Tween = create_tween()
    tween.tween_property(%Card, "offset_transform_scale", Vector2(1, 1), 0.5).set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_OUT)
