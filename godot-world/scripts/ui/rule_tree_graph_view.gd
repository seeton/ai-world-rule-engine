class_name RuleTreeGraphView
extends Control

const NODE_WIDTH: float = 232.0
const NODE_HEIGHT: float = 116.0
const COLUMN_SPACING: float = 56.0
const ROW_SPACING: float = 96.0
const PADDING: Vector2 = Vector2(120.0, 120.0)
const MIN_ZOOM: float = 0.45
const MAX_ZOOM: float = 1.7
const ZOOM_STEP: float = 0.1
const GRID_SPACING: float = 88.0

const COLOR_BG_TOP := Color(0.07, 0.10, 0.16, 1.0)
const COLOR_BG_BOTTOM := Color(0.03, 0.05, 0.09, 1.0)
const COLOR_GRID := Color(0.18, 0.26, 0.36, 0.18)
const COLOR_GRID_STRONG := Color(0.28, 0.40, 0.55, 0.32)
const COLOR_LINE_NORMAL := Color(0.78, 0.66, 0.36, 0.95)
const COLOR_LINE_UNRESOLVED := Color(0.86, 0.42, 0.28, 0.95)
const COLOR_LINE_EXTRA := Color(0.46, 0.74, 0.92, 0.85)
const COLOR_LINE_DIM := Color(0.78, 0.66, 0.36, 0.32)

const COLOR_NODE_BG := Color(0.12, 0.16, 0.22, 0.96)
const COLOR_NODE_BG_HIGHLIGHT := Color(0.16, 0.22, 0.30, 1.0)
const COLOR_NODE_BG_DIM := Color(0.10, 0.13, 0.18, 0.78)

const COLOR_BORDER_ROOT := Color(0.86, 0.70, 0.30, 1.0)
const COLOR_BORDER_NORMAL := Color(0.42, 0.66, 0.92, 1.0)
const COLOR_BORDER_UNRESOLVED := Color(0.92, 0.46, 0.30, 1.0)
const COLOR_BORDER_CYCLE := Color(0.84, 0.46, 0.92, 1.0)
const COLOR_BORDER_HOVER := Color(1.0, 0.96, 0.78, 1.0)
const COLOR_BORDER_DIM := Color(0.32, 0.40, 0.50, 0.85)

const COLOR_TITLE := Color(0.96, 0.97, 1.0, 1.0)
const COLOR_TITLE_DIM := Color(0.62, 0.66, 0.74, 0.88)
const COLOR_RULE_ID := Color(0.70, 0.78, 0.90, 0.78)
const COLOR_RULE_ID_DIM := Color(0.46, 0.50, 0.58, 0.7)
const COLOR_BADGE_PROVIDES := Color(0.30, 0.58, 0.40, 1.0)
const COLOR_BADGE_REQUIRES := Color(0.78, 0.40, 0.30, 1.0)
const COLOR_BADGE_REQUIRES_OK := Color(0.40, 0.58, 0.78, 1.0)
const COLOR_BADGE_TEXT := Color(0.98, 0.99, 1.0, 1.0)

var _graph_layer: Control = null
var _grid_layer: Control = null
var _viewport_clip: Control = null
var _empty_label: Label = null
var _hover_rule_id: String = ""
var _highlight_set: Dictionary = {}
var _zoom: float = 1.0
var _pan: Vector2 = Vector2.ZERO
var _is_panning: bool = false
var _pan_start_mouse: Vector2 = Vector2.ZERO
var _pan_start_value: Vector2 = Vector2.ZERO
var _node_controls: Dictionary = {}
var _node_positions: Dictionary = {}
var _node_states: Dictionary = {}
var _connectors: Array = []
var _graph_size: Vector2 = Vector2.ZERO
var _last_signature: String = ""
var _has_centered: bool = false


func _ready() -> void:
	clip_contents = true
	mouse_filter = MOUSE_FILTER_STOP
	focus_mode = FOCUS_NONE
	if not resized.is_connected(_on_self_resized):
		resized.connect(_on_self_resized)
	_ensure_layers()


func update_rule_tree(rule_tree: Dictionary) -> int:
	_ensure_layers()
	var signature := JSON.stringify(rule_tree)
	if signature == _last_signature and not _node_controls.is_empty():
		return _node_controls.size()
	_last_signature = signature
	return _rebuild(rule_tree)


