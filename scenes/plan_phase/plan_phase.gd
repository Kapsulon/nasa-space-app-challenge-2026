@tool
extends Control
## Phase 1: pick cards for the cargo, three offers at a time, until the slots
## are full. Logistics cards act on the cargo right away (throw a card away,
## swap it, open a crate...). Some of them need a target: the manifest then
## turns into buttons until the player picks one.

const TIME_TO_PICK: float = 60.0
const LAUNCH_REPORT_SCENE: String = "res://scenes/launch_report/launch_report.tscn"
const PROMPT_TEXT: String = "Choose wisely:"

@export_tool_button("Generate cards") var gen = gen_cards

const AUGMENT_CARD_PACKED_SCENE: PackedScene = preload("res://prefabs/augment_card.tscn")
const SLOT_PACKED_SCENE: PackedScene = preload("res://scenes/plan_phase/slot.tscn")

const AUGMENTS: Registry = preload("res://data/augments/augments.tres")

const EMPTY_SLOT_COLOR := Color(1, 1, 1, 0.15)

## Actions that need the player to pick card(s) in the manifest.
const TARGETED_ACTIONS: Array[Augment.PlanAction] = [
    Augment.PlanAction.REMOVE, Augment.PlanAction.SWAP, Augment.PlanAction.DUPLICATE, Augment.PlanAction.TRADE_UP,
]

## Launch odds bar colors, from hopeless (red) to safe (green).
static var ODDS_GRADIENT: Gradient = _make_odds_gradient()


static func _make_odds_gradient() -> Gradient:
    var gradient := Gradient.new()
    gradient.offsets = PackedFloat32Array([0.0, 0.5, 0.8, 1.0])
    gradient.colors = PackedColorArray([Color("ff3a55"), Color("ff8a2a"), Color("ffb800"), Color("39ff6a")])
    return gradient

@export var available_augment_slots: int = 30:
    set(n_available_augment_slots):
        available_augment_slots = n_available_augment_slots
        if is_node_ready():
            gen_slots()

var selected_augments: Array[AugmentInstance] = []
## Slots taken by crates and gambles themselves (their cards ride inside).
var overhead_slots: int = 0
## Weight, thrust and fuel of everything picked so far.
var launch: LaunchProfile = LaunchProfile.new()
var finished: bool = false

var time_left: float = TIME_TO_PICK

## A Logistics card waiting for the player to pick its target(s).
var _pending: AugmentInstance = null
var _pending_targets: Array[AugmentInstance] = []
var _message_tween: Tween


func _ready() -> void:
    if not Engine.is_editor_hint() and TransitionData.scenario_base_slot_count > 0:
        available_augment_slots = TransitionData.scenario_base_slot_count
    gen_cards()
    gen_slots()
    update_manifest()
    update_launch_odds()


func _process(delta: float) -> void:
    if Engine.is_editor_hint() or finished:
        return
    time_left -= delta
    if time_left <= 0.0:
        time_left = TIME_TO_PICK
        if _pending != null:
            # Out of time: pick the target(s) at random.
            var targets := _targets_for(_pending.augment).filter(func(t): return not _pending_targets.has(t))
            targets.shuffle()
            while _pending_targets.size() < _targets_needed(_pending.augment) and not targets.is_empty():
                _pending_targets.append(targets.pop_back())
            _resolve_pending()
        else:
            var cards := %CardsHolder.get_children().filter(func(c: Node): return not c.is_queued_for_deletion())
            if not cards.is_empty():
                cards.pick_random().pick()
    %TimeLeftProgress.value = time_left / TIME_TO_PICK * 100.0


func used_slots() -> int:
    var used := overhead_slots
    for instance in selected_augments:
        used += instance.slots_taken()
    return used


func remaining_slots() -> int:
    return available_augment_slots - used_slots()


