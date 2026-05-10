extends Control

# In-game C-key overlay (Tier 1 control surface).
# Renders the same report the headless CLI's `inspect` produces (via the
# shared scripts/cli/inspect_report.gd) and lets the player run engine-safe
# actuation directly: per-rule enable/disable, snapshot save, snapshot load.
# Actuation is funneled through scripts/cli/cli_actions.gd so it cannot drift
# from the headless CLI dispatcher (Tier 2).

signal closed

const InspectReportScript = preload("res://scripts/cli/inspect_report.gd")
const CliActionsScript = preload("res://scripts/cli/cli_actions.gd")
const REFRESH_INTERVAL: float = 0.35

const COLLAPSE_SIGNAL_LABELS := {
	"no_installed_rules": "ルールが 1 つも導入されていません",
	"disabled_rules_present": "無効化されたルールがあります",
	"rules_with_unmet_requirements": "親ルールが解決できないルールがあります"
}

var _world_state: Node = null
var _auto_open_reasons: PackedStringArray = PackedStringArray()
var _auto_open_badge: Label = null
var _world_label: Label = null
var _summary_label: Label = null
var _signals_label: Label = null
var _unmet_label: Label = null
var _snapshot_status_label: Label = null
var _action_status_label: Label = null
var _rules_container: VBoxContainer = null
var _rules_empty_label: Label = null
var _snapshot_picker: OptionButton = null
var _snapshot_load_button: Button = null
var _snapshot_refresh_button: Button = null
var _snapshot_entries: Array = []
var _last_snapshot_path: String = ""
var _last_report_signature: String = ""
var _refresh_timer: float = 0.0
var _is_closing: bool = false


func _ready() -> void:
	set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	mouse_filter = MOUSE_FILTER_STOP
	modulate.a = 0.0
	_world_state = get_node_or_null("/root/WorldState")
	_build_ui()
	_refresh_snapshot_picker()
	_refresh_overlay(true)
	_fade_in()


func _process(delta: float) -> void:
	_refresh_timer -= delta
	if _refresh_timer > 0.0:
		return

	_refresh_timer = REFRESH_INTERVAL
	_refresh_overlay()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey:
		var key_event := event as InputEventKey
		if key_event.pressed and not key_event.echo and (key_event.keycode == KEY_C or key_event.physical_keycode == KEY_C):
			close_overlay()
			get_viewport().set_input_as_handled()
			return

	if event.is_action_pressed("ui_cancel"):
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

	_world_label = _make_body_label(layout)
	_summary_label = _make_body_label(layout)
	_signals_label = _make_body_label(layout)
	_unmet_label = _make_body_label(layout)

	_build_rule_actuation_section(layout)
	_build_snapshot_section(layout)

	_action_status_label = _make_body_label(layout)
	_action_status_label.text = "操作待機中。ルールの enable/disable やスナップショットの保存・読み込みができます。"


func _build_header(layout: VBoxContainer) -> void:
	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 16)
	layout.add_child(header)

	var title_wrap := VBoxContainer.new()
	title_wrap.size_flags_horizontal = SIZE_EXPAND_FILL
	title_wrap.add_theme_constant_override("separation", 4)
	header.add_child(title_wrap)

	var title := Label.new()
	title.text = "CLI inspect / 制御パネル"
	title.add_theme_font_size_override("font_size", 28)
	title.add_theme_color_override("font_color", Color(0.62, 0.94, 0.84, 1.0))
	title_wrap.add_child(title)

	var description := Label.new()
	description.text = "headless CLI の `inspect` と同じ集計を表示し、engine-safe な操作 (rule enable/disable, snapshot 保存・読み込み) を直接実行できます。actuation は scripts/cli/cli_actions.gd 経由で headless CLI と同じ経路を使います。"
	description.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	description.add_theme_font_size_override("font_size", 12)
	description.add_theme_color_override("font_color", Color(0.78, 0.86, 0.92, 0.9))
	title_wrap.add_child(description)

	var help_label := Label.new()
	help_label.text = "C / Esc: 閉じる"
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
	close_button.text = "閉じる (C / Esc)"
	close_button.size_flags_vertical = SIZE_SHRINK_CENTER
	close_button.pressed.connect(close_overlay)
	header.add_child(close_button)


func _build_rule_actuation_section(layout: VBoxContainer) -> void:
	var section_label := Label.new()
	section_label.text = "ルール lifecycle:"
	section_label.add_theme_font_size_override("font_size", 14)
	section_label.add_theme_color_override("font_color", Color(0.86, 0.94, 0.78, 0.95))
	layout.add_child(section_label)

	var scroll := ScrollContainer.new()
	scroll.size_flags_horizontal = SIZE_EXPAND_FILL
	scroll.size_flags_vertical = SIZE_EXPAND_FILL
	scroll.custom_minimum_size = Vector2(0.0, 160.0)
	layout.add_child(scroll)

	_rules_container = VBoxContainer.new()
	_rules_container.size_flags_horizontal = SIZE_EXPAND_FILL
	_rules_container.add_theme_constant_override("separation", 4)
	scroll.add_child(_rules_container)

	_rules_empty_label = Label.new()
	_rules_empty_label.text = "導入済みルールはありません。"
	_rules_empty_label.add_theme_font_size_override("font_size", 13)
	_rules_empty_label.add_theme_color_override("font_color", Color(0.78, 0.84, 0.92, 0.85))
	_rules_container.add_child(_rules_empty_label)


