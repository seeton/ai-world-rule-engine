extends Control

signal closed

const RUNTIME_RULE_TREE_VIEW_SCRIPT := preload("res://scripts/ui/runtime_rule_tree_view.gd")
const REFRESH_INTERVAL: float = 0.35

var _world_state: Node = null
var _summary_label: Label = null
var _rule_tree: Tree = null
var _refresh_timer: float = 0.0
var _last_snapshot_signature: String = ""
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
		if key_event.pressed and not key_event.echo and (key_event.keycode == KEY_T or key_event.physical_keycode == KEY_T):
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
	scrim.color = Color(0.01, 0.02, 0.04, 0.34)
	scrim.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	scrim.mouse_filter = MOUSE_FILTER_STOP
	add_child(scrim)

	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", 24)
	margin.add_theme_constant_override("margin_top", 24)
	margin.add_theme_constant_override("margin_right", 24)
	margin.add_theme_constant_override("margin_bottom", 24)
	add_child(margin)

	var row := HBoxContainer.new()
	row.size_flags_horizontal = SIZE_EXPAND_FILL
	row.size_flags_vertical = SIZE_EXPAND_FILL
	margin.add_child(row)

	var spacer := Control.new()
	spacer.size_flags_horizontal = SIZE_EXPAND_FILL
	row.add_child(spacer)

	var frame := PanelContainer.new()
	frame.custom_minimum_size = Vector2(700.0, 0.0)
	frame.size_flags_vertical = SIZE_EXPAND_FILL
	frame.mouse_filter = MOUSE_FILTER_STOP
	row.add_child(frame)

	var frame_style := StyleBoxFlat.new()
	frame_style.bg_color = Color(0.05, 0.07, 0.11, 0.94)
	frame_style.border_width_left = 2
	frame_style.border_width_top = 2
	frame_style.border_width_right = 2
	frame_style.border_width_bottom = 2
	frame_style.border_color = Color(0.72, 0.84, 1.0, 0.95)
	frame_style.corner_radius_top_left = 18
	frame_style.corner_radius_top_right = 18
	frame_style.corner_radius_bottom_left = 18
	frame_style.corner_radius_bottom_right = 18
	frame.add_theme_stylebox_override("panel", frame_style)

	var content_margin := MarginContainer.new()
	content_margin.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	content_margin.add_theme_constant_override("margin_left", 18)
	content_margin.add_theme_constant_override("margin_top", 18)
	content_margin.add_theme_constant_override("margin_right", 18)
	content_margin.add_theme_constant_override("margin_bottom", 18)
	frame.add_child(content_margin)

	var layout := VBoxContainer.new()
	layout.size_flags_horizontal = SIZE_EXPAND_FILL
	layout.size_flags_vertical = SIZE_EXPAND_FILL
	layout.add_theme_constant_override("separation", 12)
	content_margin.add_child(layout)

	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 12)
	layout.add_child(header)

	var title_wrap := VBoxContainer.new()
	title_wrap.size_flags_horizontal = SIZE_EXPAND_FILL
	title_wrap.add_theme_constant_override("separation", 6)
	header.add_child(title_wrap)

	var title := Label.new()
	title.text = "ライブ ルールツリー"
	title.add_theme_font_size_override("font_size", 26)
	title.add_theme_color_override("font_color", Color(0.97, 0.99, 1.0, 1.0))
	title_wrap.add_child(title)

	_summary_label = Label.new()
	_summary_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_summary_label.add_theme_font_size_override("font_size", 15)
	_summary_label.add_theme_color_override("font_color", Color(0.82, 0.9, 0.98, 0.96))
	title_wrap.add_child(_summary_label)

	var close_button := Button.new()
	close_button.text = "閉じる (T / Esc)"
	close_button.pressed.connect(close_overlay)
	header.add_child(close_button)

	var help_label := Label.new()
	help_label.text = "現在の世界を一時停止したまま、ライブのルール依存を確認できます。背景を暗くして読みやすくしています。"
	help_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	help_label.add_theme_font_size_override("font_size", 14)
	help_label.add_theme_color_override("font_color", Color(0.74, 0.8, 0.89, 0.92))
	layout.add_child(help_label)

	_rule_tree = Tree.new()
	_rule_tree.columns = 2
	_rule_tree.column_titles_visible = true
	_rule_tree.hide_root = true
	_rule_tree.size_flags_vertical = SIZE_EXPAND_FILL
	_rule_tree.focus_mode = Control.FOCUS_NONE
	_rule_tree.clip_contents = true
	_rule_tree.set_column_title(0, "ルール")
	_rule_tree.set_column_title(1, "依存 / 状態")
	_rule_tree.mouse_filter = MOUSE_FILTER_STOP
	layout.add_child(_rule_tree)


func _refresh_overlay(force: bool = false) -> void:
	var snapshot := _get_world_snapshot()
	var rule_tree := _coerce_dictionary(snapshot.get("rule_tree", {}))
	var world_name := str(snapshot.get("world_name", "現在の世界"))
	var snapshot_signature := "%s|%s" % [world_name, JSON.stringify(rule_tree)]
	if not force and snapshot_signature == _last_snapshot_signature:
		return

	_last_snapshot_signature = snapshot_signature
	var visible_rule_count := RUNTIME_RULE_TREE_VIEW_SCRIPT.populate(_rule_tree, rule_tree)
	var root_count := 0
	var root_rule_ids_variant: Variant = rule_tree.get("root_rule_ids", [])
	if root_rule_ids_variant is Array:
		root_count = (root_rule_ids_variant as Array).size()
	_summary_label.text = "%s / %d ルール表示 / 根 %d 件 / T または Esc で閉じる" % [world_name, visible_rule_count, root_count]


func _get_world_snapshot() -> Dictionary:
	if _world_state != null and _world_state.has_method("get_world_snapshot"):
		var snapshot_variant = _world_state.call("get_world_snapshot")
		if snapshot_variant is Dictionary:
			return snapshot_variant
	return {}


func _fade_in() -> void:
	var tween := create_tween()
	tween.tween_property(self, "modulate:a", 1.0, 0.16)


func _coerce_dictionary(value: Variant) -> Dictionary:
	return value if value is Dictionary else {}
