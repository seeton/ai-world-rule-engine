extends Control

signal closed

const CliCommandParserScript = preload("res://scripts/cli/cli_command_parser.gd")

const MAX_HISTORY := 50
const COLOR_PROMPT := "#9adfff"
const COLOR_OUTPUT := "#e8edf2"
const COLOR_OK := "#88e0a4"
const COLOR_ERROR := "#f4a07a"
const COLOR_HINT := "#bcc6d2"

const COLLAPSE_SIGNAL_LABELS := {
	"no_installed_rules": "ルールが 1 つも導入されていません",
	"disabled_rules_present": "無効化されたルールがあります",
	"rules_with_unmet_requirements": "親ルールが解決できないルールがあります"
}

var _world_state: Node = null
var _auto_open_reasons: PackedStringArray = PackedStringArray()
var _auto_open_badge: Label = null
var _scrollback: RichTextLabel = null
var _input: LineEdit = null
var _history: Array = []
var _history_cursor: int = -1
var _is_closing: bool = false


func _ready() -> void:
	set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	mouse_filter = MOUSE_FILTER_STOP
	modulate.a = 0.0
	_world_state = get_node_or_null("/root/WorldState")
	_build_ui()
	_print_intro()
	_fade_in()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		close_overlay()
		get_viewport().set_input_as_handled()
		return

	if _input != null and _input.has_focus():
		return

	if event is InputEventKey:
		var key_event := event as InputEventKey
		if key_event.pressed and not key_event.echo and (key_event.keycode == KEY_C or key_event.physical_keycode == KEY_C):
			close_overlay()
			get_viewport().set_input_as_handled()


func close_overlay() -> void:
	if _is_closing:
		return

	_is_closing = true
	var tween := create_tween()
	tween.tween_property(self, "modulate:a", 0.0, 0.12)
	tween.tween_callback(func() -> void:
		closed.emit()
		queue_free()
	)


func set_auto_open_reasons(reasons: PackedStringArray) -> void:
	_auto_open_reasons = reasons.duplicate()


func _build_ui() -> void:
	var scrim := ColorRect.new()
	scrim.color = Color(0.01, 0.02, 0.04, 0.62)
	scrim.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	scrim.mouse_filter = MOUSE_FILTER_STOP
	add_child(scrim)

	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", 32)
	margin.add_theme_constant_override("margin_top", 32)
	margin.add_theme_constant_override("margin_right", 32)
	margin.add_theme_constant_override("margin_bottom", 32)
	add_child(margin)

	var frame := PanelContainer.new()
	frame.size_flags_horizontal = SIZE_EXPAND_FILL
	frame.size_flags_vertical = SIZE_EXPAND_FILL
	frame.mouse_filter = MOUSE_FILTER_STOP
	margin.add_child(frame)

	var frame_style := StyleBoxFlat.new()
	frame_style.bg_color = Color(0.04, 0.06, 0.10, 0.96)
	frame_style.border_width_left = 2
	frame_style.border_width_top = 2
	frame_style.border_width_right = 2
	frame_style.border_width_bottom = 2
	frame_style.border_color = Color(0.46, 0.78, 0.66, 0.95)
	frame_style.corner_radius_top_left = 18
	frame_style.corner_radius_top_right = 18
	frame_style.corner_radius_bottom_left = 18
	frame_style.corner_radius_bottom_right = 18
	frame_style.shadow_color = Color(0.0, 0.0, 0.0, 0.55)
	frame_style.shadow_size = 18
	frame.add_theme_stylebox_override("panel", frame_style)

	var content_margin := MarginContainer.new()
	content_margin.add_theme_constant_override("margin_left", 18)
	content_margin.add_theme_constant_override("margin_top", 16)
	content_margin.add_theme_constant_override("margin_right", 18)
	content_margin.add_theme_constant_override("margin_bottom", 16)
	frame.add_child(content_margin)

	var layout := VBoxContainer.new()
	layout.size_flags_horizontal = SIZE_EXPAND_FILL
	layout.size_flags_vertical = SIZE_EXPAND_FILL
	layout.add_theme_constant_override("separation", 10)
	content_margin.add_child(layout)

	_build_header(layout)
	_build_scrollback(layout)
	_build_input(layout)


