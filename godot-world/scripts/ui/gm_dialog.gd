extends Control

signal closed

const ACTIVE_LANGUAGE := "ja"
const UI_TEXT := {
	"ja": {
		"title": "ゲームマスター",
		"back": "← 戻る",
		"input_label": "あなたの指示:",
		"placeholder": "例: 時間のルールを作成しろ",
		"send": "送信",
		"refresh_review": "PoC4状態を更新",
		"review_title": "PoC4 review",
		"review_description": "proposal を確認し、必要ならそのままゲームへ適用できます。",
		"consent_label": "proposal 内容を確認した",
		"apply_to_game": "ゲームへ適用",
		"cancel_review": "キャンセル",
		"no_proposal": "まだ review 対象の proposal はありません。相談を送ると、PoC4 backend の結果がここに表示されます。",
		"welcome_1": "[color=cyan]ゲームマスター:[/color] ようこそ。私に世界のルール作成を依頼できます。",
		"welcome_2": "例えば「時間のルールを作成しろ」と入力してみてください。",
		"missing_worldstate": "[color=red]エラー:[/color] WorldStateが見つかりません。",
		"clock_hint": "[color=cyan]ゲームマスター:[/color] 世界に戻ると右上に時計が表示されます。",
		"proposal_ready_hint": "[color=cyan]ゲームマスター:[/color] PoC4 proposal を review 欄に表示しました。内容を確認し、必要ならそのままゲームへ適用してください。",
		"proposal_running_review": "PoC4 backend が Codex proposal generation を実行中です。画面は操作可能なままなので、この review 欄で session detail と進行状態を確認してください。",
		"template_hint": "[color=cyan]ゲームマスター:[/color] 既存テンプレート候補が見つかりました。PoC4 review は使わず、既存のテンプレート導線で試せます。",
		"consent_updated": "[color=cyan]ゲームマスター:[/color] proposal の確認状態を更新しました。",
		"consent_cancelled": "[color=cyan]ゲームマスター:[/color] 確認状態を外しました。proposal は review 欄に残っています。",
		"consent_required": "[color=red]エラー:[/color] 先に proposal 内容を確認してください。",
		"review_update_failed": "[color=red]エラー:[/color] review 更新に失敗しました。",
		"apply_succeeded": "[color=green]完了:[/color] proposal をゲームへ適用しました。",
		"apply_failed": "[color=red]エラー:[/color] proposal のゲーム適用に失敗しました。",
		"review_refresh_failed": "[color=red]エラー:[/color] PoC4 review 状態を取得できませんでした。"
	},
	"en": {
		"title": "Game Master",
		"back": "<- Back",
		"input_label": "Your request:",
		"placeholder": "Example: create time rule",
		"send": "Send",
		"refresh_review": "Refresh PoC4 state",
		"review_title": "PoC4 review",
		"review_description": "Review the proposal, then apply it to the game when ready.",
		"consent_label": "I reviewed the proposal",
		"apply_to_game": "Apply to game",
		"cancel_review": "Cancel",
		"no_proposal": "No pending proposal yet. Send a request to review the PoC4 backend result here.",
		"welcome_1": "[color=cyan]Game Master:[/color] Welcome. You can ask me to create world rules.",
		"welcome_2": "Try entering 'create time rule'.",
		"missing_worldstate": "[color=red]Error:[/color] WorldState was not found.",
		"clock_hint": "[color=cyan]Game Master:[/color] Return to the world to see the clock in the top-right.",
		"proposal_ready_hint": "[color=cyan]Game Master:[/color] The PoC4 proposal is ready in the review panel. Review it, then apply it to the game if you want.",
		"proposal_running_review": "The PoC4 backend is still generating a Codex proposal. Keep this screen open to watch the session details and execution state without freezing the UI.",
		"template_hint": "[color=cyan]Game Master:[/color] An existing template proposal is available. Use the template flow instead of the PoC4 apply flow.",
		"consent_updated": "[color=cyan]Game Master:[/color] Updated proposal review acknowledgement.",
		"consent_cancelled": "[color=cyan]Game Master:[/color] Review acknowledgement was cleared. The proposal remains visible.",
		"consent_required": "[color=red]Error:[/color] Review acknowledgement is required first.",
		"review_update_failed": "[color=red]Error:[/color] Failed to update review acknowledgement.",
		"apply_succeeded": "[color=green]Done:[/color] Proposal applied to the game.",
		"apply_failed": "[color=red]Error:[/color] Failed to apply the proposal to the game.",
		"review_refresh_failed": "[color=red]Error:[/color] Failed to refresh PoC4 review state."
	}
}

