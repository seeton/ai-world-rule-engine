extends PanelContainer
class_name RulePackageTile

# Visual tile for a rule_package_v1 entry. Single click → `pressed` signal.
# Layout mirrors `gm-shared.jsx` RuleCard from the React mock.

const UiData = preload("res://scripts/ui/rule_package_ui_data.gd")

signal pressed

var _package_id: String = ""
var _stylebox_normal: StyleBoxFlat
var _stylebox_hover: StyleBoxFlat


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	custom_minimum_size = Vector2(0, 0)
	gui_input.connect(_on_gui_input)
	mouse_entered.connect(_on_mouse_entered)
	mouse_exited.connect(_on_mouse_exited)


# Public API ─────────────────────────────────────────────────────────────

func get_package_id() -> String:
	return _package_id


func populate(
	package_summary: Dictionary,
	package_details: Dictionary,
	state: String
) -> void:
	# state: "uninstalled" | "enabled" | "disabled" | "mixed"
	_package_id = String(package_summary.get("package_id", ""))
	var visual: Dictionary = UiData.ui_for(_package_id)
	var accent: Color = visual["color"] if visual.has("color") else visual.get("accent", Color("#a8acb7"))

	_apply_styleboxes(accent, state)

	for child in get_children():
		remove_child(child)
		child.queue_free()

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 12)
	margin.add_theme_constant_override("margin_right", 12)
	margin.add_theme_constant_override("margin_top", 12)
	margin.add_theme_constant_override("margin_bottom", 12)
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(margin)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 8)
	vbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
	margin.add_child(vbox)

	vbox.add_child(_build_header_row(package_summary, visual, accent))

	var description := String(package_summary.get("description", "")).strip_edges()
	if not description.is_empty():
		var desc_label := Label.new()
		desc_label.text = _truncate(description, 110)
		desc_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		desc_label.add_theme_color_override("font_color", Color("#a8acb7"))
		desc_label.add_theme_font_size_override("font_size", 11)
		desc_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		vbox.add_child(desc_label)

	var operations: Array = []
	if package_details.has("patch") and package_details["patch"] is Dictionary:
		var patch: Dictionary = package_details["patch"]
		var ops_variant: Variant = patch.get("operations", [])
		if ops_variant is Array:
			operations = ops_variant

	var stats: Array = UiData.derived_stats(operations)
	if not stats.is_empty():
		vbox.add_child(_build_stat_bar(stats[0], accent))

	var effects: Array = UiData.derived_effects(operations)
	if not effects.is_empty():
		var effects_box := VBoxContainer.new()
		effects_box.add_theme_constant_override("separation", 4)
		effects_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
		for i in range(min(effects.size(), 3)):
			effects_box.add_child(_build_effect_row(effects[i]))
		vbox.add_child(effects_box)

	vbox.add_child(_build_footer_row(package_summary, state))


# Internal builders ──────────────────────────────────────────────────────

func _build_header_row(package_summary: Dictionary, visual: Dictionary, accent: Color) -> Control:
	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 10)
	header.mouse_filter = Control.MOUSE_FILTER_IGNORE
	header.add_child(_build_avatar(visual.get("icon", "▣"), accent, 36))

	var text_vbox := VBoxContainer.new()
	text_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	text_vbox.add_theme_constant_override("separation", 2)
	text_vbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
	header.add_child(text_vbox)

	var title_row := HBoxContainer.new()
	title_row.add_theme_constant_override("separation", 6)
	title_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	text_vbox.add_child(title_row)

	var ja_title := String(visual.get("ja", "")).strip_edges()
	if ja_title.is_empty():
		ja_title = String(package_summary.get("display_name", package_summary.get("package_id", ""))).strip_edges()

	var title_label := Label.new()
	title_label.text = ja_title
	title_label.add_theme_color_override("font_color", Color("#e6e8ed"))
	title_label.add_theme_font_size_override("font_size", 14)
	title_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title_label.clip_text = true
	title_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	title_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	title_row.add_child(title_label)

	var version := String(package_summary.get("version", "")).strip_edges()
	if not version.is_empty():
		var version_label := Label.new()
		version_label.text = "v%s" % version
		version_label.add_theme_color_override("font_color", Color("#6a6e78"))
		version_label.add_theme_font_size_override("font_size", 10)
		version_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		title_row.add_child(version_label)

	var tier := String(package_summary.get("package_tier", "")).strip_edges()
	var tier_label := UiData.ja_for_tier(tier)
	if not tier_label.is_empty():
		var tier_accent: Color = UiData.accent_for_tier(tier)
		title_row.add_child(_build_pill(
			tier_label,
			tier_accent,
			Color(tier_accent.r, tier_accent.g, tier_accent.b, 0.14)
		))

	var pkg_id_label := Label.new()
	pkg_id_label.text = String(package_summary.get("package_id", ""))
	pkg_id_label.add_theme_color_override("font_color", Color("#6a6e78"))
	pkg_id_label.add_theme_font_size_override("font_size", 9)
	pkg_id_label.clip_text = true
	pkg_id_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	pkg_id_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	text_vbox.add_child(pkg_id_label)

	return header


