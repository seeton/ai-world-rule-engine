extends Node

const SimulationRuntimeScript = preload("res://scripts/core/SimulationRuntime.gd")
const RuleTemplatesScript = preload("res://scripts/core/RuleTemplates.gd")
const RuleProposalWorkflowScript = preload("res://scripts/integration/rule_proposal_workflow.gd")

var _runtime = null
var _available_templates: Array = []
var _proposal_workflow = null
var _proposal_thread: Thread = null
var _proposal_request_serial: int = 0


func _ready() -> void:
	_reset_world()


func _exit_tree() -> void:
	_cancel_pending_proposal_thread()


func submit_player_task(task_text: String) -> Dictionary:
	_ensure_runtime()
	var normalized_task := task_text.strip_edges().to_lower()
	var proposals: Array = []

	for template in _available_templates:
		for keyword in template.get("keywords", []):
			if normalized_task.findn(String(keyword).to_lower()) != -1:
				proposals.append({
					"template_id": template.get("id", ""),
					"title": template.get("name", ""),
					"description": template.get("description", ""),
					"rule_patch": template.get("rule_patch", {}).duplicate(true)
				})
				break

	var result := {
		"status": "proposal_ready" if not proposals.is_empty() else "needs_rule_patch",
		"task_text": task_text,
		"proposals": proposals,
		"message": "Matched existing rule templates." if not proposals.is_empty() else "No matching template. Use create_rule_from_patch() with a dictionary patch."
	}
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
	var start_error := _proposal_thread.start(Callable(self, "_run_rule_proposal_async").bind(request_serial, trimmed))
	if start_error != OK:
		_proposal_thread = null
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
	return _runtime.create_rule_from_patch(rule_patch)


func get_world_snapshot() -> Dictionary:
	_ensure_runtime()
	return _runtime.get_snapshot()


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


func dispatch_input_event(event_name: String, context: Dictionary = {}) -> Dictionary:
	_ensure_runtime()
	return _runtime.dispatch_input_event(event_name, context)


func _reset_world() -> void:
	_cancel_pending_proposal_thread()
	_available_templates = RuleTemplatesScript.get_templates()
	_runtime = SimulationRuntimeScript.new(_available_templates)
	_proposal_workflow = RuleProposalWorkflowScript.new()


func _ensure_runtime() -> void:
	if _runtime == null:
		_reset_world()


func _ensure_workflow() -> void:
	if _proposal_workflow == null:
		_proposal_workflow = RuleProposalWorkflowScript.new()


func _run_rule_proposal_async(request_serial: int, task_text: String) -> void:
	var proposal_result: Dictionary = _proposal_workflow.generate_proposal(task_text)
	call_deferred("_complete_rule_proposal_async", request_serial, task_text, proposal_result)


func _complete_rule_proposal_async(request_serial: int, task_text: String, proposal_result: Dictionary) -> void:
	if _proposal_thread != null:
		_proposal_thread.wait_to_finish()
		_proposal_thread = null
	if request_serial != _proposal_request_serial:
		return
	if _runtime == null:
		return
	_runtime.record_poc4_proposal(task_text, proposal_result)


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


func _cancel_pending_proposal_thread() -> void:
	_proposal_request_serial += 1
	if _proposal_thread == null:
		return
	_proposal_thread.wait_to_finish()
	_proposal_thread = null
