extends RefCounted
class_name SimulationRuntime

const RuntimeRulePatchCompilerScript = preload("res://scripts/integration/runtime_rule_patch_compiler.gd")
const DEFAULT_FIXED_STEP := 0.25
const WORLD_SNAPSHOT_TYPE := "godot_world_state_snapshot"
const WORLD_SNAPSHOT_VERSION := 1
const DEFAULT_THREE_D_CAMERA := {
	"position": {"x": 6.6, "y": 6.0, "z": -7.4},
	"look_at": {"x": 0.0, "y": 1.4, "z": 0.4},
	"fov_degrees": 60.0
}
const DEFAULT_THREE_D_LIGHTING := {
	"enabled": true,
	"shadows_enabled": true,
	"light_rotation_degrees": {"x": -58.0, "y": 36.0, "z": 0.0},
	"color": "#fff1cf",
	"intensity": 1.4
}
const DEFAULT_THREE_D_GRAVITY := {
	"enabled": false,
	"floor_y": 0.0,
	"acceleration": 9.8
}
const CHARACTER_ARCHETYPE_HINTS := ["actor", "character", "gm", "npc", "origin", "person", "villager"]
const CHARACTER_TAG_HINTS := ["agent", "character", "gm", "mortal", "npc", "person", "villager"]
const GM_ARCHETYPE_HINTS := ["director", "game_master", "gm"]
const GM_TAG_HINTS := ["director", "game_master", "gm"]

var fixed_step_seconds: float = DEFAULT_FIXED_STEP
var _accumulator_seconds: float = 0.0
var _world_state: Dictionary = {}
var _template_index: Dictionary = {}
var _clone_sequence: int = 0


func _init(rule_templates: Array = []) -> void:
	for template in rule_templates:
		var template_id := String(template.get("id", ""))
		if not template_id.is_empty():
			_template_index[template_id] = template.duplicate(true)

	_world_state = _build_null_world()


func record_player_task(task_result: Dictionary) -> void:
	var history: Array = _world_state.get("player_task_history", [])
	history.append(task_result.duplicate(true))
	_world_state["player_task_history"] = history
	_append_event("player_task_submitted", "プレイヤーがルール候補用のタスクを送信しました。", {"task": task_result.get("task_text", "")})


func begin_poc4_proposal_execution(request_text: String, codex_details: Dictionary = {}) -> Dictionary:
	var poc4_state := _get_poc4_state()
	poc4_state["last_request_text"] = request_text
	poc4_state["pending_proposal"] = {}
	poc4_state["proposal_summary"] = {}
	poc4_state["issue_preview"] = {}
	poc4_state["review"] = _build_default_poc4_review()
	poc4_state["apply_result"] = {}
	poc4_state["last_error"] = {}
	poc4_state["execution"] = {
		"status": "running",
		"phase": "proposal_generation",
		"message": "Codex proposal generation is running.",
		"request_text": request_text
	}
	poc4_state["codex"] = _merge_dictionaries(_duplicate_dictionary(poc4_state.get("codex", {})), codex_details)
	_append_event("poc4_proposal_started", "PoC4 backend が Codex proposal generation を開始しました。", {"task": request_text})
	_append_poc4_history(poc4_state, {
		"type": "proposal_started",
		"request_text": request_text
	})
	_world_state["poc4"] = poc4_state
	return get_pending_poc4_proposal_state()


func record_poc4_proposal(request_text: String, proposal_result: Dictionary) -> void:
	var poc4_state := _get_poc4_state()
	poc4_state["last_request_text"] = request_text
	poc4_state["apply_result"] = {}
	poc4_state["codex"] = _merge_dictionaries(
		_duplicate_dictionary(poc4_state.get("codex", {})),
		_extract_poc4_codex(proposal_result)
	)

	if String(proposal_result.get("status", "")) == "proposal_ready":
		poc4_state["pending_proposal"] = _duplicate_dictionary(proposal_result.get("proposal", {}))
		poc4_state["proposal_summary"] = _duplicate_dictionary(proposal_result.get("summary", {}))
		poc4_state["issue_preview"] = _duplicate_dictionary(proposal_result.get("issue_preview", {}))
		poc4_state["review"] = {
			"required": true,
			"acknowledged": false,
			"status": "pending",
			"metadata": {}
		}
		poc4_state["execution"] = {
			"status": "proposal_ready",
			"phase": "review_ready",
			"message": "PoC4 proposal is ready for review.",
			"request_text": request_text
		}
		poc4_state["last_error"] = {}
		_append_event("poc4_proposal_ready", "PoC4 backend が proposal preview を生成しました。", {
			"package_id": proposal_result.get("summary", {}).get("package_id", ""),
			"operation_count": proposal_result.get("summary", {}).get("operation_count", 0)
		})
		_append_poc4_history(poc4_state, {
			"type": "proposal_ready",
			"request_text": request_text,
			"package_id": proposal_result.get("summary", {}).get("package_id", ""),
			"review_status": proposal_result.get("summary", {}).get("review_status", "needs_design_review")
		})
	else:
		poc4_state["pending_proposal"] = {}
		poc4_state["proposal_summary"] = {}
		poc4_state["issue_preview"] = {}
		poc4_state["review"] = _build_default_poc4_review()
		poc4_state["execution"] = {
			"status": "error",
			"phase": "proposal_failed",
			"message": String(proposal_result.get("message", "PoC4 backend error.")),
			"request_text": request_text
		}
		poc4_state["last_error"] = _extract_poc4_error(proposal_result)
		_append_event("poc4_proposal_error", "PoC4 backend が proposal を生成できませんでした。", poc4_state.get("last_error", {}))
		_append_poc4_history(poc4_state, {
			"type": "proposal_error",
			"request_text": request_text,
			"error_code": poc4_state.get("last_error", {}).get("error_code", "unknown")
		})

	_world_state["poc4"] = poc4_state


func update_poc4_review(reviewed: bool, metadata: Dictionary = {}) -> Dictionary:
	var poc4_state := _get_poc4_state()
	var pending_proposal: Dictionary = poc4_state.get("pending_proposal", {})
	if pending_proposal.is_empty():
		return {
			"status": "error",
			"error_code": "no_pending_proposal",
			"message": "確認対象の pending proposal がありません。"
		}

	var review := _build_default_poc4_review()
	review["required"] = true
	review["acknowledged"] = reviewed
	review["status"] = "acknowledged" if reviewed else "pending"
	review["metadata"] = metadata.duplicate(true)
	poc4_state["review"] = review
	poc4_state["apply_result"] = {
		"status": "ready_to_apply" if reviewed else "awaiting_review",
		"message": "内容確認が完了したので、proposal をゲームへ適用できます。" if reviewed else "内容確認待ちのため、proposal 適用は保留です。"
	}
	_append_event("poc4_review_updated", "PoC4 proposal の確認状態を更新しました。", {"acknowledged": reviewed})
	_append_poc4_history(poc4_state, {
		"type": "review_updated",
		"acknowledged": reviewed
	})
	_world_state["poc4"] = poc4_state
	return {
		"status": "review_updated",
		"review": review.duplicate(true),
		"pending_proposal": pending_proposal.duplicate(true),
		"apply_result": poc4_state.get("apply_result", {}).duplicate(true)
	}


func get_pending_poc4_proposal_state() -> Dictionary:
	var poc4_state := _get_poc4_state()
	var review := _duplicate_dictionary(poc4_state.get("review", {}))
	return {
		"proposal": _duplicate_dictionary(poc4_state.get("pending_proposal", {})),
		"summary": _duplicate_dictionary(poc4_state.get("proposal_summary", {})),
		"issue_preview": _duplicate_dictionary(poc4_state.get("issue_preview", {})),
		"review": review,
		"apply_result": _duplicate_dictionary(poc4_state.get("apply_result", {})),
		"last_error": _duplicate_dictionary(poc4_state.get("last_error", {})),
		"execution": _duplicate_dictionary(poc4_state.get("execution", {})),
		"codex": _duplicate_dictionary(poc4_state.get("codex", {})),
		"last_request_text": poc4_state.get("last_request_text", ""),
		"history": Array(poc4_state.get("history", [])).duplicate(true)
	}


func apply_pending_poc4_proposal() -> Dictionary:
	var poc4_state := _get_poc4_state()
	var proposal := _duplicate_dictionary(poc4_state.get("pending_proposal", {}))
	if proposal.is_empty():
		var missing_result := {
			"status": "error",
			"error_code": "no_pending_proposal",
			"message": "適用する pending proposal がありません。"
		}
		record_poc4_apply_result(missing_result)
		return missing_result

	var review := _duplicate_dictionary(poc4_state.get("review", {}))
	if bool(review.get("required", false)) and not bool(review.get("acknowledged", review.get("granted", false))):
		var review_required_result := {
			"status": "error",
			"error_code": "proposal_review_required",
			"message": "先に proposal 内容を確認してください。",
			"review": review.duplicate(true)
		}
		record_poc4_apply_result(review_required_result)
		return review_required_result

	var compiler = RuntimeRulePatchCompilerScript.new()
	var compile_result: Dictionary = compiler.compile_package(_build_runtime_rule_package_from_proposal(proposal))
	if String(compile_result.get("status", "")) != "compiled":
		var compile_error := {
			"status": "error",
			"error_code": "proposal_compile_failed",
			"message": String(compile_result.get("message", "PoC4 proposal を runtime patch に変換できませんでした。")),
			"details": _duplicate_dictionary(compile_result),
			"package_id": proposal.get("package_id", ""),
			"proposal_title": proposal.get("proposal_title", "")
		}
		record_poc4_apply_result(compile_error)
		return compile_error

	var runtime_patch := _duplicate_dictionary(compile_result.get("runtime_patch", {}))
	if runtime_patch.is_empty():
		var missing_patch_error := {
			"status": "error",
			"error_code": "runtime_patch_missing",
			"message": "runtime patch を生成できませんでした。",
			"package_id": proposal.get("package_id", ""),
			"proposal_title": proposal.get("proposal_title", "")
		}
		record_poc4_apply_result(missing_patch_error)
		return missing_patch_error

	var install_actions := _build_proposal_install_actions(proposal)
	if not install_actions.is_empty():
		runtime_patch["install_actions"] = install_actions

	var operations: Array = Array(proposal.get("patch", {}).get("operations", []))
	var metadata := _duplicate_dictionary(runtime_patch.get("metadata", {}))
	metadata["proposal_title"] = proposal.get("proposal_title", "")
	metadata["player_request_summary"] = proposal.get("player_request_summary", "")
	metadata["operation_count"] = operations.size()
	metadata["operation_types"] = _extract_operation_types(operations)
	metadata["review_status"] = proposal.get("review_status", "")
	metadata["validation_status"] = proposal.get("validation", {}).get("status", "")
	metadata["touched_surfaces"] = _duplicate_dictionary(proposal.get("touched_surfaces", {}))
	metadata["deferred_operations"] = Array(compile_result.get("deferred_operations", [])).duplicate(true)
	runtime_patch["metadata"] = metadata

	var install_result: Dictionary = create_rule_from_patch(runtime_patch)
	if String(install_result.get("status", "")) != "installed":
		var apply_error := {
			"status": "error",
			"error_code": "proposal_apply_failed",
			"message": String(install_result.get("message", "PoC4 proposal をゲームへ適用できませんでした。")),
			"details": {
				"install_result": install_result.duplicate(true),
				"runtime_patch_id": runtime_patch.get("id", "")
			},
			"package_id": proposal.get("package_id", ""),
			"proposal_title": proposal.get("proposal_title", "")
		}
		record_poc4_apply_result(apply_error)
		return apply_error

	var deferred_operations: Array = Array(compile_result.get("deferred_operations", [])).duplicate(true)
	var applied_operations: Array = _filter_applied_operations(operations, deferred_operations)
	var runtime_rule: Dictionary = _duplicate_dictionary(install_result.get("rule", {}))
	var apply_result := {
		"status": "applied_with_warnings" if not deferred_operations.is_empty() else "applied",
		"message": "PoC4 proposal をゲームへ適用しました。" if deferred_operations.is_empty() else "PoC4 proposal をゲームへ適用しました。未対応の操作は runtime metadata として保存しています。",
		"package_id": proposal.get("package_id", ""),
		"proposal_title": proposal.get("proposal_title", ""),
		"runtime_rule_id": runtime_rule.get("id", runtime_patch.get("id", "")),
		"runtime_rule": runtime_rule,
		"review": review.duplicate(true),
		"total_operation_count": operations.size(),
		"total_operation_types": _extract_operation_types(operations),
		"applied_operation_count": applied_operations.size(),
		"applied_operation_types": _extract_operation_types(applied_operations),
		"deferred_operation_count": deferred_operations.size(),
		"deferred_operations": deferred_operations,
		"touched_surfaces": _duplicate_dictionary(proposal.get("touched_surfaces", {}))
	}
	record_poc4_apply_result(apply_result)
	return apply_result


