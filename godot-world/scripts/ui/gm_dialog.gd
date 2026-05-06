extends Control

signal closed

const ACTION_OBJECT_BASE := "install_object_base"
const ACTION_OWNERSHIP := "install_ownership_rule"
const ACTION_PARENT_TREE := "install_parent_child_rule"
const ACTION_TIME := "install_time_rule"
const ACTION_GO_TO_3D := "go_to_poc3"
const ACTION_RETURN_TO_2D := "return_to_poc2"

var world_controller: Node = null
var _stage_label: Label = null
var _summary_label: Label = null
var _conversation_view: RichTextLabel = null
var _rule_tree: Tree = null
var _entity_tree: Tree = null
var _detail_view: TextEdit = null
var _message_input: LineEdit = null
var _button_map: Dictionary = {}

func _ready() -> void:
    set_anchors_and_offsets_preset(PRESET_FULL_RECT)
    mouse_filter = MOUSE_FILTER_STOP
    modulate.a = 0.0
    _build_ui()
    _fade_in()
    _refresh()

func set_world_controller(controller: Node) -> void:
    world_controller = controller
    if world_controller != null and world_controller.has_signal("poc_snapshot_changed"):
        world_controller.poc_snapshot_changed.connect(_refresh)
    if is_node_ready():
        _refresh()

func _unhandled_input(event: InputEvent) -> void:
    if event.is_action_pressed("ui_cancel"):
        _close()
        get_viewport().set_input_as_handled()

func _build_ui() -> void:
    var scrim := ColorRect.new()
    scrim.color = Color(0.0, 0.0, 0.0, 0.52)
    scrim.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
    add_child(scrim)

    var frame := PanelContainer.new()
    frame.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
    frame.offset_left = 80.0
    frame.offset_top = 56.0
    frame.offset_right = -80.0
    frame.offset_bottom = -56.0
    add_child(frame)

    var margin := MarginContainer.new()
    margin.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
    margin.add_theme_constant_override("margin_left", 20)
    margin.add_theme_constant_override("margin_top", 20)
    margin.add_theme_constant_override("margin_right", 20)
    margin.add_theme_constant_override("margin_bottom", 20)
    frame.add_child(margin)

    var root := VBoxContainer.new()
    root.size_flags_horizontal = SIZE_EXPAND_FILL
    root.size_flags_vertical = SIZE_EXPAND_FILL
    root.add_theme_constant_override("separation", 14)
    margin.add_child(root)

    var header := VBoxContainer.new()
    header.add_theme_constant_override("separation", 6)
    root.add_child(header)

    var top_row := HBoxContainer.new()
    top_row.add_theme_constant_override("separation", 16)
    header.add_child(top_row)

    var title_wrap := VBoxContainer.new()
    title_wrap.size_flags_horizontal = SIZE_EXPAND_FILL
    title_wrap.add_theme_constant_override("separation", 4)
    top_row.add_child(title_wrap)

    var title := Label.new()
    title.text = "ゲームマスター: PoC2 物体ルール実演"
    title.add_theme_font_size_override("font_size", 28)
    title_wrap.add_child(title)

    _stage_label = Label.new()
    _stage_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
    _stage_label.add_theme_font_size_override("font_size", 16)
    title_wrap.add_child(_stage_label)

    var back_button := Button.new()
    back_button.text = "世界へ戻る"
    back_button.pressed.connect(_close)
    top_row.add_child(back_button)

    _summary_label = Label.new()
    _summary_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
    header.add_child(_summary_label)

    var split := HSplitContainer.new()
    split.size_flags_horizontal = SIZE_EXPAND_FILL
    split.size_flags_vertical = SIZE_EXPAND_FILL
    split.split_offset = 520
    root.add_child(split)

    var left_column := VBoxContainer.new()
    left_column.size_flags_horizontal = SIZE_EXPAND_FILL
    left_column.size_flags_vertical = SIZE_EXPAND_FILL
    left_column.add_theme_constant_override("separation", 12)
    split.add_child(left_column)

    left_column.add_child(_build_action_panel())
    left_column.add_child(_build_conversation_panel())

    var right_column := VBoxContainer.new()
    right_column.size_flags_horizontal = SIZE_EXPAND_FILL
    right_column.size_flags_vertical = SIZE_EXPAND_FILL
    right_column.add_theme_constant_override("separation", 12)
    split.add_child(right_column)

    right_column.add_child(_build_rule_panel())
    right_column.add_child(_build_entity_panel())
    right_column.add_child(_build_detail_panel())

