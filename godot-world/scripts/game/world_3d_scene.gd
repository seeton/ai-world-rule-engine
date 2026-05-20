extends Node3D

signal gm_interaction_requested
signal rule_tree_toggle_requested
signal cli_overlay_toggle_requested

const VisualEffectBurstScript := preload("res://scripts/game/visual_effect_burst_2d.gd")

const PLAYER_ENTITY_ID := "origin_entity"
const GM_ENTITY_ID := "gm_entity"
const INTERACTION_DISTANCE: float = 3.2
const CAMERA_DISTANCE: float = 9.2
const CAMERA_YAW_DEGREES: float = -42.0
const CAMERA_PITCH_DEGREES: float = -28.0
const CAMERA_LOOK_HEIGHT: float = 1.7
const CAMERA_SMOOTH_SPEED: float = 6.5
const DEFAULT_LIGHT_DIRECTION := Vector3(-0.55, -1.0, 0.32)
const ACTIVE_LANGUAGE := "ja"
const UI_TEXT := {
	"ja": {
		"hint_near": "Eキー / クリックでGMに話しかける",
		"hint_far": "GMに近づくと相談できます",
		"clock_prefix": "時刻 ",
		"tick_prefix": "Tick ",
		"goal": "3D化された世界です。矢印キーで歩き、GMに近づいてください。",
		"subgoal": "光ルールや重力ルールを追加したら、世界の見え方の変化を確認できます。",
		"tree_hint": "Tキー: ルールツリー / Cキー: CLI",
		"world_fallback": "3D広場",
		"player_status": "プレイヤーは3D世界の中を移動できます。",
		"gm_status": "GMは3D世界の中に存在し、会話できます。"
	}
}

@onready var player: CharacterBody3D = $Player
@onready var gm: Area3D = $GameMaster
@onready var camera: Camera3D = $CameraRig/Camera3D
@onready var world_entities_root: Node3D = $WorldEntities
@onready var ground: StaticBody3D = $Ground
@onready var ground_collision: CollisionShape3D = $Ground/CollisionShape3D
@onready var ground_visual: MeshInstance3D = $Ground/Visual
@onready var sun: DirectionalLight3D = $Sun

var _world_state: Node = null
var _hud_layer: CanvasLayer = null
var _world_name_label: Label = null
var _clock_label: Label = null
var _tree_hint_label: Label = null
var _goal_hint: Label = null
var _status_hint: Label = null
var _interaction_hint: Label = null
var _effects_overlay: Node2D = null
var _is_hovering_gm: bool = false
var _entity_nodes: Dictionary = {}
var _effect_nodes: Dictionary = {}
var _overlay_active: bool = false
var _last_runtime_movement_intent: Vector3 = Vector3(9999.0, 9999.0, 9999.0)


func _ready() -> void:
	_world_state = get_node_or_null("/root/WorldState")
	if player.has_method("set_reference_camera"):
		player.call("set_reference_camera", camera)
	if gm.has_signal("interaction_triggered"):
		gm.interaction_triggered.connect(_on_gm_interaction)
	if gm.has_signal("hover_changed"):
		gm.hover_changed.connect(_on_gm_hover_changed)
	_setup_hud()
	var snapshot := _get_world_snapshot()
	_apply_snapshot(snapshot)
	camera.global_position = _desired_camera_position()
	camera.look_at(player.global_position + Vector3.UP * CAMERA_LOOK_HEIGHT, Vector3.UP)


func _process(delta: float) -> void:
	_sync_runtime_movement_intent()
	if not _overlay_active and _world_state != null and _world_state.has_method("advance_tick"):
		_world_state.call("advance_tick", delta)

	var snapshot := _get_world_snapshot()
	_apply_snapshot(snapshot)
	_update_camera(delta)
	_update_interaction_hint(delta)
	_update_clock(snapshot)