func record_poc4_apply_result(apply_result: Dictionary) -> void:
	var poc4_state := _get_poc4_state()
	poc4_state["apply_result"] = apply_result.duplicate(true)
	if String(apply_result.get("status", "")) in ["applied", "applied_with_warnings"]:
		poc4_state["last_error"] = {}
		poc4_state["execution"] = {
			"status": String(apply_result.get("status", "applied")),
			"phase": "proposal_applied",
			"message": String(apply_result.get("message", "")),
			"request_text": String(poc4_state.get("last_request_text", ""))
		}
		_append_event("poc4_proposal_applied", "PoC4 proposal をゲームへ適用しました。", {
			"package_id": apply_result.get("package_id", ""),
			"runtime_rule_id": apply_result.get("runtime_rule_id", ""),
			"deferred_operation_count": apply_result.get("deferred_operation_count", 0)
		})
		_append_poc4_history(poc4_state, {
			"type": "proposal_applied",
			"package_id": apply_result.get("package_id", ""),
			"runtime_rule_id": apply_result.get("runtime_rule_id", ""),
			"status": apply_result.get("status", "applied")
		})
	elif String(apply_result.get("status", "")) == "error":
		poc4_state["last_error"] = _extract_poc4_error(apply_result)
		poc4_state["execution"] = {
			"status": "error",
			"phase": "proposal_apply_failed",
			"message": String(apply_result.get("message", "PoC4 apply error.")),
			"request_text": String(poc4_state.get("last_request_text", ""))
		}
		_append_event("poc4_apply_error", "PoC4 proposal の適用に失敗しました。", poc4_state.get("last_error", {}))
		_append_poc4_history(poc4_state, {
			"type": "proposal_apply_error",
			"error_code": apply_result.get("error_code", "unknown")
		})
	_world_state["poc4"] = poc4_state


func get_last_poc4_apply_result() -> Dictionary:
	return _duplicate_dictionary(_get_poc4_state().get("apply_result", {}))


func create_rule_from_patch(rule_patch: Dictionary) -> Dictionary:
	var normalized_rule := _normalize_rule_patch(rule_patch)
	if normalized_rule.is_empty():
		return {
			"status": "error",
			"message": "ルールパッチが空、または不正です。"
		}

	return _install_normalized_rule(normalized_rule)


func clone_rule(rule_id: String) -> Dictionary:
	var installed_rules: Dictionary = _world_state.get("installed_rules", {})
	if not installed_rules.has(rule_id):
		if _template_index.has(rule_id):
			var template_rule: Dictionary = _template_index[rule_id].get("rule_patch", {}).duplicate(true)
			template_rule["id"] = _make_unique_rule_id(String(template_rule.get("id", "rule_%s" % rule_id)))
			template_rule["name"] = "%s (Installed)" % String(_template_index[rule_id].get("name", rule_id))
			return create_rule_from_patch(template_rule)

		return {
			"status": "error",
			"message": "ルール '%s' は未導入で、対応するテンプレートもありません。" % rule_id
		}

	var cloned_rule: Dictionary = installed_rules[rule_id].duplicate(true)
	var clone_id := _make_unique_rule_id("%s_clone" % rule_id)
	cloned_rule["id"] = clone_id
	cloned_rule["name"] = "%s (Clone)" % String(cloned_rule.get("name", rule_id))
	cloned_rule["source_rule_id"] = rule_id

	var install_result := create_rule_from_patch(cloned_rule)
	if String(install_result.get("status", "")) == "installed":
		install_result["status"] = "cloned"
		install_result["source_rule_id"] = rule_id
		_append_event("rule_cloned", "ルール '%s' を '%s' として複製しました。" % [rule_id, clone_id], {"rule_id": rule_id, "clone_id": clone_id})
	return install_result


func get_snapshot() -> Dictionary:
	var snapshot := _world_state.duplicate(true)
	var installed_rules_by_id: Dictionary = snapshot.get("installed_rules", {}).duplicate(true)
	var installed_rule_ids: Array = installed_rules_by_id.keys()
	installed_rule_ids.sort()
	var installed_rules: Array = []
	for rule_id in installed_rule_ids:
		installed_rules.append(installed_rules_by_id[rule_id].duplicate(true))

	var template_ids: Array = _template_index.keys()
	template_ids.sort()
	var installed_package_summary := _build_installed_rule_packages(installed_rules_by_id)

	snapshot["accumulator_seconds"] = _accumulator_seconds
	snapshot["available_template_ids"] = template_ids
	snapshot["installed_rules_by_id"] = installed_rules_by_id
	snapshot["installed_rules"] = installed_rules
	snapshot["installed_rule_packages_by_id"] = installed_package_summary.get("packages_by_id", {}).duplicate(true)
	snapshot["installed_rule_packages"] = installed_package_summary.get("packages", []).duplicate(true)
	snapshot["world_mode"] = "three_d" if bool(_world_state.get("preview_3d", {}).get("enabled", false)) else "two_d"
	snapshot["tick"] = snapshot.get("tick_index", 0)
	snapshot["world_name"] = snapshot.get("world_name", "はじまりの広場")
	snapshot["characters"] = _build_character_list(snapshot.get("entities", {}))
	snapshot["objects"] = _build_object_list(snapshot.get("entities", {}))
	snapshot["three_d_preview"] = _build_three_d_preview(snapshot.get("entities", {}), snapshot.get("preview_3d", {}))
	snapshot["rule_tree"] = _build_rule_tree(installed_rules_by_id)
	snapshot["rule_dependency_status"] = _build_rule_dependency_status(installed_rules_by_id)
	var world_clock := _build_world_clock_summary(installed_rules_by_id, snapshot)
	if not world_clock.is_empty():
		snapshot["world_clock"] = world_clock
	snapshot["events"] = _build_event_messages(snapshot.get("event_log", []))
	snapshot["poc4"] = _build_snapshot_poc4_state()
	snapshot["visual_effects"] = _build_visual_effects_snapshot(Array(_world_state.get("visual_effects", [])))
	return snapshot


func create_snapshot() -> Dictionary:
	var template_ids: Array = _template_index.keys()
	template_ids.sort()
	return {
		"snapshot_type": WORLD_SNAPSHOT_TYPE,
		"snapshot_version": WORLD_SNAPSHOT_VERSION,
		"runtime": {
			"fixed_step_seconds": fixed_step_seconds,
			"accumulator_seconds": _accumulator_seconds,
			"clone_sequence": _clone_sequence
		},
		"template_catalog": {
			"available_template_ids": template_ids.duplicate(true)
		},
		"world": _serialize_world_state()
	}


func restore_snapshot(snapshot_data: Dictionary) -> Dictionary:
	var normalized := _normalize_saved_snapshot(snapshot_data)
	if String(normalized.get("status", "")) == "error":
		return normalized

	fixed_step_seconds = float(normalized.get("fixed_step_seconds", DEFAULT_FIXED_STEP))
	_accumulator_seconds = float(normalized.get("accumulator_seconds", 0.0))
	_clone_sequence = int(normalized.get("clone_sequence", 0))
	_world_state = normalized.get("world_state", {}).duplicate(true)
	_world_state["fixed_step_seconds"] = fixed_step_seconds

	_refresh_rule_relationships()
	var installed_rules: Dictionary = _world_state.get("installed_rules", {})
	var rule_ids: Array = installed_rules.keys()
	rule_ids.sort()
	for rule_id in rule_ids:
		_initialize_rule_targets(installed_rules[rule_id])

	return {
		"status": "loaded",
		"snapshot": get_snapshot(),
		"saved_snapshot": create_snapshot()
	}


func save_snapshot(file_path: String) -> Dictionary:
	var normalized_path := String(file_path).strip_edges()
	if normalized_path.is_empty():
		return {
			"status": "error",
			"message": "保存先のパスが空です。"
		}

	var snapshot := create_snapshot()
	var file := FileAccess.open(normalized_path, FileAccess.WRITE)
	if file == null:
		var open_error := FileAccess.get_open_error()
		return {
			"status": "error",
			"message": "スナップショットを保存できませんでした: %s" % error_string(open_error),
			"path": normalized_path,
			"error_code": open_error
		}

	file.store_string("%s\n" % JSON.stringify(snapshot, "\t", true))
	return {
		"status": "saved",
		"path": normalized_path,
		"snapshot": snapshot
	}


func load_snapshot(file_path: String) -> Dictionary:
	var normalized_path := String(file_path).strip_edges()
	if normalized_path.is_empty():
		return {
			"status": "error",
			"message": "読み込み元のパスが空です。"
		}

	var file := FileAccess.open(normalized_path, FileAccess.READ)
	if file == null:
		var open_error := FileAccess.get_open_error()
		return {
			"status": "error",
			"message": "スナップショットを開けませんでした: %s" % error_string(open_error),
			"path": normalized_path,
			"error_code": open_error
		}

	var parser := JSON.new()
	var parse_error := parser.parse(file.get_as_text())
	if parse_error != OK:
		return {
			"status": "error",
			"message": "スナップショット JSON を解析できませんでした: %s" % parser.get_error_message(),
			"path": normalized_path,
			"line": parser.get_error_line()
		}

	if not (parser.data is Dictionary):
		return {
			"status": "error",
			"message": "スナップショットのルートは Dictionary である必要があります。",
			"path": normalized_path
		}

	var load_result := restore_snapshot(parser.data)
	load_result["path"] = normalized_path
	return load_result


func set_rule_enabled(rule_id: String, enabled: bool) -> Dictionary:
	var normalized_id := String(rule_id).strip_edges()
	if normalized_id.is_empty():
		return {
			"status": "error",
			"message": "ルール ID が空です。"
		}

	var installed_rules: Dictionary = _world_state.get("installed_rules", {})
	if not installed_rules.has(normalized_id):
		return {
			"status": "error",
			"message": "ルール '%s' は導入されていません。" % normalized_id,
			"rule_id": normalized_id
		}

	var rule: Dictionary = installed_rules[normalized_id]
	var previous_enabled := bool(rule.get("enabled", true))
	rule["enabled"] = enabled
	installed_rules[normalized_id] = rule
	_world_state["installed_rules"] = installed_rules

	if previous_enabled != enabled:
		var event_type := "rule_enabled" if enabled else "rule_disabled"
		var message := "ルール '%s' を有効化しました。" % normalized_id if enabled else "ルール '%s' を無効化しました。" % normalized_id
		_append_event(event_type, message, {"rule_id": normalized_id})

	return {
		"status": "enabled" if enabled else "disabled",
		"rule_id": normalized_id,
		"previous_enabled": previous_enabled,
		"enabled": enabled
	}


func set_package_enabled(package_id: String, enabled: bool) -> Dictionary:
	var normalized_package_id := String(package_id).strip_edges()
	if normalized_package_id.is_empty():
		return {
			"status": "error",
			"message": "パッケージ ID が空です。"
		}

	var installed_rules: Dictionary = _world_state.get("installed_rules", {})
	var matched_rule_ids := _find_package_rule_ids(installed_rules, normalized_package_id)
	if matched_rule_ids.is_empty():
		return {
			"status": "error",
			"message": "パッケージ '%s' 由来のルールは導入されていません。" % normalized_package_id,
			"package_id": normalized_package_id
		}

	var changed_rule_ids: Array = []
	var previous_enabled_rule_ids: Array = []
	for rule_id in matched_rule_ids:
		var rule: Dictionary = installed_rules.get(rule_id, {}).duplicate(true)
		var previous_enabled := bool(rule.get("enabled", true))
		if previous_enabled:
			previous_enabled_rule_ids.append(rule_id)
		if previous_enabled != enabled:
			changed_rule_ids.append(rule_id)
		rule["enabled"] = enabled
		installed_rules[rule_id] = rule
	_world_state["installed_rules"] = installed_rules

	var summary := _build_package_summary(normalized_package_id, matched_rule_ids, installed_rules)
	if not changed_rule_ids.is_empty():
		var event_type := "rule_package_enabled" if enabled else "rule_package_disabled"
		var message := "パッケージ '%s' を有効化しました。" % normalized_package_id if enabled else "パッケージ '%s' を無効化しました。" % normalized_package_id
		_append_event(event_type, message, {
			"package_id": normalized_package_id,
			"rule_ids": matched_rule_ids.duplicate(true),
			"changed_rule_ids": changed_rule_ids.duplicate(true)
		})

	return {
		"status": "enabled" if enabled else "disabled",
		"package_id": normalized_package_id,
		"enabled": enabled,
		"rule_ids": matched_rule_ids.duplicate(true),
		"changed_rule_ids": changed_rule_ids.duplicate(true),
		"previous_enabled_rule_ids": previous_enabled_rule_ids.duplicate(true),
		"package": summary
	}


