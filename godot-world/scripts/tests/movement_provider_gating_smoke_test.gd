extends SceneTree

const WorldStateScript = preload("res://scripts/core/WorldState.gd")
const World2DScene = preload("res://scenes/World2D.tscn")
const World3DScene = preload("res://scenes/World3D.tscn")
const MOVEMENT_RULE_ID := "default_package.movement"
const MOVEMENT_STEP := 0.05
const POSITION_EPSILON := 0.0001
const SCREEN_SPEED_EPSILON := 0.5


func _initialize() -> void:
	var exit_code := 0
	var failure_message := ""

	var checks := [
		{"label": "2D", "scene": World2DScene, "action": "ui_up"},
		{"label": "3D", "scene": World3DScene, "action": "ui_up"}
	]

	for check_variant in checks:
		if exit_code != 0:
			break
		var check: Dictionary = check_variant
		var result := await _verify_scene(String(check.get("label", "world")), check.get("scene", null), String(check.get("action", "ui_right")))
		if String(result.get("status", "")) != "ok":
			exit_code = 1
			failure_message = String(result.get("message", "Unknown movement gating failure."))

	if exit_code != 0:
		push_error(failure_message)
	else:
		print("movement_provider_gating_smoke: ok")
	quit(exit_code)


func _verify_scene(label: String, scene_resource: PackedScene, movement_action: String) -> Dictionary:
	var world := root.get_node_or_null("WorldState")
	var owns_world := false
	if world == null:
		world = WorldStateScript.new()
		world.name = "WorldState"
		root.add_child(world)
		owns_world = true

	var scene := scene_resource.instantiate()
	root.add_child(scene)
	await process_frame
	await process_frame

	var failure_message := ""
	var player := scene.get_node_or_null("Player")
	if player == null:
		failure_message = "%s player node was not found." % label

	var initial_runtime_position := _origin_position(world)
	var initial_scene_position = _player_position(player)
	if failure_message.is_empty():
		_tick_scene_with_action(scene, movement_action, MOVEMENT_STEP)
		var moved_runtime_position := _origin_position(world)
		var moved_scene_position = _player_position(player)
		if _positions_match(initial_runtime_position, moved_runtime_position):
			failure_message = "%s runtime position did not move while movement rule was enabled." % label
		elif _positions_match(initial_scene_position, moved_scene_position):
			failure_message = "%s scene player did not reflect runtime-driven movement." % label
		elif label == "2D":
			if moved_runtime_position.z >= initial_runtime_position.z - POSITION_EPSILON:
				failure_message = "2D runtime movement moved in the wrong vertical direction for ui_up: initial=%s moved=%s" % [
					JSON.stringify(initial_runtime_position),
					JSON.stringify(moved_runtime_position)
				]
			elif moved_scene_position is Vector2 and initial_scene_position is Vector2:
				if (moved_scene_position as Vector2).y >= (initial_scene_position as Vector2).y - POSITION_EPSILON:
					failure_message = "2D rendered movement moved in the wrong vertical direction for ui_up: initial=%s moved=%s" % [
						JSON.stringify(initial_scene_position),
						JSON.stringify(moved_scene_position)
					]
			else:
				failure_message = "2D player position was not a Vector2 during vertical direction check."
			if failure_message.is_empty():
				failure_message = _verify_2d_screen_speed_parity(world, scene, player, initial_runtime_position, initial_scene_position, moved_scene_position)

	var frozen_runtime_position := Vector3.ZERO
	var frozen_scene_position = null
	if failure_message.is_empty():
		var disable_result: Dictionary = world.set_rule_enabled(MOVEMENT_RULE_ID, false)
		if String(disable_result.get("status", "")) != "disabled":
			failure_message = "%s movement rule did not disable: %s" % [label, JSON.stringify(disable_result)]
		else:
			frozen_runtime_position = _origin_position(world)
			frozen_scene_position = _player_position(player)
			_tick_scene_with_action(scene, movement_action, MOVEMENT_STEP)
			if not _positions_match(frozen_runtime_position, _origin_position(world)):
				failure_message = "%s runtime position changed after movement rule disable." % label
			elif not _positions_match(frozen_scene_position, _player_position(player)):
				failure_message = "%s scene player moved after movement rule disable." % label

	if failure_message.is_empty():
		var enable_result: Dictionary = world.set_rule_enabled(MOVEMENT_RULE_ID, true)
		if String(enable_result.get("status", "")) != "enabled":
			failure_message = "%s movement rule did not re-enable: %s" % [label, JSON.stringify(enable_result)]
		else:
			var resumed_runtime_position := _origin_position(world)
			_tick_scene_with_action(scene, movement_action, MOVEMENT_STEP)
			if _positions_match(resumed_runtime_position, _origin_position(world)):
				failure_message = "%s runtime position did not resume after movement rule enable." % label

	if failure_message.is_empty():
		scene.set_overlay_active(true)
		var overlay_runtime_position := _origin_position(world)
		var overlay_scene_position = _player_position(player)
		_tick_scene_with_action(scene, movement_action, MOVEMENT_STEP)
		if not _positions_match(overlay_runtime_position, _origin_position(world)):
			failure_message = "%s overlay open should pause runtime-driven movement." % label
		elif not _positions_match(overlay_scene_position, _player_position(player)):
			failure_message = "%s overlay open should keep the rendered player stationary." % label
		scene.set_overlay_active(false)

	if failure_message.is_empty():
		var resumed_after_overlay := _origin_position(world)
		_tick_scene_with_action(scene, movement_action, MOVEMENT_STEP)
		if _positions_match(resumed_after_overlay, _origin_position(world)):
			failure_message = "%s overlay close did not restore runtime-driven movement." % label

	if is_instance_valid(scene):
		scene.queue_free()
	if owns_world and is_instance_valid(world):
		world.queue_free()
	await process_frame

	if failure_message.is_empty():
		return {"status": "ok"}
	return {"status": "error", "message": failure_message}