func _unhandled_input(event: InputEvent) -> void:
	if _overlay_active:
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
		if key_event.pressed and not key_event.echo and (key_event.keycode == KEY_C or key_event.physical_keycode == KEY_C):
			cli_overlay_toggle_requested.emit()
			get_viewport().set_input_as_handled()
			return
		if key_event.pressed and not key_event.echo and key_event.keycode == KEY_E and _is_player_in_range():
			gm_interaction_requested.emit()
		_dispatch_runtime_input_event(key_event)


func set_overlay_active(active: bool) -> void:
	_overlay_active = active
	_sync_runtime_movement_intent(true)
	if _hud_layer != null:
		_hud_layer.visible = not active


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
	_status_hint.size = Vector2(520.0, 42.0)
	_status_hint.text = "%s\n%s" % [_text("player_status"), _text("gm_status")]
	_status_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status_hint.add_theme_font_size_override("font_size", 14)
	_status_hint.add_theme_color_override("font_color", Color(0.12, 0.14, 0.17, 0.88))
	_status_hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hud_layer.add_child(_status_hint)

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
	_tree_hint_label.add_theme_color_override("font_color", Color(0.12, 0.14, 0.17, 0.92))
	_tree_hint_label.add_theme_color_override("font_shadow_color", Color(1.0, 1.0, 1.0, 0.72))
	_tree_hint_label.add_theme_constant_override("shadow_offset_x", 1)
	_tree_hint_label.add_theme_constant_override("shadow_offset_y", 1)
	_tree_hint_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hud_layer.add_child(_tree_hint_label)

	_interaction_hint = Label.new()
	_interaction_hint.position = Vector2(480.0, 804.0)
	_interaction_hint.size = Vector2(480.0, 32.0)
	_interaction_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_interaction_hint.text = _text("hint_near")
	_interaction_hint.visible = false
	_interaction_hint.modulate.a = 0.0
	_interaction_hint.add_theme_font_size_override("font_size", 18)
	_interaction_hint.add_theme_color_override("font_color", Color(0.06, 0.08, 0.1, 1.0))
	_interaction_hint.add_theme_color_override("font_shadow_color", Color(1.0, 1.0, 1.0, 0.72))
	_interaction_hint.add_theme_constant_override("shadow_offset_x", 1)
	_interaction_hint.add_theme_constant_override("shadow_offset_y", 1)
	_interaction_hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hud_layer.add_child(_interaction_hint)

	_effects_overlay = Node2D.new()
	_effects_overlay.name = "VisualEffectsOverlay"
	_hud_layer.add_child(_effects_overlay)


func _get_world_snapshot() -> Dictionary:
	if _world_state != null and _world_state.has_method("get_world_snapshot"):
		var snapshot_variant = _world_state.call("get_world_snapshot")
		if snapshot_variant is Dictionary:
			return snapshot_variant
	return {}


func _apply_snapshot(snapshot: Dictionary) -> void:
	if snapshot.is_empty():
		_world_name_label.text = _text("world_fallback")
		_set_player_visible(false)
		_set_gm_visible(false)
		_set_ground_visible(false)
		_set_sun_visible(false)
		_is_hovering_gm = false
		_sync_world_entities([])
		_sync_visual_effects([])
		return

	var world_name := String(snapshot.get("world_name", "")).strip_edges()
	_world_name_label.text = world_name if not world_name.is_empty() else _text("world_fallback")
	var preview_data := _coerce_dictionary(snapshot.get("three_d_preview", {}))
	var renderables := _normalize_renderables(preview_data.get("renderables", []))
	if renderables.is_empty():
		renderables = _build_renderables_from_entities(_coerce_dictionary(snapshot.get("entities", {})))

	_set_player_visible(false)
	_set_gm_visible(false)
	_set_ground_visible(false)
	_is_hovering_gm = false
	var renderable_by_id: Dictionary = {}
	for renderable in renderables:
		renderable_by_id[String(renderable.get("id", ""))] = renderable

	_apply_floor_and_lighting(preview_data, renderables)
	_apply_player_renderable(renderable_by_id.get(PLAYER_ENTITY_ID, {}))
	_apply_gm_renderable(renderable_by_id.get(GM_ENTITY_ID, {}))
	_sync_world_entities(renderables)
	_sync_visual_effects(snapshot.get("visual_effects", []))


