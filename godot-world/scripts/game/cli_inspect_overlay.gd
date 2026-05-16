extends Control

signal closed

const CliCommandParserScript = preload("res://scripts/cli/cli_command_parser.gd")

const MAX_HISTORY := 50
const COLOR_PROMPT := "#9adfff"
const COLOR_OUTPUT := "#e8edf2"
const COLOR_OK := "#88e0a4"
const COLOR_ERROR := "#f4a07a"
const COLOR_HINT := "#bcc6d2"
const CLI_COMPLETION_TEMPLATES := [
	{"value": "help", "summary": "利用可能なコマンド一覧を表示"},
	{"value": "inspect", "summary": "現在のワールド状態を表示"},
	{"value": "clear", "summary": "overlay のスクロールバックを消去"},
	{"value": "package list", "summary": "利用可能な package を列挙"},
	{"value": "package install ", "summary": "指定 package を現在の world に導入"},
	{"value": "rule enable ", "summary": "指定 rule を有効化"},
	{"value": "rule disable ", "summary": "指定 rule を無効化"},
	{"value": "snapshot dump user://world.json", "summary": "スナップショットを書き出し"},
	{"value": "snapshot load user://world.json", "summary": "スナップショットを読み込み"}
]

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
var _history_draft: String = ""
var _completion_panel: PanelContainer = null
var _completion_list: ItemList = null
var _completion_candidates: Array = []
var _completion_index: int = 0
var _completion_requested: bool = false
var _is_programmatic_input_change: bool = false
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
	help_label.text = "Esc: 閉じる / ↑↓: ヒストリ / Tab: 補完 / clear: スクロールバック消去"
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
	var input_column := VBoxContainer.new()
	input_column.add_theme_constant_override("separation", 6)
	layout.add_child(input_column)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	input_column.add_child(row)

	var prompt := Label.new()
	prompt.text = "world>"
	prompt.add_theme_font_size_override("font_size", 16)
	prompt.add_theme_color_override("font_color", Color(0.62, 0.94, 0.84, 1.0))
	row.add_child(prompt)

	_input = LineEdit.new()
	_input.size_flags_horizontal = SIZE_EXPAND_FILL
	_input.placeholder_text = "例: inspect / rule disable rule_id / snapshot dump user://world.json"
	_input.keep_editing_on_text_submit = true
	_input.text_submitted.connect(_on_input_submitted)
	_input.text_changed.connect(_on_input_text_changed)
	_input.gui_input.connect(_on_input_gui_input)
	row.add_child(_input)

	var submit := Button.new()
	submit.text = "送信"
	submit.pressed.connect(_on_submit_pressed)
	row.add_child(submit)

	_completion_panel = PanelContainer.new()
	_completion_panel.visible = false
	input_column.add_child(_completion_panel)

	var completion_margin := MarginContainer.new()
	completion_margin.add_theme_constant_override("margin_left", 10)
	completion_margin.add_theme_constant_override("margin_top", 8)
	completion_margin.add_theme_constant_override("margin_right", 10)
	completion_margin.add_theme_constant_override("margin_bottom", 8)
	_completion_panel.add_child(completion_margin)

	var completion_column := VBoxContainer.new()
	completion_column.add_theme_constant_override("separation", 4)
	completion_margin.add_child(completion_column)

	var completion_hint := Label.new()
	completion_hint.text = "Tab で候補表示 / ↑↓ で候補選択 / Tab でもう一度確定"
	completion_hint.add_theme_font_size_override("font_size", 11)
	completion_hint.add_theme_color_override("font_color", Color(0.74, 0.80, 0.90, 0.85))
	completion_column.add_child(completion_hint)

	_completion_list = ItemList.new()
	_completion_list.custom_minimum_size = Vector2(0.0, 96.0)
	_completion_list.select_mode = ItemList.SELECT_SINGLE
	_completion_list.item_selected.connect(_on_completion_item_selected)
	_completion_list.item_activated.connect(_on_completion_item_activated)
	completion_column.add_child(_completion_list)

	_request_input_focus()