func _build_header(layout: VBoxContainer) -> void:
	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 16)
	layout.add_child(header)

	var title_wrap := VBoxContainer.new()
	title_wrap.size_flags_horizontal = SIZE_EXPAND_FILL
	title_wrap.add_theme_constant_override("separation", 4)
	header.add_child(title_wrap)

	var title := Label.new()
	title.text = "World CLI"
	title.add_theme_font_size_override("font_size", 28)
	title.add_theme_color_override("font_color", Color(0.62, 0.94, 0.84, 1.0))
	title_wrap.add_child(title)

	var description := Label.new()
	description.text = "ゲーム内 CLI。headless CLI と同じ文法を使い、実行はすべて CliCommandParser.dispatch_string() → WorldOpDispatcher を通ります。"
	description.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	description.add_theme_font_size_override("font_size", 12)
	description.add_theme_color_override("font_color", Color(0.78, 0.86, 0.92, 0.9))
	title_wrap.add_child(description)

	var help_label := Label.new()
	help_label.text = "Esc: 閉じる / ↑↓: ヒストリ / clear: スクロールバック消去"
	help_label.add_theme_font_size_override("font_size", 12)
	help_label.add_theme_color_override("font_color", Color(0.74, 0.80, 0.90, 0.85))
	title_wrap.add_child(help_label)

	if _auto_open_reasons.size() > 0:
		_auto_open_badge = Label.new()
		_auto_open_badge.text = _format_auto_open_reasons(_auto_open_reasons)
		_auto_open_badge.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_auto_open_badge.add_theme_font_size_override("font_size", 13)
		_auto_open_badge.add_theme_color_override("font_color", Color(1.0, 0.78, 0.36, 1.0))
		title_wrap.add_child(_auto_open_badge)

	var close_button := Button.new()
	close_button.text = "閉じる"
	close_button.size_flags_vertical = SIZE_SHRINK_CENTER
	close_button.pressed.connect(close_overlay)
	header.add_child(close_button)


func _build_scrollback(layout: VBoxContainer) -> void:
	_scrollback = RichTextLabel.new()
	_scrollback.bbcode_enabled = true
	_scrollback.scroll_active = true
	_scrollback.scroll_following = true
	_scrollback.size_flags_horizontal = SIZE_EXPAND_FILL
	_scrollback.size_flags_vertical = SIZE_EXPAND_FILL
	_scrollback.selection_enabled = true
	_scrollback.add_theme_font_size_override("normal_font_size", 14)
	_scrollback.custom_minimum_size = Vector2(0.0, 220.0)
	layout.add_child(_scrollback)


func _build_input(layout: VBoxContainer) -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	layout.add_child(row)

	var prompt := Label.new()
	prompt.text = "world>"
	prompt.add_theme_font_size_override("font_size", 16)
	prompt.add_theme_color_override("font_color", Color(0.62, 0.94, 0.84, 1.0))
	row.add_child(prompt)

	_input = LineEdit.new()
	_input.size_flags_horizontal = SIZE_EXPAND_FILL
	_input.placeholder_text = "例: inspect / rule disable rule_id / snapshot dump user://world.json"
	_input.text_submitted.connect(_on_input_submitted)
	_input.gui_input.connect(_on_input_gui_input)
	row.add_child(_input)

	var submit := Button.new()
	submit.text = "送信"
	submit.pressed.connect(_on_submit_pressed)
	row.add_child(submit)

	_input.call_deferred("grab_focus")


func _on_submit_pressed() -> void:
	if _input == null:
		return
	_on_input_submitted(_input.text)