## Cards that fit in the remaining slots and can do something right now.
func available_augments() -> Array[Augment]:
    var result: Array[Augment] = []
    for augment in _all_augments():
        if augment.slot_cost() <= remaining_slots() and _can_use(augment):
            result.append(augment)
    return result


func _all_augments() -> Array[Augment]:
    var result: Array[Augment] = []
    for id in AUGMENTS.get_all_string_ids():
        var augment: Augment = AUGMENTS.load_entry(id)
        if augment != null:
            result.append(augment)
    return result


func gen_cards() -> void:
    for child in %CardsHolder.get_children():
        child.queue_free()
    update_launch_odds()
    show_details(null)
    for augment in draw_offers(available_augments(), 3):
        var card: AugmentCard = AUGMENT_CARD_PACKED_SCENE.instantiate()
        card.augment_instance = AugmentInstance.new(augment, "")
        card.connect("picked", func(): card_picked(card.augment_instance))
        card.hover_changed.connect(func(hovering: bool):
            update_launch_odds(card.augment_instance.augment if hovering else null)
            show_details(card.augment_instance.augment if hovering else null))
        %CardsHolder.add_child(card)
        card.owner = get_tree().edited_scene_root


## Up to `count` different cards, rarer cards showing up less often
## (Augment.RARITY_WEIGHTS).
static func draw_offers(pool: Array[Augment], count: int) -> Array[Augment]:
    var remaining := pool.duplicate()
    var offers: Array[Augment] = []
    while offers.size() < count and not remaining.is_empty():
        var total := 0.0
        for augment: Augment in remaining:
            total += Augment.RARITY_WEIGHTS[augment.rarity]
        var roll := randf() * total
        var picked: Augment = remaining[-1]
        for augment: Augment in remaining:
            roll -= Augment.RARITY_WEIGHTS[augment.rarity]
            if roll <= 0.0:
                picked = augment
                break
        remaining.erase(picked)
        offers.append(picked)
    return offers


func gen_slots() -> void:
    for child in %Slots.get_children():
        child.queue_free()
    for i in range(available_augment_slots):
        var slot := SLOT_PACKED_SCENE.instantiate()
        %Slots.add_child(slot)
        slot.owner = get_tree().edited_scene_root
    update_slots()


## Tints filled slots with the domain color of the card occupying them, so
## neighbours in the cargo are easy to spot. Crates and gambles show in the
## Logistics color at the end.
func update_slots() -> void:
    var colors: Array[Color] = []
    for instance in selected_augments:
        for i in instance.slots_taken():
            colors.append(Augment.DOMAIN_COLORS[instance.augment.domain])
    for i in overhead_slots:
        colors.append(Augment.DOMAIN_COLORS[Augment.Domain.LOGISTICS])
    var slots := %Slots.get_children().filter(func(c: Node): return not c.is_queued_for_deletion())
    for i in slots.size():
        slots[i].modulate = colors[i] if i < colors.size() else EMPTY_SLOT_COLOR


func update_manifest() -> void:
    %SlotsLabel.text = "%d / %d slots filled" % [used_slots(), available_augment_slots]
    for child in %ManifestList.get_children():
        child.queue_free()
    if _pending != null:
        _build_target_list()
        update_balance()
        return

    # Cargo order matters (neighbours), so list it in order and only merge
    # identical cards picked one after the other: "3x Fuel Tank".
    var runs: Array[Array] = []
    for instance in selected_augments:
        if not runs.is_empty() and runs[-1][0] == instance.augment:
            runs[-1][1] += 1
        else:
            runs.append([instance.augment, 1])
    for run in runs:
        var augment: Augment = run[0]
        var row := HBoxContainer.new()
        row.add_theme_constant_override("separation", 10)
        row.add_child(_swatch(augment))
        var label := Label.new()
        label.text = ("%dx " % run[1] if run[1] > 1 else "") + augment.card_name()
        label.add_theme_font_size_override("font_size", 22)
        label.add_theme_color_override("font_color", Augment.RARITY_COLORS[augment.rarity])
        label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
        label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
        row.add_child(label)
        %ManifestList.add_child(row)
    if overhead_slots > 0:
        var crates := Label.new()
        crates.text = "Crates and gambles: %d slot%s" % [overhead_slots, "" if overhead_slots == 1 else "s"]
        crates.add_theme_font_size_override("font_size", 18)
        crates.add_theme_color_override("font_color", Augment.DOMAIN_COLORS[Augment.Domain.LOGISTICS])
        %ManifestList.add_child(crates)
    update_balance()