func _on_submit_pressed() -> void:
	if _input == null:
		return
	_on_input_submitted(_input.text)


func _on_input_submitted(text: String) -> void:
	var line := text.strip_edges()
	if line.is_empty():
		_request_input_focus()
		return
	_push_history(line)
	_history_cursor = -1
	_history_draft = ""
	_input.text = ""
	_hide_completion_candidates()

	_append_prompt(line)
	var args := _tokenize(line)
	if args.is_empty():
		_request_input_focus()
		return
	var result: Dictionary = CliCommandParserScript.dispatch_string(_world_state, args, {})
	_handle_result(result)
	_request_input_focus()

func _on_input_text_changed(_new_text: String) -> void:
	if _is_programmatic_input_change:
		return
	if _history_cursor == -1:
		_history_draft = _input.text
	if _completion_requested:
		_refresh_completion_candidates(true)


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
		KEY_TAB:
			_handle_tab_completion()
			get_viewport().set_input_as_handled()
		KEY_UP:
			if _completion_panel != null and _completion_panel.visible and not _completion_candidates.is_empty():
				_cycle_completion_candidate(-1)
			else:
				_navigate_history(-1)
			get_viewport().set_input_as_handled()
		KEY_DOWN:
			if _completion_panel != null and _completion_panel.visible and not _completion_candidates.is_empty():
				_cycle_completion_candidate(1)
			else:
				_navigate_history(1)
			get_viewport().set_input_as_handled()

func _handle_tab_completion() -> void:
	if _completion_panel != null and _completion_panel.visible and not _completion_candidates.is_empty():
		_apply_completion_candidate(_completion_index)
		return
	_completion_requested = true
	_refresh_completion_candidates(true)

func _refresh_completion_candidates(force_visible: bool) -> void:
	if _completion_panel == null or _completion_list == null:
		return
	_completion_candidates = _build_completion_candidates(_input.text)
	if _completion_candidates.is_empty():
		_hide_completion_candidates()
		return
	_completion_index = clampi(_completion_index, 0, _completion_candidates.size() - 1)
	_completion_list.clear()
	for candidate in _completion_candidates:
		_completion_list.add_item("%s — %s" % [
			String(candidate.get("value", "")),
			String(candidate.get("summary", ""))
		])
	_select_completion_candidate(_completion_index)
	if force_visible:
		_completion_panel.visible = true

func _hide_completion_candidates() -> void:
	_completion_requested = false
	_completion_candidates.clear()
	_completion_index = 0
	if _completion_list != null:
		_completion_list.clear()
	if _completion_panel != null:
		_completion_panel.visible = false

func _select_completion_candidate(index: int) -> void:
	if _completion_list == null or _completion_candidates.is_empty():
		return
	_completion_index = clampi(index, 0, _completion_candidates.size() - 1)
	_completion_list.deselect_all()
	_completion_list.select(_completion_index)
	_completion_list.ensure_current_is_visible()

func _cycle_completion_candidate(direction: int) -> void:
	if _completion_candidates.is_empty():
		return
	var next_index := _completion_index + direction
	if next_index < 0:
		next_index = _completion_candidates.size() - 1
	elif next_index >= _completion_candidates.size():
		next_index = 0
	_select_completion_candidate(next_index)

func _apply_completion_candidate(index: int) -> void:
	if index < 0 or index >= _completion_candidates.size():
		return
	_set_input_text(String(_completion_candidates[index].get("value", "")))
	_hide_completion_candidates()
	_request_input_focus()

func _set_input_text(value: String) -> void:
	if _input == null:
		return
	_is_programmatic_input_change = true
	_input.text = value
	_input.caret_column = value.length()
	_is_programmatic_input_change = false
	if _history_cursor == -1:
		_history_draft = value

func _on_completion_item_selected(index: int) -> void:
	_select_completion_candidate(index)

func _on_completion_item_activated(index: int) -> void:
	_apply_completion_candidate(index)