func _on_input_submitted(text: String) -> void:
	var line := text.strip_edges()
	if line.is_empty():
		return
	_push_history(line)
	_history_cursor = -1
	_input.text = ""
	_input.grab_focus()

	_append_prompt(line)
	var args := _tokenize(line)
	if args.is_empty():
		return
	var result: Dictionary = CliCommandParserScript.dispatch_string(_world_state, args, {})
	_handle_result(result)


func _handle_result(result: Dictionary) -> void:
	if String(result.get("status", "")) == "directive":
		var payload: Dictionary = result.get("payload", {})
		match String(payload.get("directive", "")):
			"clear":
				_scrollback.clear()
				_append_hint("scrollback cleared.")
				return

	var status := String(result.get("status", ""))
	var color := COLOR_OUTPUT
	if status == "ok" or status == "dry_run":
		color = COLOR_OK
	elif status == "execution_error" or status == "validation_error" or status == "usage_error":
		color = COLOR_ERROR

	for line in result.get("lines", PackedStringArray()):
		_append_colored(String(line), color)


func _on_input_gui_input(event: InputEvent) -> void:
	if not (event is InputEventKey):
		return
	var key_event := event as InputEventKey
	if not key_event.pressed or key_event.echo:
		return
	match key_event.keycode:
		KEY_UP:
			_navigate_history(-1)
			get_viewport().set_input_as_handled()
		KEY_DOWN:
			_navigate_history(1)
			get_viewport().set_input_as_handled()


func _navigate_history(direction: int) -> void:
	if _history.is_empty():
		return
	if _history_cursor == -1:
		_history_cursor = _history.size()
	_history_cursor = clampi(_history_cursor + direction, 0, _history.size())
	if _history_cursor >= _history.size():
		_input.text = ""
		_input.caret_column = 0
		_history_cursor = -1
		return
	_input.text = String(_history[_history_cursor])
	_input.caret_column = _input.text.length()


func _push_history(line: String) -> void:
	if not _history.is_empty() and String(_history[-1]) == line:
		return
	_history.append(line)
	if _history.size() > MAX_HISTORY:
		_history.remove_at(0)


func _print_intro() -> void:
	_append_hint("World CLI へようこそ。'help' で一覧、'clear' でスクロールバックを消去します。")
	if _auto_open_reasons.size() > 0:
		_append_colored("(自動オープン: %s)" % ", ".join(_auto_open_reasons), COLOR_ERROR)
	_handle_result(CliCommandParserScript.dispatch_string(_world_state, PackedStringArray(["help"]), {}))


func _append_prompt(line: String) -> void:
	_append_colored("world> %s" % line, COLOR_PROMPT)


func _append_hint(line: String) -> void:
	_append_colored(line, COLOR_HINT)


func _append_colored(line: String, color: String) -> void:
	if _scrollback == null:
		return
	_scrollback.append_text("[color=%s]%s[/color]\n" % [color, _escape_bbcode(line)])


func _escape_bbcode(text: String) -> String:
	return text.replace("[", "[lb]")


func _tokenize(line: String) -> PackedStringArray:
	var result := PackedStringArray()
	var buffer := ""
	var in_quote := false
	for index in range(line.length()):
		var ch := line.substr(index, 1)
		if ch == "\"":
			in_quote = not in_quote
			continue
		if not in_quote and (ch == " " or ch == "\t"):
			if not buffer.is_empty():
				result.append(buffer)
				buffer = ""
			continue
		buffer += ch
	if not buffer.is_empty():
		result.append(buffer)
	return result


func _format_auto_open_reasons(reasons: PackedStringArray) -> String:
	if reasons.is_empty():
		return ""
	var lines: PackedStringArray = PackedStringArray()
	for reason in reasons:
		var label := String(COLLAPSE_SIGNAL_LABELS.get(reason, reason))
		lines.append("  - %s (%s)" % [label, reason])
	return "自動オープン:\n%s" % "\n".join(lines)


func _fade_in() -> void:
	var tween := create_tween()
	tween.tween_property(self, "modulate:a", 1.0, 0.16)