func _ensure_layers() -> void:
	if _graph_layer == null:
		_build_layers()


func reset_view() -> void:
	_has_centered = false
	_apply_transform()
	_center_graph_in_viewport()


func _build_layers() -> void:
	var bg := _GridBackground.new()
	bg.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	bg.mouse_filter = MOUSE_FILTER_IGNORE
	add_child(bg)

	_viewport_clip = Control.new()
	_viewport_clip.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	_viewport_clip.mouse_filter = MOUSE_FILTER_IGNORE
	_viewport_clip.clip_contents = true
	add_child(_viewport_clip)

	_grid_layer = _LineGrid.new()
	_grid_layer.mouse_filter = MOUSE_FILTER_IGNORE
	_viewport_clip.add_child(_grid_layer)

	_graph_layer = _ConnectorLayer.new()
	_graph_layer.mouse_filter = MOUSE_FILTER_IGNORE
	(_graph_layer as _ConnectorLayer).owner_view = self
	_viewport_clip.add_child(_graph_layer)

	_empty_label = Label.new()
	_empty_label.set_anchors_and_offsets_preset(PRESET_CENTER)
	_empty_label.size = Vector2(420.0, 60.0)
	_empty_label.position = Vector2(-210.0, -30.0)
	_empty_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_empty_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_empty_label.text = "導入済みルールがありません"
	_empty_label.add_theme_font_size_override("font_size", 18)
	_empty_label.add_theme_color_override("font_color", Color(0.8, 0.86, 0.94, 0.9))
	_empty_label.visible = false
	add_child(_empty_label)


func _rebuild(rule_tree: Dictionary) -> int:
	for child in _graph_layer.get_children():
		child.queue_free()
	_node_controls.clear()
	_node_positions.clear()
	_node_states.clear()
	_connectors.clear()

	var nodes_by_rule_id := _coerce_dictionary(rule_tree.get("nodes_by_rule_id", {}))
	if nodes_by_rule_id.is_empty():
		_empty_label.visible = true
		_graph_size = Vector2.ZERO
		_graph_layer.queue_redraw()
		_grid_layer.queue_redraw()
		return 0

	_empty_label.visible = false
	var roots := _normalize_string_array(rule_tree.get("root_rule_ids", []))
	var layout := _compute_layout(nodes_by_rule_id, roots)
	_node_positions = layout["positions"]
	_node_states = layout["states"]
	_graph_size = layout["bounds"]

	for rule_id_variant in _node_positions.keys():
		var rule_id := str(rule_id_variant)
		var node_data := _coerce_dictionary(nodes_by_rule_id.get(rule_id, {}))
		var state := str(_node_states.get(rule_id, "normal"))
		var control := _build_node_card(rule_id, node_data, state, nodes_by_rule_id)
		var pos: Vector2 = _node_positions[rule_id]
		control.position = Vector2(round(pos.x), round(pos.y))
		control.size = Vector2(NODE_WIDTH, NODE_HEIGHT)
		control.custom_minimum_size = Vector2(NODE_WIDTH, NODE_HEIGHT)
		_graph_layer.add_child(control)
		_node_controls[rule_id] = control

	_connectors = _compute_connectors(nodes_by_rule_id)
	_graph_layer.size = _graph_size
	_grid_layer.size = _graph_size
	_graph_layer.queue_redraw()
	_grid_layer.queue_redraw()
	_has_centered = false
	_apply_transform()
	_center_graph_in_viewport()
	return _node_controls.size()