func _build_completion_candidates(input_text: String) -> Array:
	var query := input_text
	var tokens := _tokenize(query)
	var ends_with_space := not query.is_empty() and (query.ends_with(" ") or query.ends_with("\t"))
	var trimmed_query := query.strip_edges()
	if tokens.is_empty():
		return _filter_completion_candidates(CLI_COMPLETION_TEMPLATES, query)

	var command := String(tokens[0])
	if command == "rule" and tokens.size() >= 2 and (String(tokens[1]) == "enable" or String(tokens[1]) == "disable"):
		var rule_partial := ""
		if tokens.size() >= 3:
			rule_partial = String(tokens[2])
		elif ends_with_space or trimmed_query == "rule %s" % String(tokens[1]):
			rule_partial = ""
		return _build_rule_completion_candidates(String(tokens[1]), rule_partial)

	if command == "package" and tokens.size() >= 2 and String(tokens[1]) == "install":
		var package_partial := ""
		if tokens.size() >= 3:
			package_partial = String(tokens[2])
		elif ends_with_space or trimmed_query == "package install":
			package_partial = ""
		return _build_package_completion_candidates(package_partial)

	if command == "snapshot" and tokens.size() >= 2 and (String(tokens[1]) == "dump" or String(tokens[1]) == "load"):
		var action := String(tokens[1])
		var typed_path := ""
		if tokens.size() >= 3:
			typed_path = String(tokens[2])
		elif ends_with_space or trimmed_query == "snapshot %s" % action:
			typed_path = ""
		return _build_snapshot_completion_candidates(action, typed_path)

	return _filter_completion_candidates(CLI_COMPLETION_TEMPLATES, query)

func _build_rule_completion_candidates(action: String, partial_rule_id: String) -> Array:
	var candidates: Array = []
	var partial_lower := partial_rule_id.to_lower()
	var installed_rules := _extract_installed_rules()
	var target_enabled_state := action == "disable"
	for rule_data in installed_rules:
		if not (rule_data is Dictionary):
			continue
		var rule_id := String(rule_data.get("id", "")).strip_edges()
		if rule_id.is_empty():
			continue
		var label := String(rule_data.get("name", rule_id))
		var enabled := bool(rule_data.get("enabled", true))
		if enabled != target_enabled_state:
			continue
		if not partial_lower.is_empty() and rule_id.to_lower().find(partial_lower) == -1 and label.to_lower().find(partial_lower) == -1:
			continue
		candidates.append({
			"value": "rule %s %s" % [action, rule_id],
			"summary": "%s (%s)" % [label, "enabled" if enabled else "disabled"]
		})
	if candidates.is_empty():
		var summary := ""
		if installed_rules.is_empty():
			summary = "現在の world には導入済み rule がないため、%s 候補はありません" % action
		elif action == "enable":
			summary = "現在は無効な rule がないため、enable 候補はありません"
		elif action == "disable":
			summary = "現在は有効な rule がないため、disable 候補はありません"
		elif partial_lower.is_empty():
			summary = "%s 候補になる rule が見つかりません" % action
		else:
			summary = "入力に一致する rule が見つかりません"
		candidates.append({
			"value": "rule %s " % action,
			"summary": summary
	})
	return candidates

func _build_package_completion_candidates(partial_package_id: String) -> Array:
	var candidates: Array = []
	var partial_lower := partial_package_id.to_lower()
	var packages := _extract_available_packages()
	for package_summary in packages:
		if not (package_summary is Dictionary):
			continue
		var package_data: Dictionary = package_summary
		var package_id := String(package_data.get("package_id", "")).strip_edges()
		if package_id.is_empty():
			continue
		var display_name := String(package_data.get("display_name", package_id))
		var description := String(package_data.get("description", "")).strip_edges()
		var haystack := ("%s %s %s" % [package_id, display_name, description]).to_lower()
		if not partial_lower.is_empty() and haystack.find(partial_lower) == -1:
			continue
		var summary := display_name
		if not description.is_empty():
			summary = "%s — %s" % [display_name, description]
		candidates.append({
			"value": "package install %s" % package_id,
			"summary": summary
		})
	if candidates.is_empty():
		var summary := "現在利用可能な package が見つかりません"
		if not partial_lower.is_empty():
			summary = "入力に一致する package が見つかりません"
		candidates.append({
			"value": "package install ",
			"summary": summary
		})
	return candidates