func _build_avatar(icon_char: String, accent: Color, size: int) -> Control:
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(size, size)
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(accent.r, accent.g, accent.b, 0.18)
	sb.border_color = Color(accent.r, accent.g, accent.b, 0.55)
	sb.set_border_width_all(1)
	var radius := int(round(size * 0.28))
	sb.corner_radius_top_left = radius
	sb.corner_radius_top_right = radius
	sb.corner_radius_bottom_left = radius
	sb.corner_radius_bottom_right = radius
	panel.add_theme_stylebox_override("panel", sb)

	var center := CenterContainer.new()
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(center)

	var icon_label := Label.new()
	icon_label.text = icon_char
	icon_label.add_theme_color_override("font_color", accent)
	icon_label.add_theme_font_size_override("font_size", int(round(size * 0.55)))
	icon_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	center.add_child(icon_label)

	return panel


func _build_stat_bar(stat: Dictionary, accent: Color) -> Control:
	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 3)
	vbox.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var header_row := HBoxContainer.new()
	header_row.add_theme_constant_override("separation", 6)
	header_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.add_child(header_row)

	var label_node := Label.new()
	label_node.text = String(stat.get("label", stat.get("id", "")))
	label_node.add_theme_color_override("font_color", Color("#a8acb7"))
	label_node.add_theme_font_size_override("font_size", 10)
	label_node.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label_node.clip_text = true
	label_node.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	label_node.mouse_filter = Control.MOUSE_FILTER_IGNORE
	header_row.add_child(label_node)

	var range_label := Label.new()
	range_label.text = "%s–%s" % [UiData.fmt_num(stat.get("min", 0)), UiData.fmt_num(stat.get("max", 0))]
	range_label.add_theme_color_override("font_color", Color("#7a7e88"))
	range_label.add_theme_font_size_override("font_size", 10)
	range_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	header_row.add_child(range_label)

	var bar := ProgressBar.new()
	bar.show_percentage = false
	bar.custom_minimum_size = Vector2(0, 4)
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var max_v := float(stat.get("max", 0))
	bar.min_value = 0.0
	bar.max_value = max_v if max_v > 0.0 else 1.0
	bar.value = clamp(float(stat.get("default", 0)), bar.min_value, bar.max_value)

	var bg_sb := StyleBoxFlat.new()
	bg_sb.bg_color = Color("#262833")
	bg_sb.corner_radius_top_left = 2
	bg_sb.corner_radius_top_right = 2
	bg_sb.corner_radius_bottom_left = 2
	bg_sb.corner_radius_bottom_right = 2
	bar.add_theme_stylebox_override("background", bg_sb)

	var fill_sb := StyleBoxFlat.new()
	fill_sb.bg_color = Color(accent.r, accent.g, accent.b, 0.85)
	fill_sb.corner_radius_top_left = 2
	fill_sb.corner_radius_top_right = 2
	fill_sb.corner_radius_bottom_left = 2
	fill_sb.corner_radius_bottom_right = 2
	bar.add_theme_stylebox_override("fill", fill_sb)
	vbox.add_child(bar)

	return vbox


func _build_effect_row(effect: Dictionary) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var kind := String(effect.get("kind", ""))
	var glyph_label := Label.new()
	glyph_label.text = UiData.glyph_for_effect(kind)
	glyph_label.add_theme_color_override("font_color", UiData.color_for_effect(kind))
	glyph_label.add_theme_font_size_override("font_size", 12)
	glyph_label.custom_minimum_size = Vector2(14, 0)
	glyph_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(glyph_label)

	var trigger_label := Label.new()
	trigger_label.text = String(effect.get("trigger", ""))
	trigger_label.add_theme_color_override("font_color", Color("#d5d7de"))
	trigger_label.add_theme_font_size_override("font_size", 11)
	trigger_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	trigger_label.clip_text = true
	trigger_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	trigger_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(trigger_label)

	var delta_label := Label.new()
	delta_label.text = String(effect.get("delta", ""))
	delta_label.add_theme_color_override("font_color", Color("#e8e8ed"))
	delta_label.add_theme_font_size_override("font_size", 10)
	delta_label.clip_text = true
	delta_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	delta_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(delta_label)

	return row