var _world_state: Node = null
var _input_field: TextEdit
var _response_panel: RichTextLabel
var _back_button: Button
var _send_button: Button
var _refresh_review_button: Button
var _review_panel: RichTextLabel
var _apply_result_panel: RichTextLabel
var _consent_checkbox: CheckBox
var _apply_button: Button
var _cancel_review_button: Button
var _pending_proposal_state: Dictionary = {}
var _last_apply_result: Dictionary = {}
var _async_request_running := false
var _async_poll_elapsed := 0.0
var compact_mode := false


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	modulate.a = 0.0
	_world_state = get_node_or_null("/root/WorldState")
	_build_ui()
	_show_welcome_message()
	_refresh_review_state(false)
	_fade_in()


func _process(delta: float) -> void:
	if not visible or not _async_request_running:
		return

	_async_poll_elapsed += delta
	if _async_poll_elapsed < 0.25:
		return

	_async_poll_elapsed = 0.0
	_refresh_review_state(false)
	var execution: Dictionary = _pending_proposal_state.get("execution", {})
	if String(execution.get("status", "idle")) == "running":
		return

	_async_request_running = false
	_set_submission_busy(false)
	_announce_async_completion()


func notify_overlay_visible() -> void:
	if not _async_request_running:
		return
	_async_poll_elapsed = 0.0
	_refresh_review_state(false)
	var execution: Dictionary = _pending_proposal_state.get("execution", {})
	if String(execution.get("status", "idle")) == "running":
		return
	_async_request_running = false
	_set_submission_busy(false)
	_announce_async_completion()


func _fade_in() -> void:
	var tween := create_tween()
	tween.tween_property(self, "modulate:a", 1.0, 0.25)


func _build_ui() -> void:
	if not compact_mode:
		var bg := ColorRect.new()
		bg.color = Color(0.1, 0.1, 0.15, 1.0)
		bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		add_child(bg)

	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var page_margin := 0 if compact_mode else 32
	margin.add_theme_constant_override("margin_left", page_margin)
	margin.add_theme_constant_override("margin_top", page_margin)
	margin.add_theme_constant_override("margin_right", page_margin)
	margin.add_theme_constant_override("margin_bottom", page_margin)
	add_child(margin)

	var vbox := VBoxContainer.new()
	vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vbox.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vbox.add_theme_constant_override("separation", 16)
	margin.add_child(vbox)

	if not compact_mode:
		var header := HBoxContainer.new()
		header.add_theme_constant_override("separation", 12)
		vbox.add_child(header)

		var title := Label.new()
		title.text = _text("title")
		title.add_theme_font_size_override("font_size", 28)
		title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		header.add_child(title)

		_back_button = Button.new()
		_back_button.text = _text("back")
		_back_button.pressed.connect(_on_back_pressed)
		header.add_child(_back_button)

	var response_container := PanelContainer.new()
	response_container.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vbox.add_child(response_container)

	var response_margin := MarginContainer.new()
	response_margin.add_theme_constant_override("margin_left", 12)
	response_margin.add_theme_constant_override("margin_top", 12)
	response_margin.add_theme_constant_override("margin_right", 12)
	response_margin.add_theme_constant_override("margin_bottom", 12)
	response_container.add_child(response_margin)

	_response_panel = RichTextLabel.new()
	_response_panel.bbcode_enabled = true
	_response_panel.scroll_following = true
	_response_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_response_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	response_margin.add_child(_response_panel)

	var input_label := Label.new()
	input_label.text = _text("input_label")
	input_label.add_theme_font_size_override("font_size", 16)
	vbox.add_child(input_label)

	var input_container := PanelContainer.new()
	vbox.add_child(input_container)

	var input_margin := MarginContainer.new()
	input_margin.add_theme_constant_override("margin_left", 8)
	input_margin.add_theme_constant_override("margin_top", 8)
	input_margin.add_theme_constant_override("margin_right", 8)
	input_margin.add_theme_constant_override("margin_bottom", 8)
	input_container.add_child(input_margin)

	_input_field = TextEdit.new()
	_input_field.custom_minimum_size = Vector2(0, 80)
	_input_field.placeholder_text = _text("placeholder")
	_input_field.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
	input_margin.add_child(_input_field)

	var button_row := HBoxContainer.new()
	button_row.add_theme_constant_override("separation", 12)
	vbox.add_child(button_row)

	_send_button = Button.new()
	_send_button.text = _text("send")
	_send_button.pressed.connect(_on_send_pressed)
	button_row.add_child(_send_button)

	_refresh_review_button = Button.new()
	_refresh_review_button.text = _text("refresh_review")
	_refresh_review_button.pressed.connect(func() -> void:
		_refresh_review_state(true)
	)
	button_row.add_child(_refresh_review_button)

	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	button_row.add_child(spacer)

	vbox.add_child(_build_review_section())