func _build_node_card(rule_id: String, node_data: Dictionary, state: String, nodes_by_rule_id: Dictionary) -> Panel:
	var card := Panel.new()
	card.mouse_filter = MOUSE_FILTER_PASS
	card.clip_contents = true
	card.set_meta("rule_id", rule_id)
	card.set_meta("state", state)
	_apply_card_style(card, state, false, true)
	card.mouse_entered.connect(_on_card_hover.bind(rule_id, true))
	card.mouse_exited.connect(_on_card_hover.bind(rule_id, false))

	var content := VBoxContainer.new()
	content.set_anchors_preset(PRESET_FULL_RECT)
	content.offset_left = 12
	content.offset_right = -12
	content.offset_top = 8
	content.offset_bottom = -8
	content.add_theme_constant_override("separation", 4)
	content.mouse_filter = MOUSE_FILTER_IGNORE
	card.add_child(content)

	var rule_id_label := Label.new()
	rule_id_label.text = rule_id
	rule_id_label.add_theme_font_size_override("font_size", 11)
	rule_id_label.add_theme_color_override("font_color", COLOR_RULE_ID)
	rule_id_label.clip_text = true
	rule_id_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	rule_id_label.mouse_filter = MOUSE_FILTER_IGNORE
	content.add_child(rule_id_label)

	var name_label := Label.new()
	name_label.text = str(node_data.get("name", rule_id))
	name_label.add_theme_font_size_override("font_size", 17)
	name_label.add_theme_color_override("font_color", COLOR_TITLE)
	name_label.clip_text = true
	name_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	name_label.mouse_filter = MOUSE_FILTER_IGNORE
	content.add_child(name_label)

	var badges := HBoxContainer.new()
	badges.add_theme_constant_override("separation", 4)
	badges.size_flags_vertical = SIZE_SHRINK_END
	badges.clip_contents = true
	badges.mouse_filter = MOUSE_FILTER_IGNORE
	content.add_child(badges)

	var provides := _normalize_string_array(node_data.get("provides_rule_kinds", []))
	var requires := _normalize_string_array(node_data.get("requires_rule_kinds", []))
	var resolved_parent_ids := _normalize_string_array(node_data.get("resolved_parent_rule_ids", []))
	var unresolved := _unresolved_required_kinds(node_data, resolved_parent_ids, nodes_by_rule_id)

	var added_badges := 0
	var max_badges := 3
	for kind in provides:
		if added_badges >= max_badges:
			break
		badges.add_child(_make_badge("提 " + str(kind), COLOR_BADGE_PROVIDES))
		added_badges += 1
	for kind in requires:
		if added_badges >= max_badges:
			break
		var ok := not unresolved.has(kind)
		var badge_color := COLOR_BADGE_REQUIRES_OK if ok else COLOR_BADGE_REQUIRES
		var prefix := "必 " if ok else "未 "
		badges.add_child(_make_badge(prefix + str(kind), badge_color))
		added_badges += 1

	if added_badges < max_badges:
		if state == "root" and provides.is_empty() and requires.is_empty():
			badges.add_child(_make_badge("根", COLOR_BORDER_ROOT))
			added_badges += 1
		elif state == "cycle":
			badges.add_child(_make_badge("循環", COLOR_BORDER_CYCLE))
			added_badges += 1
		elif state == "unresolved":
			badges.add_child(_make_badge("親未解決", COLOR_BORDER_UNRESOLVED))
			added_badges += 1

	return card


func _make_badge(text: String, color: Color) -> Control:
	var panel := PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = color
	style.corner_radius_top_left = 6
	style.corner_radius_top_right = 6
	style.corner_radius_bottom_left = 6
	style.corner_radius_bottom_right = 6
	style.content_margin_left = 6
	style.content_margin_right = 6
	style.content_margin_top = 1
	style.content_margin_bottom = 1
	panel.add_theme_stylebox_override("panel", style)
	panel.mouse_filter = MOUSE_FILTER_IGNORE
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", 10)
	label.add_theme_color_override("font_color", COLOR_BADGE_TEXT)
	panel.add_child(label)
	return panel


func _apply_card_style(card: Panel, state: String, hovered: bool, full_alpha: bool) -> void:
	var style := StyleBoxFlat.new()
	var bg := COLOR_NODE_BG
	if hovered:
		bg = COLOR_NODE_BG_HIGHLIGHT
	elif not full_alpha:
		bg = COLOR_NODE_BG_DIM
	style.bg_color = bg
	var border_color := COLOR_BORDER_NORMAL
	match state:
		"root":
			border_color = COLOR_BORDER_ROOT
		"unresolved":
			border_color = COLOR_BORDER_UNRESOLVED
		"cycle":
			border_color = COLOR_BORDER_CYCLE
		_:
			border_color = COLOR_BORDER_NORMAL
	if hovered:
		border_color = COLOR_BORDER_HOVER
	elif not full_alpha:
		border_color = COLOR_BORDER_DIM
	style.border_color = border_color
	var border_width := 3 if (hovered or state == "root") else 2
	style.border_width_left = border_width
	style.border_width_right = border_width
	style.border_width_top = border_width
	style.border_width_bottom = border_width
	style.corner_radius_top_left = 12
	style.corner_radius_top_right = 12
	style.corner_radius_bottom_left = 12
	style.corner_radius_bottom_right = 12
	style.shadow_size = 6 if hovered else 0
	style.shadow_color = Color(border_color.r, border_color.g, border_color.b, 0.6)
	card.add_theme_stylebox_override("panel", style)