func _tick_scene_with_action(scene: Node, action_name: String, delta: float) -> void:
	Input.action_press(action_name)
	scene.call("_process", delta)
	Input.action_release(action_name)
	scene.call("_process", 0.0)


func _verify_2d_screen_speed_parity(world: Node, scene: Node, player: Node, initial_runtime_position: Vector3, initial_scene_position: Variant, moved_scene_position: Variant) -> String:
	if not (initial_scene_position is Vector2 and moved_scene_position is Vector2):
		return "2D player position was not a Vector2 during speed parity check."

	var vertical_distance := (moved_scene_position as Vector2).distance_to(initial_scene_position as Vector2)
	world.set_entity_position("origin_entity", {
		"x": initial_runtime_position.x,
		"y": initial_runtime_position.y,
		"z": initial_runtime_position.z
	})
	world.dispatch_input_event("input.move.intent", {
		"entity_id": "origin_entity",
		"movement_vector": {"x": 0.0, "y": 0.0, "z": 0.0},
		"world_mode": "two_d"
	})
	scene.call("_process", 0.0)
	var reset_scene_position: Variant = _player_position(player)
	if not (reset_scene_position is Vector2):
		return "2D player position was not a Vector2 after reset during speed parity check."

	_tick_scene_with_action(scene, "ui_right", MOVEMENT_STEP)
	var moved_right_scene_position: Variant = _player_position(player)
	if not (moved_right_scene_position is Vector2):
		return "2D player position was not a Vector2 after horizontal movement during speed parity check."

	var horizontal_distance := (moved_right_scene_position as Vector2).distance_to(reset_scene_position as Vector2)
	if abs(horizontal_distance - vertical_distance) > SCREEN_SPEED_EPSILON:
		return "2D screen movement speed was not symmetric: vertical=%.3f horizontal=%.3f" % [vertical_distance, horizontal_distance]
	return ""


func _origin_position(world: Node) -> Vector3:
	var snapshot: Dictionary = world.get_world_snapshot()
	var entity: Dictionary = snapshot.get("entities", {}).get("origin_entity", {})
	var position: Dictionary = entity.get("position", {})
	return Vector3(
		float(position.get("x", 0.0)),
		float(position.get("y", 0.0)),
		float(position.get("z", 0.0))
	)


func _player_position(player: Node) -> Variant:
	if player is Node3D:
		return (player as Node3D).global_position
	if player is Node2D:
		return (player as Node2D).global_position
	return null


func _positions_match(left: Variant, right: Variant) -> bool:
	if left is Vector3 and right is Vector3:
		return (left as Vector3).distance_to(right as Vector3) <= POSITION_EPSILON
	if left is Vector2 and right is Vector2:
		return (left as Vector2).distance_to(right as Vector2) <= POSITION_EPSILON
	return left == right