func _build_review_section() -> Control:
	var panel := PanelContainer.new()
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.size_flags_vertical = Control.SIZE_SHRINK_END

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 12)
	margin.add_theme_constant_override("margin_top", 12)
	margin.add_theme_constant_override("margin_right", 12)
	margin.add_theme_constant_override("margin_bottom", 12)
	panel.add_child(margin)

	var body := VBoxContainer.new()
	body.add_theme_constant_override("separation", 10)
	margin.add_child(body)

	var title := Label.new()
	title.text = _text("review_title")
	title.add_theme_font_size_override("font_size", 20)
	body.add_child(title)

	var description := Label.new()
	description.text = _text("review_description")
	description.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body.add_child(description)

	var review_scroll := ScrollContainer.new()
	review_scroll.custom_minimum_size = Vector2(0, 180)
	review_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_child(review_scroll)

	_review_panel = RichTextLabel.new()
	_review_panel.bbcode_enabled = true
	_review_panel.fit_content = true
	_review_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	review_scroll.add_child(_review_panel)

	_consent_checkbox = CheckBox.new()
	_consent_checkbox.text = _text("consent_label")
	_consent_checkbox.toggled.connect(_on_consent_toggled)
	body.add_child(_consent_checkbox)

	var action_row := HBoxContainer.new()
	action_row.add_theme_constant_override("separation", 12)
	body.add_child(action_row)

	_cancel_review_button = Button.new()
	_cancel_review_button.text = _text("cancel_review")
	_cancel_review_button.pressed.connect(_on_cancel_review_pressed)
	action_row.add_child(_cancel_review_button)

	_apply_button = Button.new()
	_apply_button.text = _text("apply_to_game")
	_apply_button.disabled = true
	_apply_button.pressed.connect(_on_apply_pressed)
	action_row.add_child(_apply_button)

	var result_scroll := ScrollContainer.new()
	result_scroll.custom_minimum_size = Vector2(0, 96)
	body.add_child(result_scroll)

	_apply_result_panel = RichTextLabel.new()
	_apply_result_panel.bbcode_enabled = true
	_apply_result_panel.fit_content = true
	_apply_result_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	result_scroll.add_child(_apply_result_panel)

	return panel


func _show_welcome_message() -> void:
	_append_response(_text("welcome_1"))
	_append_response(_text("welcome_2"))


func _on_back_pressed() -> void:
	var tween := create_tween()
	tween.tween_property(self, "modulate:a", 0.0, 0.18)
	tween.tween_callback(func():
		closed.emit()
		queue_free()
	)


func _on_send_pressed() -> void:
	var user_text := _input_field.text.strip_edges()
	if user_text.is_empty():
		return

	_append_response("[color=yellow]あなた:[/color] " + user_text)
	_input_field.text = ""
	_process_user_message(user_text)


