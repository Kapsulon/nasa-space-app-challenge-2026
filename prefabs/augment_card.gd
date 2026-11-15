@tool class_name AugmentCard extends Control

signal picked
## Emitted when the mouse enters / leaves the card, for previews.
signal hover_changed(hovering: bool)

@export var augment_instance: AugmentInstance:
    set(new_augment_instance):
        augment_instance = new_augment_instance
        update_display()


## Card face colors (dark, readable on the parchment).
const FACE_COLORS: Dictionary[String, String] = {
    "good": "1b7a2e",
    "bad": "b3261e",
    "risk": "a35c00",
    "info": "4a4a4a",
}


## Set once the card leaves the offer row (picked or discarded): it only
## plays its exit animation and ignores the mouse.
var _retired: bool = false
var _hover_tween: Tween
var _motion_tween: Tween
## Glowing outline and badge ("SWAP", "NEW"...), built on first use.
var _outline: Panel
var _badge: PanelContainer

@onready var _box: Control = $AspectRatioContainer


func _ready() -> void:
    %NameLabel.resized.connect(_fit_name)
    %AugmentDescription.resized.connect(_fit_face)
    # The offer row lays the card out; the motion runs on the inner box's
    # offset transform so it never fights the container.
    _box.offset_transform_enabled = true
    _box.offset_transform_pivot_ratio = Vector2(0.5, 0.5)
    %Card.offset_transform_pivot_ratio = Vector2(0.5, 0.5)


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
    # The flag of the country that built the card (none in the codex).
    %CountryImage.texture = Country.flag(augment_instance.country)
    %CountryImage.visible = %CountryImage.texture != null
    %AugmentImage.texture = augment.image
    %Foil.visible = augment.rarity == Augment.Rarity.MYTHIC

    _face_lines = []
    if augment.description != "":
        _face_lines.append(augment.description)
    else:
        for entry in augment.summary_entries():
            _face_lines.append("[color=#%s]%s[/color]" % [FACE_COLORS[entry["kind"]], entry["text"]])
    var footer := "%.1f t" % augment.weight
    if augment.slot_cost() != Augment.RARITY_SLOTS[augment.rarity]:
        footer += "  -  %d slots" % augment.slot_cost()
    _face_footer = "[color=#%s]%s  -  %s[/color]" % [FACE_COLORS["info"], augment.card_type_name(), footer]
    _set_face_text(FACE_MAX_FONT, _face_lines.size())
    _fit_face.call_deferred()


## Card face text: one BBCode line per effect (no sizes) plus a footer.
## `_fit_face` picks the size, and drops the last lines when they cannot be
## read at the minimum size (the details panel shows everything).
var _face_lines: Array[String] = []
var _face_footer: String = ""

## Biggest and smallest text sizes of the card face. The biggest one that
## fits the parchment wins, so short cards are easy to read from afar.
const FACE_MAX_FONT: int = 36
const FACE_MIN_FONT: int = 25


func _set_face_text(size: int, line_count: int) -> void:
    var shown := _face_lines.slice(0, line_count)
    %AugmentDescription.text = "[font_size=%d]%s[/font_size]\n[font_size=%d]%s[/font_size]" % [
        size, "\n".join(shown), maxi(size - 8, FACE_MIN_FONT - 6), _face_footer]


## Largest text size that fits the description box, dropping the least
## important lines when even the smallest size is too big.
func _fit_face() -> void:
    var label: RichTextLabel = %AugmentDescription
    if label.size.y <= 0.0 or _face_lines.is_empty():
        return
    var room := label.size.y - 4.0
    for line_count in range(_face_lines.size(), 0, -1):
        for size in range(FACE_MAX_FONT, FACE_MIN_FONT - 1, -2):
            _set_face_text(size, line_count)
            if label.get_content_height() <= room:
                return


## Shrinks the name until it fits on (at most) two lines.
func _fit_name() -> void:
    var label: Label = %NameLabel
    if label.size.x <= 0.0:
        return
    label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
    label.clip_text = true
    var font := label.get_theme_font("font")
    for font_size in range(40, 15, -2):
        var height := font.get_multiline_string_size(label.text, HORIZONTAL_ALIGNMENT_CENTER, label.size.x, font_size).y
        if height <= label.size.y:
            label.add_theme_font_size_override("font_size", font_size)
            return
    label.add_theme_font_size_override("font_size", 16)


## Marks the card with a glowing outline and a badge on its top edge, e.g.
## "THROW AWAY" on a picked target or "NEW" on a revealed card. An empty
## text removes the mark.
func set_mark(text: String, color: Color = Color.WHITE) -> void:
    if text == "":
        if _outline != null:
            _outline.hide()
            _badge.hide()
        return
    if _outline == null:
        _outline = Panel.new()
        _outline.mouse_filter = Control.MOUSE_FILTER_IGNORE
        _outline.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
        %Card.add_child(_outline)
        _badge = PanelContainer.new()
        _badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
        _badge.anchor_left = 0.5
        _badge.anchor_right = 0.5
        _badge.grow_horizontal = Control.GROW_DIRECTION_BOTH
        _badge.offset_top = -28.0
        var label := Label.new()
        label.add_theme_font_size_override("font_size", 29)
        label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
        _badge.add_child(label)
        %Card.add_child(_badge)
    var line := StyleBoxFlat.new()
    line.draw_center = false
    line.border_color = color
    line.set_border_width_all(5)
    line.set_corner_radius_all(14)
    line.shadow_color = Color(color, 0.55)
    line.shadow_size = 16
    _outline.add_theme_stylebox_override("panel", line)
    var tag := StyleBoxFlat.new()
    tag.bg_color = color
    tag.set_corner_radius_all(4)
    tag.content_margin_left = 16
    tag.content_margin_right = 16
    tag.content_margin_top = 4
    tag.content_margin_bottom = 4
    _badge.add_theme_stylebox_override("panel", tag)
    var badge_label: Label = _badge.get_child(0)
    badge_label.text = text
    badge_label.add_theme_color_override("font_color", Color("0b1220"))
    _outline.show()
    _badge.show()


