extends SceneTree

const WorldStateScript = preload("res://scripts/core/WorldState.gd")
const RuleTreeGraphViewScript = preload("res://scripts/ui/rule_tree_graph_view.gd")
const FOUNDATION_RULE_ID := "default_package.foundation"
const EXISTENCE_RULE_ID := "default_package.existence"
const EXPECTED_UNRESOLVED_NAME_COLOR := Color(1.0, 0.73, 0.70, 1.0)
const EXPECTED_DISABLED_STATUS_TEXT := "無効化中/未適用"


func _initialize() -> void:
	var exit_code := 0
	var failure_message := ""

	var world_state: Node = WorldStateScript.new()
	root.add_child(world_state)

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
				var view := RuleTreeGraphViewScript.new()
				root.add_child(view)
				view.size = Vector2(1280.0, 720.0)
				var displayed: int = int(view.update_rule_tree(rule_tree))
				if displayed != (nodes_by_rule_id_variant as Dictionary).size():
					exit_code = 1
					failure_message = "displayed count %d does not match nodes %d" % [displayed, (nodes_by_rule_id_variant as Dictionary).size()]
				else:
					var disable_result: Dictionary = world_state.set_rule_enabled(FOUNDATION_RULE_ID, false)
					if String(disable_result.get("status", "")) != "disabled":
						exit_code = 1
						failure_message = "disable foundation failed: %s" % JSON.stringify(disable_result)
					else:
						var disabled_snapshot: Dictionary = world_state.get_world_snapshot()
						var disabled_rule_tree_variant: Variant = disabled_snapshot.get("rule_tree", {})
						if not (disabled_rule_tree_variant is Dictionary):
							exit_code = 1
							failure_message = "disabled snapshot has no rule_tree dictionary"
						else:
							var disabled_rule_tree: Dictionary = disabled_rule_tree_variant
							var disabled_displayed: int = int(view.update_rule_tree(disabled_rule_tree))
							var disabled_nodes_by_rule_id: Dictionary = disabled_rule_tree.get("nodes_by_rule_id", {})
							if disabled_displayed != disabled_nodes_by_rule_id.size():
								exit_code = 1
								failure_message = "disabled displayed count %d does not match nodes %d" % [disabled_displayed, disabled_nodes_by_rule_id.size()]
							else:
								var foundation_card := view.get_node_card(FOUNDATION_RULE_ID)
								var existence_card := view.get_node_card(EXISTENCE_RULE_ID)
								if foundation_card == null or existence_card == null:
									exit_code = 1
									failure_message = "view did not build cards for disabled rule tree"
								else:
									var foundation_status_label := foundation_card.get_node_or_null("Content/StatusLabel") as Label
									var foundation_name_label := foundation_card.get_node_or_null("Content/NameLabel") as Label
									var status_label := existence_card.get_node_or_null("Content/StatusLabel") as Label
									var name_label := existence_card.get_node_or_null("Content/NameLabel") as Label
									if foundation_status_label == null or foundation_name_label == null or status_label == null or name_label == null:
										exit_code = 1
										failure_message = "view did not expose status/name labels for disabled rule tree"
									elif foundation_status_label.text != EXPECTED_DISABLED_STATUS_TEXT:
										exit_code = 1
										failure_message = "unexpected disabled status text: %s" % foundation_status_label.text
									elif not _colors_match(foundation_name_label.get_theme_color("font_color"), EXPECTED_UNRESOLVED_NAME_COLOR):
										exit_code = 1
										failure_message = "disabled parent name color was not highlighted red enough: %s" % str(foundation_name_label.get_theme_color("font_color"))
									elif status_label.text != "親未解決/未適用":
										exit_code = 1
										failure_message = "unexpected unresolved status text: %s" % status_label.text
									elif not _colors_match(name_label.get_theme_color("font_color"), EXPECTED_UNRESOLVED_NAME_COLOR):
										exit_code = 1
										failure_message = "unresolved node name color was not highlighted red enough: %s" % str(name_label.get_theme_color("font_color"))
				print("[smoke] displayed=%d roots=%d" % [displayed, (roots_variant as Array).size()])

	if exit_code != 0:
		push_error(failure_message)
	else:
		print("[smoke] rule_tree_graph_view smoke test passed")
	quit(exit_code)


func _colors_match(left: Color, right: Color) -> bool:
	return abs(left.r - right.r) < 0.001 \
		and abs(left.g - right.g) < 0.001 \
		and abs(left.b - right.b) < 0.001 \
		and abs(left.a - right.a) < 0.001
