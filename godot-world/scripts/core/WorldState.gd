extends Node

const SimulationRuntimeScript = preload("res://scripts/core/SimulationRuntime.gd")
const RulePackageRepositoryScript = preload("res://scripts/integration/rule_package_repository.gd")
const RuleCompilerScript = preload("res://scripts/integration/rule_compiler.gd")
const RuntimeRulePatchCompilerScript = preload("res://scripts/integration/runtime_rule_patch_compiler.gd")
const RULE_PACKAGE_SCHEMA_VERSION := "rule_package_v1"

var _runtime = null
var _rule_package_repository = null
var _rule_compiler = null
var _runtime_rule_patch_compiler = null
var _available_rule_packages: Array = []
var _available_templates: Array = []


func _ready() -> void:
	_reset_world()


func submit_player_task(task_text: String) -> Dictionary:
	_ensure_runtime()
	var normalized_task := task_text.strip_edges()
	if normalized_task.is_empty():
		return {
			"status": "error",
			"task_text": task_text,
			"proposals": [],
			"message": "Task text was empty."
		}

	var resolution: Dictionary = _rule_compiler.resolve_player_task({
		"title": normalized_task,
		"prompt": normalized_task
	})
	var result: Dictionary = resolution.duplicate(true)
	result["task_text"] = task_text
	result["proposals"] = _build_task_proposals(result)

	match String(result.get("resolution", "")):
		"clone_candidate":
			result["status"] = "proposal_ready"
			result["message"] = "Matched reusable rule packages."
		"draft_custom_rule_patch":
			result["status"] = "needs_rule_patch"
			result["message"] = "No strong package match. Review the generated rule package draft."
		_:
			result["status"] = "error"
			result["message"] = "Could not resolve task to a rule package."

	_runtime.record_player_task(result)
	return result


func clone_rule(rule_id: String) -> Dictionary:
	_ensure_runtime()
	return _runtime.clone_rule(rule_id)


func create_rule_from_patch(rule_patch: Dictionary) -> Dictionary:
	_ensure_runtime()
	var rule_package := _resolve_rule_package(rule_patch)
	if not rule_package.is_empty():
		return _install_rule_package(rule_package)
	return _runtime.create_rule_from_patch(rule_patch)


func review_rule_package_proposal(rule_package: Dictionary) -> Dictionary:
	_ensure_runtime()
	if rule_package.is_empty():
		return {
			"status": "error",
			"message": "Rule package was empty."
		}

	var missing_keys := _find_missing_rule_package_keys(rule_package)
	if not missing_keys.is_empty():
		return {
			"status": "error",
			"message": "Rule package is missing required fields.",
			"missing_keys": missing_keys,
			"rule_package": rule_package.duplicate(true)
		}

	if String(rule_package.get("schema_version", "")) != RULE_PACKAGE_SCHEMA_VERSION:
		return {
			"status": "error",
			"message": "Unsupported rule package schema version '%s'." % String(rule_package.get("schema_version", "")),
			"rule_package": rule_package.duplicate(true)
		}

	var patch = rule_package.get("patch", {})
	if not (patch is Dictionary):
		return {
			"status": "error",
			"message": "Rule package patch must be a dictionary.",
			"rule_package": rule_package.duplicate(true)
		}

	var operations = patch.get("operations", [])
	if not (operations is Array):
		return {
			"status": "error",
			"message": "Rule package patch operations must be an array.",
			"rule_package": rule_package.duplicate(true)
		}

	var compilation: Dictionary = _runtime_rule_patch_compiler.compile_package(rule_package)
	if String(compilation.get("status", "")) != "compiled":
		var error_result: Dictionary = compilation.duplicate(true)
		error_result["rule_package"] = rule_package.duplicate(true)
		return error_result

	var warnings: Array = []
	if operations.is_empty():
		warnings.append("Rule package has no operations to install.")
	if not bool(compilation.get("safe_to_apply_directly", false)):
		warnings.append("Some operations are deferred until the runtime supports them.")

	var review_status := String(patch.get("review_status", "draft"))
	return {
		"status": "ready_for_install" if review_status == "approved" else "needs_approval",
		"package_id": rule_package.get("package_id", ""),
		"display_name": rule_package.get("display_name", rule_package.get("package_id", "")),
		"review_status": review_status,
		"operation_count": operations.size(),
		"safe_to_apply_directly": bool(compilation.get("safe_to_apply_directly", false)),
		"deferred_operations": compilation.get("deferred_operations", []).duplicate(true),
		"compiled_runtime_patch": compilation.get("runtime_patch", {}).duplicate(true),
		"forked_from": rule_package.get("forked_from", null),
		"suggested_pr_target": rule_package.get("suggested_pr_target", null),
		"warnings": warnings,
		"rule_package": rule_package.duplicate(true)
	}