func _process_user_message(message: String) -> void:
	if _world_state == null:
		_append_response(_text("missing_worldstate"))
		return

	var result: Dictionary = {}
	if _world_state.has_method("talk_to_game_master_async"):
		result = _world_state.call("talk_to_game_master_async", message)
	elif _world_state.has_method("talk_to_game_master"):
		result = _world_state.call("talk_to_game_master", message)
	else:
		_append_response(_text("missing_worldstate"))
		return
	var gm_response := String(result.get("gm_response", result.get("reply", "")))
	if not gm_response.is_empty():
		_append_response("[color=cyan]ゲームマスター:[/color] " + gm_response)
	if String(result.get("action", "")) == "installed_time_rule":
		_append_response(_text("clock_hint"))

	match String(result.get("status", "")):
		"proposal_running", "proposal_busy":
			_async_request_running = true
			_async_poll_elapsed = 0.0
			_set_submission_busy(true)
			_refresh_review_state(false)
		"proposal_ready":
			_set_submission_busy(false)
			_refresh_review_state(false)
			_append_response(_text("proposal_ready_hint"))
		"template_proposal_ready":
			_set_submission_busy(false)
			_refresh_review_state(false)
			_append_response(_text("template_hint"))
		"error":
			_set_submission_busy(false)
			_refresh_review_state(false)
		_:
			_set_submission_busy(false)


func _refresh_review_state(announce_error: bool) -> void:
	var state := _fetch_pending_proposal_state()
	var last_apply := _fetch_last_apply_result()
	if state.is_empty() and _world_state != null and announce_error:
		_append_response(_text("review_refresh_failed"))
	_update_review_ui(state, last_apply)


func _fetch_pending_proposal_state() -> Dictionary:
	if _world_state == null:
		return {}

	if _world_state.has_method("get_pending_rule_proposal"):
		var state = _world_state.call("get_pending_rule_proposal")
		if state is Dictionary:
			return _merge_review_state(state)

	if _world_state.has_method("get_world_snapshot"):
		var snapshot = _world_state.call("get_world_snapshot")
		if snapshot is Dictionary:
			return _merge_review_state(snapshot.get("poc4", {}))

	return {}


func _fetch_last_apply_result() -> Dictionary:
	if _world_state == null:
		return {}
	if _world_state.has_method("get_last_rule_apply_result"):
		var apply_result = _world_state.call("get_last_rule_apply_result")
		if apply_result is Dictionary:
			return apply_result
	return {}


func _merge_review_state(source: Variant) -> Dictionary:
	if not (source is Dictionary):
		return {}

	var state: Dictionary = source
	return {
		"proposal": _duplicate_dict(state.get("proposal", state.get("pending_proposal", {}))),
		"summary": _duplicate_dict(state.get("summary", state.get("proposal_summary", {}))),
		"issue_preview": _duplicate_dict(state.get("issue_preview", {})),
		"review": _duplicate_dict(state.get("review", {})),
		"apply_result": _duplicate_dict(state.get("apply_result", {})),
		"last_error": _duplicate_dict(state.get("last_error", {})),
		"execution": _duplicate_dict(state.get("execution", {})),
		"codex": _duplicate_dict(state.get("codex", {})),
		"last_request_text": String(state.get("last_request_text", "")),
		"history": Array(state.get("history", [])).duplicate(true)
	}


func _update_review_ui(state: Dictionary, last_apply: Dictionary) -> void:
	_pending_proposal_state = state.duplicate(true)
	_last_apply_result = last_apply.duplicate(true)

	var proposal: Dictionary = _pending_proposal_state.get("proposal", {})
	var review: Dictionary = _pending_proposal_state.get("review", {})
	var execution: Dictionary = _pending_proposal_state.get("execution", {})
	var apply_result: Dictionary = _last_apply_result if not _last_apply_result.is_empty() else _pending_proposal_state.get("apply_result", {})
	var acknowledged := bool(review.get("acknowledged", review.get("granted", false)))
	var has_proposal := not proposal.is_empty()
	var running := String(execution.get("status", "idle")) == "running"
	var already_applied := String(apply_result.get("status", "")) in ["applied", "applied_with_warnings"]

	_consent_checkbox.disabled = not has_proposal or running
	_consent_checkbox.set_pressed_no_signal(acknowledged)
	_cancel_review_button.disabled = not has_proposal or running
	_apply_button.disabled = not has_proposal or not acknowledged or running or already_applied
	_review_panel.text = _format_review_text()
	_apply_result_panel.text = _format_apply_result_text()


