extends Node2D

signal gm_interaction_requested
signal rule_tree_toggle_requested

const PLAYER_ENTITY_ID := "origin_entity"
const GM_ENTITY_ID := "gm_entity"
const PIXELS_PER_UNIT_X: float = 92.0
const PIXELS_PER_UNIT_Z: float = 46.0
const WORLD_CENTER := Vector2(720.0, 470.0)
const INTERACTION_DISTANCE: float = 110.0
const ACTIVE_LANGUAGE := "ja"
const UI_TEXT := {
	"ja": {
		"hint_near": "Eキー / クリックでGMに話しかける",
		"hint_far": "GMに近づくと相談できます",
		"clock_prefix": "時刻 ",
		"tick_prefix": "Tick ",
		"goal": "矢印キーで2Dの世界を歩き、GMのところまで移動してください。",
		"subgoal": "GMとの会話で 3D化 を適用すると、プレイヤーがいる世界そのものが3Dに切り替わります。",
		"tree_hint": "Tキーでルールツリー表示",
		"world_fallback": "2D広場",
		"player_status": "プレイヤーは2D世界の中を移動できます。",
		"gm_status": "GMは2D世界の中に存在し、会話できます。"
	}
}

@onready var player: CharacterBody2D = $Player
@onready var gm: Node2D = $GameMaster
@onready var world_entities_root: Node2D = $WorldEntities
@onready var interaction_hint: Label = $InteractionHint

var _world_state: Node = null
var _hud_layer: CanvasLayer = null
var _world_name_label: Label = null
var _clock_label: Label = null
var _tree_hint_label: Label = null
var _goal_hint: Label = null
var _status_hint: Label = null
var _is_hovering_gm: bool = false
var _player_position_initialized: bool = false
var _last_synced_player_position: Vector2 = Vector2(9999.0, 9999.0)
var _interaction_paused: bool = false
var _overlay_active: bool = false
var _entity_nodes: Dictionary = {}
var _overlay_hidden_hud_controls: Array[Control] = []


func _ready() -> void:
	_world_state = get_node_or_null("/root/WorldState")
	if gm.has_signal("interaction_triggered"):
		gm.interaction_triggered.connect(_on_gm_interaction)
	if gm.has_signal("hover_changed"):
		gm.hover_changed.connect(_on_gm_hover_changed)
	_setup_hud()
	_apply_snapshot(_get_world_snapshot())


func _process(delta: float) -> void:
	if not _interaction_paused and _world_state != null and _world_state.has_method("advance_tick"):
		_world_state.call("advance_tick", delta)

	_sync_player_to_world_state()

	var snapshot := _get_world_snapshot()
	_apply_snapshot(snapshot)
	_update_interaction_hint(delta)
	_update_clock(snapshot)


func _unhandled_input(event: InputEvent) -> void:
	if _interaction_paused:
		return

	if event.is_action_pressed("ui_accept") and _is_player_in_range():
		gm_interaction_requested.emit()
		return

	if event is InputEventKey:
		var key_event := event as InputEventKey
		if key_event.pressed and not key_event.echo and (key_event.keycode == KEY_T or key_event.physical_keycode == KEY_T):
			rule_tree_toggle_requested.emit()
			get_viewport().set_input_as_handled()
			return
		if key_event.pressed and not key_event.echo and key_event.keycode == KEY_E and _is_player_in_range():
			gm_interaction_requested.emit()


func set_interaction_paused(paused: bool) -> void:
	_interaction_paused = paused
	player.set_physics_process(not paused)


func set_overlay_active(active: bool) -> void:
	_overlay_active = active
	_refresh_overlay_sensitive_hud_visibility()


