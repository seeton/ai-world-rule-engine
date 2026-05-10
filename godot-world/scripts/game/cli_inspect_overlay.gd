extends Control

# In-game overlay for verifying the collapse-safe CLI's `inspect` output.
# Reads the live WorldState through the same shared report builder the
# headless CLI uses (scripts/cli/inspect_report.gd), so what you see here is
# what `bash scripts/world_cli.sh ... -- inspect` would report against the
# same world. Includes a snapshot-save button so you can write a snapshot
# file to feed back into the headless CLI for a process-isolated check.

signal closed

const InspectReportScript = preload("res://scripts/cli/inspect_report.gd")
const REFRESH_INTERVAL: float = 0.35
const SNAPSHOT_DIR := "user://"

var _world_state: Node = null
var _summary_label: Label = null
var _world_label: Label = null
var _signals_label: Label = null
var _disabled_label: Label = null
var _unmet_label: Label = null
var _snapshot_status_label: Label = null
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

	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 16)
	layout.add_child(header)

	var title_wrap := VBoxContainer.new()
	title_wrap.size_flags_horizontal = SIZE_EXPAND_FILL
	title_wrap.add_theme_constant_override("separation", 4)
	header.add_child(title_wrap)

	var title := Label.new()
	title.text = "CLI inspect ビュー"
	title.add_theme_font_size_override("font_size", 28)
	title.add_theme_color_override("font_color", Color(0.62, 0.94, 0.84, 1.0))
	title_wrap.add_child(title)

	var description := Label.new()
	description.text = "headless CLI の `inspect` と同じ集計を、稼働中のワールドに対して見ています。崩壊状態の見え方を検証する用途。"
	description.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	description.add_theme_font_size_override("font_size", 12)
	description.add_theme_color_override("font_color", Color(0.78, 0.86, 0.92, 0.9))
	title_wrap.add_child(description)

	var help_label := Label.new()
	help_label.text = "C / Esc: 閉じる"
	help_label.add_theme_font_size_override("font_size", 12)
	help_label.add_theme_color_override("font_color", Color(0.74, 0.80, 0.90, 0.85))
	title_wrap.add_child(help_label)

	var save_button := Button.new()
	save_button.text = "スナップショットを保存"
	save_button.tooltip_text = "現在の世界を user:// 配下に書き出して、headless CLI の --snapshot 入力として使える状態にします。"
	save_button.size_flags_vertical = SIZE_SHRINK_CENTER
	save_button.pressed.connect(_on_save_snapshot_pressed)
	header.add_child(save_button)

	var close_button := Button.new()
	close_button.text = "閉じる (C / Esc)"
	close_button.size_flags_vertical = SIZE_SHRINK_CENTER
	close_button.pressed.connect(close_overlay)
	header.add_child(close_button)

	_world_label = _make_body_label(layout)
	_summary_label = _make_body_label(layout)
	_signals_label = _make_body_label(layout)
	_disabled_label = _make_body_label(layout)
	_unmet_label = _make_body_label(layout)
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

	var disabled_ids: Array = report.get("disabled_rule_ids", [])
	_disabled_label.text = "無効化中のルール: %s" % _format_id_list(disabled_ids)

	var unmet_ids: Array = report.get("rules_with_unmet_requirements", [])
	_unmet_label.text = "親ルール未充足: %s" % _format_id_list(unmet_ids)

	if _last_snapshot_path.is_empty():
		_snapshot_status_label.text = "スナップショット: 未保存。「スナップショットを保存」を押すと user:// に書き出します。"
	else:
		_snapshot_status_label.text = "最終保存: %s" % _last_snapshot_path


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


func _on_save_snapshot_pressed() -> void:
	if _world_state == null or not _world_state.has_method("save_world_snapshot"):
		_snapshot_status_label.text = "スナップショット: WorldState が利用できません。"
		return

	var timestamp := Time.get_datetime_string_from_system(true).replace(":", "").replace("-", "").replace("T", "_")
	var snapshot_path := "%scli_inspect_%s.json" % [SNAPSHOT_DIR, timestamp]
	var result_variant: Variant = _world_state.call("save_world_snapshot", snapshot_path)
	var result: Dictionary = result_variant if result_variant is Dictionary else {}
	if String(result.get("status", "")) == "saved":
		_last_snapshot_path = "%s (絶対パス: %s)" % [snapshot_path, ProjectSettings.globalize_path(snapshot_path)]
		_snapshot_status_label.text = "保存しました: %s" % _last_snapshot_path
	else:
		_snapshot_status_label.text = "保存に失敗しました: %s" % JSON.stringify(result)


func _fade_in() -> void:
	var tween := create_tween()
	tween.tween_property(self, "modulate:a", 1.0, 0.16)