func _format_review_text() -> String:
	var proposal: Dictionary = _pending_proposal_state.get("proposal", {})
	var last_error: Dictionary = _pending_proposal_state.get("last_error", {})
	var execution: Dictionary = _pending_proposal_state.get("execution", {})
	var codex: Dictionary = _pending_proposal_state.get("codex", {})
	if proposal.is_empty():
		var empty_lines: Array[String] = []
		_append_execution_lines(empty_lines, execution)
		if not empty_lines.is_empty():
			empty_lines.append("")
		empty_lines.append(_text("proposal_running_review") if String(execution.get("status", "idle")) == "running" else _text("no_proposal"))
		if not last_error.is_empty():
			empty_lines.append("")
			empty_lines.append("[color=red][b]error_code[/b]: %s[/color]" % _display_value(last_error.get("error_code", "unknown")))
			empty_lines.append("[color=red][b]error[/b]: %s[/color]" % _display_value(last_error.get("message", "")))
		_append_codex_review_lines(empty_lines, codex)
		return "\n".join(empty_lines)

	var summary: Dictionary = _pending_proposal_state.get("summary", {})
	var issue_preview: Dictionary = _pending_proposal_state.get("issue_preview", {})
	var review: Dictionary = _pending_proposal_state.get("review", {})
	var submission_target := _format_submission_target(summary.get("suggested_pr_target", null), issue_preview, _last_apply_result)
	var review_lines: Array[String] = []
	_append_execution_lines(review_lines, execution)
	if not review_lines.is_empty():
		review_lines.append("")
	review_lines.append_array([
		"[b]proposal タイトル[/b]: %s" % _sanitize(summary.get("title", issue_preview.get("title", proposal.get("proposal_title", "n/a")))),
		"[b]proposal 要約[/b]: %s" % _sanitize(summary.get("player_request_summary", proposal.get("player_request_summary", "n/a"))),
		"[b]package_id[/b]: %s" % _sanitize(summary.get("package_id", proposal.get("package_id", "n/a"))),
		"[b]operation_count[/b]: %d" % int(summary.get("operation_count", 0)),
		"[b]operation_types[/b]: %s" % _format_array(summary.get("operation_types", [])),
		"[b]stats[/b]: %s" % _bool_label(bool(summary.get("has_stat_changes", false))),
		"[b]rules[/b]: %s" % _bool_label(bool(summary.get("has_rule_changes", false))),
		"[b]event_bindings[/b]: %s" % _bool_label(bool(summary.get("has_event_binding_changes", false))),
		"[b]relations[/b]: %s" % _bool_label(bool(summary.get("has_relation_changes", false))),
		"[b]review_status[/b]: %s" % _sanitize(summary.get("review_status", proposal.get("review_status", "n/a"))),
		"[b]validation_status[/b]: %s" % _sanitize(summary.get("validation_status", proposal.get("validation", {}).get("status", "n/a"))),
		"[b]suggested_pr_target[/b]: %s" % submission_target,
		"[b]review[/b]: %s (%s)" % [
			_bool_label(bool(review.get("acknowledged", review.get("granted", false)))),
			_sanitize(review.get("status", "pending"))
		]
	])

	var request_text := String(_pending_proposal_state.get("last_request_text", "")).strip_edges()
	if not request_text.is_empty():
		review_lines.append("[b]request[/b]: %s" % _display_value(request_text))

	_append_codex_review_lines(review_lines, codex)
	return "\n".join(review_lines)


