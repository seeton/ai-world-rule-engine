extends Node

const SimulationRuntimeScript = preload("res://scripts/core/SimulationRuntime.gd")
const RuleTemplatesScript = preload("res://scripts/core/RuleTemplates.gd")
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
        var review_result := review_rule_package_proposal(rule_package)
        if String(review_result.get("status", "")) == "error":
            return review_result
        if String(review_result.get("status", "")) != "ready_for_install":
            return review_result
        return _install_rule_package(review_result.get("rule_package", rule_package))
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

    var operations_result := _validate_rule_package_operations(patch.get("operations", []), rule_package)
    if String(operations_result.get("status", "")) == "error":
        return operations_result
    var operations: Array = operations_result.get("operations", [])

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


func get_available_rule_packages() -> Array:
    _ensure_runtime()
    var packages: Array = []
    for package_summary in _available_rule_packages:
        packages.append(package_summary.duplicate(true))
    return packages


func create_world_snapshot() -> Dictionary:
    _ensure_runtime()
    return _runtime.create_snapshot()


func restore_world_snapshot(snapshot_data: Dictionary) -> Dictionary:
    _ensure_runtime()
    return _runtime.restore_snapshot(snapshot_data)


func save_world_snapshot(file_path: String) -> Dictionary:
    _ensure_runtime()
    return _runtime.save_snapshot(file_path)


func load_world_snapshot(file_path: String) -> Dictionary:
    _ensure_runtime()
    return _runtime.load_snapshot(file_path)


func get_available_rule_templates() -> Array:
    _ensure_runtime()
    var templates: Array = []
    for template in _available_templates:
        templates.append(template.duplicate(true))
    return templates


func advance_tick(delta_seconds: float) -> void:
    _ensure_runtime()
    _runtime.advance_tick(delta_seconds)


func set_rule_enabled(rule_id: String, enabled: bool) -> Dictionary:
    _ensure_runtime()
    return _runtime.set_rule_enabled(rule_id, enabled)


func set_entity_position(entity_id: String, position_patch: Dictionary) -> Dictionary:
    _ensure_runtime()
    return _runtime.set_entity_position(entity_id, position_patch)


func seed_demo_rule_tree() -> Dictionary:
    _ensure_runtime()
    var demo_template_ids := [
        "three_d_preview_rule",
        "three_d_light_rule",
        "three_d_gravity_rule",
        "object_rule",
        "ownership_rule",
        "hunger"
    ]
    var installed_count := 0
    var skipped_count := 0
    var errors: Array = []
    for template_id in demo_template_ids:
        var result: Dictionary = _runtime.create_rule_from_patch({"template_id": template_id})
        var status := String(result.get("status", ""))
        if status == "installed":
            installed_count += 1
        elif status == "error" and String(result.get("message", "")).find("すでに導入") != -1:
            skipped_count += 1
        else:
            errors.append({"template_id": template_id, "result": result})
    return {
        "status": "ok" if errors.is_empty() else "partial",
        "installed": installed_count,
        "skipped": skipped_count,
        "errors": errors
    }


func _reset_world() -> void:
    _rule_package_repository = RulePackageRepositoryScript.new()
    _rule_compiler = RuleCompilerScript.new(_rule_package_repository)
    _runtime_rule_patch_compiler = RuntimeRulePatchCompilerScript.new()
    _available_rule_packages = _rule_compiler.list_available_rule_packages()
    _available_templates = RuleTemplatesScript.get_templates()
    _runtime = SimulationRuntimeScript.new(_available_templates)