func get_world_snapshot() -> Dictionary:
	_ensure_runtime()
	var snapshot: Dictionary = _runtime.get_snapshot()
	snapshot["available_rule_packages"] = get_available_rule_packages()
	return snapshot


func save_world_snapshot(file_path: String = "user://world_snapshot.json") -> Dictionary:
	_ensure_runtime()
	var resolved_path := _resolve_snapshot_path(file_path)
	if resolved_path.is_empty():
		return _snapshot_error("Snapshot path cannot be empty.")

	var directory_path := resolved_path.get_base_dir()
	if not directory_path.is_empty():
		var make_directory_result := DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(directory_path))
		if make_directory_result != OK:
			return _snapshot_error("Failed to create snapshot directory.", {
				"path": resolved_path,
				"error_code": make_directory_result
			})

	var snapshot := get_world_snapshot()
	var file := FileAccess.open(resolved_path, FileAccess.WRITE)
	if file == null:
		return _snapshot_error("Failed to open snapshot file for writing.", {
			"path": resolved_path,
			"error_code": FileAccess.get_open_error()
		})

	file.store_string(JSON.stringify(snapshot, "\t"))
	file.close()
	return {
		"status": "saved",
		"path": resolved_path,
		"snapshot": snapshot
	}


func load_world_snapshot(file_path: String = "user://world_snapshot.json") -> Dictionary:
	_ensure_runtime()
	var resolved_path := _resolve_snapshot_path(file_path)
	if resolved_path.is_empty():
		return _snapshot_error("Snapshot path cannot be empty.")
	if not FileAccess.file_exists(resolved_path):
		return _snapshot_error("Snapshot file does not exist.", {"path": resolved_path})

	var file := FileAccess.open(resolved_path, FileAccess.READ)
	if file == null:
		return _snapshot_error("Failed to open snapshot file for reading.", {
			"path": resolved_path,
			"error_code": FileAccess.get_open_error()
		})

	var parser := JSON.new()
	var parse_result := parser.parse(file.get_as_text())
	file.close()
	if parse_result != OK:
		return _snapshot_error("Failed to parse snapshot JSON.", {
			"path": resolved_path,
			"error_code": parse_result,
			"line": parser.get_error_line(),
			"details": parser.get_error_message()
		})
	if not parser.data is Dictionary:
		return _snapshot_error("Snapshot JSON must decode to a dictionary.", {"path": resolved_path})

	var restored_result := restore_world_snapshot(parser.data)
	if restored_result.get("status", "") == "error":
		restored_result["path"] = resolved_path
		return restored_result

	restored_result["status"] = "loaded"
	restored_result["path"] = resolved_path
	return restored_result


func restore_world_snapshot(snapshot: Dictionary) -> Dictionary:
	_ensure_runtime()
	return _runtime.restore_snapshot(snapshot)


func get_available_rule_packages() -> Array:
	_ensure_runtime()
	var packages: Array = []
	for package_summary in _available_rule_packages:
		packages.append(package_summary.duplicate(true))
	return packages


func get_available_rule_templates() -> Array:
	_ensure_runtime()
	var templates: Array = []
	for template in _available_templates:
		templates.append(template.duplicate(true))
	return templates


