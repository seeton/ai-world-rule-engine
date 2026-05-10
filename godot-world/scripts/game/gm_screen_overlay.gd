extends Control

signal closed

const GM_DIALOG_SCRIPT := preload("res://scripts/ui/gm_dialog.gd")
const MAIN_DESKTOP_SCRIPT := preload("res://scripts/ui/main_desktop.gd")

var _conversation_view: Control
var _admin_view: Control
var _conversation_button: Button
var _admin_button: Button


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
	top_row.add_theme_constant_override("separation", 12)
	header.add_child(top_row)

	var title_wrap := VBoxContainer.new()
	title_wrap.size_flags_horizontal = SIZE_EXPAND_FILL
	title_wrap.add_theme_constant_override("separation", 4)
	top_row.add_child(title_wrap)

	var title := Label.new()
	title.text = "PoC4 / GMとの会話"
	title.add_theme_font_size_override("font_size", 24)
	title_wrap.add_child(title)

	var subtitle := Label.new()
	subtitle.text = "プレイヤー向け会話から PoC4 proposal / Codex detail / 同意 / issue 結果まで確認できます。必要なら管理・デバッグ画面へ切り替えて既存の GM 操作も続けられます。"
	subtitle.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	title_wrap.add_child(subtitle)

	var mode_row := HBoxContainer.new()
	mode_row.add_theme_constant_override("separation", 10)
	header.add_child(mode_row)

	_conversation_button = Button.new()
	_conversation_button.text = "プレイヤー会話 / PoC4 review"
	_conversation_button.pressed.connect(func() -> void:
		_set_mode("conversation")
	)
	mode_row.add_child(_conversation_button)

	_admin_button = Button.new()
	_admin_button.text = "管理 / デバッグ"
	_admin_button.pressed.connect(func() -> void:
		_set_mode("admin")
	)
	mode_row.add_child(_admin_button)

	var back_button := Button.new()
	back_button.text = "← 会話を終えて世界へ戻る"
	back_button.pressed.connect(_close)
	top_row.add_child(back_button)
	back_button.call_deferred("grab_focus")

	var help_label := Label.new()
	help_label.text = "Escキーでも閉じられます。最初はプレイヤー向け会話が開き、必要なら上の切り替えで管理画面へ移動できます。"
	help_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	header.add_child(help_label)

	var content_host := Control.new()
	content_host.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	content_host.size_flags_horizontal = SIZE_EXPAND_FILL
	content_host.size_flags_vertical = SIZE_EXPAND_FILL
	layout.add_child(content_host)

	_conversation_view = GM_DIALOG_SCRIPT.new()
	_conversation_view.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	if _conversation_view.has_signal("closed"):
		_conversation_view.closed.connect(_close)
	content_host.add_child(_conversation_view)

	_admin_view = MAIN_DESKTOP_SCRIPT.new()
	_admin_view.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	if _admin_view.has_signal("close_requested"):
		_admin_view.close_requested.connect(_close)
	content_host.add_child(_admin_view)

	_set_mode("conversation")


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


func _set_mode(mode: String) -> void:
	var showing_conversation := mode != "admin"
	if _conversation_view != null:
		_conversation_view.visible = showing_conversation
		if showing_conversation and _conversation_view.has_method("notify_overlay_visible"):
			_conversation_view.call("notify_overlay_visible")
	if _admin_view != null:
		_admin_view.visible = not showing_conversation
	if _conversation_button != null:
		_conversation_button.disabled = showing_conversation
	if _admin_button != null:
		_admin_button.disabled = not showing_conversation