func advance_tick(delta_seconds: float) -> void:
	if delta_seconds <= 0.0:
		return

	_accumulator_seconds += delta_seconds
	while _accumulator_seconds >= fixed_step_seconds:
		_run_tick(fixed_step_seconds)
		_accumulator_seconds -= fixed_step_seconds


func set_entity_position(entity_id: String, position_patch: Dictionary) -> Dictionary:
	if entity_id.is_empty():
		return {}
	var entities: Dictionary = _world_state.get("entities", {})
	if not entities.has(entity_id):
		return {}
	var entity: Dictionary = entities[entity_id].duplicate(true)
	var current_position: Dictionary = entity.get("position", {}).duplicate(true) if entity.get("position", {}) is Dictionary else {}
	var default_position := current_position if not current_position.is_empty() else {"x": 0.0, "y": 0.0, "z": 0.0}
	var next_position := _merge_dictionaries(current_position, position_patch)
	var normalized_position := _normalize_vector3_dict(next_position, default_position)
	for key in next_position.keys():
		if not normalized_position.has(key):
			normalized_position[key] = next_position[key]
	entity["position"] = normalized_position
	entities[entity_id] = entity
	_world_state["entities"] = entities
	return normalized_position.duplicate(true)


func dispatch_input_event(event_name: String, context: Dictionary = {}) -> Dictionary:
	var normalized_event := event_name.strip_edges().to_lower()
	if normalized_event.is_empty():
		return {
			"status": "ignored",
			"event": "",
			"triggered_effect_count": 0
		}

	var proposal_runtime: Dictionary = _world_state.get("proposal_runtime", {})
	if proposal_runtime.is_empty():
		return {
			"status": "ignored",
			"event": normalized_event,
			"triggered_effect_count": 0
		}

	var package_ids: Array = proposal_runtime.keys()
	package_ids.sort()
	var triggered_rule_ids: Array = []
	var effect_ids: Array = []

	for package_id_variant in package_ids:
		var package_id := String(package_id_variant)
		var package_runtime_variant: Variant = proposal_runtime.get(package_id, {})
		if not (package_runtime_variant is Dictionary):
			continue
		var package_runtime: Dictionary = package_runtime_variant
		var rule_operations := _build_rule_operation_index(Array(package_runtime.get("rule_operations", [])))
		var relations: Array = Array(package_runtime.get("relations", []))

		for binding_variant in Array(package_runtime.get("event_bindings", [])):
			if not (binding_variant is Dictionary):
				continue
			var binding: Dictionary = binding_variant
			if String(binding.get("event", "")).strip_edges().to_lower() != normalized_event:
				continue

			var target_rule_id := String(binding.get("target_rule", "")).strip_edges()
			if target_rule_id.is_empty() or not rule_operations.has(target_rule_id):
				continue
			if not _relation_allows_event(relations, target_rule_id, context):
				continue

			var execution_result := _dispatch_runtime_rule_operation(package_id, target_rule_id, rule_operations.get(target_rule_id, {}), context)
			var triggered_effect_ids: Array = Array(execution_result.get("effect_ids", []))
			if triggered_effect_ids.is_empty():
				continue
			_append_unique_string(triggered_rule_ids, target_rule_id)
			for effect_id_variant in triggered_effect_ids:
				_append_unique_string(effect_ids, String(effect_id_variant))

	if effect_ids.is_empty():
		return {
			"status": "ignored",
			"event": normalized_event,
			"triggered_effect_count": 0
		}

	_append_event("runtime_input_event", "入力イベント '%s' で視覚効果を発火しました。" % normalized_event, {
		"event": normalized_event,
		"triggered_rule_ids": triggered_rule_ids.duplicate(true),
		"effect_ids": effect_ids.duplicate(true)
	})
	return {
		"status": "triggered",
		"event": normalized_event,
		"triggered_rule_ids": triggered_rule_ids.duplicate(true),
		"effect_ids": effect_ids.duplicate(true),
		"triggered_effect_count": effect_ids.size()
	}


func _serialize_world_state() -> Dictionary:
	var serialized_world := _world_state.duplicate(true)
	serialized_world["fixed_step_seconds"] = fixed_step_seconds
	serialized_world["concepts"] = _normalize_string_array(_duplicate_array(serialized_world.get("concepts", [])))
	serialized_world["preview_3d"] = _serialize_preview_state(serialized_world.get("preview_3d", {}))
	serialized_world["entities"] = _serialize_entities(serialized_world.get("entities", {}))
	serialized_world["installed_rules"] = _serialize_installed_rules(serialized_world.get("installed_rules", {}))
	serialized_world["player_task_history"] = _duplicate_array(serialized_world.get("player_task_history", []))
	serialized_world["event_log"] = _duplicate_array(serialized_world.get("event_log", []))
	return serialized_world


func _normalize_saved_snapshot(snapshot_data: Dictionary) -> Dictionary:
	var snapshot_type := String(snapshot_data.get("snapshot_type", ""))
	if snapshot_type != WORLD_SNAPSHOT_TYPE:
		return {
			"status": "error",
			"message": "未対応のスナップショット形式です: %s" % snapshot_type
		}

	var snapshot_version := int(snapshot_data.get("snapshot_version", 0))
	if snapshot_version != WORLD_SNAPSHOT_VERSION:
		return {
			"status": "error",
			"message": "未対応のスナップショットバージョンです: %d" % snapshot_version
		}

	var runtime_data: Dictionary = snapshot_data.get("runtime", {}).duplicate(true) if snapshot_data.get("runtime", {}) is Dictionary else {}
	var world_data: Dictionary = snapshot_data.get("world", {}).duplicate(true) if snapshot_data.get("world", {}) is Dictionary else {}
	var next_fixed_step: float = max(0.001, float(runtime_data.get("fixed_step_seconds", world_data.get("fixed_step_seconds", DEFAULT_FIXED_STEP))))
	var next_world_state := _build_null_world_with_fixed_step(next_fixed_step)
	next_world_state = _merge_dictionaries(next_world_state, world_data)
	next_world_state["fixed_step_seconds"] = next_fixed_step
	next_world_state["concepts"] = _normalize_string_array(_duplicate_array(world_data.get("concepts", next_world_state.get("concepts", []))))
	next_world_state["preview_3d"] = _serialize_preview_state(world_data.get("preview_3d", next_world_state.get("preview_3d", {})))
	next_world_state["entities"] = _deserialize_entities(world_data.get("entities", next_world_state.get("entities", {})))
	next_world_state["installed_rules"] = _deserialize_installed_rules(world_data.get("installed_rules", next_world_state.get("installed_rules", {})))
	next_world_state["player_task_history"] = _duplicate_array(world_data.get("player_task_history", next_world_state.get("player_task_history", [])))
	next_world_state["event_log"] = _duplicate_array(world_data.get("event_log", next_world_state.get("event_log", [])))
	next_world_state["elapsed_seconds"] = max(0.0, float(world_data.get("elapsed_seconds", next_world_state.get("elapsed_seconds", 0.0))))
	next_world_state["tick_index"] = max(0, int(world_data.get("tick_index", next_world_state.get("tick_index", 0))))

	return {
		"status": "ok",
		"fixed_step_seconds": next_fixed_step,
		"accumulator_seconds": max(0.0, float(runtime_data.get("accumulator_seconds", 0.0))),
		"clone_sequence": max(0, int(runtime_data.get("clone_sequence", 0))),
		"world_state": next_world_state
	}


func _build_null_world_with_fixed_step(step_seconds: float) -> Dictionary:
	var previous_fixed_step := fixed_step_seconds
	fixed_step_seconds = step_seconds
	var world_state := _build_null_world()
	fixed_step_seconds = previous_fixed_step
	world_state["fixed_step_seconds"] = step_seconds
	return world_state


func _serialize_preview_state(raw_preview: Variant) -> Dictionary:
	var merged_preview := _build_default_three_d_preview_state()
	if raw_preview is Dictionary:
		merged_preview = _merge_dictionaries(merged_preview, raw_preview)

	var enabled := bool(merged_preview.get("enabled", false))
	merged_preview["enabled"] = enabled
	merged_preview["lighting"] = _normalize_preview_lighting(merged_preview.get("lighting", {}), enabled)
	merged_preview["gravity"] = _normalize_preview_gravity(merged_preview.get("gravity", {}), enabled)
	merged_preview["camera"] = _normalize_preview_camera(merged_preview.get("camera", {}))
	return merged_preview


func _serialize_entities(raw_entities: Variant) -> Array:
	var serialized_entities: Array = []
	if not (raw_entities is Dictionary):
		return serialized_entities

	var entity_ids: Array = raw_entities.keys()
	entity_ids.sort()
	for entity_id in entity_ids:
		if not (raw_entities[entity_id] is Dictionary):
			continue
		var entity_data: Dictionary = raw_entities[entity_id].duplicate(true)
		if String(entity_data.get("id", "")).is_empty():
			entity_data["id"] = String(entity_id)
		var normalized_entity := _normalize_entity(entity_data)
		if not normalized_entity.is_empty():
			serialized_entities.append(normalized_entity)
	return serialized_entities


func _serialize_installed_rules(raw_rules: Variant) -> Array:
	var serialized_rules: Array = []
	if not (raw_rules is Dictionary):
		return serialized_rules

	var rule_ids: Array = raw_rules.keys()
	rule_ids.sort()
	for rule_id in rule_ids:
		if not (raw_rules[rule_id] is Dictionary):
			continue
		var rule_data: Dictionary = raw_rules[rule_id].duplicate(true)
		if String(rule_data.get("id", "")).is_empty():
			rule_data["id"] = String(rule_id)
		serialized_rules.append(rule_data)
	return serialized_rules


func _deserialize_entities(raw_entities: Variant) -> Dictionary:
	var entities: Dictionary = {}
	if raw_entities is Dictionary:
		var entity_ids: Array = raw_entities.keys()
		entity_ids.sort()
		for entity_id in entity_ids:
			if not (raw_entities[entity_id] is Dictionary):
				continue
			var entity_data: Dictionary = raw_entities[entity_id].duplicate(true)
			if String(entity_data.get("id", "")).is_empty():
				entity_data["id"] = String(entity_id)
			var normalized_entity := _normalize_entity(entity_data)
			if not normalized_entity.is_empty():
				entities[String(normalized_entity.get("id", entity_id))] = normalized_entity
	elif raw_entities is Array:
		for raw_entity in raw_entities:
			if not (raw_entity is Dictionary):
				continue
			var normalized_entity := _normalize_entity(raw_entity.duplicate(true))
			if not normalized_entity.is_empty():
				entities[String(normalized_entity.get("id", ""))] = normalized_entity
	return entities


func _deserialize_installed_rules(raw_rules: Variant) -> Dictionary:
	var installed_rules: Dictionary = {}
	if raw_rules is Dictionary:
		var rule_ids: Array = raw_rules.keys()
		rule_ids.sort()
		for rule_id in rule_ids:
			if not (raw_rules[rule_id] is Dictionary):
				continue
			var rule_data: Dictionary = raw_rules[rule_id].duplicate(true)
			if String(rule_data.get("id", "")).is_empty():
				rule_data["id"] = String(rule_id)
			var normalized_rule := _normalize_rule_patch(rule_data, false)
			if not normalized_rule.is_empty():
				installed_rules[String(normalized_rule.get("id", rule_id))] = normalized_rule
	elif raw_rules is Array:
		for raw_rule in raw_rules:
			if not (raw_rule is Dictionary):
				continue
			var normalized_rule := _normalize_rule_patch(raw_rule.duplicate(true), false)
			if not normalized_rule.is_empty():
				installed_rules[String(normalized_rule.get("id", ""))] = normalized_rule
	return installed_rules
