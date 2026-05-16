extends SceneTree

# Smoke test for godot-world/docs/rule_composition_invariants.md (issue #86).
# Covers the runtime-observable guarantees of the world-order composition contract:
#   1. installing a package with multi-parent capability requirements produces a
#      valid prerequisite DAG (`resolved_parent_rule_ids` carries >1 entry)
#   2. snapshot `rule_tree.nodes_by_rule_id` lists each rule exactly once with
#      both `resolved_parent_rule_ids` and `child_rule_ids` so consumers cannot
#      mistake the DAG for a strict tree
#   3. `root_rule_ids` and each node's `child_rule_ids` are sorted and stable
#      across re-snapshots
#   4. a rule whose required capability kind has no provider is rejected at
#      install time with `missing_required_rule_kinds` listing the unmet kinds
#   5. a package whose `package_dependencies` references an unknown package is
#      rejected with a clear error message
#   6. multiple providers of the same capability kind are accepted as
#      alternative providers (not flagged as a conflict)

const WorldStateScript = preload("res://scripts/core/WorldState.gd")
const WorldOpDispatcherScript = preload("res://scripts/world_ops/dispatcher.gd")

const PEACEFUL_PACKAGE_ID := "builtin.peaceful_world_order"
const DEFAULT_PACKAGE_ID := "builtin.default_package"
const MULTI_PARENT_RULE_ID := "world_order.time"
const MULTI_PARENT_REQUIRED_KINDS := ["world-order.base", "world.base-time"]


