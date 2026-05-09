extends Control

signal closed

const RULE_TREE_GRAPH_VIEW_SCRIPT := preload("res://scripts/ui/rule_tree_graph_view.gd")
const REFRESH_INTERVAL: float = 0.35

var _world_state: Node = null
var _summary_label: Label = null
var _graph_view: Control = null
var _demo_button: Button = null
var _refresh_timer: float = 0.0
var _last_snapshot_signature: String = ""
var _is_closing: bool = false
var _last_visible_rule_count: int = 0


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
		if key_event.pressed and not key_event.echo and key_event.keycode == KEY_F:
			if _graph_view != null and _graph_view.has_method("reset_view"):
				_graph_view.call("reset_view")
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
	frame_style.border_color = Color(0.78, 0.66, 0.36, 0.95)
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
	title.text = "ルール フォーカス ツリー"
	title.add_theme_font_size_override("font_size", 28)
	title.add_theme_color_override("font_color", Color(0.96, 0.84, 0.46, 1.0))
	title_wrap.add_child(title)

	_summary_label = Label.new()
	_summary_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_summary_label.add_theme_font_size_override("font_size", 14)
	_summary_label.add_theme_color_override("font_color", Color(0.82, 0.88, 0.96, 0.9))
	title_wrap.add_child(_summary_label)

	var help_label := Label.new()
	help_label.text = "ホイール: ズーム / ドラッグ: パン / F: 全体表示 / T・Esc: 閉じる"
	help_label.add_theme_font_size_override("font_size", 12)
	help_label.add_theme_color_override("font_color", Color(0.74, 0.80, 0.90, 0.85))
	title_wrap.add_child(help_label)

	var legend_container := _build_legend()
	header.add_child(legend_container)

	_demo_button = Button.new()
	_demo_button.text = "サンプルツリーを導入"
	_demo_button.tooltip_text = "サンプルとして3D化や所有ルールなど親子関係を持つルールを一括導入します"
	_demo_button.size_flags_vertical = SIZE_SHRINK_CENTER
	_demo_button.pressed.connect(_on_demo_button_pressed)
	header.add_child(_demo_button)

	var close_button := Button.new()
	close_button.text = "閉じる (T / Esc)"
	close_button.size_flags_vertical = SIZE_SHRINK_CENTER
	close_button.pressed.connect(close_overlay)
	header.add_child(close_button)

	_graph_view = RULE_TREE_GRAPH_VIEW_SCRIPT.new()
	_graph_view.size_flags_horizontal = SIZE_EXPAND_FILL
	_graph_view.size_flags_vertical = SIZE_EXPAND_FILL
	layout.add_child(_graph_view)


func _build_legend() -> Control:
	var legend := HBoxContainer.new()
	legend.add_theme_constant_override("separation", 8)
	legend.size_flags_vertical = SIZE_SHRINK_CENTER

	var entries := [
		{"label": "根ルール", "color": Color(0.86, 0.70, 0.30, 1.0)},
		{"label": "通常", "color": Color(0.42, 0.66, 0.92, 1.0)},
		{"label": "親未解決", "color": Color(0.92, 0.46, 0.30, 1.0)},
		{"label": "循環", "color": Color(0.84, 0.46, 0.92, 1.0)}
	]
	for entry in entries:
		legend.add_child(_make_legend_chip(entry["label"], entry["color"]))
	return legend


func _make_legend_chip(text: String, color: Color) -> Control:
	var wrapper := HBoxContainer.new()
	wrapper.add_theme_constant_override("separation", 6)

	var swatch := ColorRect.new()
	swatch.custom_minimum_size = Vector2(14.0, 14.0)
	swatch.color = color
	swatch.size_flags_vertical = SIZE_SHRINK_CENTER
	wrapper.add_child(swatch)

	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", 12)
	label.add_theme_color_override("font_color", Color(0.85, 0.9, 0.98, 0.95))
	wrapper.add_child(label)

	return wrapper


func _refresh_overlay(force: bool = false) -> void:
	var snapshot := _get_world_snapshot()
	var rule_tree := _coerce_dictionary(snapshot.get("rule_tree", {}))
	var world_name := str(snapshot.get("world_name", "現在の世界"))
	var snapshot_signature := "%s|%s" % [world_name, JSON.stringify(rule_tree)]
	if not force and snapshot_signature == _last_snapshot_signature:
		return

	_last_snapshot_signature = snapshot_signature

	var visible_rule_count := 0
	if _graph_view != null and _graph_view.has_method("update_rule_tree"):
		visible_rule_count = int(_graph_view.call("update_rule_tree", rule_tree))

	var root_count := 0
	var root_rule_ids_variant: Variant = rule_tree.get("root_rule_ids", [])
	if root_rule_ids_variant is Array:
		root_count = (root_rule_ids_variant as Array).size()
	_summary_label.text = "%s / %d ルール / 根 %d 件" % [world_name, visible_rule_count, root_count]
	_last_visible_rule_count = visible_rule_count
	if _demo_button != null:
		_demo_button.visible = visible_rule_count == 0


func _get_world_snapshot() -> Dictionary:
	if _world_state != null and _world_state.has_method("get_world_snapshot"):
		var snapshot_variant = _world_state.call("get_world_snapshot")
		if snapshot_variant is Dictionary:
			return snapshot_variant
	return {}


func _fade_in() -> void:
	var tween := create_tween()
	tween.tween_property(self, "modulate:a", 1.0, 0.16)


func _on_demo_button_pressed() -> void:
	if _world_state != null and _world_state.has_method("seed_demo_rule_tree"):
		_world_state.call("seed_demo_rule_tree")
		_refresh_overlay(true)


func _coerce_dictionary(value: Variant) -> Dictionary:
	return value if value is Dictionary else {}