func _build_snapshot_section(layout: VBoxContainer) -> void:
	var section_label := Label.new()
	section_label.text = "スナップショット:"
	section_label.add_theme_font_size_override("font_size", 14)
	section_label.add_theme_color_override("font_color", Color(0.86, 0.94, 0.78, 0.95))
	layout.add_child(section_label)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	layout.add_child(row)

	var save_button := Button.new()
	save_button.text = "現在の世界を保存"
	save_button.tooltip_text = "user:// に cli_inspect_<timestamp>.json として書き出します。"
	save_button.pressed.connect(_on_save_snapshot_pressed)
	row.add_child(save_button)

	_snapshot_picker = OptionButton.new()
	_snapshot_picker.size_flags_horizontal = SIZE_EXPAND_FILL
	row.add_child(_snapshot_picker)

	_snapshot_refresh_button = Button.new()
	_snapshot_refresh_button.text = "再スキャン"
	_snapshot_refresh_button.tooltip_text = "user:// 配下の cli_inspect_*.json を再読込します。"
	_snapshot_refresh_button.pressed.connect(_refresh_snapshot_picker)
	row.add_child(_snapshot_refresh_button)

	_snapshot_load_button = Button.new()
	_snapshot_load_button.text = "選択を読み込む"
	_snapshot_load_button.tooltip_text = "選択したスナップショットで現在の WorldState を上書きします。"
	_snapshot_load_button.pressed.connect(_on_load_snapshot_pressed)
	row.add_child(_snapshot_load_button)

	_snapshot_status_label = _make_body_label(layout)


func _make_body_label(parent: Control) -> Label:
	var label := Label.new()
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.add_theme_font_size_override("font_size", 14)
	label.add_theme_color_override("font_color", Color(0.92, 0.96, 0.98, 0.95))
	parent.add_child(label)
	return label


func _refresh_overlay(force: bool = false) -> void:
	var report: Dictionary = InspectReportScript.build(_world_state, "")
	var signature := JSON.stringify(report)
	if not force and signature == _last_report_signature:
		return
	_last_report_signature = signature

	var world_info: Dictionary = report.get("world", {})
	_world_label.text = "ワールド: %s (%s) / mode=%s / tick=%d / 経過 %.2fs" % [
		String(world_info.get("world_name", "")),
		String(world_info.get("world_id", "")),
		String(world_info.get("world_mode", "")),
		int(world_info.get("tick", 0)),
		float(world_info.get("elapsed_seconds", 0.0))
	]

	_summary_label.text = "ルール %d 件 / 利用可能パッケージ %d 件" % [
		int(report.get("installed_rule_count", 0)),
		int(report.get("installed_package_count", 0))
	]

	var status: Dictionary = report.get("world_status", {})
	var collapse_signals: Array = status.get("collapse_signals", [])
	var signals_text := ", ".join(_to_string_array(collapse_signals)) if not collapse_signals.is_empty() else "なし"
	_signals_label.text = "崩壊シグナル: %s\nworld_clock=%s / movement=%s / input=%s" % [
		signals_text,
		_yes_no(bool(status.get("has_world_clock", false))),
		_yes_no(bool(status.get("has_movement_provider", false))),
		_yes_no(bool(status.get("has_input_provider", false)))
	]

	var unmet_ids: Array = report.get("rules_with_unmet_requirements", [])
	_unmet_label.text = "親ルール未充足: %s" % _format_id_list(unmet_ids)

	_rebuild_rule_rows(report.get("installed_rules", []))

	if _last_snapshot_path.is_empty():
		_snapshot_status_label.text = "保存履歴: 未保存。「現在の世界を保存」を押すと user:// に書き出します。"
	else:
		_snapshot_status_label.text = "最終保存: %s" % _last_snapshot_path


func _rebuild_rule_rows(installed_rules: Array) -> void:
	if _rules_container == null:
		return
	for child in _rules_container.get_children():
		child.queue_free()

	if installed_rules.is_empty():
		_rules_empty_label = Label.new()
		_rules_empty_label.text = "導入済みルールはありません。"
		_rules_empty_label.add_theme_font_size_override("font_size", 13)
		_rules_empty_label.add_theme_color_override("font_color", Color(0.78, 0.84, 0.92, 0.85))
		_rules_container.add_child(_rules_empty_label)
		return

	for rule in installed_rules:
		if not (rule is Dictionary):
			continue
		_rules_container.add_child(_build_rule_row(rule))