func _build_null_world() -> Dictionary:
	return {
		"world_id": "starter-plaza",
		"world_name": "はじまりの広場",
		"runtime_choice": "godot-4-desktop",
		"elapsed_seconds": 0.0,
		"tick_index": 0,
		"fixed_step_seconds": fixed_step_seconds,
		"concepts": ["main_scene_2d_start", "gm_in_world"],
		"preview_3d": _build_default_three_d_preview_state(),
		"entities": {
			"origin_entity": {
				"id": "origin_entity",
				"name": "プレイヤー",
				"archetype": "origin",
				"tags": ["origin", "mortal", "mutable", "character", "player"],
				"position": {
					"x": 0.0,
					"y": 0.9,
					"z": -4.2,
					"location": "starter_path"
				},
				"render_3d": {
					"kind": "character",
					"size": {
						"x": 0.9,
						"y": 1.8,
						"z": 0.9
					},
					"color": "#5b8cff"
				},
				"components": {
					"needs": {},
					"stats": {},
					"traits": {
						"curiosity": 1.0,
						"morale": 50.0,
						"focus": 50.0
					},
					"behavior": {
						"current_task": "ゲームマスターのところへ歩いて相談する"
					},
					"physics": {
						"dynamic": false,
						"grounded": true,
						"gravity_scale": 0.0,
						"floor_offset_y": 0.9,
						"velocity": {"x": 0.0, "y": 0.0, "z": 0.0}
					}
				}
			},
			"gm_entity": {
				"id": "gm_entity",
				"name": "ゲームマスター",
				"archetype": "gm",
				"tags": ["character", "gm", "director", "mortal"],
				"position": {
					"x": -1.8,
					"y": 1.1,
					"z": 1.4,
					"location": "gm_dais"
				},
				"render_3d": {
					"kind": "gm",
					"size": {"x": 1.1, "y": 2.2, "z": 1.1},
					"color": "#f3c969"
				},
				"components": {
					"behavior": {
						"current_task": "プレイヤーからの相談を待機中"
					},
					"physics": {
						"dynamic": false,
						"grounded": true,
						"gravity_scale": 0.0,
						"floor_offset_y": 1.1,
						"velocity": {"x": 0.0, "y": 0.0, "z": 0.0}
					}
				}
			},
			"rule_board": {
				"id": "rule_board",
				"name": "相談ボード",
				"archetype": "structure",
				"tags": ["object", "structure"],
				"position": {
					"x": 2.2,
					"y": 1.1,
					"z": 0.1,
					"location": "plaza_edge"
				},
				"render_3d": {
					"kind": "object",
					"size": {"x": 2.4, "y": 2.2, "z": 0.4},
					"color": "#7e8794"
				},
				"components": {
					"state": {
						"status": "GMへ相談すると管理画面を開けます"
					}
				}
			},
			"supply_crate": {
				"id": "supply_crate",
				"name": "補給箱",
				"archetype": "object",
				"tags": ["object", "portable"],
				"position": {
					"x": 3.1,
					"y": 0.6,
					"z": 2.3,
					"location": "supply_corner"
				},
				"render_3d": {
					"kind": "crate",
					"size": {"x": 1.2, "y": 1.2, "z": 1.2},
					"color": "#b67a45"
				},
				"components": {
					"state": {
						"status": "PoC3用の小道具"
					}
				}
			},
			"rest_stone": {
				"id": "rest_stone",
				"name": "腰掛け石",
				"archetype": "object",
				"tags": ["object", "structure"],
				"position": {
					"x": -4.0,
					"y": 0.55,
					"z": -1.1,
					"location": "rest_corner"
				},
				"render_3d": {
					"kind": "object",
					"size": {"x": 1.8, "y": 1.1, "z": 1.8},
					"color": "#8f939a"
				},
				"components": {
					"state": {
						"status": "広場の目印"
					}
				}
			}
		},
		"installed_rules": {},
		"proposal_runtime": {},
		"visual_effects": [],
		"player_task_history": [],
		"poc4": _build_default_poc4_state(),
		"event_log": [
			{
				"type": "world_initialized",
				"message": "プレイヤーとGMが同じ2D広場にいる初期ワールドを起動しました。GM会話で3D化できます。",
				"details": {}
			}
		]
	}


func _run_tick(step_seconds: float) -> void:
	var entities: Dictionary = _world_state.get("entities", {})
	var installed_rules: Dictionary = _world_state.get("installed_rules", {})
	var entity_ids: Array = entities.keys()
	var rule_ids: Array = installed_rules.keys()
	entity_ids.sort()
	rule_ids.sort()

	for entity_id in entity_ids:
		var entity: Dictionary = entities[entity_id]
		for rule_id in rule_ids:
			var rule: Dictionary = installed_rules[rule_id]
			if not bool(rule.get("enabled", true)):
				continue
			if bool(rule.get("blocked", false)) or bool(rule.get("inactive", false)):
				continue
			if not _entity_matches_rule(entity, rule):
				continue
			_apply_rule(entity, rule, step_seconds)
		entities[entity_id] = entity

	_apply_gravity(entities, step_seconds)
	_update_visual_effects(step_seconds)
	_world_state["entities"] = entities
	_world_state["tick_index"] = int(_world_state.get("tick_index", 0)) + 1
	_world_state["elapsed_seconds"] = float(_world_state.get("elapsed_seconds", 0.0)) + step_seconds


func _entity_matches_rule(entity: Dictionary, rule: Dictionary) -> bool:
	var target_tags: Array = rule.get("target_tags", [])
	if target_tags.is_empty():
		return true

	var entity_tags: Array = entity.get("tags", [])
	for target_tag in target_tags:
		if not entity_tags.has(target_tag):
			return false
	return true


func _apply_rule(entity: Dictionary, rule: Dictionary, step_seconds: float) -> void:
	var components: Dictionary = entity.get("components", {})
	for effect in rule.get("effects", []):
		var component_name := String(effect.get("component", "stats"))
		var field_name := String(effect.get("field", "value"))
		if not components.has(component_name):
			components[component_name] = {}

		var component: Dictionary = components[component_name]
		var current_value := float(component.get(field_name, effect.get("default", 0.0)))
		var next_value := current_value
		var operation := String(effect.get("op", "add"))

		match operation:
			"set":
				next_value = float(effect.get("value", effect.get("default", 0.0)))
			"min":
				next_value = min(current_value, float(effect.get("value", current_value)))
			"max":
				next_value = max(current_value, float(effect.get("value", current_value)))
			_:
				next_value = current_value + float(effect.get("value_per_second", 0.0)) * step_seconds

		if effect.has("min"):
			next_value = max(next_value, float(effect["min"]))
		if effect.has("max"):
			next_value = min(next_value, float(effect["max"]))

		component[field_name] = snappedf(next_value, 0.0001)
		components[component_name] = component

	entity["components"] = components


func _install_normalized_rule(normalized_rule: Dictionary) -> Dictionary:
	var rule_id := String(normalized_rule.get("id", ""))
	var installed_rules: Dictionary = _world_state.get("installed_rules", {})
	if installed_rules.has(rule_id):
		return {
			"status": "error",
			"message": "ルール '%s' はすでに導入されています。" % rule_id
		}

	var parent_resolution := _resolve_parent_rule_links(normalized_rule, installed_rules)
	if String(parent_resolution.get("status", "")) == "error":
		return parent_resolution

	normalized_rule["resolved_parent_rule_ids"] = parent_resolution.get("resolved_parent_rule_ids", []).duplicate(true)
	normalized_rule["resolved_parent_rule_links"] = parent_resolution.get("resolved_parent_rule_links", []).duplicate(true)
	normalized_rule["missing_required_rule_kinds"] = []
	normalized_rule["blocked"] = false
	normalized_rule["inactive"] = not bool(normalized_rule.get("enabled", true))
	normalized_rule["dependency_status"] = "inactive" if bool(normalized_rule.get("inactive", false)) else "active"

	installed_rules[rule_id] = normalized_rule
	_world_state["installed_rules"] = installed_rules
	_apply_install_actions(normalized_rule)
	_initialize_rule_targets(normalized_rule)
	_refresh_rule_relationships()
	_append_concept(normalized_rule.get("concept", rule_id))
	_append_event(
		"rule_installed",
		"ルール '%s' を導入しました。" % rule_id,
		{
			"rule_id": rule_id,
			"requires_rule_kinds": normalized_rule.get("requires_rule_kinds", []),
			"provides_rule_kinds": normalized_rule.get("provides_rule_kinds", []),
			"resolved_parent_rule_ids": _world_state.get("installed_rules", {}).get(rule_id, {}).get("resolved_parent_rule_ids", [])
		}
	)

	return {
		"status": "installed",
		"installed": true,
		"rule": _world_state.get("installed_rules", {}).get(rule_id, {}).duplicate(true)
	}


func _normalize_rule_patch(rule_patch: Dictionary, merge_template: bool = true) -> Dictionary:
	var base_rule: Dictionary = {}
	var template_id := String(rule_patch.get("template_id", ""))
	if merge_template and not template_id.is_empty() and _template_index.has(template_id):
		base_rule = _template_index[template_id].get("rule_patch", {}).duplicate(true)

	var merged_rule := _merge_dictionaries(base_rule, rule_patch)
	if merged_rule.is_empty():
		return {}

	var rule_id := String(merged_rule.get("id", ""))
	if rule_id.is_empty():
		rule_id = _make_unique_rule_id("rule_%d" % (int(_world_state.get("tick_index", 0)) + int(_world_state.get("installed_rules", {}).size()) + 1))
		merged_rule["id"] = rule_id

	merged_rule["enabled"] = bool(merged_rule.get("enabled", true))
	merged_rule["scope"] = String(merged_rule.get("scope", "entity"))
	merged_rule["requires_rule_kinds"] = _normalize_string_array(_extract_rule_array_metadata(merged_rule, "requires_rule_kinds"))
	merged_rule["provides_rule_kinds"] = _normalize_string_array(_extract_rule_array_metadata(merged_rule, "provides_rule_kinds"))
	merged_rule["install_actions"] = _normalize_install_actions(_extract_rule_array_metadata(merged_rule, "install_actions"))
	merged_rule["resolved_parent_rule_ids"] = []
	merged_rule["resolved_parent_rule_links"] = []
	merged_rule["missing_required_rule_kinds"] = []
	merged_rule["blocked"] = false
	merged_rule["inactive"] = not bool(merged_rule.get("enabled", true))
	merged_rule["dependency_status"] = "inactive" if bool(merged_rule.get("inactive", false)) else "active"
	var target_tags: Array = []
	for tag in merged_rule.get("target_tags", []):
		target_tags.append(String(tag))
	merged_rule["target_tags"] = target_tags

	var normalized_effects: Array = []
	for raw_effect in merged_rule.get("effects", []):
		var effect: Dictionary = raw_effect.duplicate(true)
		effect["component"] = String(effect.get("component", "stats"))
		effect["field"] = String(effect.get("field", "value"))
		effect["op"] = String(effect.get("op", "add"))
		effect["default"] = float(effect.get("default", 0.0))
		if effect.has("value_per_second"):
			effect["value_per_second"] = float(effect["value_per_second"])
		if effect.has("value"):
			effect["value"] = float(effect["value"])
		if effect.has("min"):
			effect["min"] = float(effect["min"])
		if effect.has("max"):
			effect["max"] = float(effect["max"])
		normalized_effects.append(effect)
	merged_rule["effects"] = normalized_effects

	return merged_rule