func advance_tick(delta_seconds: float) -> void:
	_ensure_runtime()
	_runtime.advance_tick(delta_seconds)


func _reset_world() -> void:
	var rule_package_repository_script = load("res://scripts/integration/rule_package_repository.gd")
	var rule_compiler_script = load("res://scripts/integration/rule_compiler.gd")
	var runtime_rule_patch_compiler_script = load("res://scripts/integration/runtime_rule_patch_compiler.gd")
	var simulation_runtime_script = load("res://scripts/core/SimulationRuntime.gd")

	_rule_package_repository = rule_package_repository_script.new()
	_rule_compiler = rule_compiler_script.new()
	_rule_compiler.configure_repository(_rule_package_repository)
	_runtime_rule_patch_compiler = runtime_rule_patch_compiler_script.new()
	_available_rule_packages = _rule_compiler.list_available_rule_packages()
	_available_templates = _build_available_templates()
	_runtime = simulation_runtime_script.new(_available_templates)


func _ensure_runtime() -> void:
	if _runtime == null:
		_reset_world()


func _resolve_snapshot_path(file_path: String) -> String:
	var normalized_path := file_path.strip_edges()
	if normalized_path.is_empty():
		return ""
	if normalized_path.find("://") != -1 or normalized_path.find(":/") == 1 or normalized_path.begins_with("/"):
		return normalized_path
	return "user://%s" % normalized_path


func _snapshot_error(message: String, details: Dictionary = {}) -> Dictionary:
	var result := {
		"status": "error",
		"message": message
	}
	if not details.is_empty():
		result["details"] = details.duplicate(true)
	return result


func _resolve_rule_package(rule_patch: Dictionary) -> Dictionary:
	if _looks_like_rule_package(rule_patch):
		return rule_patch.duplicate(true)

	for key in ["package_id", "template_id"]:
		var candidate_id := String(rule_patch.get(key, "")).strip_edges()
		if candidate_id.is_empty():
			continue
		var package: Dictionary = _rule_package_repository.get_rule_package(candidate_id)
		if not package.is_empty():
			return package

	return {}


func _install_rule_package(rule_package: Dictionary) -> Dictionary:
	var compilation: Dictionary = _runtime_rule_patch_compiler.compile_package(rule_package)
	if String(compilation.get("status", "")) != "compiled":
		return compilation

	var runtime_result: Dictionary = _runtime.create_rule_from_patch(compilation.get("runtime_patch", {}))
	var install_result: Dictionary = runtime_result.duplicate(true)
	install_result["install_source"] = "rule_package"
	install_result["package_id"] = rule_package.get("package_id", "")
	install_result["source_repo"] = rule_package.get("source_repo", "")
	install_result["source_ref"] = rule_package.get("source_ref", "")
	install_result["forked_from"] = rule_package.get("forked_from", null)
	install_result["suggested_pr_target"] = rule_package.get("suggested_pr_target", null)
	install_result["safe_to_apply_directly"] = bool(compilation.get("safe_to_apply_directly", false))
	install_result["deferred_operations"] = compilation.get("deferred_operations", []).duplicate(true)
	install_result["compiled_runtime_patch"] = compilation.get("runtime_patch", {}).duplicate(true)
	return install_result


func _build_task_proposals(resolution: Dictionary) -> Array:
	var proposals: Array = []
	match String(resolution.get("resolution", "")):
		"clone_candidate":
			var candidate = resolution.get("candidate", {})
			if candidate is Dictionary and not candidate.is_empty():
				proposals.append(_package_summary_to_proposal(candidate))
			for alternative in resolution.get("alternatives", []):
				if alternative is Dictionary:
					proposals.append(_package_summary_to_proposal(alternative))
		"draft_custom_rule_patch":
			var draft_package = resolution.get("draft_package", {})
			if draft_package is Dictionary and not draft_package.is_empty():
				var compilation: Dictionary = _runtime_rule_patch_compiler.compile_package(draft_package)
				proposals.append(_rule_package_to_template(draft_package, compilation))
	return proposals