## The manifest as buttons, one per card, while a Logistics card waits for
## its target(s).
func _build_target_list() -> void:
    var targets := _targets_for(_pending.augment)
    for instance in selected_augments:
        var augment := instance.augment
        var row := HBoxContainer.new()
        row.add_theme_constant_override("separation", 10)
        row.add_child(_swatch(augment))
        var button := Button.new()
        button.text = augment.card_name()
        button.alignment = HORIZONTAL_ALIGNMENT_LEFT
        button.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
        button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
        button.add_theme_font_size_override("font_size", 20)
        button.add_theme_color_override("font_color", Augment.RARITY_COLORS[augment.rarity])
        button.toggle_mode = true
        button.button_pressed = _pending_targets.has(instance)
        button.disabled = not targets.has(instance)
        button.pressed.connect(_on_target_pressed.bind(instance))
        row.add_child(button)
        %ManifestList.add_child(row)
    var cancel := Button.new()
    cancel.text = "Cancel: pick another card"
    cancel.add_theme_font_size_override("font_size", 20)
    cancel.pressed.connect(_cancel_pending)
    %ManifestList.add_child(cancel)


func _swatch(augment: Augment) -> ColorRect:
    var swatch := ColorRect.new()
    swatch.color = Augment.DOMAIN_COLORS[augment.domain]
    swatch.custom_minimum_size = Vector2(10, 22)
    swatch.size_flags_vertical = Control.SIZE_SHRINK_CENTER
    return swatch


## How long the supplies would last with this cargo, and how the cargo order
## affects the modules.
func update_balance() -> void:
    if Engine.is_editor_hint():
        return
    var preview := MissionState.new("", TransitionData.scenario_days, [], selected_augments)
    var forecast := preview.forecast()
    var t := ""
    for res_id in ["water", "oxygen", "food", "power"]:
        var stock: int = preview.resources[res_id]
        var net: int = forecast[res_id]
        var lasts := ""
        var color := "7be38b"
        if net >= 0:
            lasts = "steady"
        else:
            var days := floori(stock / float(-net))
            lasts = "lasts %d day%s" % [days, "" if days == 1 else "s"]
            if days < preview.mission_days:
                color = "ff5a6e" if days * 2 < preview.mission_days else "ffb35c"
        t += "%s %d %s  [color=#8a94a6]%+d/day[/color]  [color=#%s]%s[/color]\n" % [
            MissionState.resource_name(res_id), stock, MissionState.unit(res_id), net, color, lasts]
    var hazard := preview.hazard_change()
    if hazard < 0.0:
        t += "Hazard alerts  [color=#7be38b]%d%% less likely[/color]\n" % roundi(-hazard * 100.0)
    for note in preview.adjacency_notes():
        t += "[color=#ffb35c][font_size=18]%s[/font_size][/color]\n" % note
    %Balance.text = t.strip_edges()