func pick() -> void:
    %Button.emit_signal("pressed")


func _on_button_pressed() -> void:
    picked.emit()


func _on_button_mouse_entered() -> void:
    if not is_inside_tree() or is_queued_for_deletion() or _retired:
        return
    hover_changed.emit(true)
    _hover(Vector2(1.08, 1.08), Vector2(0, -22), deg_to_rad(randf_range(-1.5, 1.5)))


func _on_button_mouse_exited() -> void:
    if not is_inside_tree() or is_queued_for_deletion() or _retired:
        return
    hover_changed.emit(false)
    _hover(Vector2.ONE, Vector2.ZERO, 0.0)


## Lifts the card towards the player (or settles it back).
func _hover(scale_to: Vector2, lift: Vector2, tilt: float) -> void:
    if _hover_tween != null:
        _hover_tween.kill()
    _hover_tween = create_tween().set_parallel(true).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
    _hover_tween.tween_property(%Card, "offset_transform_scale", scale_to, 0.3)
    _hover_tween.tween_property(%Card, "offset_transform_position", lift, 0.3)
    _hover_tween.tween_property(%Card, "offset_transform_rotation", tilt, 0.3)


# --- Plan phase motion ----------------------------------------------------------

## Deals the card in: it flies up from below the screen, tilted, and snaps
## into place with a little overshoot.
func deal_in(delay: float) -> void:
    _box.offset_transform_position = Vector2(randf_range(-60.0, 60.0), 520.0)
    _box.offset_transform_rotation = deg_to_rad(randf_range(-14.0, 14.0))
    _box.offset_transform_scale = Vector2(0.75, 0.75)
    _box.modulate.a = 0.0
    _motion_tween = create_tween().set_parallel(true)
    _motion_tween.tween_property(_box, "offset_transform_position", Vector2.ZERO, 0.55) \
        .set_delay(delay).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
    _motion_tween.tween_property(_box, "offset_transform_rotation", 0.0, 0.6) \
        .set_delay(delay).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
    _motion_tween.tween_property(_box, "offset_transform_scale", Vector2.ONE, 0.55) \
        .set_delay(delay).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
    _motion_tween.tween_property(_box, "modulate:a", 1.0, 0.2).set_delay(delay)


## The card leaves the offer row: no more hover or clicks.
func retire() -> void:
    _retired = true
    if _hover_tween != null:
        _hover_tween.kill()
    if _motion_tween != null:
        _motion_tween.kill()
    _box.modulate.a = 1.0
    for node in find_children("*", "Control", true, false):
        (node as Control).mouse_filter = Control.MOUSE_FILTER_IGNORE
    mouse_filter = Control.MOUSE_FILTER_IGNORE


## Picked: a quick punch and flash, then the card shrinks into the cargo slot
## at `target` (global position). Without a target (a Logistics card used up
## on the spot) it bursts in place.
func fly_to(target: Vector2, has_target: bool) -> void:
    var tween := create_tween()
    tween.set_parallel(true)
    tween.tween_property(_box, "offset_transform_scale", Vector2(1.18, 1.18), 0.12).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
    tween.tween_property(_box, "modulate", Color(1.8, 1.8, 1.8, 1.0), 0.12)
    tween.chain().tween_interval(0.06)
    if has_target:
        var travel := target - _box.get_global_rect().get_center()
        tween.chain().tween_property(_box, "offset_transform_position", travel, 0.45).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
        tween.tween_property(_box, "offset_transform_scale", Vector2(0.1, 0.1), 0.45).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
        tween.tween_property(_box, "offset_transform_rotation", deg_to_rad(randf_range(-25.0, 25.0)), 0.45)
        tween.tween_property(_box, "modulate", Color(1.4, 1.4, 1.4, 0.6), 0.45)
    else:
        tween.chain().tween_property(_box, "offset_transform_scale", Vector2(1.6, 1.6), 0.35).set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_OUT)
        tween.tween_property(_box, "modulate", Color(2.5, 2.5, 2.5, 0.0), 0.35)
    tween.chain().tween_callback(queue_free)


## Not picked: the card drops away and fades.
func drop_away(delay: float) -> void:
    var tween := create_tween().set_parallel(true).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
    tween.tween_property(_box, "offset_transform_position", Vector2(randf_range(-40.0, 40.0), 380.0), 0.38).set_delay(delay)
    tween.tween_property(_box, "offset_transform_rotation", deg_to_rad(randf_range(-18.0, 18.0)), 0.38).set_delay(delay)
    tween.tween_property(_box, "modulate:a", 0.0, 0.3).set_delay(delay + 0.08)
    tween.chain().tween_callback(queue_free)