func _build_action_panel() -> Control:
    var panel := _make_panel("進行ボタン", "PoC2 の本筋は 2D での物体基礎 → 所有関係 → 親子ツリーです。時間と 3D は補助です。")
    var body := panel.get_meta("body") as VBoxContainer

    var grid := GridContainer.new()
    grid.columns = 2
    grid.size_flags_horizontal = SIZE_EXPAND_FILL
    grid.add_theme_constant_override("h_separation", 8)
    grid.add_theme_constant_override("v_separation", 8)
    body.add_child(grid)

    _add_action_button(grid, ACTION_OBJECT_BASE, "1. 物体基礎を有効化")
    _add_action_button(grid, ACTION_OWNERSHIP, "2. 所有関係を有効化")
    _add_action_button(grid, ACTION_PARENT_TREE, "3. 親子ツリーを有効化")
    _add_action_button(grid, ACTION_TIME, "補助: 時間ルール")
    _add_action_button(grid, ACTION_GO_TO_3D, "PoC3 3D途中証明へ")
    _add_action_button(grid, ACTION_RETURN_TO_2D, "2D 本筋へ戻る")

    _message_input = LineEdit.new()
    _message_input.placeholder_text = "例: 所有関係を見せて / 3D を見せて / 時間ルールを追加して"
    _message_input.text_submitted.connect(_on_message_submitted)
    body.add_child(_message_input)

    var send_button := Button.new()
    send_button.text = "GMへ送る"
    send_button.pressed.connect(_on_send_pressed)
    body.add_child(send_button)
    return panel

func _build_conversation_panel() -> Control:
    var panel := _make_panel("会話ログ", "プレイヤーとGMのやりとりを日本語で表示します。")
    var body := panel.get_meta("body") as VBoxContainer

    _conversation_view = RichTextLabel.new()
    _conversation_view.bbcode_enabled = true
    _conversation_view.fit_content = true
    _conversation_view.scroll_following = true
    _conversation_view.size_flags_horizontal = SIZE_EXPAND_FILL
    _conversation_view.size_flags_vertical = SIZE_EXPAND_FILL
    body.add_child(_conversation_view)
    return panel

func _build_rule_panel() -> Control:
    var panel := _make_panel("ルールツリー", "親ルールから子ルールへ、PoC2 の段階を確認できます。")
    var body := panel.get_meta("body") as VBoxContainer

    _rule_tree = Tree.new()
    _rule_tree.columns = 2
    _rule_tree.column_titles_visible = true
    _rule_tree.hide_root = true
    _rule_tree.set_column_title(0, "ルール")
    _rule_tree.set_column_title(1, "状態")
    _rule_tree.custom_minimum_size = Vector2(0.0, 190.0)
    body.add_child(_rule_tree)
    return panel

func _build_entity_panel() -> Control:
    var panel := _make_panel("物体 / 所有 / 親子状態", "2Dのプレイ中に確認できる関係を日本語で整理しています。")
    var body := panel.get_meta("body") as VBoxContainer

    _entity_tree = Tree.new()
    _entity_tree.columns = 2
    _entity_tree.column_titles_visible = true
    _entity_tree.hide_root = true
    _entity_tree.set_column_title(0, "対象")
    _entity_tree.set_column_title(1, "状態")
    _entity_tree.custom_minimum_size = Vector2(0.0, 220.0)
    _entity_tree.item_selected.connect(_on_entity_tree_selected)
    body.add_child(_entity_tree)
    return panel

func _build_detail_panel() -> Control:
    var panel := _make_panel("選択中の詳細", "2D世界でクリックした物体、またはツリーで選んだ項目の詳細です。")
    var body := panel.get_meta("body") as VBoxContainer

    _detail_view = TextEdit.new()
    _detail_view.editable = false
    _detail_view.custom_minimum_size = Vector2(0.0, 150.0)
    _detail_view.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
    body.add_child(_detail_view)
    return panel

func _make_panel(title_text: String, description: String) -> PanelContainer:
    var panel := PanelContainer.new()
    panel.size_flags_horizontal = SIZE_EXPAND_FILL
    panel.size_flags_vertical = SIZE_EXPAND_FILL

    var margin := MarginContainer.new()
    margin.add_theme_constant_override("margin_left", 12)
    margin.add_theme_constant_override("margin_top", 12)
    margin.add_theme_constant_override("margin_right", 12)
    margin.add_theme_constant_override("margin_bottom", 12)
    panel.add_child(margin)

    var body := VBoxContainer.new()
    body.size_flags_horizontal = SIZE_EXPAND_FILL
    body.size_flags_vertical = SIZE_EXPAND_FILL
    body.add_theme_constant_override("separation", 8)
    margin.add_child(body)

    var title := Label.new()
    title.text = title_text
    title.add_theme_font_size_override("font_size", 18)
    body.add_child(title)

    var description_label := Label.new()
    description_label.text = description
    description_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
    body.add_child(description_label)

    panel.set_meta("body", body)
    return panel