func _resolve_parent_rule_links(rule: Dictionary, installed_rules: Dictionary) -> Dictionary:
	var required_rule_kinds: Array = rule.get("requires_rule_kinds", [])
	var missing_rule_kinds: Array = []
	var resolved_parent_rule_ids: Array = []
	var resolved_parent_rule_links: Array = []
	var installed_rule_ids: Array = installed_rules.keys()
	installed_rule_ids.sort()
	var rule_id := String(rule.get("id", ""))

	for required_kind_variant in required_rule_kinds:
		var required_kind := String(required_kind_variant).strip_edges()
		if required_kind.is_empty():
			continue

		var matching_rule_ids: Array = []
		for installed_rule_id in installed_rule_ids:
			var candidate_rule: Dictionary = installed_rules[installed_rule_id]
			if String(candidate_rule.get("id", installed_rule_id)) == rule_id:
				continue
			if _rule_provides_kind(candidate_rule, required_kind):
				matching_rule_ids.append(installed_rule_id)
				if not resolved_parent_rule_ids.has(installed_rule_id):
					resolved_parent_rule_ids.append(installed_rule_id)
		matching_rule_ids.sort()
		resolved_parent_rule_links.append({
			"required_kind": required_kind,
			"rule_ids": matching_rule_ids.duplicate(true)
		})
		if matching_rule_ids.is_empty():
			missing_rule_kinds.append(required_kind)

	resolved_parent_rule_ids.sort()
	if not missing_rule_kinds.is_empty():
		return {
			"status": "error",
			"message": "ルール '%s' には、導入済みの親ルール種別 [%s] が必要です。先に対応するルールを入れてください。" % [rule_id, ", ".join(missing_rule_kinds)],
			"rule_id": rule_id,
			"requires_rule_kinds": required_rule_kinds.duplicate(true),
			"missing_required_rule_kinds": missing_rule_kinds.duplicate(true)
		}

	return {
		"status": "resolved",
		"resolved_parent_rule_ids": resolved_parent_rule_ids.duplicate(true),
		"resolved_parent_rule_links": resolved_parent_rule_links.duplicate(true),
		"missing_required_rule_kinds": []
	}


func _rule_provides_kind(rule: Dictionary, required_kind: String) -> bool:
	for provided_kind_variant in rule.get("provides_rule_kinds", []):
		if String(provided_kind_variant).strip_edges() == required_kind:
			return true
	return false


func _apply_install_actions(rule: Dictionary) -> void:
	var entities: Dictionary = _world_state.get("entities", {})
	for raw_action in rule.get("install_actions", []):
		if not (raw_action is Dictionary):
			continue
		var action: Dictionary = raw_action
		match String(action.get("op", "")):
			"upsert_entities":
				for raw_entity_patch in action.get("entities", []):
					if not (raw_entity_patch is Dictionary):
						continue
					var entity_patch: Dictionary = raw_entity_patch
					var entity_id := String(entity_patch.get("id", ""))
					if entity_id.is_empty():
						continue
					var existing_entity: Dictionary = entities.get(entity_id, {})
					var merged_entity := _merge_dictionaries(existing_entity, entity_patch)
					entities[entity_id] = _normalize_entity(merged_entity)
			"merge_world_state":
				_apply_world_state_merge_action(action)
	_world_state["entities"] = entities


func _refresh_rule_relationships() -> void:
	var installed_rules: Dictionary = _world_state.get("installed_rules", {})
	var rule_ids: Array = installed_rules.keys()
	rule_ids.sort()

	for rule_id in rule_ids:
		var rule: Dictionary = installed_rules[rule_id]
		var parent_resolution := _resolve_parent_rule_links(rule, installed_rules)
		rule["resolved_parent_rule_ids"] = parent_resolution.get("resolved_parent_rule_ids", []).duplicate(true)
		rule["resolved_parent_rule_links"] = parent_resolution.get("resolved_parent_rule_links", []).duplicate(true)
		var missing_required_rule_kinds: Array = parent_resolution.get("missing_required_rule_kinds", [])
		rule["missing_required_rule_kinds"] = missing_required_rule_kinds.duplicate(true)
		rule["blocked"] = not missing_required_rule_kinds.is_empty()
		rule["inactive"] = bool(rule.get("blocked", false)) or not bool(rule.get("enabled", true))
		if bool(rule.get("blocked", false)):
			rule["dependency_status"] = "blocked"
		elif bool(rule.get("inactive", false)):
			rule["dependency_status"] = "inactive"
		else:
			rule["dependency_status"] = "active"
		installed_rules[rule_id] = rule

	_world_state["installed_rules"] = installed_rules


func _initialize_rule_targets(rule: Dictionary) -> void:
	var entities: Dictionary = _world_state.get("entities", {})
	var entity_ids: Array = entities.keys()
	entity_ids.sort()

	for entity_id in entity_ids:
		var entity: Dictionary = entities[entity_id]
		if not _entity_matches_rule(entity, rule):
			continue

		var components: Dictionary = entity.get("components", {})
		for effect in rule.get("effects", []):
			var component_name := String(effect.get("component", "stats"))
			var field_name := String(effect.get("field", "value"))
			if not components.has(component_name):
				components[component_name] = {}
			var component: Dictionary = components[component_name]
			if not component.has(field_name):
				component[field_name] = float(effect.get("default", 0.0))
			components[component_name] = component

		entity["components"] = components
		entities[entity_id] = entity

	_world_state["entities"] = entities


func _append_concept(concept_name: Variant) -> void:
	var concept := String(concept_name)
	if concept.is_empty():
		return

	var concepts: Array = _world_state.get("concepts", [])
	if not concepts.has(concept):
		concepts.append(concept)
	_world_state["concepts"] = concepts


func _append_event(event_type: String, message: String, details: Dictionary = {}) -> void:
	var event_log: Array = _world_state.get("event_log", [])
	event_log.append({
		"type": event_type,
		"message": message,
		"details": details.duplicate(true)
	})
	_world_state["event_log"] = event_log


func _build_default_poc4_state() -> Dictionary:
	return {
		"pending_proposal": {},
		"proposal_summary": {},
		"issue_preview": {},
		"review": _build_default_poc4_review(),
		"apply_result": {},
		"last_error": {},
		"execution": _build_default_poc4_execution(),
		"codex": {},
		"last_request_text": "",
		"history": []
	}


func _build_default_poc4_execution() -> Dictionary:
	return {
		"status": "idle",
		"phase": "idle",
		"message": "",
		"request_text": ""
	}


func _build_default_poc4_review() -> Dictionary:
	return {
		"required": false,
		"acknowledged": false,
		"status": "not_requested",
		"metadata": {}
	}

func _get_poc4_state() -> Dictionary:
	var poc4_state = _world_state.get("poc4", _build_default_poc4_state())
	return poc4_state.duplicate(true) if poc4_state is Dictionary else _build_default_poc4_state()


func _build_snapshot_poc4_state() -> Dictionary:
	var poc4_state := _get_poc4_state()
	poc4_state["codex"] = _compact_poc4_codex(_duplicate_dictionary(poc4_state.get("codex", {})))
	return poc4_state


func _extract_poc4_error(result: Dictionary) -> Dictionary:
	return {
		"status": String(result.get("status", "error")),
		"error_code": String(result.get("error_code", "unknown")),
		"message": String(result.get("message", "PoC4 backend error.")),
		"details": _duplicate_dictionary(result.get("details", {}))
	}


func _extract_poc4_codex(result: Dictionary) -> Dictionary:
	if result.get("codex", {}) is Dictionary:
		return _compact_poc4_codex(_duplicate_dictionary(result.get("codex", {})))
	var details: Dictionary = result.get("details", {})
	if details.get("codex", {}) is Dictionary:
		return _compact_poc4_codex(_duplicate_dictionary(details.get("codex", {})))
	return {}


func _compact_poc4_codex(codex: Dictionary) -> Dictionary:
	if codex.is_empty():
		return {}
	return {
		"status": String(codex.get("status", "")),
		"path": String(codex.get("path", "")),
		"session_id": String(codex.get("session_id", "")),
		"model": String(codex.get("model", "")),
		"workdir": String(codex.get("workdir", "")),
		"approval": String(codex.get("approval", "")),
		"sandbox": String(codex.get("sandbox", "")),
		"exit_code": int(codex.get("exit_code", 0)),
		"cli_output_excerpt": String(codex.get("cli_output_excerpt", "")),
		"cli_output_line_count": int(codex.get("cli_output_line_count", 0))
	}


func _build_runtime_rule_package_from_proposal(proposal: Dictionary) -> Dictionary:
	return {
		"schema_version": "rule_package_v1",
		"package_id": String(proposal.get("package_id", "draft.poc4.proposal")),
		"display_name": String(proposal.get("proposal_title", proposal.get("package_id", "PoC4 Proposal"))),
		"description": String(proposal.get("player_request_summary", "")),
		"source_repo": "runtime://poc4-proposal",
		"source_ref": "proposal",
		"forked_from": proposal.get("forked_from", null),
		"suggested_pr_target": proposal.get("suggested_pr_target", null),
		"patch": _duplicate_dictionary(proposal.get("patch", {}))
	}


func _build_proposal_install_actions(proposal: Dictionary) -> Array:
	var operations: Array = Array(proposal.get("patch", {}).get("operations", []))
	var event_bindings: Array = []
	var relations: Array = []
	var rule_operations: Array = []
	for operation_variant in operations:
		if not (operation_variant is Dictionary):
			continue
		var operation: Dictionary = operation_variant
		match String(operation.get("op", "")):
			"add_event_binding":
				event_bindings.append(_duplicate_dictionary(operation))
			"add_relation":
				relations.append(_duplicate_dictionary(operation))
			"upsert_rule":
				if String(operation.get("rule_type", "")) != "tick_delta":
					rule_operations.append(_duplicate_dictionary(operation))
	if event_bindings.is_empty() and relations.is_empty() and rule_operations.is_empty():
		return []
	return [{
		"op": "merge_world_state",
		"path": "proposal_runtime",
		"value": {
			String(proposal.get("package_id", "draft.poc4.proposal")).replace("/", "_"): {
				"proposal_title": String(proposal.get("proposal_title", "")),
				"event_bindings": event_bindings,
				"relations": relations,
				"rule_operations": rule_operations
			}
		}
	}]


func _extract_operation_types(operations: Array) -> Array:
	var operation_types: Array = []
	for operation_variant in operations:
		if not (operation_variant is Dictionary):
			continue
		var operation_type := String(operation_variant.get("op", "")).strip_edges()
		if operation_type.is_empty() or operation_types.has(operation_type):
			continue
		operation_types.append(operation_type)
	return operation_types


func _append_poc4_history(poc4_state: Dictionary, entry: Dictionary) -> void:
	var history: Array = poc4_state.get("history", [])
	history.append(entry.duplicate(true))
	if history.size() > 12:
		history.remove_at(0)
	poc4_state["history"] = history


func _duplicate_dictionary(value) -> Dictionary:
	return value.duplicate(true) if value is Dictionary else {}


func _build_world_clock_summary(installed_rules_by_id: Dictionary, snapshot: Dictionary) -> Dictionary:
	var provider := _find_world_clock_provider(installed_rules_by_id)
	if provider.is_empty():
		return {}
	var source_field := String(provider.get("source_field", "elapsed_seconds"))
	return {
		"elapsed_seconds": float(snapshot.get("elapsed_seconds", 0.0)),
		"total_ticks": int(snapshot.get("tick_index", 0)),
		"source_field": source_field,
		"source_package_id": String(provider.get("source_package_id", "")),
		"source_rule_id": String(provider.get("source_rule_id", "")),
		"description": String(provider.get("description", "WorldState.%s をプレイヤー向けの時計として見える化します。" % source_field))
	}


func _find_world_clock_provider(installed_rules_by_id: Dictionary) -> Dictionary:
	for rule in installed_rules_by_id.values():
		if not (rule is Dictionary):
			continue
		var rule_data: Dictionary = rule
		if not bool(rule_data.get("enabled", true)):
			continue
		var metadata: Dictionary = rule_data.get("metadata", {})
		var package_id := String(metadata.get("package_id", ""))
		var rule_id := String(rule_data.get("id", ""))
		var source_field := ""
		for effect in rule_data.get("effects", []):
			if not (effect is Dictionary):
				continue
			var effect_data: Dictionary = effect
			if String(effect_data.get("component", "")) == "time":
				source_field = String(effect_data.get("field", ""))
				if source_field == "elapsed_seconds":
					break
		if package_id == "builtin.time":
			if source_field.is_empty():
				source_field = "elapsed_seconds"
			return {
				"source_field": source_field,
				"source_package_id": package_id,
				"source_rule_id": rule_id,
				"description": "builtin.time は WorldState.%s をプレイヤー向けの時計として見える化します。" % source_field
			}
		for provided_kind in rule_data.get("provides_rule_kinds", []):
			if String(provided_kind) == "world-clock":
				if source_field.is_empty():
					source_field = "elapsed_seconds"
				var provider_id := package_id if not package_id.is_empty() else rule_id
				return {
					"source_field": source_field,
					"source_package_id": package_id,
					"source_rule_id": rule_id,
					"description": "%s は WorldState.%s をプレイヤー向けの時計として見える化します。" % [provider_id if not provider_id.is_empty() else "このルール", source_field]
				}
		if source_field == "elapsed_seconds":
			var provider_id := package_id if not package_id.is_empty() else rule_id
			return {
				"source_field": source_field,
				"source_package_id": package_id,
				"source_rule_id": rule_id,
				"description": "%s は WorldState.%s をプレイヤー向けの時計として見える化します。" % [provider_id if not provider_id.is_empty() else "このルール", source_field]
			}
	return {}