func _build_footer_row(package_summary: Dictionary, state: String) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var tags_box := HBoxContainer.new()
	tags_box.add_theme_constant_override("separation", 4)
	tags_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tags_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(tags_box)

	var tags: Array = package_summary.get("tags", []) if package_summary.get("tags", null) is Array else []
	var tag_count := 0
	for tag_variant in tags:
		if tag_count >= 2:
			break
		var tag_text := UiData.ja_for_tag(String(tag_variant))
		tags_box.add_child(_build_pill(tag_text, Color("#7a7e88"), Color("#1a1c24")))
		tag_count += 1

	row.add_child(_build_state_pill(state))

	return row


func _build_pill(text: String, fg: Color, bg: Color) -> Control:
	var panel := PanelContainer.new()
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.border_color = Color(fg.r, fg.g, fg.b, 0.3)
	sb.set_border_width_all(1)
	sb.corner_radius_top_left = 999
	sb.corner_radius_top_right = 999
	sb.corner_radius_bottom_left = 999
	sb.corner_radius_bottom_right = 999
	sb.content_margin_left = 8
	sb.content_margin_right = 8
	sb.content_margin_top = 2
	sb.content_margin_bottom = 2
	panel.add_theme_stylebox_override("panel", sb)

	var lbl := Label.new()
	lbl.text = text
	lbl.add_theme_color_override("font_color", fg)
	lbl.add_theme_font_size_override("font_size", 10)
	lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(lbl)

	return panel


func _build_state_pill(state: String) -> Control:
	var label_text: String
	var fg: Color
	var bg: Color
	match state:
		"enabled":
			label_text = "有効"
			fg = Color("#7ec488")
			bg = Color(0.49, 0.77, 0.53, 0.14)
		"disabled":
			label_text = "無効"
			fg = Color("#e07474")
			bg = Color(0.88, 0.45, 0.45, 0.14)
		"mixed":
			label_text = "一部有効"
			fg = Color("#e8c66a")
			bg = Color(0.91, 0.78, 0.41, 0.14)
		"uninstalled":
			label_text = "未インストール"
			fg = Color("#e8a464")
			bg = Color(0.91, 0.64, 0.39, 0.14)
		_:
			label_text = state
			fg = Color("#a8acb7")
			bg = Color("#1a1c24")
	return _build_pill(label_text, fg, bg)


# Style + interaction ────────────────────────────────────────────────────

func _apply_styleboxes(accent: Color, _state: String) -> void:
	_stylebox_normal = StyleBoxFlat.new()
	_stylebox_normal.bg_color = Color(0.10, 0.11, 0.14, 0.55)
	_stylebox_normal.border_color = Color(1, 1, 1, 0.06)
	_stylebox_normal.set_border_width_all(1)
	_stylebox_normal.border_width_top = 2
	# Top accent stripe — paint via additional top inset
	_stylebox_normal.border_color = Color(accent.r, accent.g, accent.b, 0.55)
	_stylebox_normal.corner_radius_top_left = 12
	_stylebox_normal.corner_radius_top_right = 12
	_stylebox_normal.corner_radius_bottom_left = 12
	_stylebox_normal.corner_radius_bottom_right = 12

	_stylebox_hover = _stylebox_normal.duplicate() as StyleBoxFlat
	_stylebox_hover.bg_color = Color(accent.r * 0.5, accent.g * 0.5, accent.b * 0.5, 0.18)
	_stylebox_hover.border_color = accent

	add_theme_stylebox_override("panel", _stylebox_normal)


func _on_gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT:
			pressed.emit()
			accept_event()


func _on_mouse_entered() -> void:
	if _stylebox_hover != null:
		add_theme_stylebox_override("panel", _stylebox_hover)


func _on_mouse_exited() -> void:
	if _stylebox_normal != null:
		add_theme_stylebox_override("panel", _stylebox_normal)


# Helpers ────────────────────────────────────────────────────────────────

func _truncate(text: String, limit: int) -> String:
	if text.length() <= limit:
		return text
	return text.substr(0, limit).strip_edges() + "…"