func _ensure_runtime() -> void:
    if _runtime == null:
        _reset_world()
        return

    var refreshed_rule_packages := false
    if _rule_package_repository == null:
        _rule_package_repository = RulePackageRepositoryScript.new()
        refreshed_rule_packages = true
    if _rule_compiler == null or _rule_compiler.get("_repository") != _rule_package_repository:
        _rule_compiler = RuleCompilerScript.new(_rule_package_repository)
        refreshed_rule_packages = true
    if _runtime_rule_patch_compiler == null:
        _runtime_rule_patch_compiler = RuntimeRulePatchCompilerScript.new()
    if refreshed_rule_packages or _available_rule_packages.is_empty():
        _available_rule_packages = _rule_compiler.list_available_rule_packages()
    if _available_templates.is_empty():
        _available_templates = RuleTemplatesScript.get_templates()


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
                proposals.append(_rule_package_to_proposal(draft_package, compilation))
    return proposals


func _package_summary_to_proposal(package_summary: Dictionary) -> Dictionary:
    var package_id := String(package_summary.get("package_id", ""))
    if package_id.is_empty():
        return package_summary.duplicate(true)

    var rule_package: Dictionary = _rule_package_repository.get_rule_package(package_id)
    if rule_package.is_empty():
        return package_summary.duplicate(true)

    var compilation: Dictionary = _runtime_rule_patch_compiler.compile_package(rule_package)
    return _rule_package_to_proposal(rule_package, compilation)


func _rule_package_to_proposal(rule_package: Dictionary, compilation: Dictionary = {}) -> Dictionary:
    var proposal := {
        "package_id": rule_package.get("package_id", ""),
        "display_name": rule_package.get("display_name", rule_package.get("package_id", "")),
        "description": rule_package.get("description", ""),
        "version": rule_package.get("version", ""),
        "author": rule_package.get("author", ""),
        "source_repo": rule_package.get("source_repo", ""),
        "source_ref": rule_package.get("source_ref", ""),
        "forked_from": rule_package.get("forked_from", null),
        "suggested_pr_target": rule_package.get("suggested_pr_target", null),
        "tags": rule_package.get("tags", []).duplicate(true),
        "match_phrases": rule_package.get("match_phrases", []).duplicate(true),
        "community": rule_package.get("community", {}).duplicate(true),
        "rule_package": rule_package.duplicate(true),
        "review_status": rule_package.get("patch", {}).get("review_status", "draft")
    }

    if String(compilation.get("status", "")) == "compiled":
        proposal["rule_patch"] = compilation.get("runtime_patch", {}).duplicate(true)
        proposal["compiled_runtime_patch"] = compilation.get("runtime_patch", {}).duplicate(true)
        proposal["safe_to_apply_directly"] = bool(compilation.get("safe_to_apply_directly", false))
        proposal["deferred_operations"] = compilation.get("deferred_operations", []).duplicate(true)

    return proposal


func _looks_like_rule_package(candidate: Dictionary) -> bool:
    if String(candidate.get("schema_version", "")) != RULE_PACKAGE_SCHEMA_VERSION:
        return false
    if typeof(candidate.get("patch", {})) != TYPE_DICTIONARY:
        return false
    return _find_missing_rule_package_keys(candidate).is_empty()


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


func _validate_rule_package_operations(operations_variant: Variant, rule_package: Dictionary) -> Dictionary:
    if not (operations_variant is Array):
        return {
            "status": "error",
            "message": "Rule package patch operations must be an array.",
            "rule_package": rule_package.duplicate(true)
        }

    var operations: Array = operations_variant
    for operation_index in range(operations.size()):
        var operation_variant = operations[operation_index]
        if not (operation_variant is Dictionary):
            return {
                "status": "error",
                "message": "Rule package patch.operations[%d] must be a dictionary." % operation_index,
                "rule_package": rule_package.duplicate(true)
            }

        var operation: Dictionary = operation_variant
        if String(operation.get("op", "")).strip_edges().is_empty():
            return {
                "status": "error",
                "message": "Rule package patch.operations[%d] must include a non-empty op." % operation_index,
                "rule_package": rule_package.duplicate(true)
            }

    return {
        "status": "ok",
        "operations": operations
    }
