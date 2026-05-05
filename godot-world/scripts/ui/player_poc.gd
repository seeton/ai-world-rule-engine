extends Control

var _world_state: Node = null
var _chat_log: RichTextLabel
var _chat_input: LineEdit
var _send_button: Button
var _clock_label: Label
var _player_card: PanelContainer
var _gm_card: PanelContainer
var _player_name_label: Label
var _player_status_label: Label
var _gm_name_label: Label
var _gm_status_label: Label
var _auto_advance_timer: Timer

var _conversation_history: Array = []

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_refresh_world_state_reference()
	_build_ui()
	_setup_auto_advance()
	_refresh_display()

func _build_ui() -> void:
	# Root margin container
	var root_margin := MarginContainer.new()
	root_margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root_margin.add_theme_constant_override("margin_left", 24)
	root_margin.add_theme_constant_override("margin_top", 24)
	root_margin.add_theme_constant_override("margin_right", 24)
	root_margin.add_theme_constant_override("margin_bottom", 24)
	add_child(root_margin)

	# Main layout
	var main_vbox := VBoxContainer.new()
	main_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	main_vbox.size_flags_vertical = Control.SIZE_EXPAND_FILL
	main_vbox.add_theme_constant_override("separation", 16)
	root_margin.add_child(main_vbox)

	# Top row: Characters and clock
	var top_row := HBoxContainer.new()
	top_row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top_row.add_theme_constant_override("separation", 16)
	main_vbox.add_child(top_row)

	# Player character card
	_player_card = _build_character_card("Player", "Aria", "Curious villager seeking purpose")
	_player_card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top_row.add_child(_player_card)

	# GM character card
	_gm_card = _build_character_card("Game Master", "Oracle", "Guides the world and responds to inquiries")
	_gm_card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top_row.add_child(_gm_card)

	# Clock (top-right, initially hidden)
	_clock_label = Label.new()
	_clock_label.add_theme_font_size_override("font_size", 20)
	_clock_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_clock_label.visible = false
	top_row.add_child(_clock_label)

	# GM Conversation panel
	var chat_panel := _build_chat_panel()
	chat_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	chat_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	main_vbox.add_child(chat_panel)

func _build_character_card(role: String, char_name: String, description: String) -> PanelContainer:
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(300, 0)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 16)
	margin.add_theme_constant_override("margin_top", 16)
	margin.add_theme_constant_override("margin_right", 16)
	margin.add_theme_constant_override("margin_bottom", 16)
	panel.add_child(margin)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 8)
	margin.add_child(vbox)

	var role_label := Label.new()
	role_label.text = role
	role_label.add_theme_font_size_override("font_size", 14)
	role_label.add_theme_color_override("font_color", Color(0.7, 0.7, 0.7))
	vbox.add_child(role_label)

	var name_label := Label.new()
	name_label.text = char_name
	name_label.add_theme_font_size_override("font_size", 22)
	vbox.add_child(name_label)

	var desc_label := Label.new()
	desc_label.text = description
	desc_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	desc_label.add_theme_font_size_override("font_size", 12)
	desc_label.add_theme_color_override("font_color", Color(0.8, 0.8, 0.8))
	vbox.add_child(desc_label)

	var status_label := Label.new()
	status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	status_label.add_theme_font_size_override("font_size", 11)
	status_label.text = ""
	vbox.add_child(status_label)

	# Store reference for player card
	if role == "Player":
		_player_name_label = name_label
		_player_status_label = status_label
	elif role == "Game Master":
		_gm_name_label = name_label
		_gm_status_label = status_label

	return panel

func _build_chat_panel() -> PanelContainer:
	var panel := PanelContainer.new()

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 16)
	margin.add_theme_constant_override("margin_top", 16)
	margin.add_theme_constant_override("margin_right", 16)
	margin.add_theme_constant_override("margin_bottom", 16)
	panel.add_child(margin)

	var vbox := VBoxContainer.new()
	vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vbox.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vbox.add_theme_constant_override("separation", 12)
	margin.add_child(vbox)

	var header := Label.new()
	header.text = "Game Master Conversation"
	header.add_theme_font_size_override("font_size", 20)
	vbox.add_child(header)

	var subtitle := Label.new()
	subtitle.text = "Ask the Game Master about the world, request actions, or discuss your plans."
	subtitle.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	subtitle.add_theme_color_override("font_color", Color(0.7, 0.7, 0.7))
	vbox.add_child(subtitle)

	# Transcript area
	var transcript_scroll := ScrollContainer.new()
	transcript_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	transcript_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	transcript_scroll.custom_minimum_size = Vector2(0, 300)
	vbox.add_child(transcript_scroll)

	_chat_log = RichTextLabel.new()
	_chat_log.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_chat_log.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_chat_log.bbcode_enabled = true
	_chat_log.scroll_following = true
	_chat_log.fit_content = true
	transcript_scroll.add_child(_chat_log)

	# Input row
	var input_row := HBoxContainer.new()
	input_row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	input_row.add_theme_constant_override("separation", 8)
	vbox.add_child(input_row)

	_chat_input = LineEdit.new()
	_chat_input.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_chat_input.placeholder_text = "Type your message to the Game Master..."
	_chat_input.text_submitted.connect(_on_send_message)
	input_row.add_child(_chat_input)

	_send_button = Button.new()
	_send_button.text = "Send"
	_send_button.pressed.connect(_on_send_button_pressed)
	input_row.add_child(_send_button)

	return panel