func _apply_player_renderable(renderable: Dictionary) -> void:
	if renderable.is_empty():
		_set_player_visible(false)
		return
	_set_player_visible(true)
	player.global_position = renderable.get("position", player.global_position)
	if player.has_method("apply_visual_style"):
		player.call("apply_visual_style", renderable.get("size", Vector3(0.9, 1.8, 0.9)), renderable.get("color", Color(0.33, 0.55, 0.97, 1.0)))
	if player.has_method("apply_runtime_motion"):
		var physics := _coerce_dictionary(renderable.get("physics", {}))
		player.call("apply_runtime_motion", _vector3_from_variant(physics.get("velocity", {}), Vector3.ZERO))


func _apply_gm_renderable(renderable: Dictionary) -> void:
	if renderable.is_empty():
		_set_gm_visible(false)
		_is_hovering_gm = false
		return
	_set_gm_visible(true)
	gm.global_position = renderable.get("position", gm.global_position)
	if gm.has_method("apply_renderable"):
		gm.call("apply_renderable", renderable.get("size", Vector3(1.1, 2.2, 1.1)), renderable.get("color", Color(0.95, 0.79, 0.41, 1.0)))


func _sync_world_entities(renderables: Array) -> void:
	var active_ids: Dictionary = {}
	for renderable in renderables:
		var entity_id := String(renderable.get("id", ""))
		if entity_id.is_empty() or entity_id == PLAYER_ENTITY_ID or entity_id == GM_ENTITY_ID:
			continue
		active_ids[entity_id] = true
		var entity_node: Node3D = _entity_nodes.get(entity_id, null)
		if entity_node == null:
			entity_node = _create_world_entity_node(entity_id)
			_entity_nodes[entity_id] = entity_node
			world_entities_root.add_child(entity_node)
		_update_world_entity_node(entity_node, renderable)

	for entity_id in _entity_nodes.keys():
		if active_ids.has(entity_id):
			continue
		var stale_node: Node = _entity_nodes[entity_id]
		stale_node.queue_free()
		_entity_nodes.erase(entity_id)


func _create_world_entity_node(entity_id: String) -> Node3D:
	var node := Node3D.new()
	node.name = "Entity_%s" % entity_id.replace("/", "_")
	var mesh_instance := MeshInstance3D.new()
	mesh_instance.name = "Visual"
	mesh_instance.mesh = BoxMesh.new()
	mesh_instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	node.add_child(mesh_instance)
	return node


func _update_world_entity_node(entity_node: Node3D, renderable: Dictionary) -> void:
	entity_node.global_position = renderable.get("position", Vector3.ZERO)
	var mesh_instance := entity_node.get_node("Visual") as MeshInstance3D
	if mesh_instance == null:
		return
	if mesh_instance.mesh is BoxMesh:
		(mesh_instance.mesh as BoxMesh).size = renderable.get("size", Vector3.ONE)
	var material := mesh_instance.material_override
	if not (material is StandardMaterial3D):
		material = StandardMaterial3D.new()
		mesh_instance.material_override = material
	(material as StandardMaterial3D).albedo_color = renderable.get("color", Color(0.7, 0.7, 0.7, 1.0))
	(material as StandardMaterial3D).roughness = 0.78


