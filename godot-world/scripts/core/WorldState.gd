extends Node

const SimulationRuntimeScript = preload("res://scripts/core/SimulationRuntime.gd")
const RuleTemplatesScript = preload("res://scripts/core/RuleTemplates.gd")
const RuleProposalWorkflowScript = preload("res://scripts/integration/rule_proposal_workflow.gd")
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
var _proposal_workflow = null
var _proposal_thread: Thread = null
var _proposal_request_serial: int = 0
var _proposal_thread_request_serial: int = 0
var _proposal_thread_task_text: String = ""

static var _detached_proposal_threads: Array = []


func _ready() -> void:
    _reap_detached_proposal_threads()
    _reset_world()


func _exit_tree() -> void:
    _cancel_pending_proposal_thread(false)


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


func talk_to_game_master(message: String) -> Dictionary:
    _ensure_runtime()
    var trimmed := message.strip_edges()
    if trimmed.is_empty():
        return {
            "status": "error",
            "error_code": "empty_request",
            "message": "相談内容を入力してください。",
            "gm_response": "どんなルール変更を考えていますか？"
        }

    var template_result := submit_player_task(trimmed)
    var template_proposals: Array = template_result.get("proposals", [])
    if String(template_result.get("status", "")) == "proposal_ready" and not template_proposals.is_empty():
        return {
            "status": "template_proposal_ready",
            "task_text": trimmed,
            "task_result": template_result.duplicate(true),
            "proposals": template_proposals.duplicate(true),
            "gm_response": "既存のテンプレート候補があります。まずは安全な既存ルール案を確認してください。",
            "snapshot": _runtime.get_snapshot()
        }

    var proposal_result := request_rule_proposal(trimmed)
    var response := proposal_result.duplicate(true)
    response["gm_response"] = _gm_response_for_proposal_result(response)
    response["snapshot"] = _runtime.get_snapshot()
    return response


func talk_to_game_master_async(message: String) -> Dictionary:
    _ensure_runtime()
    var trimmed := message.strip_edges()
    if trimmed.is_empty():
        return {
            "status": "error",
            "error_code": "empty_request",
            "message": "相談内容を入力してください。",
            "gm_response": "どんなルール変更を考えていますか？"
        }

    var template_result := submit_player_task(trimmed)
    var template_proposals: Array = template_result.get("proposals", [])
    if String(template_result.get("status", "")) == "proposal_ready" and not template_proposals.is_empty():
        return {
            "status": "template_proposal_ready",
            "task_text": trimmed,
            "task_result": template_result.duplicate(true),
            "proposals": template_proposals.duplicate(true),
            "gm_response": "既存のテンプレート候補があります。まずは安全な既存ルール案を確認してください。",
            "snapshot": _runtime.get_snapshot()
        }

    var proposal_result := request_rule_proposal_async(trimmed)
    var response := proposal_result.duplicate(true)
    response["gm_response"] = _gm_response_for_proposal_result(response)
    response["snapshot"] = _runtime.get_snapshot()
    return response


func request_rule_proposal(task_text: String) -> Dictionary:
    _ensure_runtime()
    _ensure_workflow()
    var trimmed := task_text.strip_edges()
    if trimmed.is_empty():
        return {
            "status": "error",
            "error_code": "empty_request",
            "message": "相談内容を入力してください。"
        }

    var proposal_result: Dictionary = _proposal_workflow.generate_proposal(trimmed)
    _runtime.record_poc4_proposal(trimmed, proposal_result)
    return proposal_result


func request_rule_proposal_async(task_text: String) -> Dictionary:
    _ensure_runtime()
    _ensure_workflow()
    _poll_pending_proposal_thread()
    var trimmed := task_text.strip_edges()
    if trimmed.is_empty():
        return {
            "status": "error",
            "error_code": "empty_request",
            "message": "相談内容を入力してください。"
        }

    if _proposal_thread != null:
        var busy_state: Dictionary = _runtime.get_pending_poc4_proposal_state()
        return {
            "status": "proposal_busy",
            "error_code": "proposal_in_progress",
            "message": "PoC4 backend はまだ前の proposal を生成中です。",
            "execution": busy_state.get("execution", {}).duplicate(true),
            "codex": busy_state.get("codex", {}).duplicate(true),
            "task_text": String(busy_state.get("last_request_text", trimmed))
        }

    var codex_details: Dictionary = _proposal_workflow.describe_codex_execution()
    if String(codex_details.get("status", "")) == "error":
        _runtime.record_poc4_proposal(trimmed, codex_details)
        return codex_details

    var state: Dictionary = _runtime.begin_poc4_proposal_execution(trimmed, codex_details)
    _proposal_request_serial += 1
    var request_serial := _proposal_request_serial
    _proposal_thread = Thread.new()
    _proposal_thread_request_serial = request_serial
    _proposal_thread_task_text = trimmed
    var start_error := _proposal_thread.start(Callable(_proposal_workflow, "generate_proposal").bind(trimmed))
    if start_error != OK:
        _proposal_thread = null
        _proposal_thread_request_serial = 0
        _proposal_thread_task_text = ""
        var error_result := {
            "status": "error",
            "error_code": "proposal_thread_start_failed",
            "message": "PoC4 proposal generation thread を開始できませんでした。",
            "details": {"code": start_error},
            "codex": codex_details.duplicate(true)
        }
        _runtime.record_poc4_proposal(trimmed, error_result)
        return error_result

    return {
        "status": "proposal_running",
        "message": "PoC4 backend が非同期で proposal を生成中です。",
        "execution": state.get("execution", {}).duplicate(true),
        "codex": state.get("codex", {}).duplicate(true),
        "task_text": trimmed
    }