func _compute_layout(nodes_by_rule_id: Dictionary, declared_roots: Array) -> Dictionary:
	var rule_ids: Array = nodes_by_rule_id.keys()
	rule_ids.sort()

	var roots: Array = []
	for root_id in declared_roots:
		var rid := str(root_id)
		if nodes_by_rule_id.has(rid) and not roots.has(rid):
			roots.append(rid)
	for rid_v in rule_ids:
		var rid := str(rid_v)
		var node := _coerce_dictionary(nodes_by_rule_id.get(rid, {}))
		var parents := _normalize_string_array(node.get("resolved_parent_rule_ids", []))
		if parents.is_empty() and not roots.has(rid):
			roots.append(rid)

	var assigned_x: Dictionary = {}
	var depth_by_id: Dictionary = {}
	var cycle_set: Dictionary = {}
	var counter := [0.0]
	for rid in roots:
		_assign_subtree_x(rid, 0, nodes_by_rule_id, assigned_x, depth_by_id, counter, {}, cycle_set)

	for rid_v in rule_ids:
		var rid := str(rid_v)
		if assigned_x.has(rid):
			continue
		_assign_subtree_x(rid, 0, nodes_by_rule_id, assigned_x, depth_by_id, counter, {}, cycle_set)

	var positions: Dictionary = {}
	var states: Dictionary = {}
	var min_x := INF
	var max_x := -INF
	var max_depth := 0
	for rid_v in assigned_x.keys():
		var rid := str(rid_v)
		var slot := float(assigned_x[rid])
		var depth := int(depth_by_id.get(rid, 0))
		max_depth = max(max_depth, depth)
		var px := slot * (NODE_WIDTH + COLUMN_SPACING)
		var py := float(depth) * (NODE_HEIGHT + ROW_SPACING)
		positions[rid] = Vector2(px, py) + PADDING
		min_x = min(min_x, px)
		max_x = max(max_x, px + NODE_WIDTH)

		var node := _coerce_dictionary(nodes_by_rule_id.get(rid, {}))
		var parents := _normalize_string_array(node.get("resolved_parent_rule_ids", []))
		var unresolved := _unresolved_required_kinds(node, parents, nodes_by_rule_id)
		if cycle_set.has(rid):
			states[rid] = "cycle"
		elif parents.is_empty() and unresolved.is_empty():
			states[rid] = "root"
		elif not unresolved.is_empty():
			states[rid] = "unresolved"
		else:
			states[rid] = "normal"

	if positions.is_empty():
		return {
			"positions": {},
			"states": {},
			"bounds": Vector2.ZERO
		}

	var width := (max_x - min_x) + PADDING.x * 2.0
	var height := (max_depth + 1) * (NODE_HEIGHT + ROW_SPACING) + PADDING.y * 2.0
	return {
		"positions": positions,
		"states": states,
		"bounds": Vector2(width, height)
	}


