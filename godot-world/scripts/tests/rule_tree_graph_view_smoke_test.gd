extends SceneTree

const WorldStateScript = preload("res://scripts/core/WorldState.gd")
const RuleTreeGraphViewScript = preload("res://scripts/ui/rule_tree_graph_view.gd")


func _initialize() -> void:
	var exit_code := 0
	var failure_message := ""

	var world_state: Node = WorldStateScript.new()
	root.add_child(world_state)
	world_state._ready()

	var seed_result: Dictionary = world_state.seed_demo_rule_tree()
	if int(seed_result.get("installed", 0)) == 0:
		exit_code = 1
		failure_message = "seed_demo_rule_tree installed nothing: %s" % JSON.stringify(seed_result)

	if exit_code == 0:
		var snapshot: Dictionary = world_state.get_world_snapshot()
		var rule_tree_variant = snapshot.get("rule_tree", {})
		if not (rule_tree_variant is Dictionary):
			exit_code = 1
			failure_message = "snapshot has no rule_tree dictionary"
		else:
			var rule_tree: Dictionary = rule_tree_variant
			var nodes_by_rule_id_variant = rule_tree.get("nodes_by_rule_id", {})
			var roots_variant = rule_tree.get("root_rule_ids", [])
			if not (nodes_by_rule_id_variant is Dictionary) or (nodes_by_rule_id_variant as Dictionary).is_empty():
				exit_code = 1
				failure_message = "nodes_by_rule_id was empty"
			elif not (roots_variant is Array) or (roots_variant as Array).is_empty():
				exit_code = 1
				failure_message = "root_rule_ids was empty"
			else:
				var view: Control = RuleTreeGraphViewScript.new()
				root.add_child(view)
				view.size = Vector2(1280.0, 720.0)
				var displayed: int = int(view.update_rule_tree(rule_tree))
				if displayed != (nodes_by_rule_id_variant as Dictionary).size():
					exit_code = 1
					failure_message = "displayed count %d does not match nodes %d" % [displayed, (nodes_by_rule_id_variant as Dictionary).size()]
				print("[smoke] displayed=%d roots=%d" % [displayed, (roots_variant as Array).size()])

	if exit_code != 0:
		push_error(failure_message)
	else:
		print("[smoke] rule_tree_graph_view smoke test passed")
	quit(exit_code)
