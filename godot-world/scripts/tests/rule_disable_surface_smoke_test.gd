extends SceneTree

const WorldStateScript = preload("res://scripts/core/WorldState.gd")
const World2DScene = preload("res://scenes/World2D.tscn")
const World3DScene = preload("res://scenes/World3D.tscn")
const FOUNDATION_RULE_ID := "default_package.foundation"


func _initialize() -> void:
	var exit_code := 0
	var failure_message := ""

	var checks := [
		{"label": "2D", "scene": World2DScene},
		{"label": "3D", "scene": World3DScene}
	]

	for check_variant in checks:
		if exit_code != 0:
			break
		var check: Dictionary = check_variant
		var result := await _verify_scene(String(check.get("label", "world")), check.get("scene", null))
		if String(result.get("status", "")) != "ok":
			exit_code = 1
			failure_message = String(result.get("message", "Unknown rule disable surface failure."))

	if exit_code != 0:
		push_error(failure_message)
	else:
		print("rule_disable_surface_smoke: ok")
	quit(exit_code)


func _verify_scene(label: String, scene_resource: PackedScene) -> Dictionary:
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
	var baseline_player: Node = scene.get_node_or_null("Player")
	var baseline_gm: Node = scene.get_node_or_null("GameMaster")
	var baseline_player_visible := _node_visible(baseline_player) if baseline_player != null else false
	var baseline_gm_visible := _node_visible(baseline_gm) if baseline_gm != null else false
	var baseline_ground_visible := false
	var baseline_sun_visible := false
	if label == "3D":
		var baseline_ground: Node = scene.get_node_or_null("Ground")
		var baseline_sun: Node = scene.get_node_or_null("Sun")
		baseline_ground_visible = _node_visible(baseline_ground) if baseline_ground != null else false
		baseline_sun_visible = _node_visible(baseline_sun) if baseline_sun != null else false
	var disable_result: Dictionary = world.set_rule_enabled(FOUNDATION_RULE_ID, false)
	if String(disable_result.get("status", "")) != "disabled":
		failure_message = "%s foundation rule did not disable: %s" % [label, JSON.stringify(disable_result)]
	else:
		scene.call("_process", 0.05)
		await process_frame
		var snapshot: Dictionary = world.get_world_snapshot()
		scene.call("_apply_snapshot", snapshot)
		await process_frame
		var rule_tree: Dictionary = snapshot.get("rule_tree", {})
		var root_rule_ids: Array = rule_tree.get("root_rule_ids", [])
		var nodes_by_rule_id: Dictionary = rule_tree.get("nodes_by_rule_id", {})
		var entities_variant: Variant = snapshot.get("entities", {})
		var entities: Dictionary = entities_variant if entities_variant is Dictionary else {}
		if not entities.is_empty():
			failure_message = "%s snapshot still exposed entities after foundation disable: %s" % [label, JSON.stringify(snapshot)]
		elif String(snapshot.get("world_name", "")).strip_edges() != "":
			failure_message = "%s snapshot still exposed world_name after foundation disable: %s" % [label, JSON.stringify(snapshot)]
		elif String(snapshot.get("world_mode", "")).strip_edges() != "":
			failure_message = "%s snapshot still exposed world_mode after foundation disable: %s" % [label, JSON.stringify(snapshot)]
		else:
			var world_clock_variant: Variant = snapshot.get("world_clock", {})
			if world_clock_variant is Dictionary and not (world_clock_variant as Dictionary).is_empty():
				failure_message = "%s snapshot still exposed world_clock after foundation disable: %s" % [label, JSON.stringify(snapshot)]
			else:
				var preview_variant: Variant = snapshot.get("three_d_preview", {})
				var preview: Dictionary = preview_variant if preview_variant is Dictionary else {}
				var renderables_variant: Variant = preview.get("renderables", [])
				var renderables: Array = renderables_variant if renderables_variant is Array else []
				if not renderables.is_empty():
					failure_message = "%s snapshot still exposed renderables after foundation disable: %s" % [label, JSON.stringify(snapshot)]
				elif not root_rule_ids.has(FOUNDATION_RULE_ID):
					failure_message = "%s rule tree lost the foundation root after disable: %s" % [label, JSON.stringify(rule_tree)]
				else:
					var existence_node: Dictionary = nodes_by_rule_id.get("default_package.existence", {})
					if existence_node.is_empty():
						failure_message = "%s rule tree lost default_package.existence after disable: %s" % [label, JSON.stringify(rule_tree)]
					elif root_rule_ids.has("default_package.existence"):
						failure_message = "%s rule tree flattened default_package.existence into a root after disable: %s" % [label, JSON.stringify(rule_tree)]
					elif not Array(existence_node.get("resolved_parent_rule_ids", [])).has(FOUNDATION_RULE_ID):
						failure_message = "%s rule tree removed the structural parent link from existence to foundation after disable: %s" % [label, JSON.stringify(rule_tree)]
					elif not Array(existence_node.get("missing_required_rule_kinds", [])).has("world.foundation"):
						failure_message = "%s rule tree did not keep existence marked unresolved after disable: %s" % [label, JSON.stringify(rule_tree)]

	if failure_message.is_empty():
		var player: Node = scene.get_node_or_null("Player")
		var gm: Node = scene.get_node_or_null("GameMaster")
		if player == null or gm == null:
			failure_message = "%s scene player/GM node was not found." % label
		else:
			var player_visible := _node_visible(player)
			var gm_visible := _node_visible(gm)
			if player_visible or gm_visible:
				failure_message = "%s scene still rendered player or GM after foundation disable (player_visible=%s gm_visible=%s player_render_api=%s gm_render_api=%s)." % [label, str(player_visible), str(gm_visible), str(player.has_method("set_render_enabled")), str(gm.has_method("set_render_enabled"))]
			elif label == "3D":
				var ground: Node = scene.get_node_or_null("Ground")
				var sun: Node = scene.get_node_or_null("Sun")
				if ground == null or sun == null:
					failure_message = "%s scene ground/sun node was not found." % label
				elif _node_visible(ground) or _node_visible(sun):
					failure_message = "%s scene still rendered ground or sun after foundation disable." % label

	if failure_message.is_empty():
		var enable_result: Dictionary = world.set_rule_enabled(FOUNDATION_RULE_ID, true)
		if String(enable_result.get("status", "")) != "enabled":
			failure_message = "%s foundation rule did not re-enable: %s" % [label, JSON.stringify(enable_result)]
		else:
			scene.call("_process", 0.05)
			await process_frame
			var restored_snapshot: Dictionary = world.get_world_snapshot()
			scene.call("_apply_snapshot", restored_snapshot)
			await process_frame
			var restored_rule_tree: Dictionary = restored_snapshot.get("rule_tree", {})
			var restored_root_rule_ids: Array = restored_rule_tree.get("root_rule_ids", [])
			var restored_nodes_by_rule_id: Dictionary = restored_rule_tree.get("nodes_by_rule_id", {})
			var restored_entities_variant: Variant = restored_snapshot.get("entities", {})
			var restored_entities: Dictionary = restored_entities_variant if restored_entities_variant is Dictionary else {}
			if restored_entities.is_empty():
				failure_message = "%s snapshot did not restore entities after foundation re-enable: %s" % [label, JSON.stringify(restored_snapshot)]
			elif String(restored_snapshot.get("world_name", "")).strip_edges().is_empty():
				failure_message = "%s snapshot did not restore world_name after foundation re-enable: %s" % [label, JSON.stringify(restored_snapshot)]
			elif String(restored_snapshot.get("world_mode", "")).strip_edges().is_empty():
				failure_message = "%s snapshot did not restore world_mode after foundation re-enable: %s" % [label, JSON.stringify(restored_snapshot)]
			else:
				var restored_player: Node = scene.get_node_or_null("Player")
				var restored_gm: Node = scene.get_node_or_null("GameMaster")
				if restored_player == null or restored_gm == null:
					failure_message = "%s scene player/GM node was not found after re-enable." % label
				elif _node_visible(restored_player) != baseline_player_visible or _node_visible(restored_gm) != baseline_gm_visible:
					failure_message = "%s scene did not restore player/GM baseline visibility after foundation re-enable." % label
				elif label == "3D":
					var restored_ground: Node = scene.get_node_or_null("Ground")
					var restored_sun: Node = scene.get_node_or_null("Sun")
					if restored_ground == null or restored_sun == null:
						failure_message = "%s scene ground/sun node was not found after re-enable." % label
					elif _node_visible(restored_ground) != baseline_ground_visible or _node_visible(restored_sun) != baseline_sun_visible:
						failure_message = "%s scene did not restore ground/sun baseline visibility after foundation re-enable." % label
				if failure_message.is_empty():
					var restored_existence_node: Dictionary = restored_nodes_by_rule_id.get("default_package.existence", {})
					if not restored_root_rule_ids.has(FOUNDATION_RULE_ID):
						failure_message = "%s rule tree lost foundation root after re-enable: %s" % [label, JSON.stringify(restored_rule_tree)]
					elif restored_existence_node.is_empty():
						failure_message = "%s rule tree lost default_package.existence after re-enable: %s" % [label, JSON.stringify(restored_rule_tree)]
					elif restored_root_rule_ids.has("default_package.existence"):
						failure_message = "%s rule tree kept default_package.existence flattened after re-enable: %s" % [label, JSON.stringify(restored_rule_tree)]
					elif not Array(restored_existence_node.get("resolved_parent_rule_ids", [])).has(FOUNDATION_RULE_ID):
						failure_message = "%s rule tree did not restore the structural parent link from existence to foundation after re-enable: %s" % [label, JSON.stringify(restored_rule_tree)]
					elif not Array(restored_existence_node.get("missing_required_rule_kinds", [])).is_empty():
						failure_message = "%s rule tree kept existence unresolved after re-enable: %s" % [label, JSON.stringify(restored_rule_tree)]

	if is_instance_valid(scene):
		scene.queue_free()
	if owns_world and is_instance_valid(world):
		world.queue_free()
	await process_frame

	if failure_message.is_empty():
		return {"status": "ok"}
	return {"status": "error", "message": failure_message}


func _node_visible(node: Node) -> bool:
	if node.has_method("is_render_enabled"):
		return bool(node.call("is_render_enabled"))
	if node is CanvasItem:
		return (node as CanvasItem).visible
	if node is Node3D:
		return (node as Node3D).visible
	return false
