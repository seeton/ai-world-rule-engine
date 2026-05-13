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
    var dependency_resolution := _resolve_rule_package_dependencies(rule_package)
    if String(dependency_resolution.get("status", "")) == "error":
        return dependency_resolution

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
        "package_dependencies": dependency_resolution.get("package_dependencies", []).duplicate(true),
        "safe_to_apply_directly": bool(compilation.get("safe_to_apply_directly", false)),
        "deferred_operations": compilation.get("deferred_operations", []).duplicate(true),
        "compiled_runtime_patch": compilation.get("runtime_patch", {}).duplicate(true),
        "compiled_runtime_rules": _extract_compiled_runtime_rules(compilation),
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


func set_entity_position(entity_id: String, position_patch: Dictionary) -> Dictionary:
    _ensure_runtime()
    return _runtime.set_entity_position(entity_id, position_patch)


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


func _install_rule_package(rule_package: Dictionary, install_stack: Array = []) -> Dictionary:
    var package_id := String(rule_package.get("package_id", "")).strip_edges()
    if package_id.is_empty():
        return {
            "status": "error",
            "message": "Rule package is missing package_id."
        }
    if install_stack.has(package_id):
        var dependency_chain := install_stack.duplicate(true)
        dependency_chain.append(package_id)
        return {
            "status": "error",
            "message": "Rule package dependency cycle detected: %s" % " -> ".join(dependency_chain),
            "package_id": package_id,
            "rule_package": rule_package.duplicate(true)
        }

    var dependency_resolution := _resolve_rule_package_dependencies(rule_package)
    if String(dependency_resolution.get("status", "")) == "error":
        return dependency_resolution

    var compilation: Dictionary = _runtime_rule_patch_compiler.compile_package(rule_package)
    if String(compilation.get("status", "")) != "compiled":
        return compilation

    var compiled_runtime_rules := _extract_compiled_runtime_rules(compilation)
    var runtime_targets := _runtime_targets_for_compilation(compilation, compiled_runtime_rules)
    if runtime_targets.is_empty():
        return {
            "status": "error",
            "message": "Rule package did not compile any runtime install targets.",
            "package_id": package_id,
            "rule_package": rule_package.duplicate(true)
        }

    var dependency_results: Array = []
    var next_install_stack := install_stack.duplicate(true)
    next_install_stack.append(package_id)
    for dependency_package in dependency_resolution.get("dependency_packages", []):
        if not (dependency_package is Dictionary):
            continue
        var dependency_result: Dictionary = _install_rule_package(dependency_package, next_install_stack)
        if String(dependency_result.get("status", "")) != "installed":
            return dependency_result
        dependency_results.append(dependency_result)

    if _runtime_targets_already_installed(runtime_targets):
        return _build_rule_package_install_result(rule_package, compilation, dependency_resolution.get("package_dependencies", []), dependency_results, [], true)

    var runtime_results: Array = []
    for runtime_target_variant in runtime_targets:
        if not (runtime_target_variant is Dictionary):
            continue
        var runtime_target: Dictionary = runtime_target_variant
        var runtime_rule_id := String(runtime_target.get("id", "")).strip_edges()
        if runtime_rule_id.is_empty() or _runtime_rule_is_installed(runtime_rule_id):
            continue
        var runtime_result: Dictionary = _runtime.create_rule_from_patch(runtime_target)
        if String(runtime_result.get("status", "")) != "installed":
            var error_result: Dictionary = runtime_result.duplicate(true)
            error_result["install_source"] = "rule_package"
            error_result["package_id"] = package_id
            error_result["package_dependencies"] = dependency_resolution.get("package_dependencies", []).duplicate(true)
            error_result["dependency_results"] = dependency_results.duplicate(true)
            error_result["compiled_runtime_patch"] = compilation.get("runtime_patch", {}).duplicate(true)
            error_result["compiled_runtime_rules"] = compiled_runtime_rules.duplicate(true)
            error_result["deferred_operations"] = compilation.get("deferred_operations", []).duplicate(true)
            return error_result
        runtime_results.append(runtime_result)

    return _build_rule_package_install_result(rule_package, compilation, dependency_resolution.get("package_dependencies", []), dependency_results, runtime_results)


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
        "package_dependencies": rule_package.get("package_dependencies", []).duplicate(true),
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
        proposal["compiled_runtime_rules"] = _extract_compiled_runtime_rules(compilation)
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
        "package_dependencies",
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


func _validate_rule_package_dependencies(dependencies_variant: Variant, rule_package: Dictionary) -> Dictionary:
    if not (dependencies_variant is Array):
        return {
            "status": "error",
            "message": "Rule package package_dependencies must be an array.",
            "rule_package": rule_package.duplicate(true)
        }

    var package_dependencies: Array = []
    for dependency_index in range(dependencies_variant.size()):
        var dependency_value = dependencies_variant[dependency_index]
        if not (dependency_value is String):
            return {
                "status": "error",
                "message": "Rule package package_dependencies[%d] must be a string." % dependency_index,
                "rule_package": rule_package.duplicate(true)
            }
        var dependency_id := String(dependency_value).strip_edges()
        if dependency_id.is_empty():
            return {
                "status": "error",
                "message": "Rule package package_dependencies[%d] must not be empty." % dependency_index,
                "rule_package": rule_package.duplicate(true)
            }
        if not package_dependencies.has(dependency_id):
            package_dependencies.append(dependency_id)

    return {
        "status": "ok",
        "package_dependencies": package_dependencies
    }


