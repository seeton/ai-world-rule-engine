extends SceneTree

const RuntimeRuleTreeViewScript = preload("res://scripts/ui/runtime_rule_tree_view.gd")


func _initialize() -> void:
	var exit_code := 0
	var failure_message := ""

	var tree := Tree.new()
	tree.columns = 2
	tree.hide_root = true
	root.add_child(tree)

	var rule_tree := {
		"roots": [{
			"rule_id": "demo.root",
			"name": "Demo Root",
			"concept": "foundation",
			"rule_type": "runtime_rule",
			"package_id": "demo.package",
			"package_display_name": "Demo Package",
			"provides_rule_kinds": ["world.foundation"],
			"resolved_parent_rule_ids": [],
			"child_rule_ids": ["demo.child"],
			"children": [{
				"rule_id": "demo.child",
				"name": "Demo Child",
				"concept": "hunger",
				"rule_type": "runtime_rule",
				"requires_rule_kinds": ["world.foundation"],
				"resolved_parent_rule_ids": ["demo.root"],
				"children": []
			}]
		}],
		"nodes_by_rule_id": {
			"demo.root": {
				"rule_id": "demo.root",
				"name": "Demo Root",
				"concept": "foundation",
				"rule_type": "runtime_rule",
				"package_id": "demo.package",
				"package_display_name": "Demo Package",
				"provides_rule_kinds": ["world.foundation"],
				"resolved_parent_rule_ids": [],
				"child_rule_ids": ["demo.child"]
			},
			"demo.child": {
				"rule_id": "demo.child",
				"name": "Demo Child",
				"concept": "hunger",
				"rule_type": "runtime_rule",
				"requires_rule_kinds": ["world.foundation"],
				"resolved_parent_rule_ids": ["demo.root"],
				"child_rule_ids": []
			}
		}
	}

	var displayed := RuntimeRuleTreeViewScript.populate(tree, rule_tree)
	if displayed != 2:
		exit_code = 1
		failure_message = "expected 2 displayed rules, got %d" % displayed
	else:
		var root_item := tree.get_root()
		if root_item == null or root_item.get_first_child() == null:
			exit_code = 1
			failure_message = "rule tree produced no root item"
		else:
			var rule_item := root_item.get_first_child()
			var tooltip := rule_item.get_tooltip_text(0)
			if tooltip.is_empty():
				exit_code = 1
				failure_message = "root rule tooltip was empty"
			elif tooltip.find("これは何？:") == -1 or tooltip.find("Demo Package") == -1 or tooltip.find("世界の土台") == -1:
				exit_code = 1
				failure_message = "root rule tooltip missing expected details: %s" % tooltip

	if exit_code != 0:
		push_error(failure_message)
	else:
		print("[smoke] runtime_rule_tree_view tooltip smoke test passed")
	quit(exit_code)
