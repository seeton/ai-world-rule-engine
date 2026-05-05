extends Control

signal closed

var _world_state: Node = null
var _input_field: TextEdit
var _response_panel: RichTextLabel
var _back_button: Button
var _send_button: Button
var _pending_proposals: Array = []


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_world_state = get_node("/root/WorldState")
	_build_ui()
	_show_welcome_message()


func _build_ui() -> void:
	var bg := ColorRect.new()
	bg.color = Color(0.1, 0.1, 0.15, 1.0)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", 32)
	margin.add_theme_constant_override("margin_top", 32)
	margin.add_theme_constant_override("margin_right", 32)
	margin.add_theme_constant_override("margin_bottom", 32)
	add_child(margin)

	var vbox := VBoxContainer.new()
	vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vbox.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vbox.add_theme_constant_override("separation", 16)
	margin.add_child(vbox)

	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 12)
	vbox.add_child(header)

	var title := Label.new()
	title.text = "ゲームマスター"
	title.add_theme_font_size_override("font_size", 28)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(title)

	_back_button = Button.new()
	_back_button.text = "← 戻る"
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
	_response_panel.fit_content = true
	_response_panel.scroll_following = true
	_response_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_response_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	response_margin.add_child(_response_panel)

	var input_label := Label.new()
	input_label.text = "あなたの指示:"
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
	_input_field.placeholder_text = "例: 時間のルールを作成しろ"
	_input_field.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
	input_margin.add_child(_input_field)

	var button_row := HBoxContainer.new()
	button_row.add_theme_constant_override("separation", 12)
	button_row.alignment = BoxContainer.ALIGNMENT_END
	vbox.add_child(button_row)

	_send_button = Button.new()
	_send_button.text = "送信"
	_send_button.pressed.connect(_on_send_pressed)
	button_row.add_child(_send_button)


func _show_welcome_message() -> void:
	_append_response("[color=cyan]ゲームマスター:[/color] ようこそ。世界のルールを作成したり、変更したりすることができます。")
	_append_response("例えば「時間のルールを作成しろ」と入力してみてください。")


func _on_back_pressed() -> void:
	closed.emit()
	queue_free()


func _on_send_pressed() -> void:
	var user_text := _input_field.text.strip_edges()
	if user_text.is_empty():
		return

	_append_response("[color=yellow]あなた:[/color] " + user_text)
	_input_field.text = ""

	_process_user_message(user_text)


func _process_user_message(message: String) -> void:
	if _world_state == null:
		_append_response("[color=red]エラー:[/color] WorldStateが見つかりません。")
		return

	var result: Dictionary = _world_state.submit_player_task(message)
	var status := String(result.get("status", "unknown"))

	if status == "proposal_ready":
		var proposals: Array = result.get("proposals", [])
		if proposals.is_empty():
			_append_response("[color=orange]ゲームマスター:[/color] 提案が見つかりませんでした。")
			return

		_pending_proposals = proposals
		_append_response("[color=cyan]ゲームマスター:[/color] 次のルールを提案します:")

		for i in range(proposals.size()):
			var prop: Dictionary = proposals[i]
			var title := String(prop.get("title", "無題"))
			var desc := String(prop.get("description", "説明なし"))
			_append_response("  %d. [b]%s[/b]: %s" % [i + 1, title, desc])

		if proposals.size() == 1:
			_append_response("")
			_install_proposal(0)
		else:
			_append_response("[color=cyan]番号を入力してインストールしてください。[/color]")

	elif status == "needs_rule_patch":
		_append_response("[color=orange]ゲームマスター:[/color] 該当するテンプレートが見つかりませんでした。")
		_append_response("別の言い方で試してみてください。")

	else:
		_append_response("[color=red]エラー:[/color] 不明なステータス: " + status)


func _install_proposal(index: int) -> void:
	if index < 0 or index >= _pending_proposals.size():
		_append_response("[color=red]エラー:[/color] 無効な番号です。")
		return

	var proposal: Dictionary = _pending_proposals[index]
	var rule_patch: Dictionary = proposal.get("rule_patch", {})

	if rule_patch.is_empty():
		_append_response("[color=red]エラー:[/color] ルールパッチが空です。")
		return

	var install_result: Dictionary = _world_state.create_rule_from_patch(rule_patch)
	var install_status := String(install_result.get("status", "unknown"))

	if install_status == "installed":
		var rule_name := String(proposal.get("title", "ルール"))
		_append_response("[color=lime]成功:[/color] 「%s」をインストールしました！" % rule_name)
		_append_response("[color=cyan]ゲームマスター:[/color] 世界に戻って変化を確認してください。")
	elif install_status == "error":
		var error_msg := String(install_result.get("message", "不明なエラー"))
		_append_response("[color=red]エラー:[/color] " + error_msg)
	else:
		_append_response("[color=orange]警告:[/color] 予期しないステータス: " + install_status)

	_pending_proposals.clear()


func _append_response(text: String) -> void:
	if _response_panel.text.is_empty():
		_response_panel.text = text
	else:
		_response_panel.text += "\n\n" + text