func _assign_subtree_x(
	rule_id: String,
	depth: int,
	nodes_by_rule_id: Dictionary,
	assigned_x: Dictionary,
	depth_by_id: Dictionary,
	counter: Array,
	ancestry: Dictionary,
	cycle_set: Dictionary
) -> float:
	if assigned_x.has(rule_id):
		return float(assigned_x[rule_id])
	if ancestry.has(rule_id):
		var fallback_x: float = counter[0]
		counter[0] = counter[0] + 1.0
		assigned_x[rule_id] = fallback_x
		depth_by_id[rule_id] = max(int(depth_by_id.get(rule_id, depth)), depth)
		cycle_set[rule_id] = true
		for ancestor_id in ancestry.keys():
			cycle_set[str(ancestor_id)] = true
		return fallback_x

	depth_by_id[rule_id] = max(int(depth_by_id.get(rule_id, depth)), depth)
	var node := _coerce_dictionary(nodes_by_rule_id.get(rule_id, {}))
	var children := _normalize_string_array(node.get("child_rule_ids", []))
	children.sort()

	var next_ancestry := ancestry.duplicate()
	next_ancestry[rule_id] = true

	if children.is_empty():
		var leaf_x: float = counter[0]
		counter[0] = counter[0] + 1.0
		assigned_x[rule_id] = leaf_x
		return leaf_x

	var first_x := INF
	var last_x := -INF
	for child_id_variant in children:
		var child_id := str(child_id_variant)
		if not nodes_by_rule_id.has(child_id):
			continue
		var child_x := _assign_subtree_x(child_id, depth + 1, nodes_by_rule_id, assigned_x, depth_by_id, counter, next_ancestry, cycle_set)
		first_x = min(first_x, child_x)
		last_x = max(last_x, child_x)

	if first_x == INF:
		var fallback_x_2: float = counter[0]
		counter[0] = counter[0] + 1.0
		assigned_x[rule_id] = fallback_x_2
		return fallback_x_2

	var center_x := (first_x + last_x) * 0.5
	assigned_x[rule_id] = center_x
	return center_x


func _compute_connectors(nodes_by_rule_id: Dictionary) -> Array:
	var connectors: Array = []
	var rule_ids: Array = _node_positions.keys()
	rule_ids.sort()
	for rule_id_variant in rule_ids:
		var child_id := str(rule_id_variant)
		var node := _coerce_dictionary(nodes_by_rule_id.get(child_id, {}))
		var parents := _normalize_string_array(node.get("resolved_parent_rule_ids", []))
		var first_parent := true
		for parent_id_variant in parents:
			var parent_id := str(parent_id_variant)
			if not _node_positions.has(parent_id) or not _node_positions.has(child_id):
				continue
			var kind := "normal" if first_parent else "extra"
			connectors.append({
				"from": parent_id,
				"to": child_id,
				"kind": kind,
				"dashed": not first_parent
			})
			first_parent = false
	return connectors


func _unresolved_required_kinds(node: Dictionary, resolved_parent_ids: Array, nodes_by_rule_id: Dictionary) -> Array:
	var required := _normalize_string_array(node.get("requires_rule_kinds", []))
	if required.is_empty():
		return []
	if resolved_parent_ids.is_empty():
		return required
	var unresolved: Array = []
	for kind in required:
		var resolved := false
		for parent_id in resolved_parent_ids:
			var parent_node := _coerce_dictionary(nodes_by_rule_id.get(str(parent_id), {}))
			var provided := _normalize_string_array(parent_node.get("provides_rule_kinds", []))
			if provided.has(str(kind)):
				resolved = true
				break
		if not resolved:
			unresolved.append(kind)
	return unresolved


func _on_self_resized() -> void:
	if not _has_centered and _graph_size != Vector2.ZERO:
		_center_graph_in_viewport()
	_apply_transform()


func _center_graph_in_viewport() -> void:
	if _graph_size == Vector2.ZERO or size == Vector2.ZERO:
		return
	var fit_x: float = size.x / _graph_size.x
	var fit_y: float = size.y / _graph_size.y
	var fit: float = minf(fit_x, fit_y) * 0.92
	_zoom = clampf(fit, MIN_ZOOM, 1.0)
	var scaled_size := _graph_size * _zoom
	_pan = (size - scaled_size) * 0.5
	_has_centered = true
	_apply_transform()


