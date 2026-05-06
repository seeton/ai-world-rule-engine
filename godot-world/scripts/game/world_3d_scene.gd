extends Node3D

signal gm_interaction_requested

const INTERACTION_DISTANCE := 3.0
const PLAYER_SPEED := 4.2
const CAMERA_OFFSET := Vector3(-5.8, 5.2, 7.2)
const CLOCK_PREFIX := "時計 "

@onready var player: CharacterBody3D = $Player
@onready var gm: Area3D = $GameMaster
@onready var camera: Camera3D = $CameraRig/Camera3D
@onready var object_root: Node3D = $WorldObjects

var world_controller: Node = null
var _world_state: Node = null
var _interaction_paused := false
var _is_hovering_gm := false
var _hud_layer: CanvasLayer = null
var _title_label: Label = null
var _note_label: Label = null
var _stage_label: Label = null
var _clock_label: Label = null
var _selection_label: Label = null
var _return_button: Button = null
var _object_nodes: Dictionary = {}

func _ready() -> void:
    _world_state = get_node_or_null("/root/WorldState")
    gm.input_event.connect(_on_gm_input_event)
    gm.mouse_entered.connect(_on_gm_mouse_entered)
    gm.mouse_exited.connect(_on_gm_mouse_exited)
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

func _physics_process(_delta: float) -> void:
    if _interaction_paused:
        player.velocity = Vector3.ZERO
        player.move_and_slide()
        return

    var input := Input.get_vector("ui_left", "ui_right", "ui_up", "ui_down")
    var direction := Vector3(input.x, 0.0, input.y)
    if direction.length_squared() > 0.0001:
        direction = direction.normalized()
    player.velocity.x = direction.x * PLAYER_SPEED
    player.velocity.z = direction.z * PLAYER_SPEED
    player.velocity.y = 0.0
    player.move_and_slide()

func _process(delta: float) -> void:
    if not _interaction_paused and _world_state != null and _world_state.has_method("advance_tick"):
        _world_state.call("advance_tick", delta)
    _update_camera()
    _refresh_dynamic_labels()

func _unhandled_input(event: InputEvent) -> void:
    if _interaction_paused:
        return
    if event.is_action_pressed("ui_cancel") and world_controller != null and world_controller.has_method("switch_world"):
        world_controller.call("switch_world", "two_d")
        return
    if event.is_action_pressed("ui_accept") or (event is InputEventKey and event.pressed and event.keycode == KEY_E):
        if _is_player_in_range():
            gm_interaction_requested.emit()

func _build_hud() -> void:
    _hud_layer = CanvasLayer.new()
    add_child(_hud_layer)

    _title_label = Label.new()
    _title_label.position = Vector2(20.0, 20.0)
    _title_label.size = Vector2(840.0, 34.0)
    _title_label.add_theme_font_size_override("font_size", 26)
    _hud_layer.add_child(_title_label)

    _note_label = Label.new()
    _note_label.position = Vector2(20.0, 58.0)
    _note_label.size = Vector2(860.0, 60.0)
    _note_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
    _note_label.add_theme_font_size_override("font_size", 15)
    _hud_layer.add_child(_note_label)

    _stage_label = Label.new()
    _stage_label.position = Vector2(20.0, 126.0)
    _stage_label.size = Vector2(860.0, 56.0)
    _stage_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
    _stage_label.add_theme_font_size_override("font_size", 16)
    _hud_layer.add_child(_stage_label)

    _clock_label = Label.new()
    _clock_label.position = Vector2(1090.0, 20.0)
    _clock_label.size = Vector2(310.0, 28.0)
    _clock_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
    _clock_label.add_theme_font_size_override("font_size", 20)
    _hud_layer.add_child(_clock_label)

    _return_button = Button.new()
    _return_button.position = Vector2(1090.0, 62.0)
    _return_button.size = Vector2(310.0, 34.0)
    _return_button.text = "2D 本筋へ戻る"
    _return_button.pressed.connect(_on_return_button_pressed)
    _hud_layer.add_child(_return_button)

    var selection_panel := PanelContainer.new()
    selection_panel.position = Vector2(1020.0, 118.0)
    selection_panel.size = Vector2(380.0, 250.0)
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
    _selection_label.add_theme_font_size_override("font_size", 14)
    selection_margin.add_child(_selection_label)