func _setup_hud() -> void:
	_hud_layer = CanvasLayer.new()
	add_child(_hud_layer)

	_world_name_label = Label.new()
	_world_name_label.position = Vector2(24.0, 20.0)
	_world_name_label.size = Vector2(520.0, 34.0)
	_world_name_label.add_theme_font_size_override("font_size", 26)
	_world_name_label.add_theme_color_override("font_color", Color(0.08, 0.1, 0.12, 1.0))
	_world_name_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hud_layer.add_child(_world_name_label)

	_goal_hint = Label.new()
	_goal_hint.position = Vector2(24.0, 58.0)
	_goal_hint.size = Vector2(760.0, 58.0)
	_goal_hint.text = "%s\n%s" % [_text("goal"), _text("subgoal")]
	_goal_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_goal_hint.add_theme_font_size_override("font_size", 16)
	_goal_hint.add_theme_color_override("font_color", Color(0.12, 0.14, 0.17, 1.0))
	_goal_hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hud_layer.add_child(_goal_hint)

	_status_hint = Label.new()
	_status_hint.position = Vector2(24.0, 120.0)
	_status_hint.size = Vector2(620.0, 42.0)
	_status_hint.text = "%s\n%s" % [_text("player_status"), _text("gm_status")]
	_status_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status_hint.add_theme_font_size_override("font_size", 14)
	_status_hint.add_theme_color_override("font_color", Color(0.12, 0.14, 0.17, 0.88))
	_status_hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hud_layer.add_child(_status_hint)
	_overlay_hidden_hud_controls = [_world_name_label, _goal_hint, _status_hint]

	_clock_label = Label.new()
	_clock_label.position = Vector2(980.0, 20.0)
	_clock_label.size = Vector2(420.0, 30.0)
	_clock_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_clock_label.add_theme_font_size_override("font_size", 20)
	_clock_label.add_theme_color_override("font_color", Color(0.08, 0.1, 0.12, 1.0))
	_clock_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hud_layer.add_child(_clock_label)

	_tree_hint_label = Label.new()
	_tree_hint_label.position = Vector2(1010.0, 52.0)
	_tree_hint_label.size = Vector2(380.0, 26.0)
	_tree_hint_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_tree_hint_label.text = _text("tree_hint")
	_tree_hint_label.add_theme_font_size_override("font_size", 14)
	_tree_hint_label.add_theme_color_override("font_color", Color(0.12, 0.14, 0.17, 0.9))
	_tree_hint_label.add_theme_color_override("font_shadow_color", Color(1.0, 1.0, 1.0, 0.72))
	_tree_hint_label.add_theme_constant_override("shadow_offset_x", 1)
	_tree_hint_label.add_theme_constant_override("shadow_offset_y", 1)
	_tree_hint_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hud_layer.add_child(_tree_hint_label)

	interaction_hint.visible = false
	interaction_hint.modulate.a = 0.0
	interaction_hint.text = _text("hint_near")
	_refresh_overlay_sensitive_hud_visibility()


func _refresh_overlay_sensitive_hud_visibility() -> void:
	for control in _overlay_hidden_hud_controls:
		if control != null:
			control.visible = not _overlay_active
	if _overlay_active:
		interaction_hint.visible = false
		interaction_hint.modulate.a = 0.0


func _get_world_snapshot() -> Dictionary:
	if _world_state != null and _world_state.has_method("get_world_snapshot"):
		var snapshot_variant = _world_state.call("get_world_snapshot")
		if snapshot_variant is Dictionary:
			return snapshot_variant
	return {}


func _apply_snapshot(snapshot: Dictionary) -> void:
	if snapshot.is_empty():
		_world_name_label.text = _text("world_fallback")
		return

	_world_name_label.text = String(snapshot.get("world_name", _text("world_fallback")))
	var entities := _coerce_dictionary(snapshot.get("entities", {}))
	_apply_player_entity(entities.get(PLAYER_ENTITY_ID, {}))
	_apply_gm_entity(entities.get(GM_ENTITY_ID, {}))
	_sync_world_entities(entities)


func _apply_player_entity(entity_variant: Variant) -> void:
	if not (entity_variant is Dictionary):
		return

	var entity: Dictionary = entity_variant
	var world_position := _entity_position(entity)
	if not _player_position_initialized:
		player.global_position = _world_to_screen(world_position)
		_last_synced_player_position = player.global_position
		_player_position_initialized = true

	if player.has_method("apply_visual_style"):
		player.call("apply_visual_style", _entity_size_2d(entity), _entity_color(entity, Color(0.33, 0.55, 0.97, 1.0)))