func _apply_floor_and_lighting(preview_data: Dictionary, renderables: Array) -> void:
	var world_visible := bool(preview_data.get("enabled", false)) or not renderables.is_empty()
	_set_ground_visible(world_visible)
	if not world_visible:
		_apply_lighting({"enabled": false, "shadows_enabled": false})
		return
	var gravity_data := _coerce_dictionary(preview_data.get("gravity", {}))
	var lighting_data := _coerce_dictionary(preview_data.get("lighting", {}))
	var floor_y := float(gravity_data.get("floor_y", 0.0))
	var scene_extent := _compute_scene_extent(renderables)
	ground.position.y = floor_y - 0.1
	if ground_collision.shape is BoxShape3D:
		(ground_collision.shape as BoxShape3D).size = Vector3(scene_extent, 0.2, scene_extent)
	if ground_visual.mesh is BoxMesh:
		(ground_visual.mesh as BoxMesh).size = Vector3(scene_extent, 0.2, scene_extent)
	_apply_lighting(lighting_data)


func _apply_lighting(lighting_data: Dictionary) -> void:
	var lighting_enabled := _variant_to_bool(lighting_data.get("enabled", true), true)
	_set_sun_visible(lighting_enabled)
	sun.shadow_enabled = _variant_to_bool(lighting_data.get("shadows_enabled", true), true)
	sun.light_energy = float(lighting_data.get("intensity", 1.45))
	sun.light_color = _color_from_variant(lighting_data.get("color", "#fff1cf"), Color(1.0, 0.94, 0.82))
	if lighting_data.has("light_rotation_degrees"):
		sun.rotation_degrees = _vector3_from_variant(lighting_data.get("light_rotation_degrees"), Vector3(-58.0, 36.0, 0.0))
		return
	var direction := _vector3_from_variant(lighting_data.get("direction", DEFAULT_LIGHT_DIRECTION), DEFAULT_LIGHT_DIRECTION)
	if direction.length_squared() <= 0.0001:
		direction = DEFAULT_LIGHT_DIRECTION
	sun.position = -direction.normalized() * 10.0
	sun.look_at(Vector3.ZERO, Vector3.UP)


func _compute_scene_extent(renderables: Array) -> float:
	var max_distance := 12.0
	for renderable in renderables:
		var position: Vector3 = renderable.get("position", Vector3.ZERO)
		var size: Vector3 = renderable.get("size", Vector3.ONE)
		max_distance = max(max_distance, absf(position.x) + size.x * 2.0)
		max_distance = max(max_distance, absf(position.z) + size.z * 2.0)
	return max_distance * 2.0


func _update_camera(delta: float) -> void:
	var desired_position := _desired_camera_position()
	camera.global_position = camera.global_position.lerp(desired_position, clamp(delta * CAMERA_SMOOTH_SPEED, 0.0, 1.0))
	camera.look_at(player.global_position + Vector3.UP * CAMERA_LOOK_HEIGHT, Vector3.UP)


func _desired_camera_position() -> Vector3:
	var target := player.global_position + Vector3.UP * CAMERA_LOOK_HEIGHT
	var yaw := deg_to_rad(CAMERA_YAW_DEGREES)
	var pitch := deg_to_rad(CAMERA_PITCH_DEGREES)
	var horizontal_distance := cos(pitch) * CAMERA_DISTANCE
	return target + Vector3(
		cos(yaw) * horizontal_distance,
		sin(-pitch) * CAMERA_DISTANCE,
		sin(yaw) * horizontal_distance
	)


func _sync_runtime_movement_intent(force: bool = false) -> void:
	if _world_state == null or not _world_state.has_method("dispatch_input_event"):
		return
	var movement_intent := _movement_intent_from_input()
	if not force and movement_intent.distance_to(_last_runtime_movement_intent) < 0.0001:
		return
	_last_runtime_movement_intent = movement_intent
	_world_state.call("dispatch_input_event", "input.move.intent", {
		"entity_id": PLAYER_ENTITY_ID,
		"movement_vector": {
			"x": snappedf(movement_intent.x, 0.0001),
			"y": 0.0,
			"z": snappedf(movement_intent.z, 0.0001)
		},
		"world_mode": "three_d"
	})


func _movement_intent_from_input() -> Vector3:
	if _overlay_active:
		return Vector3.ZERO
	var input_vector := Input.get_vector("ui_left", "ui_right", "ui_up", "ui_down")
	if input_vector.length_squared() <= 0.0001:
		return Vector3.ZERO
	return _camera_relative_direction(input_vector)