func _apply_transform() -> void:
	if _graph_layer != null:
		_graph_layer.scale = Vector2(_zoom, _zoom)
		_graph_layer.position = _pan
	if _grid_layer != null:
		_grid_layer.scale = Vector2(_zoom, _zoom)
		_grid_layer.position = _pan


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_WHEEL_UP and mb.pressed:
			_zoom_at(mb.position, ZOOM_STEP)
			accept_event()
			return
		if mb.button_index == MOUSE_BUTTON_WHEEL_DOWN and mb.pressed:
			_zoom_at(mb.position, -ZOOM_STEP)
			accept_event()
			return
		if mb.button_index == MOUSE_BUTTON_MIDDLE or mb.button_index == MOUSE_BUTTON_RIGHT:
			if mb.pressed:
				_is_panning = true
				_pan_start_mouse = mb.position
				_pan_start_value = _pan
			else:
				_is_panning = false
			accept_event()
			return
		if mb.button_index == MOUSE_BUTTON_LEFT:
			if mb.pressed:
				_is_panning = true
				_pan_start_mouse = mb.position
				_pan_start_value = _pan
			else:
				_is_panning = false
			accept_event()
			return
	elif event is InputEventMouseMotion:
		if _is_panning:
			var motion := event as InputEventMouseMotion
			_pan = _pan_start_value + (motion.position - _pan_start_mouse)
			_apply_transform()
			accept_event()


func _zoom_at(mouse_pos: Vector2, delta: float) -> void:
	var new_zoom: float = clampf(_zoom + delta, MIN_ZOOM, MAX_ZOOM)
	if is_equal_approx(new_zoom, _zoom):
		return
	var graph_pos := (mouse_pos - _pan) / _zoom
	_zoom = new_zoom
	_pan = mouse_pos - graph_pos * _zoom
	_apply_transform()


func _on_card_hover(rule_id: String, hovered: bool) -> void:
	if hovered:
		_hover_rule_id = rule_id
		_highlight_set = _compute_highlight_set(rule_id)
	else:
		if _hover_rule_id == rule_id:
			_hover_rule_id = ""
			_highlight_set = {}
	_apply_highlight_styles()
	_graph_layer.queue_redraw()


func _compute_highlight_set(rule_id: String) -> Dictionary:
	var result: Dictionary = {}
	result[rule_id] = true
	# climb ancestors
	var cursor := [rule_id]
	while not cursor.is_empty():
		var current: String = cursor.pop_back()
		var control: Control = _node_controls.get(current, null)
		if control == null:
			continue
		# we stored parent links via connectors; rebuild quickly
		for connector in _connectors:
			if str(connector.get("to", "")) == current:
				var p := str(connector.get("from", ""))
				if not result.has(p):
					result[p] = true
					cursor.append(p)
	# descend descendants
	cursor = [rule_id]
	while not cursor.is_empty():
		var current_d: String = cursor.pop_back()
		for connector in _connectors:
			if str(connector.get("from", "")) == current_d:
				var c := str(connector.get("to", ""))
				if not result.has(c):
					result[c] = true
					cursor.append(c)
	return result


func _apply_highlight_styles() -> void:
	var has_focus := not _highlight_set.is_empty()
	for rule_id_variant in _node_controls.keys():
		var rule_id := str(rule_id_variant)
		var card := _node_controls[rule_id] as Panel
		var state := str(_node_states.get(rule_id, "normal"))
		var is_hover := rule_id == _hover_rule_id
		var in_focus := not has_focus or _highlight_set.has(rule_id)
		_apply_card_style(card, state, is_hover, in_focus)


func get_connectors() -> Array:
	return _connectors


func get_node_position(rule_id: String) -> Vector2:
	return _node_positions.get(rule_id, Vector2.ZERO)


func get_highlight_set() -> Dictionary:
	return _highlight_set


func get_hover_rule_id() -> String:
	return _hover_rule_id


func _normalize_string_array(value: Variant) -> Array:
	var values: Array = []
	if value is Array:
		for entry in value:
			var text := str(entry).strip_edges()
			if not text.is_empty() and not values.has(text):
				values.append(text)
		return values
	var single_value := str(value).strip_edges()
	if not single_value.is_empty() and single_value != "null":
		values.append(single_value)
	return values


func _coerce_dictionary(value: Variant) -> Dictionary:
	return value if value is Dictionary else {}


class _GridBackground extends Control:
	func _draw() -> void:
		var top := COLOR_BG_TOP
		var bottom := COLOR_BG_BOTTOM
		var colors := PackedColorArray([top, top, bottom, bottom])
		var points := PackedVector2Array([
			Vector2(0, 0),
			Vector2(size.x, 0),
			Vector2(size.x, size.y),
			Vector2(0, size.y)
		])
		draw_polygon(points, colors)
		var thickness := 80.0
		draw_rect(Rect2(0, 0, size.x, thickness), Color(0, 0, 0, 0.25))
		draw_rect(Rect2(0, size.y - thickness, size.x, thickness), Color(0, 0, 0, 0.25))