func _apply_gm_entity(entity_variant: Variant) -> void:
	if not (entity_variant is Dictionary):
		return

	var entity: Dictionary = entity_variant
	gm.global_position = _world_to_screen(_entity_position(entity))
	if gm.has_method("apply_visual_style"):
		gm.call("apply_visual_style", _entity_size_2d(entity), _entity_color(entity, Color(0.95, 0.79, 0.41, 1.0)))


func _sync_world_entities(entities: Dictionary) -> void:
	var active_ids: Dictionary = {}
	for entity_id_variant in entities.keys():
		var entity_id := String(entity_id_variant)
		if entity_id == PLAYER_ENTITY_ID or entity_id == GM_ENTITY_ID:
			continue
		var entity_variant: Variant = entities.get(entity_id, {})
		if not (entity_variant is Dictionary):
			continue
		var entity: Dictionary = entity_variant
		active_ids[entity_id] = true
		var entity_node: Node2D = _entity_nodes.get(entity_id, null)
		if entity_node == null:
			entity_node = _create_world_entity_node(entity_id)
			_entity_nodes[entity_id] = entity_node
			world_entities_root.add_child(entity_node)
		_update_world_entity_node(entity_node, entity)

	for entity_id in _entity_nodes.keys():
		if active_ids.has(entity_id):
			continue
		var stale_node: Node = _entity_nodes[entity_id]
		stale_node.queue_free()
		_entity_nodes.erase(entity_id)


func _create_world_entity_node(entity_id: String) -> Node2D:
	var node := Node2D.new()
	node.name = "Entity_%s" % entity_id.replace("/", "_")

	var visual := ColorRect.new()
	visual.name = "Visual"
	visual.mouse_filter = Control.MOUSE_FILTER_IGNORE
	node.add_child(visual)

	var label := Label.new()
	label.name = "Label"
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	node.add_child(label)
	return node


func _update_world_entity_node(entity_node: Node2D, entity: Dictionary) -> void:
	var size := _entity_size_2d(entity)
	var visual := entity_node.get_node("Visual") as ColorRect
	if visual != null:
		visual.position = -(size * 0.5)
		visual.size = size
		visual.color = _entity_color(entity, Color(0.71, 0.71, 0.75, 1.0))

	var label := entity_node.get_node("Label") as Label
	if label != null:
		label.position = Vector2(-80.0, size.y * 0.5 + 8.0)
		label.size = Vector2(160.0, 22.0)
		label.text = String(entity.get("name", entity.get("id", "entity")))
		label.add_theme_font_size_override("font_size", 12)
		label.add_theme_color_override("font_color", Color(0.15, 0.17, 0.2, 1.0))

	entity_node.global_position = _world_to_screen(_entity_position(entity))


func _sync_player_to_world_state() -> void:
	if not _player_position_initialized or _interaction_paused:
		return
	if _world_state == null or not _world_state.has_method("set_entity_position"):
		return
	if player.global_position.distance_to(_last_synced_player_position) < 0.5:
		return

	_last_synced_player_position = player.global_position
	var world_position := _screen_to_world(player.global_position)
	_world_state.call(
		"set_entity_position",
		PLAYER_ENTITY_ID,
		{
			"x": snappedf(world_position.x, 0.001),
			"z": snappedf(world_position.y, 0.001)
		}
	)


func _update_interaction_hint(delta: float) -> void:
	var should_show := (_is_player_in_range() or _is_hovering_gm) and not _interaction_paused
	if should_show:
		interaction_hint.visible = true
		interaction_hint.text = _text("hint_near") if _is_player_in_range() else _text("hint_far")
		interaction_hint.global_position = gm.global_position + Vector2(-120.0, -84.0)
		interaction_hint.modulate.a = move_toward(interaction_hint.modulate.a, 1.0, delta * 6.0)
	else:
		interaction_hint.modulate.a = move_toward(interaction_hint.modulate.a, 0.0, delta * 8.0)
		if is_zero_approx(interaction_hint.modulate.a):
			interaction_hint.visible = false