func _add_action_button(container: GridContainer, action_id: String, text: String) -> void:
    var button := Button.new()
    button.text = text
    button.pressed.connect(_on_action_button_pressed.bind(action_id))
    container.add_child(button)
    _button_map[action_id] = button

func _on_action_button_pressed(action_id: String) -> void:
    if world_controller == null or not world_controller.has_method("perform_gm_action"):
        return
    var result_variant = world_controller.call("perform_gm_action", action_id)
    if result_variant is Dictionary:
        var result: Dictionary = result_variant
        _refresh()
        if bool(result.get("close_after_action", false)):
            _close()

func _on_send_pressed() -> void:
    _submit_message()

func _on_message_submitted(_text: String) -> void:
    _submit_message()

func _submit_message() -> void:
    if world_controller == null or not world_controller.has_method("submit_gm_message"):
        return
    var message := _message_input.text.strip_edges()
    if message.is_empty():
        return
    var result_variant = world_controller.call("submit_gm_message", message)
    _message_input.clear()
    _refresh()
    if result_variant is Dictionary and bool((result_variant as Dictionary).get("close_after_action", false)):
        _close()

func _refresh() -> void:
    var snapshot := _snapshot()
    if snapshot.is_empty():
        return

    _stage_label.text = "%s\n%s" % [String(snapshot.get("stage_title", "")), String(snapshot.get("stage_summary", ""))]
    _summary_label.text = "%s\n%s" % [String(snapshot.get("success_summary", "")), String(snapshot.get("poc3_note", ""))]
    _refresh_buttons(snapshot)
    _refresh_conversation(snapshot)
    _refresh_rule_tree(snapshot)
    _refresh_entity_tree(snapshot)
    _refresh_detail_view(snapshot)

func _refresh_buttons(snapshot: Dictionary) -> void:
    var progress := _coerce_dictionary(snapshot.get("progress", {}))
    _set_button_state(ACTION_OBJECT_BASE, not bool(progress.get("object_base", false)), true)
    _set_button_state(ACTION_OWNERSHIP, not bool(progress.get("ownership", false)), bool(progress.get("object_base", false)))
    _set_button_state(ACTION_PARENT_TREE, not bool(progress.get("parent_tree", false)), bool(progress.get("ownership", false)))
    _set_button_state(ACTION_TIME, not bool(snapshot.get("time_rule_active", false)), true)

    var active_mode := String(snapshot.get("active_mode", "two_d"))
    var go_to_3d_button := _button_map.get(ACTION_GO_TO_3D, null) as Button
    if go_to_3d_button != null:
        go_to_3d_button.visible = active_mode != "three_d"
        go_to_3d_button.disabled = active_mode == "three_d"

    var return_button := _button_map.get(ACTION_RETURN_TO_2D, null) as Button
    if return_button != null:
        return_button.visible = active_mode == "three_d"
        return_button.disabled = active_mode != "three_d"

func _set_button_state(action_id: String, enabled: bool, allowed: bool) -> void:
    var button := _button_map.get(action_id, null) as Button
    if button == null:
        return
    button.disabled = not enabled or not allowed

func _refresh_conversation(snapshot: Dictionary) -> void:
    var sections: Array = []
    for entry in snapshot.get("conversation", []):
        if not (entry is Dictionary):
            continue
        var speaker := String(entry.get("speaker", "gm"))
        var speaker_label := "プレイヤー" if speaker == "player" else "ゲームマスター"
        var color := "#ffd66a" if speaker == "player" else "#7ce6ff"
        sections.append("[color=%s][b]%s:[/b][/color] %s" % [color, speaker_label, String(entry.get("text", ""))])
    _conversation_view.text = "\n\n".join(sections)

func _refresh_rule_tree(snapshot: Dictionary) -> void:
    _rule_tree.clear()
    var root := _rule_tree.create_item()
    var rule_map: Dictionary = {}
    var item_map: Dictionary = {}
    for rule in snapshot.get("installed_rules", []):
        if rule is Dictionary:
            var rule_dict: Dictionary = rule
            rule_map[String(rule_dict.get("id", ""))] = rule_dict
    for rule_id in rule_map.keys():
        _ensure_rule_item(rule_id, rule_map, item_map, root)

