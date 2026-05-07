extends Control

signal closed

const MAIN_DESKTOP_SCRIPT := preload("res://scripts/ui/main_desktop.gd")

var _shell: Control


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
	scrim.color = Color(0.0, 0.0, 0.0, 0.46)
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
	layout.add_theme_constant_override("separation", 10)
	margin.add_child(layout)

	var header := VBoxContainer.new()
	header.add_theme_constant_override("separation", 8)
	layout.add_child(header)

	var top_row := HBoxContainer.new()
	top_row.add_theme_constant_override("separation", 16)
	header.add_child(top_row)

	var title_wrap := VBoxContainer.new()
	title_wrap.size_flags_horizontal = SIZE_EXPAND_FILL
	title_wrap.add_theme_constant_override("separation", 4)
	top_row.add_child(title_wrap)

	var title := Label.new()
	title.text = "PoC3 / GMとの会話 / 世界管理"
	title.add_theme_font_size_override("font_size", 24)
	title_wrap.add_child(title)

	var subtitle := Label.new()
	subtitle.text = "ここはプレイ世界の中でGMに話しかけたときだけ開く補助画面です。ここで3D化や各種ルールを適用し、終わったら世界へ戻って続けられます。"
	subtitle.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	title_wrap.add_child(subtitle)

	var back_button := Button.new()
	back_button.text = "← 会話を終えて世界へ戻る"
	back_button.pressed.connect(_close)
	top_row.add_child(back_button)
	back_button.call_deferred("grab_focus")

	var help_label := Label.new()
	help_label.text = "Escキーでも閉じられます。メイン画面は背後のプレイ世界です。"
	help_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	header.add_child(help_label)

	var shell_host := Control.new()
	shell_host.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	shell_host.size_flags_horizontal = SIZE_EXPAND_FILL
	shell_host.size_flags_vertical = SIZE_EXPAND_FILL
	layout.add_child(shell_host)

	_shell = MAIN_DESKTOP_SCRIPT.new()
	_shell.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	if _shell.has_signal("close_requested"):
		_shell.close_requested.connect(_close)
	shell_host.add_child(_shell)


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