class _LineGrid extends Control:
	func _draw() -> void:
		if size == Vector2.ZERO:
			return
		var step := RuleTreeGraphView.GRID_SPACING
		var color := RuleTreeGraphView.COLOR_GRID
		var color_strong := RuleTreeGraphView.COLOR_GRID_STRONG
		var x := 0.0
		var col := 0
		while x <= size.x:
			var c := color_strong if (col % 4 == 0) else color
			draw_line(Vector2(x, 0), Vector2(x, size.y), c, 1.0)
			x += step
			col += 1
		var y := 0.0
		var row := 0
		while y <= size.y:
			var c := color_strong if (row % 4 == 0) else color
			draw_line(Vector2(0, y), Vector2(size.x, y), c, 1.0)
			y += step
			row += 1


class _ConnectorLayer extends Control:
	var owner_view: Control = null

	func _draw() -> void:
		if owner_view == null:
			return
		var connectors: Array = owner_view.call("get_connectors")
		if connectors.is_empty():
			return
		var highlight_set: Dictionary = owner_view.call("get_highlight_set")
		var has_focus := not highlight_set.is_empty()
		for connector in connectors:
			var from_id := str(connector.get("from", ""))
			var to_id := str(connector.get("to", ""))
			var from_pos: Vector2 = owner_view.call("get_node_position", from_id)
			var to_pos: Vector2 = owner_view.call("get_node_position", to_id)
			if from_pos == Vector2.ZERO and to_pos == Vector2.ZERO:
				continue
			var start := from_pos + Vector2(RuleTreeGraphView.NODE_WIDTH * 0.5, RuleTreeGraphView.NODE_HEIGHT)
			var end := to_pos + Vector2(RuleTreeGraphView.NODE_WIDTH * 0.5, 0.0)
			var kind := str(connector.get("kind", "normal"))
			var is_dashed := bool(connector.get("dashed", false))
			var color := RuleTreeGraphView.COLOR_LINE_NORMAL
			match kind:
				"unresolved":
					color = RuleTreeGraphView.COLOR_LINE_UNRESOLVED
				"extra":
					color = RuleTreeGraphView.COLOR_LINE_EXTRA
				_:
					color = RuleTreeGraphView.COLOR_LINE_NORMAL
			var emphasized := highlight_set.has(from_id) and highlight_set.has(to_id)
			if has_focus and not emphasized:
				color = Color(color.r, color.g, color.b, color.a * 0.25)
			var width := 3.0 if emphasized else 2.0
			_draw_l_connector(start, end, color, width, is_dashed)

	func _draw_l_connector(start: Vector2, end: Vector2, color: Color, width: float, dashed: bool) -> void:
		var sx: float = round(start.x)
		var sy: float = round(start.y)
		var ex: float = round(end.x)
		var ey: float = round(end.y)
		var midy: float = round((sy + ey) * 0.5)
		var p1 := Vector2(sx, sy)
		var p2 := Vector2(sx, midy)
		var p3 := Vector2(ex, midy)
		var p4 := Vector2(ex, ey)
		if dashed:
			_draw_dashed(p1, p2, color, width)
			_draw_dashed(p2, p3, color, width)
			_draw_dashed(p3, p4, color, width)
		else:
			draw_line(p1, p2, color, width, true)
			if not is_equal_approx(p2.x, p3.x):
				draw_line(p2, p3, color, width, true)
			draw_line(p3, p4, color, width, true)
		var endpoint_radius: float = maxf(width * 0.9, 1.6)
		draw_circle(p1, endpoint_radius, color)
		draw_circle(p4, endpoint_radius, color)

	func _draw_dashed(from_p: Vector2, to_p: Vector2, color: Color, width: float) -> void:
		var dir := to_p - from_p
		var length := dir.length()
		if length <= 0.001:
			return
		var unit := dir / length
		var dash := 8.0
		var gap := 6.0
		var traveled := 0.0
		while traveled < length:
			var seg_end: float = minf(traveled + dash, length)
			draw_line(from_p + unit * traveled, from_p + unit * seg_end, color, width, true)
			traveled = seg_end + gap