func _ensure_rule_item(rule_id: String, rule_map: Dictionary, item_map: Dictionary, root: TreeItem) -> TreeItem:
    if item_map.has(rule_id):
        return item_map[rule_id]
    if not rule_map.has(rule_id):
        return root

    var rule: Dictionary = rule_map[rule_id]
    var parent_item := root
    var parent_ids: Array = rule.get("parent_rule_ids", [])
    if not parent_ids.is_empty():
        var parent_rule_id := String(parent_ids[0])
        parent_item = _ensure_rule_item(parent_rule_id, rule_map, item_map, root)

    var item := _rule_tree.create_item(parent_item)
    item.set_text(0, String(rule.get("name", rule_id)))
    item.set_text(1, String(rule.get("status", "")))
    item_map[rule_id] = item
    return item

func _refresh_entity_tree(snapshot: Dictionary) -> void:
    _entity_tree.clear()
    var root := _entity_tree.create_item()
    var entity_map := _entity_map(snapshot)
    var rendered: Dictionary = {}

    for root_id in ["player_character", "game_master", "storehouse"]:
        if entity_map.has(root_id):
            _add_entity_item(root, root_id, entity_map, rendered)

    for entity_id in entity_map.keys():
        if rendered.has(entity_id):
            continue
        _add_entity_item(root, entity_id, entity_map, rendered)

func _add_entity_item(parent: TreeItem, entity_id: String, entity_map: Dictionary, rendered: Dictionary) -> void:
    if rendered.has(entity_id):
        return
    var entity: Dictionary = entity_map.get(entity_id, {})
    if entity.is_empty() or not bool(entity.get("visible", false)):
        return

    rendered[entity_id] = true
    var item := _entity_tree.create_item(parent)
    item.set_text(0, String(entity.get("name", entity_id)))
    item.set_text(1, _entity_status(entity))
    item.set_metadata(0, entity_id)

    var child_ids: Array = []
    child_ids.append_array(entity.get("owned_ids", []))
    child_ids.append_array(entity.get("child_ids", []))
    for child_id_variant in child_ids:
        var child_id := String(child_id_variant)
        if child_id.is_empty() or rendered.has(child_id):
            continue
        _add_entity_item(item, child_id, entity_map, rendered)

func _entity_status(entity: Dictionary) -> String:
    var summary := String(entity.get("summary", ""))
    return summary if not summary.is_empty() else "確認可能"

func _refresh_detail_view(snapshot: Dictionary) -> void:
    var selected := _coerce_dictionary(snapshot.get("selected_entity", {}))
    var lines: Array = []
    if not selected.is_empty():
        lines.append("選択中: %s" % String(selected.get("name", "")))
        for detail in selected.get("inspector_lines", []):
            lines.append("- %s" % String(detail))
    lines.append("")
    lines.append("目標:")
    for goal in snapshot.get("goal_lines", []):
        lines.append(String(goal))
    _detail_view.text = "\n".join(lines)

func _on_entity_tree_selected() -> void:
    var item := _entity_tree.get_selected()
    if item == null:
        return
    var entity_id := String(item.get_metadata(0))
    if entity_id.is_empty():
        return
    if world_controller != null and world_controller.has_method("set_selected_entity"):
        world_controller.call("set_selected_entity", entity_id)

func _snapshot() -> Dictionary:
    if world_controller != null and world_controller.has_method("get_poc_snapshot"):
        var snapshot_variant = world_controller.call("get_poc_snapshot")
        if snapshot_variant is Dictionary:
            return snapshot_variant
    return {}

func _entity_map(snapshot: Dictionary) -> Dictionary:
    var entity_map: Dictionary = {}
    for entity in snapshot.get("entities", []):
        if entity is Dictionary:
            var entity_dict: Dictionary = entity
            entity_map[String(entity_dict.get("id", ""))] = entity_dict
    return entity_map

func _coerce_dictionary(value: Variant) -> Dictionary:
    return value if value is Dictionary else {}

func _fade_in() -> void:
    var tween := create_tween()
    tween.tween_property(self, "modulate:a", 1.0, 0.16)

func _close() -> void:
    var tween := create_tween()
    tween.tween_property(self, "modulate:a", 0.0, 0.14)
    tween.tween_callback(func() -> void:
        closed.emit()
        queue_free()
    )
