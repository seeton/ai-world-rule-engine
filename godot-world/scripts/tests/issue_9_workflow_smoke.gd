extends SceneTree

const WorldStateScript = preload("res://scripts/core/WorldState.gd")

var _failures: Array[String] = []


func _initialize() -> void:
	var world_state = WorldStateScript.new()
	root.add_child(world_state)
	call_deferred("_run_smoke", world_state)


func _run_smoke(world_state: Node) -> void:
	_test_clone_candidate_review(world_state)
	_test_custom_draft_approval(world_state)
	_test_install_actions_trace(world_state)

	if _failures.is_empty():
		print("issue_9_workflow_smoke: ok")
		quit(0)
		return

	for failure in _failures:
		push_error(failure)
	quit(1)


func _test_clone_candidate_review(world_state: Node) -> void:
	var result: Dictionary = world_state.call("submit_player_task", "hunger food eat starvation")
	_expect(String(result.get("resolution", "")) == "clone_candidate", "Expected a clone_candidate result for a strong hunger query.")
	_expect(String(result.get("status", "")) == "proposal_ready", "Clone candidate should be proposal_ready.")

	var proposals: Array = result.get("proposals", [])
	_expect(not proposals.is_empty(), "Clone candidate result should expose at least one proposal.")
	if proposals.is_empty():
		return

	var proposal: Dictionary = proposals[0]
	var rule_package: Dictionary = proposal.get("rule_package", {})
	_expect(not rule_package.is_empty(), "Clone candidate proposal should include nested rule_package data.")
	_expect(String(rule_package.get("source_repo", "")).length() > 0, "Clone candidate should expose source_repo metadata.")
	_expect(String(rule_package.get("source_ref", "")).length() > 0, "Clone candidate should expose source_ref metadata.")

	var review: Dictionary = world_state.call("review_rule_package_proposal", rule_package)
	_expect(String(review.get("status", "")) == "ready_for_install", "Approved built-in package should review as ready_for_install.")
	_expect(review.get("compiled_runtime_patch", {}) is Dictionary, "Review should expose a compiled_runtime_patch.")


func _test_custom_draft_approval(world_state: Node) -> void:
	var result: Dictionary = world_state.call("submit_player_task", "invent a lantern ceremony mechanic")
	_expect(String(result.get("resolution", "")) == "draft_custom_rule_patch", "Expected a custom draft proposal for novel task text.")
	_expect(String(result.get("status", "")) == "needs_rule_patch", "Custom draft should require rule patch review.")

	var proposals: Array = result.get("proposals", [])
	_expect(not proposals.is_empty(), "Custom draft result should expose at least one proposal.")
	if proposals.is_empty():
		return

	var rule_package: Dictionary = proposals[0].get("rule_package", {})
	_expect(not rule_package.is_empty(), "Custom draft should include nested rule_package JSON.")
	if rule_package.is_empty():
		return

	var review: Dictionary = world_state.call("review_rule_package_proposal", rule_package)
	_expect(String(review.get("status", "")) == "needs_approval", "Fresh custom draft should require explicit approval.")

	var patch: Dictionary = rule_package.get("patch", {}).duplicate(true)
	patch["review_status"] = "approved"
	rule_package["patch"] = patch

	var install_result: Dictionary = world_state.call("create_rule_from_patch", rule_package)
	_expect(String(install_result.get("status", "")) == "installed", "Approved custom draft should install successfully.")
	_expect(String(install_result.get("install_source", "")) == "rule_package", "Custom install should remain traceable as a rule_package install.")
	_expect(String(install_result.get("package_id", "")).begins_with("draft.custom."), "Installed custom draft should keep its package_id.")
	_expect(install_result.get("compiled_runtime_patch", {}) is Dictionary, "Installed custom draft should include compiled runtime patch details.")


func _test_install_actions_trace(world_state: Node) -> void:
	var package_id := "draft.custom.install_actions_smoke"
	var rule_package := {
		"schema_version": "rule_package_v1",
		"package_id": package_id,
		"display_name": "Install Actions Smoke",
		"description": "Turns on preview_3d via declarative install actions.",
		"version": "0.1.0-draft",
		"author": "smoke-test",
		"source_repo": "local://smoke-tests",
		"source_ref": "issue-9",
		"forked_from": null,
		"suggested_pr_target": null,
		"tags": ["smoke", "install-actions"],
		"match_phrases": ["install actions smoke"],
		"community": {
			"likes": 0,
			"dislikes": 0,
			"alternative_package_ids": []
		},
		"patch": {
			"format": "rule_patch_v1",
			"review_status": "approved",
			"scope": "world",
			"target_tags": ["player"],
			"install_actions": [
				{
					"op": "merge_world_state",
					"path": "preview_3d",
					"value": {
						"enabled": true
					}
				}
			],
			"operations": []
		}
	}

	var review: Dictionary = world_state.call("review_rule_package_proposal", rule_package)
	var compiled_runtime_patch: Dictionary = review.get("compiled_runtime_patch", {})
	_expect(String(review.get("status", "")) == "ready_for_install", "Approved install_actions smoke package should review as ready_for_install.")
	_expect(Array(compiled_runtime_patch.get("install_actions", [])).size() == 1, "Compiled runtime patch should preserve declarative install_actions.")

	var install_result: Dictionary = world_state.call("create_rule_from_patch", rule_package)
	_expect(String(install_result.get("status", "")) == "installed", "Declarative install_actions smoke package should install successfully.")

	var snapshot: Dictionary = world_state.call("get_world_snapshot")
	var preview: Dictionary = snapshot.get("three_d_preview", {})
	_expect(bool(preview.get("enabled", false)), "Declarative install_actions should update the world snapshot state.")


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)