func _format_apply_result_text() -> String:
	var result: Dictionary = _pending_proposal_state.get("apply_result", {})
	if not _last_apply_result.is_empty():
		result = _last_apply_result
	var last_error: Dictionary = _pending_proposal_state.get("last_error", {})

	if String(result.get("status", "")) in ["applied", "applied_with_warnings"]:
		var success_lines: Array[String] = [
			"[b]apply_result[/b]: %s" % _sanitize(result.get("status", "")),
			"[b]package_id[/b]: %s" % _display_value(result.get("package_id", "")),
			"[b]runtime_rule_id[/b]: %s" % _display_value(result.get("runtime_rule_id", "")),
			"[b]operations[/b]: %d (%s)" % [
				int(result.get("applied_operation_count", 0)),
				_format_array(result.get("applied_operation_types", []))
			]
		]
		if int(result.get("deferred_operation_count", 0)) > 0:
			success_lines.append("[b]deferred[/b]: %d" % int(result.get("deferred_operation_count", 0)))
		if result.has("message"):
			success_lines.append("[b]message[/b]: %s" % _display_value(result.get("message", "")))
		return "\n".join(success_lines)

	var lines: Array[String] = []
	if not result.is_empty():
		lines.append("[b]apply_result[/b]: %s" % _sanitize(result.get("status", "unknown")))
		if result.has("message"):
			lines.append("[b]message[/b]: %s" % _sanitize(result.get("message", "")))
		if result.has("package_id"):
			lines.append("[b]package_id[/b]: %s" % _sanitize(result.get("package_id", "")))
		if result.has("runtime_rule_id"):
			lines.append("[b]runtime_rule_id[/b]: %s" % _sanitize(result.get("runtime_rule_id", "")))

	if not last_error.is_empty():
		lines.append("[color=red][b]error_code[/b]: %s[/color]" % _sanitize(last_error.get("error_code", "unknown")))
		lines.append("[color=red][b]error[/b]: %s[/color]" % _sanitize(last_error.get("message", "")))
		var details: Dictionary = last_error.get("details", {})
		if not details.is_empty():
			var detail_parts: Array[String] = []
			for key in details.keys():
				detail_parts.append("%s=%s" % [str(key), _sanitize(details.get(key, ""))])
			lines.append("[color=red][b]details[/b]: %s[/color]" % ", ".join(detail_parts))

	if lines.is_empty():
		return "[b]apply_result[/b]: まだ実行されていません。"
	return "\n".join(lines)


func _on_consent_toggled(pressed: bool) -> void:
	if _world_state == null or not _world_state.has_method("update_pending_rule_review"):
		_apply_button.disabled = not pressed
		return

	var result: Dictionary = _world_state.call("update_pending_rule_review", pressed, {
		"source": "gm_dialog",
		"screen": "poc4_review"
	})
	if String(result.get("status", "")) == "error":
		_append_response("%s %s" % [_text("review_update_failed"), String(result.get("message", "review update failed."))])
		_refresh_review_state(false)
		return

	_append_response(_text("consent_updated") if pressed else _text("consent_cancelled"))
	_refresh_review_state(false)


func _on_cancel_review_pressed() -> void:
	if _pending_proposal_state.get("proposal", {}).is_empty():
		return
	if _world_state != null and _world_state.has_method("update_pending_rule_review"):
		_world_state.call("update_pending_rule_review", false, {
			"source": "gm_dialog_cancel",
			"screen": "poc4_review"
		})
	_refresh_review_state(false)
	_append_response(_text("consent_cancelled"))


func _on_apply_pressed() -> void:
	if not bool(_pending_proposal_state.get("review", {}).get("acknowledged", _pending_proposal_state.get("review", {}).get("granted", false))):
		_append_response(_text("consent_required"))
		_refresh_review_state(false)
		return
	if _world_state == null or not _world_state.has_method("apply_pending_rule_proposal"):
		_append_response(_text("missing_worldstate"))
		return

	var result: Dictionary = _world_state.call("apply_pending_rule_proposal")
	_last_apply_result = result.duplicate(true)
	_refresh_review_state(false)

	if String(result.get("status", "")) in ["applied", "applied_with_warnings"]:
		_append_response("%s %s / %s" % [
			_text("apply_succeeded"),
			String(result.get("package_id", "")),
			String(result.get("runtime_rule_id", ""))
		])
	else:
		_append_response("%s %s" % [_text("apply_failed"), String(result.get("message", "unknown error"))])


func _append_response(text: String) -> void:
	if _response_panel.text.is_empty():
		_response_panel.text = text
	else:
		_response_panel.text += "\n\n" + text


func _announce_async_completion() -> void:
	var execution: Dictionary = _pending_proposal_state.get("execution", {})
	match String(execution.get("status", "idle")):
		"proposal_ready":
			_append_response("[color=cyan]ゲームマスター:[/color] " + _build_completion_gm_response())
			_append_response(_text("proposal_ready_hint"))
		"error":
			var last_error: Dictionary = _pending_proposal_state.get("last_error", {})
			_append_response("[color=cyan]ゲームマスター:[/color] PoC4 backend で提案を作れませんでした: %s" % _display_value(last_error.get("message", execution.get("message", "不明なエラー"))))