func _update_clock(snapshot: Dictionary) -> void:
	if snapshot.is_empty():
		_clock_label.visible = false
		return
	var world_clock := _coerce_dictionary(snapshot.get("world_clock", {}))
	if world_clock.is_empty():
		_clock_label.visible = false
		return
	_clock_label.visible = true
	_clock_label.text = "%s%.1f秒 / %s%d" % [
		_text("clock_prefix"),
		float(world_clock.get("elapsed_seconds", snapshot.get("elapsed_seconds", 0.0))),
		_text("tick_prefix"),
		int(world_clock.get("total_ticks", snapshot.get("tick_index", 0)))
	]


func _on_gm_interaction() -> void:
	if _interaction_paused or not _is_player_in_range():
		return
	gm_interaction_requested.emit()


func _is_player_in_range() -> bool:
	return player.global_position.distance_to(gm.global_position) <= INTERACTION_DISTANCE


func _on_gm_hover_changed(is_hovering: bool) -> void:
	_is_hovering_gm = is_hovering


func _entity_position(entity: Dictionary) -> Vector3:
	var position_variant: Variant = entity.get("position", {})
	if position_variant is Dictionary:
		var position: Dictionary = position_variant
		return Vector3(float(position.get("x", 0.0)), float(position.get("y", 0.0)), float(position.get("z", 0.0)))
	return Vector3.ZERO


func _entity_size_2d(entity: Dictionary) -> Vector2:
	var render_data := _coerce_dictionary(entity.get("render_3d", {}))
	var size_variant: Variant = render_data.get("size", {"x": 0.9, "z": 0.9})
	var size3 := _vector3_from_variant(size_variant, Vector3(0.9, 0.9, 0.9))
	return Vector2(max(size3.x, 0.7), max(size3.z, 0.7)) * 44.0


func _entity_color(entity: Dictionary, default_color: Color) -> Color:
	var render_data := _coerce_dictionary(entity.get("render_3d", {}))
	return _color_from_variant(render_data.get("color", default_color), default_color)


func _world_to_screen(world_position: Vector3) -> Vector2:
	return WORLD_CENTER + Vector2(world_position.x * PIXELS_PER_UNIT_X, world_position.z * PIXELS_PER_UNIT_Z)


func _screen_to_world(screen_position: Vector2) -> Vector2:
	var delta := screen_position - WORLD_CENTER
	return Vector2(delta.x / PIXELS_PER_UNIT_X, delta.y / PIXELS_PER_UNIT_Z)


func _vector3_from_variant(value: Variant, default_value: Vector3) -> Vector3:
	if value is Vector3:
		return value
	if value is Dictionary:
		var data: Dictionary = value
		return Vector3(
			float(data.get("x", default_value.x)),
			float(data.get("y", default_value.y)),
			float(data.get("z", data.get("depth", default_value.z)))
		)
	if value is Array:
		var values: Array = value
		if values.size() >= 3:
			return Vector3(float(values[0]), float(values[1]), float(values[2]))
		if values.size() == 2:
			return Vector3(float(values[0]), default_value.y, float(values[1]))
	return default_value


func _color_from_variant(value: Variant, default_value: Color) -> Color:
	if value is Color:
		return value
	if value is String:
		return Color.from_string(String(value), default_value)
	if value is Array:
		var values: Array = value
		if values.size() >= 3:
			var alpha := float(values[3]) if values.size() >= 4 else 1.0
			return Color(float(values[0]), float(values[1]), float(values[2]), alpha)
	if value is Dictionary:
		var data: Dictionary = value
		return Color(
			float(data.get("r", default_value.r)),
			float(data.get("g", default_value.g)),
			float(data.get("b", default_value.b)),
			float(data.get("a", default_value.a))
		)
	return default_value


func _coerce_dictionary(value: Variant) -> Dictionary:
	return value if value is Dictionary else {}


func _text(key: String) -> String:
	var table: Dictionary = UI_TEXT.get(ACTIVE_LANGUAGE, UI_TEXT["ja"])
	return String(table.get(key, key))