func _resolve_rule_package_dependencies(rule_package: Dictionary) -> Dictionary:
    var dependencies_result := _validate_rule_package_dependencies(rule_package.get("package_dependencies", []), rule_package)
    if String(dependencies_result.get("status", "")) == "error":
        return dependencies_result

    var dependency_packages: Array = []
    for dependency_id_variant in dependencies_result.get("package_dependencies", []):
        var dependency_id := String(dependency_id_variant)
        var dependency_package: Dictionary = _rule_package_repository.get_rule_package(dependency_id)
        if dependency_package.is_empty():
            return {
                "status": "error",
                "message": "Rule package dependency '%s' could not be found." % dependency_id,
                "package_id": rule_package.get("package_id", ""),
                "rule_package": rule_package.duplicate(true)
            }
        dependency_packages.append(dependency_package)

    return {
        "status": "ok",
        "package_dependencies": dependencies_result.get("package_dependencies", []).duplicate(true),
        "dependency_packages": dependency_packages
    }


func _extract_compiled_runtime_rules(compilation: Dictionary) -> Array:
    var compiled_runtime_rules: Array = []
    for runtime_rule_variant in compilation.get("runtime_rules", []):
        if runtime_rule_variant is Dictionary:
            compiled_runtime_rules.append(runtime_rule_variant.duplicate(true))
    return compiled_runtime_rules


func _runtime_targets_for_compilation(compilation: Dictionary, compiled_runtime_rules: Array) -> Array:
    if not compiled_runtime_rules.is_empty():
        return compiled_runtime_rules.duplicate(true)
    var runtime_patch: Dictionary = compilation.get("runtime_patch", {})
    if runtime_patch.is_empty():
        return []
    return [runtime_patch.duplicate(true)]


func _runtime_target_ids(runtime_targets: Array) -> Array:
    var runtime_target_ids: Array = []
    for runtime_target_variant in runtime_targets:
        if not (runtime_target_variant is Dictionary):
            continue
        var runtime_target_id := String(runtime_target_variant.get("id", "")).strip_edges()
        if not runtime_target_id.is_empty() and not runtime_target_ids.has(runtime_target_id):
            runtime_target_ids.append(runtime_target_id)
    return runtime_target_ids


func _runtime_rule_is_installed(rule_id: String) -> bool:
    if rule_id.is_empty():
        return false
    var installed_rules_by_id: Dictionary = _runtime.get_snapshot().get("installed_rules_by_id", {})
    return installed_rules_by_id.has(rule_id)


func _runtime_targets_already_installed(runtime_targets: Array) -> bool:
    var runtime_target_ids := _runtime_target_ids(runtime_targets)
    if runtime_target_ids.is_empty():
        return false
    for runtime_target_id in runtime_target_ids:
        if not _runtime_rule_is_installed(String(runtime_target_id)):
            return false
    return true


func _build_rule_package_install_result(rule_package: Dictionary, compilation: Dictionary, package_dependencies: Array, dependency_results: Array, runtime_results: Array, already_installed: bool = false) -> Dictionary:
    var compiled_runtime_rules := _extract_compiled_runtime_rules(compilation)
    var runtime_targets := _runtime_targets_for_compilation(compilation, compiled_runtime_rules)
    var installed_rule_ids := _runtime_target_ids(runtime_targets)
    for dependency_result_variant in dependency_results:
        if not (dependency_result_variant is Dictionary):
            continue
        for dependency_rule_id_variant in dependency_result_variant.get("installed_rule_ids", []):
            var dependency_rule_id := String(dependency_rule_id_variant).strip_edges()
            if not dependency_rule_id.is_empty() and not installed_rule_ids.has(dependency_rule_id):
                installed_rule_ids.append(dependency_rule_id)
    var install_result := {
        "status": "installed",
        "installed": true,
        "install_source": "rule_package",
        "package_id": rule_package.get("package_id", ""),
        "source_repo": rule_package.get("source_repo", ""),
        "source_ref": rule_package.get("source_ref", ""),
        "package_dependencies": package_dependencies.duplicate(true),
        "dependency_results": dependency_results.duplicate(true),
        "installed_rule_ids": installed_rule_ids,
        "runtime_results": runtime_results.duplicate(true),
        "forked_from": rule_package.get("forked_from", null),
        "suggested_pr_target": rule_package.get("suggested_pr_target", null),
        "safe_to_apply_directly": bool(compilation.get("safe_to_apply_directly", false)),
        "deferred_operations": compilation.get("deferred_operations", []).duplicate(true),
        "compiled_runtime_patch": compilation.get("runtime_patch", {}).duplicate(true),
        "compiled_runtime_rules": compiled_runtime_rules
    }
    if already_installed:
        install_result["already_installed"] = true
    return install_result