## Fills the details panel with everything about the hovered card.
func show_details(augment: Augment) -> void:
    if Engine.is_editor_hint():
        return
    if augment == null:
        %CardDetails.text = "[color=#8a94a6]Hover a card to read about it. Cards become modules aboard the ship: they bring supplies, produce or use resources every day, and some can misbehave. Order matters: cards next to each other in the cargo can help or bother each other. Engines, boosters and fuel tanks only matter for the launch, and Logistics cards rearrange the cargo as soon as you pick them.[/color]"
        return
    var t := "[b][color=#%s]%s[/color][/b]\n" % [Augment.RARITY_COLORS[augment.rarity].to_html(false), augment.display_name]
    t += "[color=#%s]%s[/color] [color=#8a94a6]-  %s  -  %s  -  %.1f t  -  %d slot%s[/color]\n" % [
        Augment.DOMAIN_COLORS[augment.domain].to_html(false), augment.domain_name(), augment.card_type_name(),
        augment.rarity_name(), augment.weight, augment.slot_cost(), "" if augment.slot_cost() == 1 else "s"]
    var rows := [["Gives", augment.gives_text, "7be38b"], ["Costs", augment.costs_text, "ff5a6e"],
        ["Risks", augment.risks_text, "ffb35c"], ["Synergy", augment.synergy_text, "63b1ff"]]
    for row in rows:
        if row[1] != "":
            t += "[color=#%s]%s:[/color] %s\n" % [row[2], row[0], row[1]]
    if augment.lore != "":
        t += "[color=#8a94a6][font_size=18]%s[/font_size][/color]" % augment.lore
    %CardDetails.text = t


## Refreshes the launch odds bar. While a card is hovered, `preview` is its
## augment and the hint shows how picking it would change the odds.
func update_launch_odds(preview: Augment = null) -> void:
    if Engine.is_editor_hint():
        return
    var chance := launch.success_chance()
    var bar: ProgressBar = %OddsBar
    bar.value = chance * 100.0
    var fill := bar.get_theme_stylebox("fill").duplicate() as StyleBoxFlat
    fill.bg_color = ODDS_GRADIENT.sample(chance)
    bar.add_theme_stylebox_override("fill", fill)
    %OddsLabel.text = "%d%%" % roundi(chance * 100.0)

    var hint: Label = %OddsHint
    if preview != null and not preview.is_consumed():
        var after := launch.with_augment(preview).success_chance()
        var delta := roundi(after * 100.0) - roundi(chance * 100.0)
        hint.text = "If picked: %d%% (%s)" % [roundi(after * 100.0), "no change" if delta == 0 else "%+d" % delta]
        hint.add_theme_color_override("font_color", Color("39ff6a") if delta > 0 else (Color("ff3a55") if delta < 0 else Color.WHITE))
    else:
        hint.text = launch.advice()
        hint.add_theme_color_override("font_color", ODDS_GRADIENT.sample(chance))

    %LaunchStats.text = "Weight %.1f t: thrust %d / needs %d\nFuel %d / engines burn %d" % [
        launch.total_weight(), roundi(launch.thrust), roundi(launch.thrust_needed()), roundi(launch.fuel_available()), roundi(launch.fuel_needed())]


func card_picked(augment_instance: AugmentInstance) -> void:
    var augment := augment_instance.augment
    if finished or _pending != null or augment.slot_cost() > remaining_slots():
        return
    time_left = TIME_TO_PICK
    if augment.plan_action in TARGETED_ACTIONS:
        _pending = augment_instance
        _pending_targets.clear()
        %CardsHolder.hide()
        _set_prompt(_target_prompt(augment), 34)
        update_manifest()
        return
    _apply_card(augment_instance, [])


# --- Logistics ------------------------------------------------------------------

## Whether a card can be picked now (Logistics cards need something to act on).
func _can_use(augment: Augment) -> bool:
    match augment.plan_action:
        Augment.PlanAction.REMOVE, Augment.PlanAction.SWAP, Augment.PlanAction.DUPLICATE:
            return not _targets_for(augment).is_empty()
        Augment.PlanAction.TRADE_UP:
            return _targets_for(augment).size() >= 2
    return true