func _setup_auto_advance() -> void:
	_auto_advance_timer = Timer.new()
	_auto_advance_timer.wait_time = 1.0
	_auto_advance_timer.autostart = true
	_auto_advance_timer.timeout.connect(_on_auto_advance_tick)
	add_child(_auto_advance_timer)

func _on_auto_advance_tick() -> void:
	if _world_state != null and _world_state.has_method("advance_tick"):
		_world_state.call("advance_tick", 1.0)
		_refresh_display()

func _on_send_button_pressed() -> void:
	_on_send_message(_chat_input.text)

func _on_send_message(message: String) -> void:
	var trimmed := message.strip_edges()
	if trimmed.is_empty():
		return

	_chat_input.clear()
	_send_to_gm(trimmed)
	_refresh_display()

func _send_to_gm(message: String) -> Dictionary:
	if _world_state != null and _world_state.has_method("talk_to_game_master"):
		return _world_state.call("talk_to_game_master", message)

	_add_chat_message("You", message, Color(0.5, 0.8, 1.0))
	_add_chat_message("Game Master", "I hear your request, though the world is still taking shape.", Color(1.0, 0.9, 0.5))
	return {
		"gm_response": "I hear your request, though the world is still taking shape.",
		"status": "ok"
	}

func _add_chat_message(speaker: String, text: String, color: Color) -> void:
	var color_hex := color.to_html(false)
	var formatted := "[color=#%s][b]%s:[/b][/color] %s\n\n" % [color_hex, speaker, text]
	_chat_log.append_text(formatted)

	_conversation_history.append({
		"speaker": speaker,
		"message": text
	})

func _refresh_display() -> void:
	_refresh_world_state_reference()
	_update_player_info()
	_update_clock()
	_sync_conversation_log()

func _refresh_world_state_reference() -> void:
	if _world_state == null:
		_world_state = get_node_or_null("/root/WorldState")

func _update_player_info() -> void:
	if _world_state == null or not _world_state.has_method("get_world_snapshot"):
		_player_status_label.text = "Status: Awaiting world initialization..."
		_gm_status_label.text = "Status: Awaiting world initialization..."
		return

	var snapshot = _world_state.call("get_world_snapshot")
	if not snapshot is Dictionary:
		return

	var entities = snapshot.get("entities", {})
	if not (entities is Dictionary):
		return

	var player_entity: Dictionary = entities.get("player_character", {})
	if not player_entity.is_empty():
		_player_name_label.text = str(player_entity.get("name", "Player Character"))
		var player_components: Dictionary = player_entity.get("components", {})
		var player_stats: Dictionary = player_components.get("stats", {})
		var player_needs: Dictionary = player_components.get("needs", {})
		var player_time: Dictionary = player_components.get("time", {})
		var player_status_parts: Array[String] = []
		if player_stats.has("morale"):
			player_status_parts.append("Morale: %d" % int(player_stats.get("morale", 0)))
		if player_needs.has("hunger"):
			player_status_parts.append("Hunger: %d" % int(player_needs.get("hunger", 0)))
		if player_time.has("elapsed_seconds"):
			player_status_parts.append("Time: %ds" % int(player_time.get("elapsed_seconds", 0.0)))
		_player_status_label.text = " | ".join(player_status_parts) if not player_status_parts.is_empty() else "Status: Active"

	var gm_entity: Dictionary = entities.get("game_master", {})
	if not gm_entity.is_empty():
		_gm_name_label.text = str(gm_entity.get("name", "Game Master"))
		var gm_components: Dictionary = gm_entity.get("components", {})
		var gm_behavior: Dictionary = gm_components.get("behavior", {})
		_gm_status_label.text = "Status: %s" % str(gm_behavior.get("current_task", "Listening"))

func _update_clock() -> void:
	if _world_state == null or not _world_state.has_method("get_world_snapshot"):
		_clock_label.visible = false
		return

	var snapshot = _world_state.call("get_world_snapshot")
	if not snapshot is Dictionary:
		_clock_label.visible = false
		return

	var clock_data = snapshot.get("clock", {})
	if not clock_data is Dictionary:
		_clock_label.visible = false
		return

	var is_visible = clock_data.get("visible", false)
	_clock_label.visible = is_visible

	if is_visible:
		var formatted = clock_data.get("formatted", "Day 1, 00:00:00")
		_clock_label.text = formatted

func _sync_conversation_log() -> void:
	if _world_state == null or not _world_state.has_method("get_world_snapshot"):
		return

	var snapshot = _world_state.call("get_world_snapshot")
	if not snapshot is Dictionary:
		return

	var conversation_log = snapshot.get("conversation_log", [])
	if not conversation_log is Array:
		return

	# Only append new messages that aren't already in our history
	var existing_count = _conversation_history.size()
	for i in range(existing_count, conversation_log.size()):
		var entry = conversation_log[i]
		if entry is Dictionary:
			var speaker = entry.get("speaker", "Unknown")
			var message = entry.get("text", entry.get("message", ""))
			var color = Color(0.8, 0.8, 0.8)

			if speaker.to_lower().contains("game master") or speaker.to_lower().contains("gm"):
				color = Color(1.0, 0.9, 0.5)
			elif speaker.to_lower().contains("player") or speaker.to_lower().contains("you"):
				color = Color(0.5, 0.8, 1.0)

			_add_chat_message(speaker, message, color)