func get_pending_rule_proposal() -> Dictionary:
    _ensure_runtime()
    _poll_pending_proposal_thread()
    return _runtime.get_pending_poc4_proposal_state()


func update_pending_rule_review(reviewed: bool, metadata: Dictionary = {}) -> Dictionary:
    _ensure_runtime()
    return _runtime.update_poc4_review(reviewed, metadata)

func apply_pending_rule_proposal() -> Dictionary:
    _ensure_runtime()
    return _runtime.apply_pending_poc4_proposal()


func get_last_rule_apply_result() -> Dictionary:
    _ensure_runtime()
    return _runtime.get_last_poc4_apply_result()


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


func dispatch_input_event(event_name: String, context: Dictionary = {}) -> Dictionary:
    _ensure_runtime()
    return _runtime.dispatch_input_event(event_name, context)


func _reset_world() -> void:
    _reap_detached_proposal_threads()
    _cancel_pending_proposal_thread(false)
    _rule_package_repository = RulePackageRepositoryScript.new()
    _rule_compiler = RuleCompilerScript.new(_rule_package_repository)
    _runtime_rule_patch_compiler = RuntimeRulePatchCompilerScript.new()
    _available_rule_packages = _rule_compiler.list_available_rule_packages()
    _available_templates = RuleTemplatesScript.get_templates()
    _runtime = SimulationRuntimeScript.new(_available_templates)
    _proposal_workflow = RuleProposalWorkflowScript.new()


func _ensure_runtime() -> void:
    _reap_detached_proposal_threads()
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
    if _proposal_workflow == null:
        _proposal_workflow = RuleProposalWorkflowScript.new()


func _ensure_workflow() -> void:
    if _proposal_workflow == null:
        _proposal_workflow = RuleProposalWorkflowScript.new()


func _gm_response_for_proposal_result(result: Dictionary) -> String:
    var status := String(result.get("status", ""))
    match status:
        "proposal_running":
            return "PoC4 backend が提案を生成中です。会話画面の review に session detail と実行状態が表示されます。"
        "proposal_busy":
            return "PoC4 backend はまだ前の提案を生成中です。完了まで同じ画面で状態を確認してください。"
        "proposal_ready":
            var summary: Dictionary = result.get("summary", {})
            return "PoC4 backend が提案を用意しました。package_id=%s / 操作数=%d。内容を確認したら、そのままゲームへ適用できます。" % [
                String(summary.get("package_id", "unknown")),
                int(summary.get("operation_count", 0))
            ]
        "error":
            return "PoC4 backend で提案を作れませんでした: %s" % String(result.get("message", "不明なエラー"))
        _:
            return String(result.get("message", "ゲームマスターが相談内容を受け取りました。"))


func _poll_pending_proposal_thread() -> void:
    if _proposal_thread == null:
        return
    if _proposal_thread.is_alive():
        return

    var finished_thread := _proposal_thread
    var request_serial := _proposal_thread_request_serial
    var task_text := _proposal_thread_task_text
    _proposal_thread = null
    _proposal_thread_request_serial = 0
    _proposal_thread_task_text = ""

    var thread_result = finished_thread.wait_to_finish()
    if request_serial != _proposal_request_serial or _runtime == null:
        return
    if thread_result is Dictionary:
        _runtime.record_poc4_proposal(task_text, thread_result)
        return

    _runtime.record_poc4_proposal(task_text, {
        "status": "error",
        "error_code": "proposal_thread_invalid_result",
        "message": "PoC4 proposal generation thread が不正な結果を返しました。"
    })


func _cancel_pending_proposal_thread(blocking: bool = true) -> void:
    _proposal_request_serial += 1
    if _proposal_thread == null:
        _proposal_thread_request_serial = 0
        _proposal_thread_task_text = ""
        return
    if not blocking and _proposal_thread.is_alive():
        _detached_proposal_threads.append(_proposal_thread)
        _proposal_thread = null
        _proposal_thread_request_serial = 0
        _proposal_thread_task_text = ""
        return
    _proposal_thread.wait_to_finish()
    _proposal_thread = null
    _proposal_thread_request_serial = 0
    _proposal_thread_task_text = ""


static func _reap_detached_proposal_threads() -> void:
    if _detached_proposal_threads.is_empty():
        return
    var remaining_threads: Array = []
    for entry in _detached_proposal_threads:
        if not (entry is Thread):
            continue
        var thread: Thread = entry
        if thread.is_alive():
            remaining_threads.append(thread)
            continue
        thread.wait_to_finish()
    _detached_proposal_threads = remaining_threads


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