func _build_installed_rule_packages(installed_rules_by_id: Dictionary) -> Dictionary:
	var package_rule_ids: Dictionary = {}
	var package_ids: Array = []
	var rule_ids: Array = installed_rules_by_id.keys()
	rule_ids.sort()

	for rule_id in rule_ids:
		var rule: Dictionary = installed_rules_by_id.get(rule_id, {})
		var package_id := _extract_rule_package_id(rule)
		if package_id.is_empty():
			continue
		if not package_rule_ids.has(package_id):
			package_rule_ids[package_id] = []
			package_ids.append(package_id)
		var grouped_rule_ids: Array = package_rule_ids[package_id]
		grouped_rule_ids.append(rule_id)
		grouped_rule_ids.sort()
		package_rule_ids[package_id] = grouped_rule_ids

	package_ids.sort()
	var packages: Array = []
	var packages_by_id: Dictionary = {}
	for package_id in package_ids:
		var grouped_rule_ids: Array = package_rule_ids.get(package_id, [])
		var summary := _build_package_summary(package_id, grouped_rule_ids, installed_rules_by_id)
		packages.append(summary.duplicate(true))
		packages_by_id[package_id] = summary

	return {
		"packages": packages,
		"packages_by_id": packages_by_id
	}


func _build_package_summary(package_id: String, rule_ids: Array, installed_rules_by_id: Dictionary) -> Dictionary:
	var enabled_rule_count := 0
	var display_name := package_id
	var package_version := ""
	var source_repo := ""
	var source_ref := ""
	var forked_from: Variant = null
	var suggested_pr_target: Variant = null

	for rule_id_variant in rule_ids:
		var rule_id := String(rule_id_variant)
		var rule: Dictionary = installed_rules_by_id.get(rule_id, {})
		if rule.is_empty():
			continue
		if bool(rule.get("enabled", true)):
			enabled_rule_count += 1
		var metadata: Dictionary = rule.get("metadata", {})
		if display_name == package_id:
			var metadata_display_name := String(metadata.get("package_display_name", "")).strip_edges()
			if not metadata_display_name.is_empty():
				display_name = metadata_display_name
			else:
				display_name = String(rule.get("name", package_id))
		if package_version.is_empty():
			package_version = String(metadata.get("package_version", "")).strip_edges()
		if source_repo.is_empty():
			source_repo = String(metadata.get("source_repo", "")).strip_edges()
		if source_ref.is_empty():
			source_ref = String(metadata.get("source_ref", "")).strip_edges()
		if forked_from == null and metadata.has("forked_from"):
			forked_from = metadata.get("forked_from")
		if suggested_pr_target == null and metadata.has("suggested_pr_target"):
			suggested_pr_target = metadata.get("suggested_pr_target")

	var total_rule_count := rule_ids.size()
	var state := "disabled"
	if enabled_rule_count == total_rule_count and total_rule_count > 0:
		state = "enabled"
	elif enabled_rule_count > 0:
		state = "mixed"

	return {
		"package_id": package_id,
		"display_name": display_name,
		"version": package_version,
		"state": state,
		"enabled": enabled_rule_count > 0,
		"all_rules_enabled": enabled_rule_count == total_rule_count and total_rule_count > 0,
		"enabled_rule_count": enabled_rule_count,
		"disabled_rule_count": max(0, total_rule_count - enabled_rule_count),
		"rule_count": total_rule_count,
		"rule_ids": rule_ids.duplicate(true),
		"source_repo": source_repo,
		"source_ref": source_ref,
		"forked_from": forked_from,
		"suggested_pr_target": suggested_pr_target
	}


func _find_package_rule_ids(installed_rules_by_id: Dictionary, package_id: String) -> Array:
	var normalized_package_id := String(package_id).strip_edges()
	if normalized_package_id.is_empty():
		return []

	var matched_rule_ids: Array = []
	var rule_ids: Array = installed_rules_by_id.keys()
	rule_ids.sort()
	for rule_id in rule_ids:
		var rule: Dictionary = installed_rules_by_id.get(rule_id, {})
		if _extract_rule_package_id(rule) != normalized_package_id:
			continue
		matched_rule_ids.append(rule_id)
	return matched_rule_ids


func _extract_rule_package_id(rule: Dictionary) -> String:
	var metadata: Dictionary = rule.get("metadata", {})
	return String(metadata.get("package_id", "")).strip_edges()
func _build_default_three_d_preview_state() -> Dictionary:
	return {
		"enabled": false,
		"lighting": DEFAULT_THREE_D_LIGHTING.duplicate(true),
		"gravity": DEFAULT_THREE_D_GRAVITY.duplicate(true),
		"camera": DEFAULT_THREE_D_CAMERA.duplicate(true)
	}


func _build_three_d_preview(entities: Dictionary, preview_state: Variant) -> Dictionary:
	var merged_preview := _build_default_three_d_preview_state()
	if preview_state is Dictionary:
		merged_preview = _merge_dictionaries(merged_preview, preview_state)

	var enabled := bool(merged_preview.get("enabled", false))
	var lighting := _normalize_preview_lighting(merged_preview.get("lighting", {}), enabled)
	var gravity := _normalize_preview_gravity(merged_preview.get("gravity", {}), enabled)
	var camera := _normalize_preview_camera(merged_preview.get("camera", {}))

	return {
		"enabled": enabled,
		"renderables": _build_three_d_renderables(entities, gravity) if enabled else [],
		"lighting": lighting,
		"gravity": gravity,
		"camera": camera
	}


func _normalize_preview_lighting(raw_lighting: Variant, preview_enabled: bool) -> Dictionary:
	var lighting := DEFAULT_THREE_D_LIGHTING.duplicate(true)
	if raw_lighting is Dictionary:
		lighting = _merge_dictionaries(lighting, raw_lighting)
	lighting["enabled"] = preview_enabled and bool(lighting.get("enabled", false))
	lighting["shadows_enabled"] = bool(lighting.get("enabled", false)) and bool(lighting.get("shadows_enabled", false))
	lighting["light_rotation_degrees"] = _normalize_vector3_dict(lighting.get("light_rotation_degrees", {}), DEFAULT_THREE_D_LIGHTING["light_rotation_degrees"])
	lighting["intensity"] = float(lighting.get("intensity", DEFAULT_THREE_D_LIGHTING["intensity"]))
	lighting["color"] = String(lighting.get("color", DEFAULT_THREE_D_LIGHTING["color"]))
	return lighting


func _normalize_preview_gravity(raw_gravity: Variant, preview_enabled: bool) -> Dictionary:
	var gravity := DEFAULT_THREE_D_GRAVITY.duplicate(true)
	if raw_gravity is Dictionary:
		gravity = _merge_dictionaries(gravity, raw_gravity)
	gravity["enabled"] = preview_enabled and bool(gravity.get("enabled", false))
	gravity["floor_y"] = float(gravity.get("floor_y", DEFAULT_THREE_D_GRAVITY["floor_y"]))
	gravity["acceleration"] = max(0.0, float(gravity.get("acceleration", DEFAULT_THREE_D_GRAVITY["acceleration"])))
	return gravity


func _normalize_preview_camera(raw_camera: Variant) -> Dictionary:
	var camera := DEFAULT_THREE_D_CAMERA.duplicate(true)
	if raw_camera is Dictionary:
		camera = _merge_dictionaries(camera, raw_camera)
	camera["position"] = _normalize_vector3_dict(camera.get("position", {}), DEFAULT_THREE_D_CAMERA["position"])
	camera["look_at"] = _normalize_vector3_dict(camera.get("look_at", {}), DEFAULT_THREE_D_CAMERA["look_at"])
	camera["fov_degrees"] = float(camera.get("fov_degrees", DEFAULT_THREE_D_CAMERA["fov_degrees"]))
	return camera


func _build_three_d_renderables(entities: Dictionary, gravity: Dictionary) -> Array:
	var renderables: Array = []
	var entity_ids: Array = entities.keys()
	entity_ids.sort()

	for entity_id in entity_ids:
		var entity: Dictionary = entities[entity_id]
		if not _entity_is_three_d_renderable(entity):
			continue
		renderables.append(_build_three_d_renderable(String(entity_id), entity, gravity))

	return renderables


func _build_three_d_renderable(entity_id: String, entity: Dictionary, gravity: Dictionary) -> Dictionary:
	var render_data: Dictionary = entity.get("render_3d", {}).duplicate(true) if entity.get("render_3d", {}) is Dictionary else {}
	var is_gm := _is_gm_entity(entity)
	var is_character := _is_character_entity(entity)
	var kind := String(render_data.get("kind", ""))
	if kind.is_empty():
		if is_gm:
			kind = "gm"
		elif is_character:
			kind = "character"
		else:
			kind = String(entity.get("archetype", "object"))

	var size := _normalize_vector3_dict(render_data.get("size", entity.get("size", {})), _default_renderable_size(is_character, is_gm))
	var position := _normalize_vector3_dict(render_data.get("position", entity.get("position", {})), _default_renderable_position(entity_id, size, gravity))
	var physics := _extract_entity_physics(entity)
	var state := _extract_entity_state(entity)
	var renderable := {
		"id": String(entity.get("id", entity_id)),
		"name": String(entity.get("name", entity_id)),
		"kind": kind,
		"is_character": is_character,
		"is_gm": is_gm,
		"position": position,
		"size": size,
		"color": _resolve_renderable_color(entity, render_data, is_character, is_gm)
	}
	if not physics.is_empty():
		renderable["physics"] = physics
	if not state.is_empty():
		renderable["state"] = state
	return renderable


func _entity_is_three_d_renderable(entity: Dictionary) -> bool:
	return _is_character_entity(entity) or _is_gm_entity(entity) or Array(entity.get("tags", [])).has("object") or (entity.get("render_3d", {}) is Dictionary and not entity.get("render_3d", {}).is_empty())


func _is_character_entity(entity: Dictionary) -> bool:
	for tag_variant in entity.get("tags", []):
		var tag := String(tag_variant).to_lower()
		if CHARACTER_TAG_HINTS.has(tag):
			return true
	var archetype := String(entity.get("archetype", "")).to_lower()
	return CHARACTER_ARCHETYPE_HINTS.has(archetype)


func _is_gm_entity(entity: Dictionary) -> bool:
	for tag_variant in entity.get("tags", []):
		var tag := String(tag_variant).to_lower()
		if GM_TAG_HINTS.has(tag):
			return true
	var archetype := String(entity.get("archetype", "")).to_lower()
	return GM_ARCHETYPE_HINTS.has(archetype)


func _default_renderable_size(is_character: bool, is_gm: bool) -> Dictionary:
	if is_gm:
		return {"x": 1.1, "y": 2.2, "z": 1.1}
	if is_character:
		return {"x": 0.9, "y": 1.8, "z": 0.9}
	return {"x": 1.0, "y": 1.0, "z": 1.0}


func _default_renderable_position(entity_id: String, size: Dictionary, gravity: Dictionary) -> Dictionary:
	var floor_y := float(gravity.get("floor_y", DEFAULT_THREE_D_GRAVITY["floor_y"]))
	var contact_y := floor_y + (float(size.get("y", 1.0)) * 0.5)
	if entity_id == "origin_entity":
		return {"x": 0.0, "y": contact_y, "z": 0.0}
	return {"x": 0.0, "y": contact_y, "z": 0.0}


func _resolve_renderable_color(entity: Dictionary, render_data: Dictionary, is_character: bool, is_gm: bool) -> String:
	if render_data.has("color"):
		return String(render_data.get("color", "#9aa3b2"))
	if entity.has("color"):
		return String(entity.get("color", "#9aa3b2"))
	if is_gm:
		return "#f3c969"
	if is_character:
		return "#5b8cff"
	if Array(entity.get("tags", [])).has("structure"):
		return "#6f7984"
	return "#9a7b5f"