func _initialize() -> void:
	var exit_code := 0
	var failure_message := ""

	var world: Node = WorldStateScript.new()
	root.add_child(world)

	# 1. Install the peaceful world order package; default_package installs
	# transitively as its declared dependency.
	var install_result: Dictionary = WorldOpDispatcherScript.dispatch(
		world,
		"InstallPackage",
		{"package_id": PEACEFUL_PACKAGE_ID},
		{}
	)
	if String(install_result.get("status", "")) != "ok":
		exit_code = 1
		failure_message = "InstallPackage(%s) failed: %s" % [
			PEACEFUL_PACKAGE_ID,
			JSON.stringify(install_result)
		]

	# 2. Multi-parent DAG: world_order.time consumes two capability kinds and
	# must resolve to two distinct parents from two providers.
	if exit_code == 0:
		var snapshot: Dictionary = world.get_world_snapshot()
		var rule_tree: Dictionary = snapshot.get("rule_tree", {})
		var nodes_by_rule_id: Dictionary = rule_tree.get("nodes_by_rule_id", {})
		var time_node_variant = nodes_by_rule_id.get(MULTI_PARENT_RULE_ID, null)
		if not (time_node_variant is Dictionary):
			exit_code = 1
			failure_message = "rule_tree.nodes_by_rule_id is missing %s" % MULTI_PARENT_RULE_ID
		else:
			var time_node: Dictionary = time_node_variant
			var parents: Array = time_node.get("resolved_parent_rule_ids", [])
			if parents.size() < 2:
				exit_code = 1
				failure_message = "%s expected multi-parent resolution, got %s" % [
					MULTI_PARENT_RULE_ID,
					JSON.stringify(parents)
				]
			else:
				var requires: Array = time_node.get("requires_rule_kinds", [])
				for required_kind in MULTI_PARENT_REQUIRED_KINDS:
					if not requires.has(required_kind):
						exit_code = 1
						failure_message = "%s missing required kind %s in requires_rule_kinds=%s" % [
							MULTI_PARENT_RULE_ID,
							required_kind,
							JSON.stringify(requires)
						]
						break

	# 3. nodes_by_rule_id must list every rule exactly once, even rules that the
	# nested `roots` rendering visits from multiple parents. The nested form
	# is a tree-friendly view; nodes_by_rule_id is the canonical DAG view.
	if exit_code == 0:
		var snapshot: Dictionary = world.get_world_snapshot()
		var rule_tree: Dictionary = snapshot.get("rule_tree", {})
		var nodes_by_rule_id: Dictionary = rule_tree.get("nodes_by_rule_id", {})
		var roots: Array = rule_tree.get("roots", [])
		var nested_ids: Dictionary = {}
		_collect_nested_rule_ids(roots, nested_ids)
		for rule_id in nodes_by_rule_id.keys():
			if not nested_ids.has(rule_id):
				exit_code = 1
				failure_message = "rule_tree.roots is missing rule %s present in nodes_by_rule_id" % rule_id
				break
		if exit_code == 0:
			# Every node carries DAG fields so consumers cannot infer a strict tree.
			for node_variant in nodes_by_rule_id.values():
				if not (node_variant is Dictionary):
					exit_code = 1
					failure_message = "nodes_by_rule_id contains non-dict entry"
					break
				var node: Dictionary = node_variant
				if not node.has("resolved_parent_rule_ids") or not node.has("child_rule_ids"):
					exit_code = 1
					failure_message = "node %s missing resolved_parent_rule_ids or child_rule_ids" % String(node.get("rule_id", "<unknown>"))
					break

	# 4. `root_rule_ids` is sorted; child_rule_ids on each node is sorted;
	# the order is stable across two consecutive snapshots of the same world.
	if exit_code == 0:
		var snapshot_a: Dictionary = world.get_world_snapshot()
		var snapshot_b: Dictionary = world.get_world_snapshot()
		var tree_a: Dictionary = snapshot_a.get("rule_tree", {})
		var tree_b: Dictionary = snapshot_b.get("rule_tree", {})
		var roots_a: Array = tree_a.get("root_rule_ids", [])
		var roots_b: Array = tree_b.get("root_rule_ids", [])
		if roots_a != _sorted_string_array(roots_a):
			exit_code = 1
			failure_message = "rule_tree.root_rule_ids is not sorted: %s" % JSON.stringify(roots_a)
		elif roots_a != roots_b:
			exit_code = 1
			failure_message = "rule_tree.root_rule_ids is not stable across snapshots: %s vs %s" % [
				JSON.stringify(roots_a),
				JSON.stringify(roots_b)
			]
		else:
			var nodes_a: Dictionary = tree_a.get("nodes_by_rule_id", {})
			var nodes_b: Dictionary = tree_b.get("nodes_by_rule_id", {})
			for rule_id in nodes_a.keys():
				var children_a: Array = nodes_a[rule_id].get("child_rule_ids", [])
				var children_b: Array = nodes_b.get(rule_id, {}).get("child_rule_ids", [])
				if children_a != _sorted_string_array(children_a):
					exit_code = 1
					failure_message = "%s.child_rule_ids is not sorted: %s" % [rule_id, JSON.stringify(children_a)]
					break
				if children_a != children_b:
					exit_code = 1
					failure_message = "%s.child_rule_ids is not stable across snapshots" % rule_id
					break

	# 5. Missing capability: registering a rule that requires a capability kind
	# that no installed rule provides is rejected at install time. The error
	# response must carry `missing_required_rule_kinds` listing every unmet
	# kind so #62 (and any future world-order author) can diagnose the failure.
	if exit_code == 0:
		var orphan_patch := {
			"id": "issue_86_smoke_orphan",
			"name": "Issue 86 Orphan Rule",
			"rule_type": "runtime_rule",
			"requires_rule_kinds": ["world-order.does_not_exist"],
			"provides_rule_kinds": ["world-order.does_not_exist.consumer"]
		}
		var orphan_result: Dictionary = world.create_rule_from_patch(orphan_patch)
		if String(orphan_result.get("status", "")) != "error":
			exit_code = 1
			failure_message = "orphan rule install was accepted: %s" % JSON.stringify(orphan_result)
		else:
			var missing: Array = orphan_result.get("missing_required_rule_kinds", [])
			if not missing.has("world-order.does_not_exist"):
				exit_code = 1
				failure_message = "orphan rule error did not list the missing kind: %s" % JSON.stringify(orphan_result)

	# 6. Package install rejects a `package_dependencies` entry that does not
	# resolve to a known package. The contract in §3 requires that bad
	# dependency graphs (missing dependencies and cycles) never reach the
	# applied state; this test covers the missing-dependency path because
	# constructing a cyclic dependency requires committing fixture packages,
	# which is out of scope for #86.
	if exit_code == 0:
		var bad_dependency_package := {
			"schema_version": "rule_package_v1",
			"package_id": "issue_86.bad_dependency",
			"display_name": "Issue 86 Bad Dependency",
			"description": "Synthetic package whose declared dependency does not exist.",
			"version": "0.0.1",
			"author": "issue-86-smoke",
			"source_repo": "",
			"source_ref": "",
			"package_dependencies": ["issue_86.does_not_exist"],
			"forked_from": null,
			"suggested_pr_target": null,
			"tags": [],
			"match_phrases": [],
			"community": {},
			"patch": {
				"operations": [
					{
						"op": "upsert_rule",
						"rule_id": "issue_86.bad_dependency.rule",
						"rule_type": "runtime_rule",
						"name": "Issue 86 Bad Dependency Rule",
						"requires_rule_kinds": [],
						"provides_rule_kinds": ["issue_86.bad_dependency.kind"]
					}
				]
			}
		}
		var bad_dependency_result: Dictionary = world.create_rule_from_patch(bad_dependency_package)
		if String(bad_dependency_result.get("status", "")) == "installed":
			exit_code = 1
			failure_message = "package with missing dependency was accepted: %s" % JSON.stringify(bad_dependency_result)
		else:
			var message := String(bad_dependency_result.get("message", ""))
			if message.find("dependency") == -1 and message.find("依存") == -1 and message.find("not be found") == -1:
				exit_code = 1
				failure_message = "package was rejected but the error did not name the dependency problem: %s" % JSON.stringify(bad_dependency_result)

	# 7. Multiple providers of the same capability kind are accepted as
	# alternative providers (not flagged as a conflict). The peaceful package
	# rule world_order.peaceful_foundation provides world-order.base. If we
	# register a second provider with a distinct id, the snapshot must keep
	# both rules active (neither blocked) and the consumer (world_order.time)
	# must still resolve to one of them.
	if exit_code == 0:
		var alt_provider_patch := {
			"id": "issue_86_smoke_alt_world_order_base",
			"name": "Issue 86 Alternative world-order.base Provider",
			"rule_type": "runtime_rule",
			"requires_rule_kinds": [],
			"provides_rule_kinds": ["world-order.base"]
		}
		var alt_result: Dictionary = world.create_rule_from_patch(alt_provider_patch)
		if String(alt_result.get("status", "")) != "installed":
			exit_code = 1
			failure_message = "alternative provider install failed: %s" % JSON.stringify(alt_result)
		else:
			var snapshot: Dictionary = world.get_world_snapshot()
			var dependency_status: Dictionary = snapshot.get("rule_dependency_status", {})
			var blocked_ids: Array = dependency_status.get("blocked_rule_ids", [])
			if blocked_ids.has("world_order.peaceful_foundation") or blocked_ids.has("issue_86_smoke_alt_world_order_base"):
				exit_code = 1
				failure_message = "alternative providers should not block each other: %s" % JSON.stringify(blocked_ids)
			else:
				var rule_tree: Dictionary = snapshot.get("rule_tree", {})
				var nodes_by_rule_id: Dictionary = rule_tree.get("nodes_by_rule_id", {})
				var time_node: Dictionary = nodes_by_rule_id.get(MULTI_PARENT_RULE_ID, {})
				var parents: Array = time_node.get("resolved_parent_rule_ids", [])
				if parents.is_empty():
					exit_code = 1
					failure_message = "%s lost its resolved parents after adding an alternative provider" % MULTI_PARENT_RULE_ID

	if exit_code != 0:
		push_error("[smoke] rule_composition_invariants smoke test failed: %s" % failure_message)
	else:
		print("[smoke] rule_composition_invariants smoke test passed")
	quit(exit_code)


func _collect_nested_rule_ids(nodes: Array, into: Dictionary) -> void:
	for node_variant in nodes:
		if not (node_variant is Dictionary):
			continue
		var node: Dictionary = node_variant
		var rule_id := String(node.get("rule_id", ""))
		if rule_id.is_empty():
			continue
		into[rule_id] = true
		var children: Array = node.get("children", [])
		_collect_nested_rule_ids(children, into)


func _sorted_string_array(values: Array) -> Array:
	var copy: Array = values.duplicate(true)
	copy.sort()
	return copy