## Cards in the cargo the action can pick.
func _targets_for(augment: Augment) -> Array[AugmentInstance]:
    var result: Array[AugmentInstance] = []
    for instance in selected_augments:
        var target := instance.augment
        if target.domain == Augment.Domain.LOGISTICS:
            continue
        match augment.plan_action:
            Augment.PlanAction.REMOVE:
                if target.rarity <= augment.action_max_rarity:
                    result.append(instance)
            Augment.PlanAction.SWAP:
                result.append(instance)
            Augment.PlanAction.DUPLICATE:
                if target.rarity == Augment.Rarity.COMMON and target.slot_cost() <= remaining_slots() - augment.slot_cost():
                    result.append(instance)
            Augment.PlanAction.TRADE_UP:
                if target.rarity == Augment.Rarity.COMMON:
                    result.append(instance)
    return result


func _targets_needed(augment: Augment) -> int:
    return 2 if augment.plan_action == Augment.PlanAction.TRADE_UP else 1


func _target_prompt(augment: Augment) -> String:
    match augment.plan_action:
        Augment.PlanAction.REMOVE:
            return "%s: pick a card in the manifest to throw away" % augment.card_name()
        Augment.PlanAction.SWAP:
            return "%s: pick a card in the manifest to swap" % augment.card_name()
        Augment.PlanAction.DUPLICATE:
            return "%s: pick a Common card to print a copy of" % augment.card_name()
        Augment.PlanAction.TRADE_UP:
            return "%s: pick 2 Common cards to trade" % augment.card_name()
    return PROMPT_TEXT


func _on_target_pressed(instance: AugmentInstance) -> void:
    if _pending == null or not _targets_for(_pending.augment).has(instance):
        return
    if _pending_targets.has(instance):
        _pending_targets.erase(instance)
    else:
        _pending_targets.append(instance)
    if _pending_targets.size() >= _targets_needed(_pending.augment):
        _resolve_pending()
    else:
        update_manifest()


func _cancel_pending() -> void:
    _pending = null
    _pending_targets.clear()
    %CardsHolder.show()
    _set_prompt(PROMPT_TEXT)
    update_manifest()


func _resolve_pending() -> void:
    var instance := _pending
    var targets := _pending_targets.duplicate()
    _pending = null
    _pending_targets.clear()
    %CardsHolder.show()
    _set_prompt(PROMPT_TEXT)
    if instance != null and targets.size() >= _targets_needed(instance.augment):
        _apply_card(instance, targets)
    else:
        update_manifest()