func _build_rule_row(rule: Dictionary) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)

	var rule_id := String(rule.get("rule_id", ""))
	var enabled := bool(rule.get("enabled", true))

	var info_label := Label.new()
	var package_id := String(rule.get("package_id", ""))
	var package_suffix := " [%s]" % package_id if not package_id.is_empty() else ""
	info_label.text = "%s — %s%s" % [rule_id, String(rule.get("name", rule_id)), package_suffix]
	info_label.size_flags_horizontal = SIZE_EXPAND_FILL
	info_label.add_theme_font_size_override("font_size", 13)
	info_label.add_theme_color_override("font_color", Color(0.92, 0.96, 0.98, 0.92) if enabled else Color(0.92, 0.74, 0.62, 0.92))
	row.add_child(info_label)

	var status_label := Label.new()
	status_label.text = "enabled" if enabled else "disabled"
	status_label.add_theme_font_size_override("font_size", 12)
	status_label.add_theme_color_override("font_color", Color(0.62, 0.94, 0.78, 0.95) if enabled else Color(0.94, 0.62, 0.46, 0.95))
	row.add_child(status_label)

	var toggle_button := Button.new()
	toggle_button.text = "無効化" if enabled else "有効化"
	var next_enabled := not enabled
	toggle_button.pressed.connect(func() -> void:
		_on_rule_toggle_pressed(rule_id, next_enabled)
	)
	row.add_child(toggle_button)

	return row


func _format_id_list(ids: Array) -> String:
	if ids.is_empty():
		return "なし"
	return ", ".join(_to_string_array(ids))


func _to_string_array(values: Array) -> PackedStringArray:
	var result := PackedStringArray()
	for value in values:
		result.append(String(value))
	return result


func _yes_no(value: bool) -> String:
	return "あり" if value else "なし"


# Called by game_scene.gd after instantiating the overlay but before adding
# it to the scene tree, so the badge is built during _ready().
func set_auto_open_reasons(reasons: PackedStringArray) -> void:
	_auto_open_reasons = reasons.duplicate()


func _format_auto_open_reasons(reasons: PackedStringArray) -> String:
	if reasons.is_empty():
		return ""
	var lines: PackedStringArray = PackedStringArray()
	for reason in reasons:
		var label := String(COLLAPSE_SIGNAL_LABELS.get(reason, reason))
		lines.append("  - %s (%s)" % [label, reason])
	return "自動オープン:\n%s" % "\n".join(lines)


func _on_rule_toggle_pressed(rule_id: String, enabled: bool) -> void:
	var result: Dictionary = CliActionsScript.set_rule_enabled(_world_state, rule_id, enabled)
	var status := String(result.get("status", ""))
	if status == "enabled" or status == "disabled":
		_action_status_label.text = "ルール '%s' を %s しました。" % [rule_id, "有効化" if enabled else "無効化"]
	else:
		_action_status_label.text = "ルール '%s' の操作に失敗しました: %s" % [rule_id, JSON.stringify(result)]
	_refresh_overlay(true)


func _on_save_snapshot_pressed() -> void:
	var snapshot_path := CliActionsScript.default_snapshot_path()
	var result: Dictionary = CliActionsScript.save_snapshot(_world_state, snapshot_path)
	if String(result.get("status", "")) == "saved":
		_last_snapshot_path = "%s (絶対パス: %s)" % [snapshot_path, ProjectSettings.globalize_path(snapshot_path)]
		_action_status_label.text = "保存しました: %s" % snapshot_path
		_refresh_snapshot_picker()
	else:
		_action_status_label.text = "保存に失敗しました: %s" % JSON.stringify(result)


func _on_load_snapshot_pressed() -> void:
	if _snapshot_entries.is_empty():
		_action_status_label.text = "読み込めるスナップショットがありません。"
		return
	var selected_index := _snapshot_picker.get_selected_id()
	if selected_index < 0 or selected_index >= _snapshot_entries.size():
		_action_status_label.text = "スナップショットを選択してください。"
		return
	var entry: Dictionary = _snapshot_entries[selected_index]
	var path := String(entry.get("path", ""))
	var result: Dictionary = CliActionsScript.load_snapshot(_world_state, path)
	if String(result.get("status", "")) == "loaded":
		_action_status_label.text = "読み込みました: %s" % path
		_refresh_overlay(true)
	else:
		_action_status_label.text = "読み込みに失敗しました: %s" % JSON.stringify(result)


func _refresh_snapshot_picker() -> void:
	if _snapshot_picker == null:
		return
	_snapshot_entries = CliActionsScript.list_user_snapshots()
	_snapshot_picker.clear()
	if _snapshot_entries.is_empty():
		_snapshot_picker.add_item("(保存済みスナップショットなし)")
		_snapshot_picker.set_item_disabled(0, true)
		_snapshot_load_button.disabled = true
		return
	for index in range(_snapshot_entries.size()):
		var entry: Dictionary = _snapshot_entries[index]
		_snapshot_picker.add_item(String(entry.get("file_name", "")), index)
	_snapshot_picker.select(0)
	_snapshot_load_button.disabled = false


func _fade_in() -> void:
	var tween := create_tween()
	tween.tween_property(self, "modulate:a", 1.0, 0.16)
