extends Node2D

signal gm_interaction_requested

const INTERACTION_DISTANCE := 86.0
const CLOCK_PREFIX := "時計 "

@onready var player: CharacterBody2D = $Player
@onready var gm: Node2D = $GameMaster
@onready var object_root: Node2D = $WorldObjects
@onready var interaction_hint: Label = $InteractionHint

var world_controller: Node = null
var _world_state: Node = null
var _interaction_paused := false
var _is_hovering_gm := false
var _hud_layer: CanvasLayer = null
var _world_name_label: Label = null
var _goal_label: Label = null
var _stage_label: Label = null
var _status_label: Label = null
var _clock_label: Label = null
var _selection_label: Label = null
var _object_nodes: Dictionary = {}

func _ready() -> void:
    _world_state = get_node_or_null("/root/WorldState")
    if gm.has_signal("interaction_triggered"):
        gm.interaction_triggered.connect(_on_gm_interaction)
    if gm.has_signal("hover_changed"):
        gm.hover_changed.connect(_on_gm_hover_changed)
    interaction_hint.visible = false
    interaction_hint.modulate.a = 0.0
    interaction_hint.text = "GMに近づいてクリック / Eキーで話す"
    _build_hud()
    _refresh_from_controller()

func set_world_controller(controller: Node) -> void:
    world_controller = controller
    if world_controller != null and world_controller.has_signal("poc_snapshot_changed"):
        world_controller.poc_snapshot_changed.connect(_refresh_from_controller)
    if is_node_ready():
        _refresh_from_controller()

func set_interaction_paused(paused: bool) -> void:
    _interaction_paused = paused
    player.set_physics_process(not paused)

func _process(delta: float) -> void:
    if not _interaction_paused and _world_state != null and _world_state.has_method("advance_tick"):
        _world_state.call("advance_tick", delta)
    _update_interaction_hint(delta)
    _refresh_dynamic_labels()

func _unhandled_input(event: InputEvent) -> void:
    if _interaction_paused:
        return
    if event.is_action_pressed("ui_accept") or (event is InputEventKey and event.pressed and event.keycode == KEY_E):
        if _is_player_in_range():
            gm_interaction_requested.emit()

func _build_hud() -> void:
    _hud_layer = CanvasLayer.new()
    add_child(_hud_layer)

    _world_name_label = Label.new()
    _world_name_label.position = Vector2(20.0, 18.0)
    _world_name_label.size = Vector2(520.0, 32.0)
    _world_name_label.add_theme_font_size_override("font_size", 26)
    _world_name_label.add_theme_color_override("font_color", Color(0.08, 0.1, 0.12, 1.0))
    _hud_layer.add_child(_world_name_label)

    _goal_label = Label.new()
    _goal_label.position = Vector2(20.0, 58.0)
    _goal_label.size = Vector2(760.0, 80.0)
    _goal_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
    _goal_label.add_theme_font_size_override("font_size", 15)
    _goal_label.add_theme_color_override("font_color", Color(0.12, 0.14, 0.17, 1.0))
    _hud_layer.add_child(_goal_label)

    _stage_label = Label.new()
    _stage_label.position = Vector2(20.0, 146.0)
    _stage_label.size = Vector2(760.0, 44.0)
    _stage_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
    _stage_label.add_theme_font_size_override("font_size", 18)
    _stage_label.add_theme_color_override("font_color", Color(0.08, 0.12, 0.2, 1.0))
    _hud_layer.add_child(_stage_label)

    _status_label = Label.new()
    _status_label.position = Vector2(20.0, 190.0)
    _status_label.size = Vector2(760.0, 56.0)
    _status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
    _status_label.add_theme_font_size_override("font_size", 14)
    _status_label.add_theme_color_override("font_color", Color(0.12, 0.14, 0.17, 0.88))
    _hud_layer.add_child(_status_label)

    _clock_label = Label.new()
    _clock_label.position = Vector2(1080.0, 18.0)
    _clock_label.size = Vector2(320.0, 28.0)
    _clock_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
    _clock_label.add_theme_font_size_override("font_size", 20)
    _clock_label.add_theme_color_override("font_color", Color(0.08, 0.1, 0.12, 1.0))
    _hud_layer.add_child(_clock_label)

    var selection_panel := PanelContainer.new()
    selection_panel.position = Vector2(1040.0, 92.0)
    selection_panel.size = Vector2(360.0, 290.0)
    _hud_layer.add_child(selection_panel)

    var selection_margin := MarginContainer.new()
    selection_margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
    selection_margin.add_theme_constant_override("margin_left", 12)
    selection_margin.add_theme_constant_override("margin_top", 12)
    selection_margin.add_theme_constant_override("margin_right", 12)
    selection_margin.add_theme_constant_override("margin_bottom", 12)
    selection_panel.add_child(selection_margin)

    _selection_label = Label.new()
    _selection_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
    _selection_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    _selection_label.size_flags_vertical = Control.SIZE_EXPAND_FILL
    _selection_label.add_theme_font_size_override("font_size", 15)
    selection_margin.add_child(_selection_label)

func _refresh_from_controller() -> void:
    var snapshot := _snapshot()
    if snapshot.is_empty():
        return
    _world_name_label.text = String(snapshot.get("world_name", "PoC2 2D実演世界"))
    _goal_label.text = "\n".join(snapshot.get("goal_lines", []))
    _stage_label.text = String(snapshot.get("stage_title", ""))
    _status_label.text = "%s\n%s" % [String(snapshot.get("stage_summary", "")), String(snapshot.get("success_summary", ""))]
    _update_object_nodes(snapshot)
    _update_selection_label(snapshot)
    _refresh_dynamic_labels()