## Puts a picked card in the cargo, or carries out its Logistics action.
func _apply_card(instance: AugmentInstance, targets: Array) -> void:
    var augment := instance.augment
    var message := ""
    if augment.is_consumed():
        overhead_slots += augment.slot_cost()
    else:
        instance.roll()
        selected_augments.append(instance)
    if augment.bonus_slots != 0:
        available_augment_slots += augment.bonus_slots
        message = "+%d cargo slots!" % augment.bonus_slots

    match augment.plan_action:
        Augment.PlanAction.REMOVE:
            var target: AugmentInstance = targets[0]
            selected_augments.erase(target)
            message = "Threw away the %s. %s" % [target.augment.card_name(), message]
        Augment.PlanAction.SWAP:
            var target: AugmentInstance = targets[0]
            var other := _random_card(target.augment.rarity, target.augment)
            if other != null:
                other.slots = target.slots_taken()
                selected_augments[selected_augments.find(target)] = other
                message = "Swapped the %s for: %s" % [target.augment.card_name(), other.augment.card_name()]
        Augment.PlanAction.DUPLICATE:
            var target: AugmentInstance = targets[0]
            var copy := AugmentInstance.new(target.augment, "")
            copy.roll()
            selected_augments.insert(selected_augments.find(target) + 1, copy)
            message = "Printed a second %s!" % target.augment.card_name()
        Augment.PlanAction.TRADE_UP:
            var index := selected_augments.find(targets[0])
            var freed := 0
            for target: AugmentInstance in targets:
                freed += target.slots_taken()
                selected_augments.erase(target)
            var rare := _random_card(Augment.Rarity.RARE)
            if rare != null:
                rare.slots = freed
                selected_augments.insert(mini(index, selected_augments.size()), rare)
                message = "Traded up for: %s" % rare.augment.card_name()
        Augment.PlanAction.CRATE:
            var found: Array[AugmentInstance] = [_random_card(Augment.Rarity.RARE), _random_card(-1), _random_card(-1)]
            message = "Inside the crate: %s" % _add_free_cards(found)
        Augment.PlanAction.DOUBLE_OR_NOTHING:
            if randf() < 0.5:
                var won: Array[AugmentInstance] = [_random_card(Augment.Rarity.RARE), _random_card(Augment.Rarity.RARE)]
                message = "Double! You won: %s" % _add_free_cards(won)
            else:
                var pool := selected_augments.filter(func(i: AugmentInstance): return i.augment.domain != Augment.Domain.LOGISTICS)
                pool.shuffle()
                var lost: PackedStringArray = []
                for target: AugmentInstance in pool.slice(0, 2):
                    selected_augments.erase(target)
                    lost.append(target.augment.card_name())
                message = "Nothing! You lost: %s" % (", ".join(lost) if not lost.is_empty() else "nothing, the cargo was empty")
        Augment.PlanAction.LOTTERY:
            var found: Array[AugmentInstance] = [_random_card(Augment.Rarity.MYTHIC)]
            message = "The prototype is: %s" % _add_free_cards(found)

    launch = LaunchProfile.from_instances(selected_augments)
    update_slots()
    update_manifest()
    update_launch_odds()
    if message.strip_edges() != "":
        _flash(message.strip_edges())

    if remaining_slots() <= 0 or available_augments().is_empty():
        finish()
    else:
        gen_cards()


## Adds cards that ride for free (inside a crate). Returns their names.
func _add_free_cards(instances: Array[AugmentInstance]) -> String:
    var names: PackedStringArray = []
    for instance in instances:
        if instance == null:
            continue
        instance.slots = 0
        selected_augments.append(instance)
        names.append(instance.augment.card_name())
    return ", ".join(names)


## A random card that can fly (no Logistics), of `rarity` (-1 = any, rarer
## ones less often), other than `exclude`.
func _random_card(rarity: int, exclude: Augment = null) -> AugmentInstance:
    var pool: Array[Augment] = []
    for augment in _all_augments():
        if augment.domain != Augment.Domain.LOGISTICS and augment != exclude and (rarity < 0 or augment.rarity == rarity):
            pool.append(augment)
    if pool.is_empty():
        return null
    var picked: Augment = pool.pick_random() if rarity >= 0 else draw_offers(pool, 1)[0]
    var instance := AugmentInstance.new(picked, "")
    instance.roll()
    return instance


func _set_prompt(text: String, font_size: int = 64) -> void:
    if _message_tween != null:
        _message_tween.kill()
    %PromptLabel.text = text
    %PromptLabel.add_theme_font_size_override("font_size", font_size)
    %PromptLabel.modulate = Color.WHITE


## Shows what a Logistics card did for a few seconds.
func _flash(text: String) -> void:
    _set_prompt(text, 34)
    %PromptLabel.modulate = Color("ffb800")
    _message_tween = create_tween()
    _message_tween.tween_interval(3.5)
    _message_tween.tween_callback(func():
        if _pending == null:
            _set_prompt(PROMPT_TEXT))


## All slots are filled: hand the selection over and go to the launch report.
func finish() -> void:
    finished = true
    for child in %CardsHolder.get_children():
        child.queue_free()
    update_launch_odds()
    %TimeLeftProgress.value = 0.0
    TransitionData.selected_augments = selected_augments
    TransitionData.cargo_slots_total = available_augment_slots
    TransitionData.cargo_overhead_slots = overhead_slots
    await get_tree().create_timer(1.0).timeout
    get_tree().change_scene_to_file(LAUNCH_REPORT_SCENE)
