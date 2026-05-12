extends Control

signal closed

const MAIN_DESKTOP_SCRIPT := preload("res://scripts/ui/main_desktop.gd")

var _admin_view: Control


func _ready() -> void:
	set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	mouse_filter = MOUSE_FILTER_STOP
	modulate.a = 0.0
	_build_ui()
	_fade_in()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		_close()
		get_viewport().set_input_as_handled()


func _build_ui() -> void:
	var scrim := ColorRect.new()
	scrim.color = Color(0.07, 0.08, 0.11, 1.0)
	scrim.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	scrim.mouse_filter = MOUSE_FILTER_STOP
	add_child(scrim)

	var frame := PanelContainer.new()
	frame.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	frame.offset_left = 88.0
	frame.offset_top = 40.0
	frame.offset_right = -88.0
	frame.offset_bottom = -40.0
	frame.clip_contents = true
	add_child(frame)

	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", 18)
	margin.add_theme_constant_override("margin_top", 18)
	margin.add_theme_constant_override("margin_right", 18)
	margin.add_theme_constant_override("margin_bottom", 18)
	frame.add_child(margin)

	var layout := VBoxContainer.new()
	layout.size_flags_horizontal = SIZE_EXPAND_FILL
	layout.size_flags_vertical = SIZE_EXPAND_FILL
	layout.add_theme_constant_override("separation", 12)
	margin.add_child(layout)

	var top_row := HBoxContainer.new()
	top_row.add_theme_constant_override("separation", 12)
	layout.add_child(top_row)

	var title_wrap := VBoxContainer.new()
	title_wrap.size_flags_horizontal = SIZE_EXPAND_FILL
	title_wrap.add_theme_constant_override("separation", 4)
	top_row.add_child(title_wrap)

	var eyebrow := Label.new()
	eyebrow.text = "GM Console"
	eyebrow.modulate = Color(1.0, 1.0, 1.0, 0.68)
	eyebrow.add_theme_font_size_override("font_size", 12)
	title_wrap.add_child(eyebrow)

	var title := Label.new()
	title.text = _get_world_title()
	title.add_theme_font_size_override("font_size", 22)
	title_wrap.add_child(title)

	var back_button := Button.new()
	back_button.text = "← 世界へ戻る (Esc)"
	back_button.pressed.connect(_close)
	top_row.add_child(back_button)
	back_button.call_deferred("grab_focus")

	var content_host := Control.new()
	content_host.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	content_host.size_flags_horizontal = SIZE_EXPAND_FILL
	content_host.size_flags_vertical = SIZE_EXPAND_FILL
	layout.add_child(content_host)

	_admin_view = MAIN_DESKTOP_SCRIPT.new()
	_admin_view.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	if _admin_view.has_signal("close_requested"):
		_admin_view.close_requested.connect(_close)
	content_host.add_child(_admin_view)


func _fade_in() -> void:
	var tween := create_tween()
	tween.tween_property(self, "modulate:a", 1.0, 0.18)


func _close() -> void:
	var tween := create_tween()
	tween.tween_property(self, "modulate:a", 0.0, 0.14)
	tween.tween_callback(func() -> void:
		closed.emit()
		queue_free()
	)


func _get_world_title() -> String:
	var world_state := get_node_or_null("/root/WorldState")
	if world_state != null and world_state.has_method("get_world_snapshot"):
		var snapshot = world_state.call("get_world_snapshot")
		if snapshot is Dictionary:
			var world_name := String(snapshot.get("world_name", snapshot.get("name", "")))
			if not world_name.is_empty():
				return world_name
	return "はじまりの広場"
