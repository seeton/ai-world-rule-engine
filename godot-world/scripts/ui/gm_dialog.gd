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
		"welcome_1": "[color=cyan]ゲームマスター:[/color] ようこそ。私に世界のルール作成を依頼できます。",
		"welcome_2": "例えば「時間のルールを作成しろ」と入力してみてください。",
		"missing_worldstate": "[color=red]エラー:[/color] WorldStateが見つかりません。",
		"clock_hint": "[color=cyan]ゲームマスター:[/color] 世界に戻ると右上に時計が表示されます。"
	},
	"en": {
		"title": "Game Master",
		"back": "<- Back",
		"input_label": "Your request:",
		"placeholder": "Example: create time rule",
		"send": "Send",
		"welcome_1": "[color=cyan]Game Master:[/color] Welcome. You can ask me to create world rules.",
		"welcome_2": "Try entering 'create time rule'.",
		"missing_worldstate": "[color=red]Error:[/color] WorldState was not found.",
		"clock_hint": "[color=cyan]Game Master:[/color] Return to the world to see the clock in the top-right."
	}
}

var _world_state: Node = null
var _input_field: TextEdit
var _response_panel: RichTextLabel
var _back_button: Button
var _send_button: Button


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	modulate.a = 0.0
	_world_state = get_node("/root/WorldState")
	_build_ui()
	_show_welcome_message()
	_fade_in()


func _fade_in() -> void:
	var tween := create_tween()
	tween.tween_property(self, "modulate:a", 1.0, 0.25)


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
	_response_panel.fit_content = true
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
	button_row.alignment = BoxContainer.ALIGNMENT_END
	vbox.add_child(button_row)

	_send_button = Button.new()
	_send_button.text = _text("send")
	_send_button.pressed.connect(_on_send_pressed)
	button_row.add_child(_send_button)


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
	if _world_state == null or not _world_state.has_method("talk_to_game_master"):
		_append_response(_text("missing_worldstate"))
		return

	var result: Dictionary = _world_state.call("talk_to_game_master", message)
	var gm_response := String(result.get("gm_response", result.get("reply", "")))
	if not gm_response.is_empty():
		_append_response("[color=cyan]ゲームマスター:[/color] " + gm_response)
	if String(result.get("action", "")) == "installed_time_rule":
		_append_response(_text("clock_hint"))


func _append_response(text: String) -> void:
	if _response_panel.text.is_empty():
		_response_panel.text = text
	else:
		_response_panel.text += "\n\n" + text


func _text(key: String) -> String:
	var table: Dictionary = UI_TEXT.get(ACTIVE_LANGUAGE, UI_TEXT["ja"])
	return String(table.get(key, key))