func _camera_relative_direction(input_vector: Vector2) -> Vector3:
	var camera_basis := camera.global_transform.basis if camera != null else global_transform.basis
	var forward := -camera_basis.z
	forward.y = 0.0
	forward = forward.normalized()
	var right := camera_basis.x
	right.y = 0.0
	right = right.normalized()
	var movement_direction := (right * input_vector.x) + (forward * -input_vector.y)
	movement_direction.y = 0.0
	return movement_direction.normalized()


func _update_interaction_hint(delta: float) -> void:
	var should_show := (_is_player_in_range() or _is_hovering_gm) and not _overlay_active
	if should_show:
		_interaction_hint.visible = true
		_interaction_hint.text = _text("hint_near") if _is_player_in_range() else _text("hint_far")
		_interaction_hint.modulate.a = move_toward(_interaction_hint.modulate.a, 1.0, delta * 6.0)
	else:
		_interaction_hint.modulate.a = move_toward(_interaction_hint.modulate.a, 0.0, delta * 8.0)
		if is_zero_approx(_interaction_hint.modulate.a):
			_interaction_hint.visible = false


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


func _dispatch_runtime_input_event(key_event: InputEventKey) -> void:
	if _world_state == null or not _world_state.has_method("dispatch_input_event"):
		return
	if not key_event.pressed or key_event.echo:
		return
	var key_name := OS.get_keycode_string(key_event.keycode).strip_edges().to_lower()
	if key_name.is_empty():
		return
	_world_state.call("dispatch_input_event", "input.key.%s.pressed" % key_name, {
		"entity_id": PLAYER_ENTITY_ID,
		"world_mode": "three_d"
	})


func _sync_visual_effects(effects_variant: Variant) -> void:
	if _effects_overlay == null:
		return
	var active_effect_ids: Dictionary = {}
	if effects_variant is Array:
		for effect_variant in effects_variant:
			if not (effect_variant is Dictionary):
				continue
			var effect: Dictionary = effect_variant
			var effect_id := String(effect.get("id", "")).strip_edges()
			if effect_id.is_empty():
				continue
			var screen_position := _effect_screen_position(effect)
			if screen_position == Vector2.INF:
				continue
			active_effect_ids[effect_id] = true
			var effect_node: Node2D = _effect_nodes.get(effect_id, null)
			if effect_node == null:
				effect_node = VisualEffectBurstScript.new()
				effect_node.name = "Effect_%s" % effect_id
				_effects_overlay.add_child(effect_node)
				_effect_nodes[effect_id] = effect_node
			effect_node.call("apply_effect", effect, screen_position)

	for effect_id in _effect_nodes.keys():
		if active_effect_ids.has(effect_id):
			continue
		var stale_node: Node = _effect_nodes[effect_id]
		stale_node.queue_free()
		_effect_nodes.erase(effect_id)


func _effect_screen_position(effect: Dictionary) -> Vector2:
	var world_position := _vector3_from_variant(effect.get("position", {}), Vector3.ZERO)
	if camera != null and camera.has_method("is_position_behind") and camera.call("is_position_behind", world_position):
		return Vector2.INF
	return camera.unproject_position(world_position)


func _on_gm_interaction() -> void:
	if _overlay_active or not _is_player_in_range():
		return
	gm_interaction_requested.emit()


func _is_player_in_range() -> bool:
	if not player.visible or not gm.visible:
		return false
	return player.global_position.distance_to(gm.global_position) <= INTERACTION_DISTANCE


func _on_gm_hover_changed(is_hovering: bool) -> void:
	_is_hovering_gm = is_hovering