func _build_snapshot_completion_candidates(action: String, typed_path: String) -> Array:
	var candidates: Array = []
	var path_candidates := [
		"user://world.json",
		"user://snapshot.json",
		"user://cli_snapshot.json"
	]
	var typed_lower := typed_path.to_lower()
	for path in path_candidates:
		if not typed_lower.is_empty() and path.to_lower().find(typed_lower) == -1:
			continue
		candidates.append({
			"value": "snapshot %s %s" % [action, path],
			"summary": "snapshot %s の候補パス" % action
		})
	return candidates

func _filter_completion_candidates(source: Array, query: String) -> Array:
	var filtered: Array = []
	var trimmed_query := query.strip_edges()
	var query_lower := trimmed_query.to_lower()
	var query_tokens := _tokenize(query_lower)
	for candidate in source:
		if not (candidate is Dictionary):
			continue
		var value := String(candidate.get("value", ""))
		if _completion_value_matches_query(value, query_lower, query_tokens):
			filtered.append(candidate)
	return filtered


func _completion_value_matches_query(value: String, query_lower: String, query_tokens: PackedStringArray) -> bool:
	if query_lower.is_empty():
		return true
	var value_lower := value.to_lower()
	if value_lower.begins_with(query_lower):
		return true
	var value_tokens := _tokenize(value_lower)
	if query_tokens.is_empty() or value_tokens.is_empty():
		return false
	if query_tokens.size() == 1:
		var token := String(query_tokens[0])
		for value_token in value_tokens:
			if String(value_token).begins_with(token):
				return true
		return false
	if query_tokens.size() > value_tokens.size():
		return false
	for index in range(query_tokens.size()):
		if not String(value_tokens[index]).begins_with(String(query_tokens[index])):
			return false
	return true

func _extract_installed_rules() -> Array:
	if _world_state == null or not _world_state.has_method("get_world_snapshot"):
		return []
	var snapshot_variant: Variant = _world_state.call("get_world_snapshot")
	if not (snapshot_variant is Dictionary):
		return []
	var snapshot: Dictionary = snapshot_variant
	var raw_rules = snapshot.get("installed_rules", [])
	if raw_rules is Array:
		return raw_rules
	if raw_rules is Dictionary:
		var rules: Array = []
		var rule_ids: Array = raw_rules.keys()
		rule_ids.sort()
		for rule_id in rule_ids:
			rules.append(raw_rules[rule_id])
		return rules
	return []


func _extract_available_packages() -> Array:
	if _world_state == null or not _world_state.has_method("get_available_rule_packages"):
		return []
	var packages_variant: Variant = _world_state.call("get_available_rule_packages")
	if not (packages_variant is Array):
		return []
	var packages: Array = packages_variant.duplicate(true)
	packages.sort_custom(func(a: Variant, b: Variant) -> bool:
		if not (a is Dictionary) or not (b is Dictionary):
			return false
		return String((a as Dictionary).get("package_id", "")) < String((b as Dictionary).get("package_id", ""))
	)
	return packages


func _request_input_focus() -> void:
	if _input == null or not is_instance_valid(_input):
		return
	_input.call_deferred("grab_focus")
	call_deferred("_finalize_input_focus")


func _finalize_input_focus() -> void:
	if _input == null or not is_instance_valid(_input):
		return
	_input.grab_focus()
	_input.caret_column = _input.text.length()


func _navigate_history(direction: int) -> void:
	if _history.is_empty():
		return
	if _history_cursor == -1:
		_history_draft = _input.text
		_history_cursor = _history.size()
	_history_cursor = clampi(_history_cursor + direction, 0, _history.size())
	if _history_cursor >= _history.size():
		_set_input_text(_history_draft)
		_history_cursor = -1
		_hide_completion_candidates()
		return
	_set_input_text(String(_history[_history_cursor]))
	_hide_completion_candidates()


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