func _extract_entity_physics(entity: Dictionary) -> Dictionary:
	var components: Dictionary = entity.get("components", {})
	if components.has("physics") and components["physics"] is Dictionary:
		return components["physics"].duplicate(true)
	return {}


func _extract_entity_state(entity: Dictionary) -> Dictionary:
	var state: Dictionary = {}
	var top_level_state: Variant = entity.get("state", {})
	if top_level_state is Dictionary:
		state = _merge_dictionaries(state, top_level_state)
	var components: Dictionary = entity.get("components", {})
	var component_state: Variant = components.get("state", {})
	if component_state is Dictionary:
		state = _merge_dictionaries(state, component_state)
	return state


func _apply_world_state_merge_action(action: Dictionary) -> void:
	var path := String(action.get("path", "")).strip_edges()
	var value: Variant = action.get("value", {})
	if path.is_empty():
		if value is Dictionary:
			_world_state = _merge_dictionaries(_world_state, value)
		return
	_world_state = _merge_value_at_path(_world_state, path.split("."), value)


func _merge_value_at_path(container: Dictionary, path_segments: PackedStringArray, value: Variant, index: int = 0) -> Dictionary:
	var merged_container := container.duplicate(true)
	if index >= path_segments.size():
		return merged_container

	var key := String(path_segments[index]).strip_edges()
	if key.is_empty():
		return merged_container

	if index == path_segments.size() - 1:
		if value is Dictionary and merged_container.get(key, {}) is Dictionary:
			merged_container[key] = _merge_dictionaries(merged_container.get(key, {}), value)
		elif value is Dictionary:
			merged_container[key] = value.duplicate(true)
		elif value is Array:
			merged_container[key] = value.duplicate(true)
		else:
			merged_container[key] = value
		return merged_container

	var nested_value: Variant = merged_container.get(key, {})
	var nested_container: Dictionary = nested_value.duplicate(true) if nested_value is Dictionary else {}
	merged_container[key] = _merge_value_at_path(nested_container, path_segments, value, index + 1)
	return merged_container


func _build_rule_operation_index(rule_operations: Array) -> Dictionary:
	var indexed: Dictionary = {}
	for rule_operation_variant in rule_operations:
		if not (rule_operation_variant is Dictionary):
			continue
		var rule_operation: Dictionary = rule_operation_variant
		var rule_id := String(rule_operation.get("rule_id", "")).strip_edges()
		if rule_id.is_empty():
			continue
		indexed[rule_id] = _duplicate_dictionary(rule_operation)
	return indexed


func _relation_allows_event(relations: Array, target_rule_id: String, context: Dictionary) -> bool:
	var matching_relations: Array = []
	for relation_variant in relations:
		if not (relation_variant is Dictionary):
			continue
		var relation: Dictionary = relation_variant
		if String(relation.get("target", "")).strip_edges() == target_rule_id:
			matching_relations.append(relation)
	if matching_relations.is_empty():
		return true

	var context_entity_id := String(context.get("entity_id", "")).strip_edges()
	for relation_variant in matching_relations:
		var relation: Dictionary = relation_variant
		var source := String(relation.get("source", "")).strip_edges().to_lower()
		if source in ["world.active", "world.current", "scene.current"]:
			return true
		if not context_entity_id.is_empty() and source == context_entity_id.to_lower():
			return true
	return false


func _dispatch_runtime_rule_operation(package_id: String, rule_id: String, rule_operation: Dictionary, context: Dictionary) -> Dictionary:
	match String(rule_operation.get("rule_type", "")).strip_edges().to_lower():
		"event_visual_effect", "visual_effect":
			return _execute_event_visual_effect_rule(package_id, rule_id, rule_operation, context)
		_:
			return {"effect_ids": [], "triggered_effect_count": 0}


func _execute_event_visual_effect_rule(package_id: String, rule_id: String, rule_operation: Dictionary, context: Dictionary) -> Dictionary:
	var effect_ids: Array = []
	for effect_variant in Array(rule_operation.get("effects", [])):
		if not (effect_variant is Dictionary):
			continue
		var effect: Dictionary = effect_variant
		var effect_type := String(effect.get("effect_type", "")).strip_edges().to_lower()
		if effect_type not in ["spawn_visual", "spawn_visual_effect", "visual_spawn"]:
			continue
		var effect_id := _spawn_visual_effect(
			String(effect.get("tag", "runtime_effect")),
			effect.get("value", ""),
			package_id,
			rule_id,
			context
		)
		if not effect_id.is_empty():
			_append_unique_string(effect_ids, effect_id)
	return {
		"effect_ids": effect_ids.duplicate(true),
		"triggered_effect_count": effect_ids.size()
	}


func _spawn_visual_effect(tag: String, descriptor: Variant, package_id: String, rule_id: String, context: Dictionary) -> String:
	var entities: Dictionary = _world_state.get("entities", {})
	var anchor_entity_id := _resolve_visual_effect_anchor_entity_id(entities, context)
	var anchor_entity: Dictionary = entities.get(anchor_entity_id, {})
	var anchor_position := _normalize_vector3_dict(anchor_entity.get("position", {}), {"x": 0.0, "y": 1.2, "z": 0.0})
	anchor_position["y"] = float(anchor_position.get("y", 1.2)) + 1.4

	var duration_seconds := 1.25
	var effect_number := Array(_world_state.get("visual_effects", [])).size() + 1
	var normalized_tag := tag.strip_edges().to_lower()
	if normalized_tag.is_empty():
		normalized_tag = "runtime_effect"
	var effect_id := "fx_%d_%d" % [int(_world_state.get("tick_index", 0)), effect_number]
	var effect_entry := {
		"id": effect_id,
		"tag": normalized_tag,
		"descriptor": str(descriptor),
		"package_id": package_id,
		"rule_id": rule_id,
		"anchor_entity_id": anchor_entity_id,
		"position": anchor_position,
		"duration_seconds": duration_seconds,
		"remaining_seconds": duration_seconds,
		"color": "#ff7a45",
		"accent_color": "#ffe082"
	}
	var visual_effects: Array = Array(_world_state.get("visual_effects", []))
	visual_effects.append(effect_entry)
	_world_state["visual_effects"] = visual_effects
	return effect_id


func _resolve_visual_effect_anchor_entity_id(entities: Dictionary, context: Dictionary) -> String:
	var context_entity_id := String(context.get("entity_id", "")).strip_edges()
	if not context_entity_id.is_empty() and entities.has(context_entity_id):
		return context_entity_id
	if entities.has("origin_entity"):
		return "origin_entity"
	var entity_ids: Array = entities.keys()
	entity_ids.sort()
	return String(entity_ids[0]) if not entity_ids.is_empty() else ""


func _update_visual_effects(step_seconds: float) -> void:
	var next_effects: Array = []
	for effect_variant in Array(_world_state.get("visual_effects", [])):
		if not (effect_variant is Dictionary):
			continue
		var effect: Dictionary = effect_variant.duplicate(true)
		var remaining_seconds: float = max(float(effect.get("remaining_seconds", effect.get("duration_seconds", 0.0))) - step_seconds, 0.0)
		effect["remaining_seconds"] = snappedf(remaining_seconds, 0.0001)
		if remaining_seconds > 0.0:
			next_effects.append(effect)
	_world_state["visual_effects"] = next_effects


func _build_visual_effects_snapshot(raw_effects: Array) -> Array:
	var snapshot_effects: Array = []
	for effect_variant in raw_effects:
		if not (effect_variant is Dictionary):
			continue
		var effect: Dictionary = effect_variant.duplicate(true)
		var duration_seconds: float = max(float(effect.get("duration_seconds", 0.0)), 0.001)
		var remaining_seconds: float = clamp(float(effect.get("remaining_seconds", duration_seconds)), 0.0, duration_seconds)
		effect["duration_seconds"] = duration_seconds
		effect["remaining_seconds"] = remaining_seconds
		effect["life_ratio"] = clamp(1.0 - (remaining_seconds / duration_seconds), 0.0, 1.0)
		effect["position"] = _normalize_vector3_dict(effect.get("position", {}), {"x": 0.0, "y": 1.2, "z": 0.0})
		snapshot_effects.append(effect)
	return snapshot_effects


func _apply_gravity(entities: Dictionary, step_seconds: float) -> void:
	var preview_state: Dictionary = _world_state.get("preview_3d", {})
	var gravity := _normalize_preview_gravity(preview_state.get("gravity", {}), bool(preview_state.get("enabled", false)))
	if not bool(gravity.get("enabled", false)):
		return

	var acceleration := float(gravity.get("acceleration", DEFAULT_THREE_D_GRAVITY["acceleration"]))
	var floor_y := float(gravity.get("floor_y", DEFAULT_THREE_D_GRAVITY["floor_y"]))
	var entity_ids: Array = entities.keys()
	entity_ids.sort()

	for entity_id in entity_ids:
		var entity: Dictionary = entities[entity_id]
		var components: Dictionary = entity.get("components", {})
		var physics_value: Variant = components.get("physics", {})
		if not (physics_value is Dictionary):
			continue
		var physics: Dictionary = physics_value
		if not bool(physics.get("dynamic", false)):
			continue

		var position := _normalize_vector3_dict(entity.get("position", {}), {"x": 0.0, "y": floor_y + 0.5, "z": 0.0})
		var render_data: Dictionary = entity.get("render_3d", {}).duplicate(true) if entity.get("render_3d", {}) is Dictionary else {}
		var size := _normalize_vector3_dict(render_data.get("size", entity.get("size", {})), _default_renderable_size(_is_character_entity(entity), _is_gm_entity(entity)))
		var velocity := _normalize_vector3_dict(physics.get("velocity", {}), {"x": 0.0, "y": 0.0, "z": 0.0})
		var gravity_scale: float = max(0.0, float(physics.get("gravity_scale", 1.0)))
		var floor_offset_y := float(physics.get("floor_offset_y", float(size.get("y", 1.0)) * 0.5))
		var target_floor_y := floor_y + floor_offset_y
		var was_grounded := bool(physics.get("grounded", false))

		velocity["y"] = float(velocity.get("y", 0.0)) - (acceleration * gravity_scale * step_seconds)
		position["y"] = float(position.get("y", target_floor_y)) + (float(velocity.get("y", 0.0)) * step_seconds)

		var is_grounded := false
		if float(position.get("y", target_floor_y)) <= target_floor_y:
			position["y"] = target_floor_y
			velocity["y"] = 0.0
			is_grounded = true

		position["y"] = snappedf(float(position.get("y", target_floor_y)), 0.0001)
		velocity["y"] = snappedf(float(velocity.get("y", 0.0)), 0.0001)
		physics["velocity"] = velocity
		physics["grounded"] = is_grounded
		components["physics"] = physics
		entity["components"] = components
		entity["position"] = position
		entities[entity_id] = entity

		if is_grounded and not was_grounded:
			_append_event("gravity_landed", "プレビュー床に '%s' が着地しました。" % String(entity.get("name", entity_id)), {"entity_id": entity_id, "floor_y": target_floor_y})


func _normalize_vector3_dict(raw_value: Variant, default_value: Dictionary) -> Dictionary:
	var normalized := default_value.duplicate(true)
	if raw_value is Dictionary:
		for axis in ["x", "y", "z"]:
			if raw_value.has(axis):
				normalized[axis] = float(raw_value.get(axis, default_value.get(axis, 0.0)))
	return normalized


func _build_character_list(entities: Dictionary) -> Array:
	var characters: Array = []
	var entity_ids: Array = entities.keys()
	entity_ids.sort()

	for entity_id in entity_ids:
		var entity: Dictionary = entities[entity_id]
		var entity_tags: Array = entity.get("tags", [])
		if not entity_tags.has("mortal"):
			continue
		var components: Dictionary = entity.get("components", {})
		var needs: Dictionary = components.get("needs", {})
		var stats: Dictionary = components.get("stats", {})
		var traits: Dictionary = components.get("traits", {})
		var behavior: Dictionary = components.get("behavior", {})

		characters.append({
			"id": entity.get("id", entity_id),
			"name": entity.get("name", entity_id),
			"hunger": needs.get("hunger", 0.0),
			"health": stats.get("health", 100.0),
			"energy": max(0.0, 100.0 - float(needs.get("sleep", 0.0))),
			"morale": traits.get("morale", 50.0),
			"focus": traits.get("focus", 50.0),
			"current_task": behavior.get("current_task", "次の世界ルールを待機中")
		})

	return characters