func _normalize_renderables(renderables_value: Variant) -> Array:
	var normalized: Array = []
	if not (renderables_value is Array):
		return normalized
	for renderable_value in renderables_value:
		if not (renderable_value is Dictionary):
			continue
		var renderable: Dictionary = renderable_value
		normalized.append({
			"id": String(renderable.get("id", "")),
			"name": String(renderable.get("name", renderable.get("id", "entity"))),
			"kind": String(renderable.get("kind", "object")),
			"position": _vector3_from_variant(renderable.get("position", Vector3.ZERO), Vector3.ZERO),
			"size": _vector3_from_variant(renderable.get("size", Vector3.ONE), Vector3.ONE),
			"color": _color_from_variant(renderable.get("color", "#bcbcbc"), Color(0.74, 0.74, 0.74, 1.0))
		})
	return normalized


func _build_renderables_from_entities(entities: Dictionary) -> Array:
	var renderables: Array = []
	var entity_ids: Array = entities.keys()
	entity_ids.sort()
	for entity_id in entity_ids:
		var entity_variant: Variant = entities.get(entity_id, {})
		if not (entity_variant is Dictionary):
			continue
		var entity: Dictionary = entity_variant
		var render_data := _coerce_dictionary(entity.get("render_3d", {}))
		if render_data.is_empty():
			continue
		renderables.append({
			"id": String(entity.get("id", entity_id)),
			"name": String(entity.get("name", entity_id)),
			"kind": String(render_data.get("kind", entity.get("archetype", "object"))),
			"position": _vector3_from_variant(entity.get("position", Vector3.ZERO), Vector3.ZERO),
			"size": _vector3_from_variant(render_data.get("size", Vector3.ONE), Vector3.ONE),
			"color": _color_from_variant(render_data.get("color", "#bcbcbc"), Color(0.74, 0.74, 0.74, 1.0))
		})
	return renderables


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


func _variant_to_bool(value: Variant, default_value: bool = false) -> bool:
	if value is bool:
		return value
	if value is int or value is float:
		return float(value) != 0.0
	if value is String:
		var normalized := String(value).strip_edges().to_lower()
		if normalized in ["1", "true", "yes", "on", "enabled"]:
			return true
		if normalized in ["0", "false", "no", "off", "disabled"]:
			return false
	return default_value


func _coerce_dictionary(value: Variant) -> Dictionary:
	return value if value is Dictionary else {}


func _set_player_visible(is_visible: bool) -> void:
	if player.has_method("set_render_enabled"):
		player.call("set_render_enabled", is_visible)
	var player_visual := player.get_node_or_null("Visual")
	if player_visual is GeometryInstance3D:
		(player_visual as GeometryInstance3D).visible = is_visible
	if player is Node3D:
		(player as Node3D).visible = is_visible
	var player_collision := player.get_node_or_null("CollisionShape3D")
	if player_collision is CollisionShape3D:
		(player_collision as CollisionShape3D).disabled = not is_visible


func _set_gm_visible(is_visible: bool) -> void:
	if gm.has_method("set_render_enabled"):
		gm.call("set_render_enabled", is_visible)
	var gm_visual := gm.get_node_or_null("Visual")
	if gm_visual is GeometryInstance3D:
		(gm_visual as GeometryInstance3D).visible = is_visible
	if gm is Node3D:
		(gm as Node3D).visible = is_visible
	var gm_collision := gm.get_node_or_null("CollisionShape3D")
	if gm_collision is CollisionShape3D:
		(gm_collision as CollisionShape3D).disabled = not is_visible
	if gm is CollisionObject3D:
		(gm as CollisionObject3D).input_ray_pickable = is_visible


func _set_ground_visible(is_visible: bool) -> void:
	if ground is Node3D:
		(ground as Node3D).visible = is_visible
	if ground_visual is GeometryInstance3D:
		ground_visual.visible = is_visible


func _set_sun_visible(is_visible: bool) -> void:
	sun.visible = is_visible


func _text(key: String) -> String:
	var table: Dictionary = UI_TEXT.get(ACTIVE_LANGUAGE, UI_TEXT["ja"])
	return String(table.get(key, key))