func _build_available_templates() -> Array:
	var templates: Array = []
	for package_summary in _available_rule_packages:
		if not (package_summary is Dictionary):
			continue
		var package_id := String(package_summary.get("package_id", ""))
		if package_id.is_empty():
			continue
		var rule_package: Dictionary = _rule_package_repository.get_rule_package(package_id)
		if rule_package.is_empty():
			continue
		var compilation: Dictionary = _runtime_rule_patch_compiler.compile_package(rule_package)
		if String(compilation.get("status", "")) != "compiled":
			continue
		templates.append(_rule_package_to_template(rule_package, compilation))
	return templates


func _package_summary_to_template(package_summary: Dictionary) -> Dictionary:
	return {
		"id": package_summary.get("package_id", ""),
		"template_id": package_summary.get("package_id", ""),
		"package_id": package_summary.get("package_id", ""),
		"name": package_summary.get("display_name", package_summary.get("package_id", "")),
		"description": package_summary.get("description", ""),
		"summary": package_summary.get("description", ""),
		"version": package_summary.get("version", ""),
		"author": package_summary.get("author", ""),
		"source_repo": package_summary.get("source_repo", ""),
		"source_ref": package_summary.get("source_ref", ""),
		"forked_from": package_summary.get("forked_from", null),
		"suggested_pr_target": package_summary.get("suggested_pr_target", null),
		"tags": package_summary.get("tags", []).duplicate(true),
		"match_phrases": package_summary.get("match_phrases", []).duplicate(true),
		"community": package_summary.get("community", {}).duplicate(true)
	}


func _package_summary_to_proposal(package_summary: Dictionary) -> Dictionary:
	var package_id := String(package_summary.get("package_id", ""))
	if package_id.is_empty():
		return _package_summary_to_template(package_summary)

	var rule_package: Dictionary = _rule_package_repository.get_rule_package(package_id)
	if rule_package.is_empty():
		return _package_summary_to_template(package_summary)

	var compilation: Dictionary = _runtime_rule_patch_compiler.compile_package(rule_package)
	return _rule_package_to_template(rule_package, compilation)


func _rule_package_to_template(rule_package: Dictionary, compilation: Dictionary = {}, include_package_data: bool = true) -> Dictionary:
	var template := _package_summary_to_template({
		"package_id": rule_package.get("package_id", ""),
		"display_name": rule_package.get("display_name", rule_package.get("package_id", "")),
		"description": rule_package.get("description", ""),
		"version": rule_package.get("version", ""),
		"author": rule_package.get("author", ""),
		"source_repo": rule_package.get("source_repo", ""),
		"source_ref": rule_package.get("source_ref", ""),
		"forked_from": rule_package.get("forked_from", null),
		"suggested_pr_target": rule_package.get("suggested_pr_target", null),
		"tags": rule_package.get("tags", []),
		"match_phrases": rule_package.get("match_phrases", []),
		"community": rule_package.get("community", {})
	})

	if String(compilation.get("status", "")) == "compiled":
		template["rule_patch"] = compilation.get("runtime_patch", {}).duplicate(true)
		template["safe_to_apply_directly"] = bool(compilation.get("safe_to_apply_directly", false))
		template["deferred_operations"] = compilation.get("deferred_operations", []).duplicate(true)

	if include_package_data:
		template["rule_package"] = rule_package.duplicate(true)
	return template


func _looks_like_rule_package(candidate: Dictionary) -> bool:
	if String(candidate.get("schema_version", "")) != RULE_PACKAGE_SCHEMA_VERSION:
		return false
	return typeof(candidate.get("patch", {})) == TYPE_DICTIONARY


func _find_missing_rule_package_keys(rule_package: Dictionary) -> Array:
	var required_keys := [
		"schema_version",
		"package_id",
		"display_name",
		"description",
		"version",
		"author",
		"source_repo",
		"source_ref",
		"tags",
		"match_phrases",
		"community",
		"patch"
	]
	var missing_keys: Array = []
	for key in required_keys:
		if not rule_package.has(key):
			missing_keys.append(key)
	return missing_keys