func _build_object_list(entities: Dictionary) -> Array:
	var objects: Array = []
	var entity_ids: Array = entities.keys()
	entity_ids.sort()

	for entity_id in entity_ids:
		var entity: Dictionary = entities[entity_id]
		var entity_tags: Array = entity.get("tags", [])
		if not entity_tags.has("object"):
			continue
		var components: Dictionary = entity.get("components", {})
		var ownership: Dictionary = components.get("ownership", {})
		objects.append({
			"id": entity.get("id", entity_id),
			"name": entity.get("name", entity_id),
			"material": entity.get("material", ""),
			"weight": entity.get("weight", 0.0),
			"position": entity.get("position", {}).duplicate(true) if entity.get("position", {}) is Dictionary else entity.get("position", {}),
			"portability": entity.get("portability", {}).duplicate(true) if entity.get("portability", {}) is Dictionary else entity.get("portability", {}),
			"state": entity.get("state", {}).duplicate(true) if entity.get("state", {}) is Dictionary else entity.get("state", {}),
			"owner": ownership.duplicate(true) if ownership is Dictionary else entity.get("owner", null)
		})
	return objects


func _build_rule_tree(installed_rules_by_id: Dictionary) -> Dictionary:
	var rule_ids: Array = installed_rules_by_id.keys()
	rule_ids.sort()
	var nodes_by_rule_id: Dictionary = {}
	var root_rule_ids: Array = []

	for rule_id in rule_ids:
		var rule: Dictionary = installed_rules_by_id[rule_id]
		nodes_by_rule_id[rule_id] = {
			"rule_id": rule_id,
			"name": rule.get("name", rule_id),
			"requires_rule_kinds": rule.get("requires_rule_kinds", []).duplicate(true),
			"provides_rule_kinds": rule.get("provides_rule_kinds", []).duplicate(true),
			"resolved_parent_rule_ids": rule.get("resolved_parent_rule_ids", []).duplicate(true),
			"missing_required_rule_kinds": rule.get("missing_required_rule_kinds", []).duplicate(true),
			"blocked": bool(rule.get("blocked", false)),
			"inactive": bool(rule.get("inactive", false)),
			"dependency_status": String(rule.get("dependency_status", "active")),
			"child_rule_ids": []
		}

	for rule_id in rule_ids:
		var parent_rule_ids: Array = installed_rules_by_id[rule_id].get("resolved_parent_rule_ids", [])
		if parent_rule_ids.is_empty():
			root_rule_ids.append(rule_id)
		for parent_rule_id in parent_rule_ids:
			if not nodes_by_rule_id.has(parent_rule_id):
				continue
			var parent_node: Dictionary = nodes_by_rule_id[parent_rule_id]
			var child_rule_ids: Array = parent_node.get("child_rule_ids", [])
			if not child_rule_ids.has(rule_id):
				child_rule_ids.append(rule_id)
				child_rule_ids.sort()
			parent_node["child_rule_ids"] = child_rule_ids
			nodes_by_rule_id[parent_rule_id] = parent_node

	root_rule_ids.sort()
	var roots: Array = []
	for root_rule_id in root_rule_ids:
		roots.append(_build_rule_tree_node(root_rule_id, nodes_by_rule_id, []))

	return {
		"root_rule_ids": root_rule_ids,
		"nodes_by_rule_id": nodes_by_rule_id,
		"roots": roots
	}


func _build_rule_dependency_status(installed_rules_by_id: Dictionary) -> Dictionary:
	var unresolved_rule_ids: Array = []
	var blocked_rule_ids: Array = []
	var inactive_rule_ids: Array = []
	var provided_rule_kinds: Array = []
	var missing_required_rule_kinds_by_rule_id: Dictionary = {}
	var rule_ids: Array = installed_rules_by_id.keys()
	rule_ids.sort()

	for rule_id in rule_ids:
		var rule: Dictionary = installed_rules_by_id[rule_id]
		for provided_kind_variant in rule.get("provides_rule_kinds", []):
			var provided_kind := String(provided_kind_variant).strip_edges()
			if not provided_kind.is_empty() and not provided_rule_kinds.has(provided_kind):
				provided_rule_kinds.append(provided_kind)
		var missing_required_rule_kinds: Array = rule.get("missing_required_rule_kinds", [])
		if not missing_required_rule_kinds.is_empty():
			unresolved_rule_ids.append(rule_id)
			missing_required_rule_kinds_by_rule_id[rule_id] = missing_required_rule_kinds.duplicate(true)
		if bool(rule.get("blocked", false)):
			blocked_rule_ids.append(rule_id)
		if bool(rule.get("inactive", false)):
			inactive_rule_ids.append(rule_id)

	provided_rule_kinds.sort()
	return {
		"provided_rule_kinds": provided_rule_kinds,
		"unresolved_rule_ids": unresolved_rule_ids,
		"blocked_rule_ids": blocked_rule_ids,
		"inactive_rule_ids": inactive_rule_ids,
		"missing_required_rule_kinds_by_rule_id": missing_required_rule_kinds_by_rule_id
	}


func _build_rule_tree_node(rule_id: String, nodes_by_rule_id: Dictionary, ancestry: Array) -> Dictionary:
	var node: Dictionary = nodes_by_rule_id.get(rule_id, {}).duplicate(true)
	if ancestry.has(rule_id):
		node["children"] = []
		return node

	var next_ancestry := ancestry.duplicate(true)
	next_ancestry.append(rule_id)
	var children: Array = []
	for child_rule_id in node.get("child_rule_ids", []):
		children.append(_build_rule_tree_node(String(child_rule_id), nodes_by_rule_id, next_ancestry))
	node["children"] = children
	return node


func _build_event_messages(event_log: Array) -> Array:
	var messages: Array = []
	for event in event_log:
		if event is Dictionary:
			messages.append(String(event.get("message", event.get("type", "event"))))
		else:
			messages.append(String(event))
	return messages


func _make_unique_rule_id(base_id: String) -> String:
	var installed_rules: Dictionary = _world_state.get("installed_rules", {})
	var candidate := base_id
	while installed_rules.has(candidate):
		_clone_sequence += 1
		candidate = "%s_%d" % [base_id, _clone_sequence]
	return candidate


func _extract_rule_array_metadata(rule: Dictionary, key: String) -> Array:
	if rule.has(key) and rule[key] is Array:
		return rule[key]
	var metadata: Dictionary = rule.get("metadata", {})
	if metadata.has(key) and metadata[key] is Array:
		return metadata[key]
	return []


func _normalize_string_array(values: Array) -> Array:
	var normalized: Array = []
	for value in values:
		var normalized_value := String(value).strip_edges()
		if normalized_value.is_empty() or normalized.has(normalized_value):
			continue
		normalized.append(normalized_value)
	return normalized


func _append_unique_string(target: Array, value: String) -> void:
	var normalized_value := value.strip_edges()
	if normalized_value.is_empty() or target.has(normalized_value):
		return
	target.append(normalized_value)


func _filter_applied_operations(operations: Array, deferred_operations: Array) -> Array:
	if deferred_operations.is_empty():
		return operations.duplicate(true)

	var deferred_counts: Dictionary = {}
	for deferred_operation_variant in deferred_operations:
		var deferred_signature := _operation_signature(deferred_operation_variant)
		if deferred_signature.is_empty():
			continue
		deferred_counts[deferred_signature] = int(deferred_counts.get(deferred_signature, 0)) + 1

	var applied_operations: Array = []
	for operation_variant in operations:
		var signature := _operation_signature(operation_variant)
		if signature.is_empty():
			continue
		var remaining_deferred := int(deferred_counts.get(signature, 0))
		if remaining_deferred > 0:
			deferred_counts[signature] = remaining_deferred - 1
			continue
		if operation_variant is Dictionary:
			applied_operations.append(operation_variant.duplicate(true))
	return applied_operations


func _operation_signature(operation_variant: Variant) -> String:
	if not (operation_variant is Dictionary):
		return ""
	return JSON.stringify(operation_variant)


func _normalize_install_actions(raw_actions: Array) -> Array:
	var normalized_actions: Array = []
	for raw_action in raw_actions:
		if not raw_action is Dictionary:
			continue
		var action: Dictionary = raw_action.duplicate(true)
		action["op"] = String(action.get("op", ""))
		var normalized_entities: Array = []
		for raw_entity in action.get("entities", []):
			if raw_entity is Dictionary:
				normalized_entities.append(raw_entity.duplicate(true))
		action["entities"] = normalized_entities
		if not String(action.get("op", "")).is_empty():
			normalized_actions.append(action)
	return normalized_actions


func _duplicate_array(raw_value: Variant) -> Array:
	var duplicated: Array = []
	if not (raw_value is Array):
		return duplicated

	for item in raw_value:
		if item is Dictionary:
			duplicated.append(item.duplicate(true))
		elif item is Array:
			duplicated.append(item.duplicate(true))
		else:
			duplicated.append(item)
	return duplicated


func _normalize_entity(entity: Dictionary) -> Dictionary:
	var normalized_entity := entity.duplicate(true)
	var entity_id := String(normalized_entity.get("id", ""))
	if entity_id.is_empty():
		return {}

	normalized_entity["id"] = entity_id
	normalized_entity["name"] = String(normalized_entity.get("name", entity_id))
	normalized_entity["archetype"] = String(normalized_entity.get("archetype", "entity"))
	normalized_entity["tags"] = _normalize_string_array(normalized_entity.get("tags", []))
	var components: Dictionary = normalized_entity.get("components", {}).duplicate(true) if normalized_entity.get("components", {}) is Dictionary else {}
	if components.has("physics") and components["physics"] is Dictionary:
		var physics: Dictionary = components["physics"].duplicate(true)
		physics["dynamic"] = bool(physics.get("dynamic", false))
		physics["grounded"] = bool(physics.get("grounded", false))
		physics["gravity_scale"] = float(physics.get("gravity_scale", 1.0))
		physics["velocity"] = _normalize_vector3_dict(physics.get("velocity", {}), {"x": 0.0, "y": 0.0, "z": 0.0})
		if physics.has("floor_offset_y"):
			physics["floor_offset_y"] = float(physics.get("floor_offset_y", 0.0))
		components["physics"] = physics
	for component_name in ["needs", "stats", "traits", "behavior"]:
		if not components.has(component_name) or not (components[component_name] is Dictionary):
			components[component_name] = {}
	normalized_entity["components"] = components
	if normalized_entity.has("position") and normalized_entity["position"] is Dictionary:
		var position_data: Dictionary = normalized_entity["position"].duplicate(true)
		var normalized_position := _normalize_vector3_dict(position_data, {"x": 0.0, "y": 0.0, "z": 0.0})
		for key in position_data.keys():
			if not normalized_position.has(key):
				normalized_position[key] = position_data[key]
		normalized_entity["position"] = normalized_position
	if normalized_entity.has("render_3d") and normalized_entity["render_3d"] is Dictionary:
		var render_data: Dictionary = normalized_entity["render_3d"].duplicate(true)
		if render_data.has("position") and render_data["position"] is Dictionary:
			render_data["position"] = _normalize_vector3_dict(render_data["position"], {"x": 0.0, "y": 0.0, "z": 0.0})
		if render_data.has("size") and render_data["size"] is Dictionary:
			render_data["size"] = _normalize_vector3_dict(render_data["size"], {"x": 1.0, "y": 1.0, "z": 1.0})
		if render_data.has("color"):
			render_data["color"] = String(render_data.get("color", "#9aa3b2"))
		normalized_entity["render_3d"] = render_data
	return normalized_entity


func _merge_dictionaries(base_value: Dictionary, patch_value: Dictionary) -> Dictionary:
	var merged := base_value.duplicate(true)
	for key in patch_value.keys():
		var incoming = patch_value[key]
		if merged.has(key) and merged[key] is Dictionary and incoming is Dictionary:
			merged[key] = _merge_dictionaries(merged[key], incoming)
		else:
			if incoming is Dictionary:
				merged[key] = incoming.duplicate(true)
			elif incoming is Array:
				merged[key] = incoming.duplicate(true)
			else:
				merged[key] = incoming
	return merged