func _refresh_dynamic_labels() -> void:
    var snapshot := _snapshot()
    if snapshot.is_empty():
        return
    var clock := _coerce_dictionary(snapshot.get("clock", {}))
    _clock_label.visible = bool(clock.get("visible", false))
    if _clock_label.visible:
        _clock_label.text = CLOCK_PREFIX + String(clock.get("formatted", ""))

func _update_object_nodes(snapshot: Dictionary) -> void:
    var visible_ids: Dictionary = {}
    for entity in snapshot.get("entities", []):
        if not (entity is Dictionary):
            continue
        var entity_dict: Dictionary = entity
        if String(entity_dict.get("kind", "")) != "object" or not bool(entity_dict.get("visible", false)):
            continue
        var entity_id := String(entity_dict.get("id", ""))
        visible_ids[entity_id] = true
        var node: Node2D = _object_nodes.get(entity_id, null)
        if node == null:
            node = _create_object_node(entity_id)
            _object_nodes[entity_id] = node
            object_root.add_child(node)
        _apply_object_node(node, entity_dict)

    for entity_id in _object_nodes.keys():
        if visible_ids.has(entity_id):
            continue
        var stale: Node = _object_nodes[entity_id]
        stale.queue_free()
        _object_nodes.erase(entity_id)

func _create_object_node(entity_id: String) -> Node2D:
    var node := Node2D.new()
    node.name = "Object_%s" % entity_id

    var visual := ColorRect.new()
    visual.name = "Visual"
    visual.mouse_filter = Control.MOUSE_FILTER_IGNORE
    node.add_child(visual)

    var label := Label.new()
    label.name = "Label"
    label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
    label.mouse_filter = Control.MOUSE_FILTER_IGNORE
    node.add_child(label)

    var area := Area2D.new()
    area.name = "Area"
    area.input_pickable = true
    area.input_event.connect(_on_object_input_event.bind(entity_id))
    node.add_child(area)

    var shape := CollisionShape2D.new()
    shape.name = "CollisionShape2D"
    shape.shape = RectangleShape2D.new()
    area.add_child(shape)
    return node

func _apply_object_node(node: Node2D, entity: Dictionary) -> void:
    var size: Vector2 = entity.get("size_2d", Vector2(64.0, 64.0))
    var visual := node.get_node("Visual") as ColorRect
    if visual != null:
        visual.position = -(size * 0.5)
        visual.size = size
        visual.color = entity.get("color", Color(0.7, 0.7, 0.7, 1.0))

    var label := node.get_node("Label") as Label
    if label != null:
        label.position = Vector2(-90.0, size.y * 0.5 + 8.0)
        label.size = Vector2(180.0, 42.0)
        label.text = String(entity.get("name", "物体"))
        label.add_theme_font_size_override("font_size", 13)
        label.add_theme_color_override("font_color", Color(0.15, 0.17, 0.2, 1.0))

    var shape := node.get_node("Area/CollisionShape2D") as CollisionShape2D
    if shape != null and shape.shape is RectangleShape2D:
        (shape.shape as RectangleShape2D).size = size

    node.position = entity.get("position_2d", Vector2.ZERO)

func _update_selection_label(snapshot: Dictionary) -> void:
    var selected := _coerce_dictionary(snapshot.get("selected_entity", {}))
    if selected.is_empty():
        _selection_label.text = "オブジェクト基礎を有効化すると、ここに選択中の物体状態が表示されます。"
        return

    var lines: Array = []
    lines.append("選択中: %s" % String(selected.get("name", "")))
    lines.append("区分: %s" % ("物体" if String(selected.get("kind", "")) == "object" else "人物"))
    for detail in selected.get("inspector_lines", []):
        lines.append("- %s" % String(detail))
    _selection_label.text = "\n".join(lines)

func _update_interaction_hint(delta: float) -> void:
    var should_show := (_is_player_in_range() or _is_hovering_gm) and not _interaction_paused
    if should_show:
        interaction_hint.visible = true
        interaction_hint.global_position = gm.global_position + Vector2(-120.0, -82.0)
        interaction_hint.modulate.a = move_toward(interaction_hint.modulate.a, 1.0, delta * 5.5)
    else:
        interaction_hint.modulate.a = move_toward(interaction_hint.modulate.a, 0.0, delta * 8.0)
        if is_zero_approx(interaction_hint.modulate.a):
            interaction_hint.visible = false

func _is_player_in_range() -> bool:
    return player.global_position.distance_to(gm.global_position) <= INTERACTION_DISTANCE

func _on_gm_interaction() -> void:
    if _interaction_paused or not _is_player_in_range():
        return
    gm_interaction_requested.emit()

func _on_gm_hover_changed(is_hovering: bool) -> void:
    _is_hovering_gm = is_hovering

func _on_object_input_event(_viewport: Node, event: InputEvent, _shape_idx: int, entity_id: String) -> void:
    if _interaction_paused:
        return
    if event is InputEventMouseButton:
        var mouse_event := event as InputEventMouseButton
        if mouse_event.pressed and mouse_event.button_index == MOUSE_BUTTON_LEFT and world_controller != null and world_controller.has_method("set_selected_entity"):
            world_controller.call("set_selected_entity", entity_id)

func _snapshot() -> Dictionary:
    if world_controller != null and world_controller.has_method("get_poc_snapshot"):
        var snapshot_variant = world_controller.call("get_poc_snapshot")
        if snapshot_variant is Dictionary:
            return snapshot_variant
    return {}

func _coerce_dictionary(value: Variant) -> Dictionary:
    return value if value is Dictionary else {}