func _refresh_from_controller() -> void:
    var snapshot := _snapshot()
    if snapshot.is_empty():
        return
    _title_label.text = "PoC3 3D途中証明"
    _note_label.text = "%s\nGMに話しかけると同じ日本語UIを開けます。" % String(snapshot.get("poc3_note", ""))
    _stage_label.text = "%s\n%s" % [String(snapshot.get("stage_title", "")), String(snapshot.get("stage_summary", ""))]
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
        var node: Area3D = _object_nodes.get(entity_id, null)
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

func _create_object_node(entity_id: String) -> Area3D:
    var area := Area3D.new()
    area.name = "Object_%s" % entity_id
    area.input_ray_pickable = true
    area.input_event.connect(_on_object_input_event.bind(entity_id))

    var collision := CollisionShape3D.new()
    collision.name = "CollisionShape3D"
    collision.shape = BoxShape3D.new()
    area.add_child(collision)

    var visual := MeshInstance3D.new()
    visual.name = "Visual"
    visual.mesh = BoxMesh.new()
    area.add_child(visual)
    return area

func _apply_object_node(node: Area3D, entity: Dictionary) -> void:
    var size: Vector3 = entity.get("size_3d", Vector3.ONE)
    node.position = entity.get("position_3d", Vector3.ZERO)

    var collision := node.get_node("CollisionShape3D") as CollisionShape3D
    if collision != null and collision.shape is BoxShape3D:
        (collision.shape as BoxShape3D).size = size

    var visual := node.get_node("Visual") as MeshInstance3D
    if visual != null:
        if visual.mesh is BoxMesh:
            (visual.mesh as BoxMesh).size = size
        var material := visual.material_override
        if not (material is StandardMaterial3D):
            material = StandardMaterial3D.new()
            visual.material_override = material
        (material as StandardMaterial3D).albedo_color = entity.get("color", Color(0.7, 0.7, 0.7, 1.0))
        (material as StandardMaterial3D).roughness = 0.78

func _update_selection_label(snapshot: Dictionary) -> void:
    var selected := _coerce_dictionary(snapshot.get("selected_entity", {}))
    if selected.is_empty():
        _selection_label.text = "物体基礎が有効になると、ここに選択中の物体情報が表示されます。"
        return
    var lines: Array = []
    lines.append("選択中: %s" % String(selected.get("name", "")))
    for detail in selected.get("inspector_lines", []):
        lines.append("- %s" % String(detail))
    _selection_label.text = "\n".join(lines)

func _update_camera() -> void:
    camera.global_position = player.global_position + CAMERA_OFFSET
    camera.look_at(player.global_position + Vector3(0.0, 1.1, 0.0), Vector3.UP)

func _is_player_in_range() -> bool:
    return player.global_position.distance_to(gm.global_position) <= INTERACTION_DISTANCE

func _on_gm_input_event(_camera: Camera3D, event: InputEvent, _event_position: Vector3, _normal: Vector3, _shape_idx: int) -> void:
    if _interaction_paused:
        return
    if event is InputEventMouseButton:
        var mouse_event := event as InputEventMouseButton
        if mouse_event.pressed and mouse_event.button_index == MOUSE_BUTTON_LEFT and _is_player_in_range():
            gm_interaction_requested.emit()

func _on_gm_mouse_entered() -> void:
    _is_hovering_gm = true
    Input.set_default_cursor_shape(Input.CURSOR_POINTING_HAND)

func _on_gm_mouse_exited() -> void:
    _is_hovering_gm = false
    Input.set_default_cursor_shape(Input.CURSOR_ARROW)

func _on_object_input_event(_camera: Camera3D, event: InputEvent, _event_position: Vector3, _normal: Vector3, _shape_idx: int, entity_id: String) -> void:
    if _interaction_paused:
        return
    if event is InputEventMouseButton:
        var mouse_event := event as InputEventMouseButton
        if mouse_event.pressed and mouse_event.button_index == MOUSE_BUTTON_LEFT and world_controller != null and world_controller.has_method("set_selected_entity"):
            world_controller.call("set_selected_entity", entity_id)

func _on_return_button_pressed() -> void:
    if world_controller != null and world_controller.has_method("switch_world"):
        world_controller.call("switch_world", "two_d")

func _snapshot() -> Dictionary:
    if world_controller != null and world_controller.has_method("get_poc_snapshot"):
        var snapshot_variant = world_controller.call("get_poc_snapshot")
        if snapshot_variant is Dictionary:
            return snapshot_variant
    return {}

func _coerce_dictionary(value: Variant) -> Dictionary:
    return value if value is Dictionary else {}