func _build_completion_gm_response() -> String:
	var summary: Dictionary = _pending_proposal_state.get("summary", {})
	if summary.is_empty():
		return "PoC4 backend の実行が完了しました。review 欄を確認してください。"
	return "PoC4 backend が提案を用意しました。package_id=%s / 操作数=%d。内容を確認したら、そのままゲームへ適用できます。" % [
		_display_value(summary.get("package_id", "unknown")),
		int(summary.get("operation_count", 0))
	]


func _set_submission_busy(busy: bool) -> void:
	_send_button.disabled = busy
	_input_field.editable = not busy


func _append_execution_lines(lines: Array, execution: Dictionary) -> void:
	if execution.is_empty():
		return
	lines.append("[b]PoC4 execution[/b]: %s" % _display_value(execution.get("status", "idle")))
	var phase := String(execution.get("phase", "")).strip_edges()
	if not phase.is_empty():
		lines.append("[b]phase[/b]: %s" % _display_value(phase))
	var message := String(execution.get("message", "")).strip_edges()
	if not message.is_empty():
		lines.append("[b]message[/b]: %s" % _display_value(message))


func _format_submission_target(suggested_target: Variant, issue_preview: Dictionary, apply_result: Dictionary) -> String:
	if suggested_target is Dictionary:
		return "%s @ %s (%s)" % [
			_sanitize(suggested_target.get("repo", "")),
			_sanitize(suggested_target.get("base_ref", "")),
			_sanitize(suggested_target.get("package_id", ""))
		]
	if apply_result is Dictionary and not String(apply_result.get("runtime_rule_id", "")).is_empty():
		return "runtime:%s" % _sanitize(apply_result.get("runtime_rule_id", ""))
	if issue_preview is Dictionary and issue_preview.has("summary"):
		var preview_summary: Dictionary = issue_preview.get("summary", {})
		if preview_summary.get("suggested_pr_target", null) is Dictionary:
			return _format_submission_target(preview_summary.get("suggested_pr_target", {}), {}, {})
	return "runtime install"


func _bool_label(value: bool) -> String:
	return "あり" if value else "なし"


func _append_codex_review_lines(lines: Array, codex: Dictionary) -> void:
	if codex.is_empty():
		return
	lines.append("")
	lines.append("[b]Codex detail[/b]:")
	lines.append("[b]session id[/b]: %s" % _display_value(codex.get("session_id", "")))
	lines.append("[b]model[/b]: %s" % _display_value(codex.get("model", "")))
	lines.append("[b]workdir[/b]: %s" % _display_value(codex.get("workdir", "")))
	lines.append("[b]approval[/b]: %s" % _display_value(codex.get("approval", "")))
	lines.append("[b]sandbox[/b]: %s" % _display_value(codex.get("sandbox", "")))
	var excerpt := _build_cli_excerpt(codex)
	if not excerpt.is_empty():
		lines.append("[b]cli 抜粋[/b]:\n%s" % _sanitize(excerpt))


func _format_array(values: Variant) -> String:
	if values is Array and not values.is_empty():
		var pieces: Array[String] = []
		for value in values:
			pieces.append(_display_value(value))
		return ", ".join(pieces)
	return "-"


func _build_cli_excerpt(codex: Dictionary) -> String:
	var excerpt := String(codex.get("cli_output_excerpt", "")).strip_edges()
	if excerpt.is_empty():
		excerpt = String(codex.get("cli_output", "")).strip_edges()
	if excerpt.length() > 280:
		excerpt = excerpt.substr(0, 280).strip_edges() + "…"
	return excerpt


func _display_value(value: Variant) -> String:
	var text := _sanitize(value)
	return text if not text.is_empty() else "-"


func _sanitize(value: Variant) -> String:
	return String(value).replace("[", "\\[").replace("]", "\\]").strip_edges()


func _duplicate_dict(value: Variant) -> Dictionary:
	return value.duplicate(true) if value is Dictionary else {}


func _text(key: String) -> String:
	var table: Dictionary = UI_TEXT.get(ACTIVE_LANGUAGE, UI_TEXT["ja"])
	return String(table.get(key, key))
