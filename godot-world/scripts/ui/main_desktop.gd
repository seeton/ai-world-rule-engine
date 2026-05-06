extends Control

const FALLBACK_TEMPLATES: Array = [
    {
        "id": "object_base",
        "name": "オブジェクト基礎",
        "description": "物体エンティティと object-base 親種別を確認するための基礎ルールです。"
    },
    {
        "id": "ownership_links",
        "name": "所有関係",
        "description": "object-base を前提に、誰が何を持つかを見えるようにします。"
    },
    {
        "id": "storage_layout",
        "name": "収納配置",
        "description": "object-base を前提に、入れ物と配置先の関係を整理します。"
    }
]

const TEMPLATE_UI_OVERRIDES: Dictionary = {
    "world_time": {
        "name": "世界時刻",
        "description": "世界の時刻を進める基本ルールです。"
    },
    "hunger": {
        "name": "空腹",
        "description": "空腹の必要量を時間経過で増やします。"
    },
    "sleep": {
        "name": "睡眠",
        "description": "眠気の必要量を時間経過で増やします。"
    },
    "health": {
        "name": "体力",
        "description": "体力ステータスを追加します。"
    },
    "mana": {
        "name": "マナ",
        "description": "マナ資源を追加します。"
    },
    "object_base": {
        "name": "オブジェクト基礎",
        "description": "物体エンティティと object-base 親種別を確認するための基礎ルールです。"
    },
    "ownership_links": {
        "name": "所有関係",
        "description": "object-base を前提に、誰が何を持つかを見えるようにします。"
    },
    "storage_layout": {
        "name": "収納配置",
        "description": "object-base を前提に、入れ物と配置先の関係を整理します。"
    }
}
const RULE_UI_NAME_OVERRIDES: Dictionary = {
    "rule_world_time": "世界時刻ルール",
    "rule_hunger": "空腹ルール",
    "rule_sleep": "睡眠ルール",
    "rule_health": "体力ルール",
    "rule_mana": "マナルール",
    "rule_object_base": "オブジェクト基礎ルール",
    "rule_ownership_links": "所有関係ルール",
    "rule_storage_layout": "収納配置ルール"
}
const RULE_PARENT_ID_FIELDS: Array = [
    "resolved_parent_rule_ids",
    "parent_rule_ids",
    "resolved_parent_ids",
    "parent_ids"
]
const RULE_REQUIRED_KIND_FIELDS: Array = [
    "requires_rule_kinds",
    "required_parent_rule_kinds",
    "required_rule_kinds",
    "parent_rule_kinds",
    "missing_required_rule_kinds"
]
const RULE_PROVIDED_KIND_FIELDS: Array = [
    "provides_rule_kinds",
    "provided_rule_kinds",
    "rule_kinds",
    "kinds"
]
const ENTITY_REFERENCE_FIELDS: Dictionary = {
    "container_id": {"forward": "入れ物", "reverse": "中身"},
    "equipped_by_entity_id": {"forward": "装備者", "reverse": "装備"},
    "held_by_entity_id": {"forward": "保持者", "reverse": "保持"},
    "holder_id": {"forward": "保持者", "reverse": "保持"},
    "home_entity_id": {"forward": "拠点", "reverse": "居住者"},
    "location_id": {"forward": "場所", "reverse": "配置"},
    "owned_by_entity_id": {"forward": "所有者", "reverse": "所有"},
    "owner_entity_id": {"forward": "所有者", "reverse": "所有"},
    "owner_id": {"forward": "所有者", "reverse": "所有"},
    "parent_entity_id": {"forward": "親", "reverse": "子"},
    "parent_id": {"forward": "親", "reverse": "子"}
}
const ENTITY_COLLECTION_FIELDS: Dictionary = {
    "child_entity_ids": {"forward": "子", "reverse": "親"},
    "contained_entity_ids": {"forward": "中身", "reverse": "入れ物"},
    "equipped_entity_ids": {"forward": "装備", "reverse": "装備者"},
    "inventory_entity_ids": {"forward": "所持品", "reverse": "所持先"},
    "inventory_ids": {"forward": "所持品", "reverse": "所持先"},
    "occupant_entity_ids": {"forward": "配置", "reverse": "場所"},
    "owned_entity_ids": {"forward": "所有", "reverse": "所有者"}
}
const CHARACTER_ARCHETYPE_HINTS: Array = ["actor", "character", "gm", "npc", "person", "player", "villager"]
const CHARACTER_TAG_HINTS: Array = ["agent", "character", "gm", "human", "mortal", "npc", "person", "player", "villager"]
const OBJECT_ARCHETYPE_HINTS: Array = ["container", "item", "location", "object", "place", "prop", "resource", "structure", "tool"]
const OBJECT_TAG_HINTS: Array = ["container", "item", "location", "object", "portable", "prop", "resource", "structure", "tool"]

var _world_state: Node = null
var _task_input: TextEdit
var _template_list: ItemList
var _install_template_button: Button
var _tick_amount: SpinBox
var _installed_rule_tree: Tree
var _installed_rule_list: ItemList
var _clone_rule_button: Button
var _installed_rule_details_view: TextEdit
var _entity_tree: Tree
var _world_state_view: TextEdit
var _event_log_view: TextEdit
var _status_label: Label

var _template_cache: Array = []
var _installed_rule_cache: Array = []
var _snapshot_cache: Dictionary = {}
var _shell_log_lines: Array[String] = []
var _fallback_snapshot: Dictionary = {
    "world_id": "fallback-world",
    "world_name": "オブジェクトルール確認用",
    "runtime_choice": "desktop-shell-preview",
    "elapsed_seconds": 0.0,
    "tick_index": 0,
    "concepts": ["ownership"],
    "installed_rules": {
        "rule_ownership_links": {
            "id": "rule_ownership_links",
            "name": "所有関係ルール",
            "concept": "ownership",
            "enabled": true,
            "requires_rule_kinds": ["object-base"],
            "provides_rule_kinds": ["ownership-base"],
            "effects": []
        }
    },
    "entities": {
        "aria": {
            "id": "aria",
            "name": "アリア",
            "archetype": "villager",
            "tags": ["mortal", "mutable", "villager"],
            "components": {
                "behavior": {
                    "current_task": "持ち物と保管物を確認中"
                },
                "needs": {
                    "hunger": 12.0,
                    "sleep": 8.0
                },
                "stats": {
                    "focus": 52.0,
                    "morale": 61.0
                }
            }
        },
        "tool_satchel": {
            "id": "tool_satchel",
            "name": "道具袋",
            "archetype": "item",
            "tags": ["object", "portable"],
            "owner_id": "aria",
            "components": {
                "inventory": {
                    "contained_entity_ids": ["berry_bundle"]
                },
                "state": {
                    "condition": "丈夫",
                    "slot": "肩掛け"
                }
            }
        },
        "berry_bundle": {
            "id": "berry_bundle",
            "name": "ベリー束",
            "archetype": "item",
            "tags": ["food", "object"],
            "container_id": "tool_satchel",
            "components": {
                "state": {
                    "freshness": "採れたて",
                    "servings": 3
                }
            }
        },
        "storehouse": {
            "id": "storehouse",
            "name": "倉庫",
            "archetype": "structure",
            "tags": ["location", "object", "structure"],
            "components": {
                "state": {
                    "condition": "乾燥",
                    "status": "在庫あり"
                }
            }
        },
        "water_jar": {
            "id": "water_jar",
            "name": "水瓶",
            "archetype": "item",
            "tags": ["container", "object"],
            "location_id": "storehouse",
            "owner_id": "aria",
            "components": {
                "state": {
                    "fill": "半分",
                    "sealed": true
                }
            }
        }
    },
    "player_task_history": [],
    "event_log": [
        {
            "type": "world_initialized",
            "message": "オブジェクトルールUIのフォールバック表示を開始しました。",
            "details": {}
        },
        {
            "type": "rule_waiting_for_parent",
            "message": "所有関係ルールは object-base の親待ちです。",
            "details": {
                "rule_id": "rule_ownership_links",
                "missing_required_rule_kinds": ["object-base"]
            }
        }
    ]
}

func _ready() -> void:
    set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
    _refresh_world_state_reference()
    _build_ui()
    _refresh_all()
    _append_log("日本語UIシェルを起動しました。", {"world_state_connected": _world_state != null})

func _build_ui() -> void:
    var root_margin := MarginContainer.new()
    root_margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
    root_margin.add_theme_constant_override("margin_left", 16)
    root_margin.add_theme_constant_override("margin_top", 16)
    root_margin.add_theme_constant_override("margin_right", 16)
    root_margin.add_theme_constant_override("margin_bottom", 16)
    add_child(root_margin)

    var main_column := VBoxContainer.new()
    main_column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    main_column.size_flags_vertical = Control.SIZE_EXPAND_FILL
    main_column.add_theme_constant_override("separation", 12)
    root_margin.add_child(main_column)

    var header := VBoxContainer.new()
    header.add_theme_constant_override("separation", 4)
    main_column.add_child(header)

    var title := Label.new()
    title.text = "オブジェクトルール PoC シェル"
    title.add_theme_font_size_override("font_size", 24)
    header.add_child(title)

    var subtitle := Label.new()
    subtitle.text = "導入済みルールの親子関係と、物体・所有関係を確認するための日本語UIです。"
    subtitle.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
    header.add_child(subtitle)

    _status_label = Label.new()
    _status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
    header.add_child(_status_label)

    var split := HSplitContainer.new()
    split.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    split.size_flags_vertical = Control.SIZE_EXPAND_FILL
    split.split_offset = 480
    main_column.add_child(split)

    var left_column := VBoxContainer.new()
    left_column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    left_column.size_flags_vertical = Control.SIZE_EXPAND_FILL
    left_column.add_theme_constant_override("separation", 12)
    split.add_child(left_column)

    left_column.add_child(_build_task_panel())
    left_column.add_child(_build_template_panel())
    left_column.add_child(_build_tick_panel())

    var right_column := VBoxContainer.new()
    right_column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    right_column.size_flags_vertical = Control.SIZE_EXPAND_FILL
    right_column.add_theme_constant_override("separation", 12)
    split.add_child(right_column)

    right_column.add_child(_build_installed_rules_panel())
    right_column.add_child(_build_world_state_panel())
    right_column.add_child(_build_text_panel("イベントログ", "最近の世界イベントとシェル操作を表示します。", "event_log", 170))

func _build_task_panel() -> Control:
    var panel := _make_panel_section("プレイヤータスク", "やりたいことを日本語で書くと、関連するルール候補を確認できます。")
    var body := panel.get_meta("body") as VBoxContainer

    _task_input = TextEdit.new()
    _task_input.custom_minimum_size = Vector2(0, 110)
    _task_input.placeholder_text = "例: 物体ルールを入れて、所有者と入れ物の関係を確認したい。"
    _task_input.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
    body.add_child(_task_input)

    var button_row := HBoxContainer.new()
    button_row.add_theme_constant_override("separation", 8)
    body.add_child(button_row)

    var submit_button := Button.new()
    submit_button.text = "タスク送信"
    submit_button.pressed.connect(_on_submit_pressed)
    button_row.add_child(submit_button)

    var refresh_button := Button.new()
    refresh_button.text = "スナップショット更新"
    refresh_button.pressed.connect(_refresh_all)
    button_row.add_child(refresh_button)

    return panel

func _build_template_panel() -> Control:
    var panel := _make_panel_section("ルールテンプレート", "使えるテンプレートを選び、このPoCで必要なルールだけを追加します。")
    var body := panel.get_meta("body") as VBoxContainer

    _template_list = ItemList.new()
    _template_list.custom_minimum_size = Vector2(0, 180)
    _template_list.select_mode = ItemList.SELECT_SINGLE
    _template_list.item_selected.connect(_on_template_selected)
    body.add_child(_template_list)

    _install_template_button = Button.new()
    _install_template_button.text = "選択したテンプレートを追加"
    _install_template_button.disabled = true
    _install_template_button.pressed.connect(_on_install_template_pressed)
    body.add_child(_install_template_button)

    return panel

func _build_tick_panel() -> Control:
    var panel := _make_panel_section("シミュレーション操作", "時間を進め、物体や所有状態に関わる変化を確認します。")
    var body := panel.get_meta("body") as VBoxContainer

    var row := HBoxContainer.new()
    row.add_theme_constant_override("separation", 8)
    body.add_child(row)

    _tick_amount = SpinBox.new()
    _tick_amount.min_value = 0.25
    _tick_amount.max_value = 30.0
    _tick_amount.step = 0.25
    _tick_amount.value = 1.0
    _tick_amount.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    row.add_child(_tick_amount)

    var tick_button := Button.new()
    tick_button.text = "1ステップ進める"
    tick_button.pressed.connect(_on_tick_pressed)
    row.add_child(tick_button)

    return panel

func _build_installed_rules_panel() -> Control:
    var panel := _make_panel_section("導入済みルール", "ルールの一覧と親子・依存状態を確認し、必要なら複製できます。")
    var body := panel.get_meta("body") as VBoxContainer

    var tree_label := Label.new()
    tree_label.text = "親子・依存ツリー"
    body.add_child(tree_label)

    _installed_rule_tree = Tree.new()
    _installed_rule_tree.columns = 2
    _installed_rule_tree.column_titles_visible = true
    _installed_rule_tree.hide_root = true
    _installed_rule_tree.custom_minimum_size = Vector2(0, 170)
    _installed_rule_tree.size_flags_vertical = Control.SIZE_EXPAND_FILL
    _installed_rule_tree.set_column_title(0, "ルール")
    _installed_rule_tree.set_column_title(1, "親・依存状態")
    _installed_rule_tree.item_selected.connect(_on_rule_tree_selected)
    body.add_child(_installed_rule_tree)

    var list_label := Label.new()
    list_label.text = "一覧"
    body.add_child(list_label)

    _installed_rule_list = ItemList.new()
    _installed_rule_list.custom_minimum_size = Vector2(0, 110)
    _installed_rule_list.select_mode = ItemList.SELECT_SINGLE
    _installed_rule_list.item_selected.connect(_on_installed_rule_selected)
    body.add_child(_installed_rule_list)

    var action_row := HBoxContainer.new()
    action_row.add_theme_constant_override("separation", 8)
    body.add_child(action_row)

    _clone_rule_button = Button.new()
    _clone_rule_button.text = "選択ルールを複製"
    _clone_rule_button.disabled = true
    _clone_rule_button.pressed.connect(_on_clone_rule_pressed)
    action_row.add_child(_clone_rule_button)

    _installed_rule_details_view = TextEdit.new()
    _installed_rule_details_view.editable = false
    _installed_rule_details_view.custom_minimum_size = Vector2(0, 110)
    _installed_rule_details_view.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
    body.add_child(_installed_rule_details_view)

    return panel

func _build_world_state_panel() -> Control:
    var panel := _make_panel_section("物体と所有状態", "物体エンティティ、所有者、入れ物、配置先を見やすく整理して表示します。")
    var body := panel.get_meta("body") as VBoxContainer

    var tree_label := Label.new()
    tree_label.text = "エンティティ関係ツリー"
    body.add_child(tree_label)

    _entity_tree = Tree.new()
    _entity_tree.columns = 2
    _entity_tree.column_titles_visible = true
    _entity_tree.hide_root = true
    _entity_tree.custom_minimum_size = Vector2(0, 180)
    _entity_tree.size_flags_vertical = Control.SIZE_EXPAND_FILL
    _entity_tree.set_column_title(0, "対象")
    _entity_tree.set_column_title(1, "状態 / 関係")
    body.add_child(_entity_tree)

    var summary_label := Label.new()
    summary_label.text = "スナップショット要約"
    body.add_child(summary_label)

    _world_state_view = TextEdit.new()
    _world_state_view.editable = false
    _world_state_view.custom_minimum_size = Vector2(0, 120)
    _world_state_view.size_flags_vertical = Control.SIZE_EXPAND_FILL
    _world_state_view.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
    body.add_child(_world_state_view)

    return panel

func _build_text_panel(title_text: String, description: String, panel_key: String, min_height: float) -> Control:
    var panel := _make_panel_section(title_text, description)
    var body := panel.get_meta("body") as VBoxContainer

    var view := TextEdit.new()
    view.editable = false
    view.custom_minimum_size = Vector2(0, min_height)
    view.size_flags_vertical = Control.SIZE_EXPAND_FILL
    view.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
    body.add_child(view)

    match panel_key:
        "world_state":
            _world_state_view = view
        "event_log":
            _event_log_view = view

    return panel

func _make_panel_section(title_text: String, description: String) -> PanelContainer:
    var panel := PanelContainer.new()
    panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    panel.size_flags_vertical = Control.SIZE_EXPAND_FILL

    var margin := MarginContainer.new()
    margin.add_theme_constant_override("margin_left", 12)
    margin.add_theme_constant_override("margin_top", 12)
    margin.add_theme_constant_override("margin_right", 12)
    margin.add_theme_constant_override("margin_bottom", 12)
    panel.add_child(margin)

    var body := VBoxContainer.new()
    body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    body.size_flags_vertical = Control.SIZE_EXPAND_FILL
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

func _refresh_all() -> void:
    _refresh_world_state_reference()
    _refresh_templates()
    _refresh_snapshot()
    _installed_rule_cache = _extract_installed_rules(_snapshot_cache)
    _update_template_list()
    _update_installed_rules_panel()
    _update_world_state_view()
    _update_event_log_view()
    _update_status_label()

func _refresh_world_state_reference() -> void:
    _world_state = get_node_or_null("/root/WorldState")

func _refresh_templates() -> void:
    if _world_state != null and _world_state.has_method("get_available_rule_templates"):
        var templates = _world_state.call("get_available_rule_templates")
        _template_cache = templates if templates is Array else []
    else:
        _template_cache = FALLBACK_TEMPLATES.duplicate(true)

func _refresh_snapshot() -> void:
    if _world_state != null and _world_state.has_method("get_world_snapshot"):
        var snapshot = _world_state.call("get_world_snapshot")
        _snapshot_cache = snapshot if snapshot is Dictionary else {}
    else:
        _snapshot_cache = _fallback_snapshot.duplicate(true)

func _update_template_list() -> void:
    _template_list.clear()
    for template_data in _template_cache:
        _template_list.add_item(_format_template_label(template_data))
    _install_template_button.disabled = _template_cache.is_empty()
    if not _template_cache.is_empty():
        _template_list.select(0)

func _update_installed_rules_panel() -> void:
    _installed_rule_list.clear()
    for rule_data in _installed_rule_cache:
        _installed_rule_list.add_item(_format_rule_list_label(rule_data))
    _update_installed_rule_tree()

    var has_rules := not _installed_rule_cache.is_empty()
    _clone_rule_button.disabled = not has_rules
    if not has_rules:
        _installed_rule_details_view.text = "まだルールはありません。テンプレートを追加すると、親ルールや未解決の依存を確認できます。"
        return

    _installed_rule_list.select(0)
    _update_installed_rule_details(0)

func _update_installed_rule_details(index: int) -> void:
    if index < 0 or index >= _installed_rule_cache.size():
        _installed_rule_details_view.text = ""
        _clone_rule_button.disabled = true
        return

    var rule_data = _installed_rule_cache[index]
    var rule_id := _extract_identifier(rule_data)
    var dependency_model := _build_rule_dependency_model()
    var summary_lines: Array[String] = []
    summary_lines.append("ルール: %s" % _format_rule_list_label(rule_data))

    var resolved_parent_ids: Array = dependency_model.get("resolved_parents_by_rule", {}).get(rule_id, [])
    summary_lines.append("解決済みの親: %s" % [
        _format_rule_reference_list(resolved_parent_ids, dependency_model) if not resolved_parent_ids.is_empty() else "なし"
    ])

    var child_ids: Array = dependency_model.get("children_by_parent", {}).get(rule_id, [])
    summary_lines.append("子ルール: %s" % [
        _format_rule_reference_list(child_ids, dependency_model) if not child_ids.is_empty() else "なし"
    ])

    var provided_kinds := _extract_rule_provided_kinds(rule_data)
    if not provided_kinds.is_empty():
        summary_lines.append("提供種別: %s" % _join_values(provided_kinds))

    var required_kinds := _extract_rule_required_kinds(rule_data)
    if not required_kinds.is_empty():
        summary_lines.append("必要な親種別: %s" % _join_values(required_kinds))

    var unresolved_kinds := _get_rule_unresolved_required_kinds(rule_id, dependency_model)
    if unresolved_kinds.is_empty():
        summary_lines.append("親要件の状態: すべて解決済み、または未定義")
    else:
        summary_lines.append("未解決の必要な親種別:")
        for required_kind in unresolved_kinds:
            var candidate_ids := _get_candidate_parent_rule_ids(rule_id, required_kind, dependency_model)
            if candidate_ids.is_empty():
                summary_lines.append("- %s (候補なし)" % required_kind)
            else:
                summary_lines.append("- %s (候補: %s)" % [
                    required_kind,
                    _format_rule_reference_list(candidate_ids, dependency_model)
                ])

    _clone_rule_button.disabled = false
    summary_lines.append("")
    summary_lines.append("生JSON:")
    summary_lines.append(JSON.stringify(rule_data, "\t"))
    _installed_rule_details_view.text = "\n".join(summary_lines)

func _update_world_state_view() -> void:
    if _snapshot_cache.is_empty():
        _update_entity_tree([], {})
        _world_state_view.text = "ワールドスナップショットを取得できません。"
        return

    var lines: Array[String] = []
    var entities := _extract_entities(_snapshot_cache)
    var entity_model := _build_entity_relationship_model(entities)
    _update_entity_tree(entities, entity_model)

    lines.append("世界: %s" % [str(_snapshot_cache.get("world_id", _snapshot_cache.get("world_name", "unknown")))])
    lines.append("実行方式: %s" % [str(_snapshot_cache.get("runtime_choice", "n/a"))])
    lines.append("進行ステップ: %s" % [str(_snapshot_cache.get("tick_index", _snapshot_cache.get("tick", "?")))])
    lines.append("経過秒: %s" % [str(_snapshot_cache.get("elapsed_seconds", 0.0))])
    var concepts := _variant_to_string_array(_snapshot_cache.get("concepts", []))
    lines.append("概念: %s" % (_join_values(concepts) if not concepts.is_empty() else "なし"))

    lines.append("")
    lines.append("所有・内包の概要:")
    var relationship_lines := _build_entity_relationship_summary_lines(entity_model)
    if relationship_lines.is_empty():
        lines.append("- 所有や内包のつながりはありません。")
    else:
        for relationship_line in relationship_lines:
            lines.append(str(relationship_line))

    lines.append("")
    lines.append("キャラクタ・エージェント:")
    var character_entities := _filter_entities_by_kind(entities, true)
    if character_entities.is_empty():
        lines.append("- キャラクタ型エンティティはありません。")
    else:
        for entity_data in character_entities:
            lines.append(_format_entity_summary(entity_data, entity_model))

    lines.append("")
    lines.append("物体・ワールド要素:")
    var object_entities := _filter_entities_by_kind(entities, false)
    if object_entities.is_empty():
        lines.append("- 物体型エンティティはありません。")
    else:
        for entity_data in object_entities:
            lines.append(_format_entity_summary(entity_data, entity_model))

    lines.append("")
    lines.append("全エンティティ数: %d" % entities.size())

    var task_history = _snapshot_cache.get("player_task_history", [])
    if task_history is Array and not task_history.is_empty():
        lines.append("")
        lines.append("直近のタスク結果:")
        lines.append(JSON.stringify(task_history[task_history.size() - 1], "\t"))

    _world_state_view.text = "\n".join(lines)

func _update_event_log_view() -> void:
    var lines: Array[String] = []
    var world_events = _snapshot_cache.get("event_log", [])
    if world_events is Array and not world_events.is_empty():
        lines.append("世界イベント:")
        for event_data in _take_last_entries(world_events, 8):
            lines.append(_format_event_entry(event_data))

    if not _shell_log_lines.is_empty():
        if not lines.is_empty():
            lines.append("")
        lines.append("シェル操作:")
        for log_line in _take_last_entries(_shell_log_lines, 8):
            lines.append(str(log_line))

    _event_log_view.text = "\n".join(lines) if not lines.is_empty() else "まだイベントはありません。"
    _event_log_view.scroll_vertical = _event_log_view.get_line_count()

func _update_status_label() -> void:
    var source := "WorldState 自動読み込み" if _world_state != null else "フォールバック表示"
    var entities := _extract_entities(_snapshot_cache)
    var object_count := _filter_entities_by_kind(entities, false).size()
    _status_label.text = "データ元: %s | テンプレート: %d | ルール: %d | 物体: %d" % [
        source,
        _template_cache.size(),
        _installed_rule_cache.size(),
        object_count
    ]

func _on_submit_pressed() -> void:
    var task_text := _task_input.text.strip_edges()
    if task_text.is_empty():
        _append_log("空のタスクは無視しました。")
        return

    var result: Dictionary = {}
    if _world_state != null and _world_state.has_method("submit_player_task"):
        result = _world_state.call("submit_player_task", task_text)
    else:
        result = _simulate_task_submission(task_text)

    _task_input.clear()
    _refresh_all()
    _append_log("タスクを送信しました: %s" % task_text, result)

func _on_install_template_pressed() -> void:
    var selected_items := _template_list.get_selected_items()
    if selected_items.is_empty():
        _append_log("テンプレート未選択のまま追加しようとしました。")
        return

    var template_id := _extract_identifier(_template_cache[selected_items[0]])
    _install_template_by_id(template_id)

func _install_template_by_id(template_id: String) -> void:
    var template_index := _find_template_index_by_id(template_id)
    if template_index == -1:
        _append_log("テンプレート '%s' が見つかりません。" % template_id)
        return

    var template_data = _template_cache[template_index]
    var result: Dictionary = {}
    if _world_state != null and _world_state.has_method("create_rule_from_patch"):
        result = _world_state.call("create_rule_from_patch", {"template_id": template_id})
    elif _world_state != null and _world_state.has_method("clone_rule"):
        result = _world_state.call("clone_rule", template_id)
    else:
        result = _simulate_template_install(template_data)

    _refresh_all()
    _append_log("テンプレートを追加しました: %s" % template_id, result)

func _on_clone_rule_pressed() -> void:
    var selected_items := _installed_rule_list.get_selected_items()
    if selected_items.is_empty():
        _append_log("導入済みルール未選択のまま複製しようとしました。")
        return

    var rule_data = _installed_rule_cache[selected_items[0]]
    var rule_id := _extract_identifier(rule_data)
    var result: Dictionary = {}
    if _world_state != null and _world_state.has_method("clone_rule"):
        result = _world_state.call("clone_rule", rule_id)
    else:
        result = _simulate_rule_clone(rule_data)

    _refresh_all()
    _append_log("ルールを複製しました: %s" % rule_id, result)

func _on_tick_pressed() -> void:
    var delta_seconds := _tick_amount.value
    if _world_state != null and _world_state.has_method("advance_tick"):
        _world_state.call("advance_tick", delta_seconds)
        _refresh_all()
        _append_log("シミュレーションを進めました。", {"delta_seconds": delta_seconds})
        return

    var result := _simulate_tick(delta_seconds)
    _refresh_all()
    _append_log("フォールバックシミュレーションを進めました。", result)

func _on_template_selected(_index: int) -> void:
    _install_template_button.disabled = _template_list.get_selected_items().is_empty()

func _on_installed_rule_selected(index: int) -> void:
    _update_installed_rule_details(index)

func _on_rule_tree_selected() -> void:
    var selected_item := _installed_rule_tree.get_selected()
    if selected_item == null:
        return

    var rule_id = selected_item.get_metadata(0)
    if rule_id == null:
        return

    var rule_index := _find_rule_index_by_id(str(rule_id))
    if rule_index == -1:
        return

    _installed_rule_list.deselect_all()
    _installed_rule_list.select(rule_index)
    _update_installed_rule_details(rule_index)

# Assumption: the live simulation autoload is available as /root/WorldState.
func _extract_installed_rules(snapshot: Dictionary) -> Array:
    var raw_rules = snapshot.get("installed_rules", [])
    if raw_rules is Array:
        return raw_rules
    if raw_rules is Dictionary:
        var rules: Array = []
        var rule_ids: Array = raw_rules.keys()
        rule_ids.sort()
        for rule_id in rule_ids:
            rules.append(raw_rules[rule_id])
        return rules
    return []

func _extract_entities(snapshot: Dictionary) -> Array:
    var raw_entities = snapshot.get("entities", [])
    if raw_entities is Array:
        return raw_entities
    if raw_entities is Dictionary:
        var entities: Array = []
        var entity_ids: Array = raw_entities.keys()
        entity_ids.sort()
        for entity_id in entity_ids:
            entities.append(raw_entities[entity_id])
        return entities
    return []

func _extract_identifier(data: Variant) -> String:
    if data is Dictionary:
        for key in ["id", "rule_id", "template_id", "name"]:
            if data.has(key):
                return str(data.get(key))
    return str(data)

func _find_template_index_by_id(template_id: String) -> int:
    for index in range(_template_cache.size()):
        if _extract_identifier(_template_cache[index]) == template_id:
            return index
    return -1

func _format_template_label(template_data: Variant) -> String:
    if template_data is Dictionary:
        var template_id := _extract_identifier(template_data)
        return "%s — %s" % [
            _get_template_display_name(template_data),
            _get_template_display_description(template_id, template_data)
        ]
    return str(template_data)

func _format_rule_list_label(rule_data: Variant) -> String:
    if rule_data is Dictionary:
        var rule_id := _extract_identifier(rule_data)
        return "%s (%s)" % [
            _get_rule_display_name(rule_data),
            rule_id
        ]
    return str(rule_data)

func _find_rule_index_by_id(rule_id: String) -> int:
    for index in range(_installed_rule_cache.size()):
        if _extract_identifier(_installed_rule_cache[index]) == rule_id:
            return index
    return -1

func _get_template_display_name(template_data: Variant) -> String:
    var template_id := _extract_identifier(template_data)
    var override_data = TEMPLATE_UI_OVERRIDES.get(template_id, null)
    if override_data is Dictionary and override_data.has("name"):
        return str(override_data.get("name"))
    if template_data is Dictionary:
        return str(template_data.get("name", template_id))
    return template_id

func _get_template_display_description(template_id: String, template_data: Variant) -> String:
    var override_data = TEMPLATE_UI_OVERRIDES.get(template_id, null)
    if override_data is Dictionary and override_data.has("description"):
        return str(override_data.get("description"))
    if template_data is Dictionary:
        return str(template_data.get("description", template_data.get("summary", "追加準備完了")))
    return "追加準備完了"

func _get_rule_display_name(rule_data: Variant) -> String:
    var rule_id := _extract_identifier(rule_data)
    if RULE_UI_NAME_OVERRIDES.has(rule_id):
        return str(RULE_UI_NAME_OVERRIDES[rule_id])
    if rule_data is Dictionary:
        return str(rule_data.get("name", rule_id))
    return rule_id

func _update_installed_rule_tree() -> void:
    if _installed_rule_tree == null:
        return

    _installed_rule_tree.clear()
    var root_item := _installed_rule_tree.create_item()
    if _installed_rule_cache.is_empty():
        var empty_item := _installed_rule_tree.create_item(root_item)
        empty_item.set_text(0, "導入済みルールなし")
        empty_item.set_text(1, "テンプレートを追加すると依存ツリーが表示されます。")
        return

    var dependency_model := _build_rule_dependency_model()
    var displayed_rule_ids: Array = []

    var root_rule_ids: Array = dependency_model.get("root_rule_ids", [])
    if not root_rule_ids.is_empty():
        var resolved_group := _installed_rule_tree.create_item(root_item)
        resolved_group.set_text(0, "根ルール")
        resolved_group.set_text(1, "親を必要としない、または親が解決済みの起点です。")
        for rule_id in root_rule_ids:
            _add_rule_tree_item(resolved_group, str(rule_id), dependency_model, [], displayed_rule_ids)

    var unresolved_rule_ids: Array = dependency_model.get("unresolved_rule_ids", [])
    if not unresolved_rule_ids.is_empty():
        var unresolved_group := _installed_rule_tree.create_item(root_item)
        unresolved_group.set_text(0, "親待ちルール")
        unresolved_group.set_text(1, "必要な親種別がまだ見つかっていません。")
        for rule_id in unresolved_rule_ids:
            _add_rule_tree_item(unresolved_group, str(rule_id), dependency_model, [], displayed_rule_ids)

    var overflow_group: TreeItem = null
    var rule_ids: Array = dependency_model.get("rule_ids", [])
    for rule_id in rule_ids:
        if displayed_rule_ids.has(rule_id):
            continue
        if overflow_group == null:
            overflow_group = _installed_rule_tree.create_item(root_item)
            overflow_group.set_text(0, "追加表示")
            overflow_group.set_text(1, "循環や複数親のため、ここにも表示しています。")
        _add_rule_tree_item(overflow_group, str(rule_id), dependency_model, [], displayed_rule_ids)

func _build_rule_dependency_model() -> Dictionary:
    var rules_by_id: Dictionary = {}
    var rule_ids: Array = []
    for rule_data in _installed_rule_cache:
        if not (rule_data is Dictionary):
            continue
        var rule_id := _extract_identifier(rule_data)
        if rules_by_id.has(rule_id):
            continue
        rules_by_id[rule_id] = rule_data
        rule_ids.append(rule_id)
    rule_ids.sort()

    var children_by_parent: Dictionary = {}
    var providers_by_kind: Dictionary = {}
    var resolved_parents_by_rule: Dictionary = {}
    var required_kinds_by_rule: Dictionary = {}
    var provided_kinds_by_rule: Dictionary = {}

    for rule_id in rule_ids:
        var rule_data: Dictionary = rules_by_id[rule_id]
        var resolved_parent_ids: Array = []
        for parent_id in _extract_rule_parent_ids(rule_data):
            if rules_by_id.has(parent_id) and not resolved_parent_ids.has(parent_id):
                resolved_parent_ids.append(parent_id)
                if not children_by_parent.has(parent_id):
                    children_by_parent[parent_id] = []
                var child_ids: Array = children_by_parent[parent_id]
                if not child_ids.has(rule_id):
                    child_ids.append(rule_id)
                children_by_parent[parent_id] = child_ids
        resolved_parents_by_rule[rule_id] = resolved_parent_ids

        var required_kinds := _extract_rule_required_kinds(rule_data)
        required_kinds_by_rule[rule_id] = required_kinds

        var provided_kinds := _extract_rule_provided_kinds(rule_data)
        provided_kinds_by_rule[rule_id] = provided_kinds
        for provided_kind in provided_kinds:
            if not providers_by_kind.has(provided_kind):
                providers_by_kind[provided_kind] = []
            var provider_ids: Array = providers_by_kind[provided_kind]
            if not provider_ids.has(rule_id):
                provider_ids.append(rule_id)
            providers_by_kind[provided_kind] = provider_ids

    for parent_id in children_by_parent.keys():
        var child_ids: Array = children_by_parent[parent_id]
        child_ids.sort()
        children_by_parent[parent_id] = child_ids
    for provided_kind in providers_by_kind.keys():
        var provider_ids: Array = providers_by_kind[provided_kind]
        provider_ids.sort()
        providers_by_kind[provided_kind] = provider_ids

    var root_rule_ids: Array = []
    var unresolved_rule_ids: Array = []
    for rule_id in rule_ids:
        var resolved_parent_ids: Array = resolved_parents_by_rule.get(rule_id, [])
        var required_kinds: Array = required_kinds_by_rule.get(rule_id, [])
        if resolved_parent_ids.is_empty():
            if required_kinds.is_empty():
                root_rule_ids.append(rule_id)
            else:
                unresolved_rule_ids.append(rule_id)

    return {
        "children_by_parent": children_by_parent,
        "provided_kinds_by_rule": provided_kinds_by_rule,
        "providers_by_kind": providers_by_kind,
        "required_kinds_by_rule": required_kinds_by_rule,
        "resolved_parents_by_rule": resolved_parents_by_rule,
        "root_rule_ids": root_rule_ids,
        "rule_ids": rule_ids,
        "rules_by_id": rules_by_id,
        "unresolved_rule_ids": unresolved_rule_ids
    }

func _add_rule_tree_item(parent_item: TreeItem, rule_id: String, dependency_model: Dictionary, ancestry: Array, displayed_rule_ids: Array) -> void:
    if ancestry.has(rule_id):
        var cycle_item := _installed_rule_tree.create_item(parent_item)
        cycle_item.set_text(0, "依存循環")
        cycle_item.set_text(1, rule_id)
        return

    var rules_by_id: Dictionary = dependency_model.get("rules_by_id", {})
    if not rules_by_id.has(rule_id):
        var missing_item := _installed_rule_tree.create_item(parent_item)
        missing_item.set_text(0, rule_id)
        missing_item.set_text(1, "スナップショットに存在しません。")
        return

    var rule_item := _installed_rule_tree.create_item(parent_item)
    rule_item.set_text(0, _format_rule_reference_list([rule_id], dependency_model))
    rule_item.set_text(1, _summarize_rule_dependency_status(rule_id, dependency_model))
    rule_item.set_metadata(0, rule_id)
    if not displayed_rule_ids.has(rule_id):
        displayed_rule_ids.append(rule_id)

    var resolved_parent_ids: Array = dependency_model.get("resolved_parents_by_rule", {}).get(rule_id, [])
    if resolved_parent_ids.size() > 1:
        var extra_parent_item := _installed_rule_tree.create_item(rule_item)
        extra_parent_item.set_text(0, "他にもぶら下がる親")
        extra_parent_item.set_text(1, _format_rule_reference_list(resolved_parent_ids.slice(1, resolved_parent_ids.size()), dependency_model))

    for required_kind in _get_rule_unresolved_required_kinds(rule_id, dependency_model):
        var unresolved_item := _installed_rule_tree.create_item(rule_item)
        unresolved_item.set_text(0, "必要な親種別")
        var candidate_ids := _get_candidate_parent_rule_ids(rule_id, required_kind, dependency_model)
        if candidate_ids.is_empty():
            unresolved_item.set_text(1, "%s (候補なし)" % str(required_kind))
        else:
            unresolved_item.set_text(1, "%s (候補: %s)" % [
                str(required_kind),
                _format_rule_reference_list(candidate_ids, dependency_model)
            ])

    var next_ancestry := ancestry.duplicate()
    next_ancestry.append(rule_id)
    var child_ids: Array = dependency_model.get("children_by_parent", {}).get(rule_id, [])
    for child_id in child_ids:
        _add_rule_tree_item(rule_item, str(child_id), dependency_model, next_ancestry, displayed_rule_ids)

func _summarize_rule_dependency_status(rule_id: String, dependency_model: Dictionary) -> String:
    var parts: Array[String] = []
    var resolved_parent_ids: Array = dependency_model.get("resolved_parents_by_rule", {}).get(rule_id, [])
    if resolved_parent_ids.is_empty():
        parts.append("根" if _get_rule_unresolved_required_kinds(rule_id, dependency_model).is_empty() else "親待ち")
    else:
        parts.append("親: %s" % _format_rule_reference_list(resolved_parent_ids, dependency_model))

    var child_ids: Array = dependency_model.get("children_by_parent", {}).get(rule_id, [])
    if not child_ids.is_empty():
        parts.append("子: %d件" % child_ids.size())

    var provided_kinds: Array = dependency_model.get("provided_kinds_by_rule", {}).get(rule_id, [])
    if not provided_kinds.is_empty():
        parts.append("提供: %s" % _join_values(provided_kinds))

    var unresolved_required_kinds := _get_rule_unresolved_required_kinds(rule_id, dependency_model)
    if not unresolved_required_kinds.is_empty():
        parts.append("未解決: %s" % _join_values(unresolved_required_kinds))

    return _join_values(parts) if not parts.is_empty() else "依存メタデータなし"

func _get_rule_unresolved_required_kinds(rule_id: String, dependency_model: Dictionary) -> Array:
    var unresolved_required_kinds: Array = []
    var required_kinds: Array = dependency_model.get("required_kinds_by_rule", {}).get(rule_id, [])
    var resolved_parent_ids: Array = dependency_model.get("resolved_parents_by_rule", {}).get(rule_id, [])
    var providers_by_kind: Dictionary = dependency_model.get("providers_by_kind", {})

    for required_kind in required_kinds:
        var provider_ids: Array = Array(providers_by_kind.get(required_kind, []))
        var is_resolved := false
        for parent_id in resolved_parent_ids:
            if provider_ids.has(parent_id):
                is_resolved = true
                break
        if not is_resolved and not unresolved_required_kinds.has(required_kind):
            unresolved_required_kinds.append(required_kind)

    return unresolved_required_kinds

func _get_candidate_parent_rule_ids(rule_id: String, required_kind: String, dependency_model: Dictionary) -> Array:
    var candidates: Array = []
    for provider_id in Array(dependency_model.get("providers_by_kind", {}).get(required_kind, [])):
        if str(provider_id) == rule_id or candidates.has(provider_id):
            continue
        candidates.append(provider_id)
    return candidates

func _extract_rule_parent_ids(rule_data: Variant) -> Array:
    return _extract_string_list_from_keys(
        rule_data,
        RULE_PARENT_ID_FIELDS,
        ["resolved_parent_rule_id", "parent_rule_id", "resolved_parent_id", "parent_id"]
    )

func _extract_rule_required_kinds(rule_data: Variant) -> Array:
    var required_kinds := _extract_string_list_from_keys(
        rule_data,
        RULE_REQUIRED_KIND_FIELDS,
        ["required_parent_rule_kind", "required_rule_kind", "requires_rule_kind", "parent_rule_kind"]
    )
    var unique_required_kinds: Array = []
    for required_kind in required_kinds:
        if not unique_required_kinds.has(required_kind):
            unique_required_kinds.append(required_kind)
    return unique_required_kinds

func _extract_rule_provided_kinds(rule_data: Variant) -> Array:
    return _extract_string_list_from_keys(
        rule_data,
        RULE_PROVIDED_KIND_FIELDS,
        ["provided_rule_kind", "provides_rule_kind", "rule_kind", "kind"]
    )

func _extract_string_list_from_keys(data: Variant, array_keys: Array, scalar_keys: Array = []) -> Array:
    var values: Array = []
    _append_strings_from_matching_keys(values, data, array_keys, scalar_keys, 0)
    return values

func _append_strings_from_matching_keys(values: Array, data: Variant, array_keys: Array, scalar_keys: Array, depth: int) -> void:
    if not (data is Dictionary):
        return

    var dictionary: Dictionary = data
    for key in array_keys:
        if dictionary.has(key):
            _append_unique_strings(values, _variant_to_string_array(dictionary.get(key)))
    for key in scalar_keys:
        if dictionary.has(key):
            _append_unique_strings(values, _variant_to_string_array(dictionary.get(key)))

    if depth >= 2:
        return
    for nested_value in dictionary.values():
        if nested_value is Dictionary:
            _append_strings_from_matching_keys(values, nested_value, array_keys, scalar_keys, depth + 1)

func _variant_to_string_array(value: Variant) -> Array:
    var values: Array = []
    if value is Array:
        for entry in value:
            var text := str(entry).strip_edges()
            if not text.is_empty() and text != "null" and not values.has(text):
                values.append(text)
        return values

    var text := str(value).strip_edges()
    if not text.is_empty() and text != "null":
        values.append(text)
    return values

func _append_unique_strings(target: Array, values: Array) -> void:
    for value in values:
        var text := str(value).strip_edges()
        if text.is_empty() or target.has(text):
            continue
        target.append(text)

func _format_rule_reference_list(rule_ids: Array, dependency_model: Dictionary) -> String:
    var labels: Array = []
    var rules_by_id: Dictionary = dependency_model.get("rules_by_id", {})
    for rule_id in rule_ids:
        var rule_key := str(rule_id)
        if rules_by_id.has(rule_key):
            labels.append(_format_rule_list_label(rules_by_id[rule_key]))
        else:
            labels.append(rule_key)
    return _join_values(labels)

func _update_entity_tree(entities: Array, entity_model: Dictionary) -> void:
    if _entity_tree == null:
        return

    _entity_tree.clear()
    var root_item := _entity_tree.create_item()
    if entities.is_empty():
        var empty_item := _entity_tree.create_item(root_item)
        empty_item.set_text(0, "エンティティなし")
        empty_item.set_text(1, "ワールドスナップショットにエンティティがありません。")
        return

    var character_entities := _filter_entities_by_kind(entities, true)
    if not character_entities.is_empty():
        var character_group := _entity_tree.create_item(root_item)
        character_group.set_text(0, "キャラクタ・エージェント")
        character_group.set_text(1, "%d件" % character_entities.size())
        for entity_data in character_entities:
            _add_entity_tree_item(character_group, entity_data, entity_model)

    var object_entities := _filter_entities_by_kind(entities, false)
    if not object_entities.is_empty():
        var object_group := _entity_tree.create_item(root_item)
        object_group.set_text(0, "物体・ワールド要素")
        object_group.set_text(1, "%d件" % object_entities.size())
        for entity_data in object_entities:
            _add_entity_tree_item(object_group, entity_data, entity_model)

func _build_entity_relationship_model(entities: Array) -> Dictionary:
    var entities_by_id := _build_entity_map(entities)
    var entity_names_by_id: Dictionary = {}
    var direct_links_by_entity: Dictionary = {}
    var reverse_links_by_entity: Dictionary = {}

    var entity_ids: Array = entities_by_id.keys()
    entity_ids.sort()
    for entity_id in entity_ids:
        entity_names_by_id[entity_id] = str(entities_by_id[entity_id].get("name", entity_id))
        direct_links_by_entity[entity_id] = []
        reverse_links_by_entity[entity_id] = []

    for entity_id in entity_ids:
        var entity_links: Array = []
        _append_entity_links_from_variant(entity_links, entities_by_id[entity_id], entity_names_by_id, 0)
        direct_links_by_entity[entity_id] = entity_links
        for entity_link in entity_links:
            var target_id := str(entity_link.get("target_id", ""))
            if target_id.is_empty() or not reverse_links_by_entity.has(target_id):
                continue
            var reverse_entries: Array = reverse_links_by_entity[target_id]
            _append_unique_entity_link(
                reverse_entries,
                str(entity_link.get("reverse_label", "関連元")),
                str(entity_link.get("label", "関連先")),
                entity_id
            )
            reverse_links_by_entity[target_id] = reverse_entries

    return {
        "direct_links_by_entity": direct_links_by_entity,
        "entities_by_id": entities_by_id,
        "entity_names_by_id": entity_names_by_id,
        "reverse_links_by_entity": reverse_links_by_entity
    }

func _build_entity_map(entities: Array) -> Dictionary:
    var entities_by_id: Dictionary = {}
    for entity_data in entities:
        if not (entity_data is Dictionary):
            continue
        entities_by_id[_extract_identifier(entity_data)] = entity_data
    return entities_by_id

func _append_entity_links_from_variant(entity_links: Array, source_data: Variant, valid_entity_ids: Dictionary, depth: int) -> void:
    if not (source_data is Dictionary):
        return

    var dictionary: Dictionary = source_data
    for field_name in ENTITY_REFERENCE_FIELDS.keys():
        if not dictionary.has(field_name):
            continue
        var field_spec: Dictionary = ENTITY_REFERENCE_FIELDS[field_name]
        for target_id in _variant_to_string_array(dictionary.get(field_name)):
            if valid_entity_ids.has(target_id):
                _append_unique_entity_link(
                    entity_links,
                    str(field_spec.get("forward", "関連先")),
                    str(field_spec.get("reverse", "関連元")),
                    str(target_id)
                )

    for field_name in ENTITY_COLLECTION_FIELDS.keys():
        if not dictionary.has(field_name):
            continue
        var field_spec: Dictionary = ENTITY_COLLECTION_FIELDS[field_name]
        for target_id in _variant_to_string_array(dictionary.get(field_name)):
            if valid_entity_ids.has(target_id):
                _append_unique_entity_link(
                    entity_links,
                    str(field_spec.get("forward", "関連先")),
                    str(field_spec.get("reverse", "関連元")),
                    str(target_id)
                )

    if depth >= 2:
        return
    for nested_value in dictionary.values():
        if nested_value is Dictionary:
            _append_entity_links_from_variant(entity_links, nested_value, valid_entity_ids, depth + 1)

func _append_unique_entity_link(entity_links: Array, label: String, reverse_label: String, target_id: String) -> void:
    for entity_link in entity_links:
        if str(entity_link.get("label", "")) == label and str(entity_link.get("target_id", "")) == target_id:
            return
    entity_links.append({
        "label": label,
        "reverse_label": reverse_label,
        "target_id": target_id
    })

func _filter_entities_by_kind(entities: Array, include_characters: bool) -> Array:
    var matching_entities: Array = []
    var entities_by_id := _build_entity_map(entities)
    var entity_ids: Array = entities_by_id.keys()
    entity_ids.sort()
    for entity_id in entity_ids:
        var entity_data: Dictionary = entities_by_id[entity_id]
        if _is_character_entity(entity_data) == include_characters:
            matching_entities.append(entity_data)
    return matching_entities

func _is_character_entity(entity_data: Dictionary) -> bool:
    var archetype := str(entity_data.get("archetype", entity_data.get("entity_type", ""))).to_lower()
    var tags := _variant_to_string_array(entity_data.get("tags", []))
    var tag_set := {}
    for tag in tags:
        tag_set[str(tag).to_lower()] = true

    for object_hint in OBJECT_ARCHETYPE_HINTS:
        if archetype == str(object_hint):
            return false
    for object_hint in OBJECT_TAG_HINTS:
        if tag_set.has(str(object_hint)):
            return false

    for character_hint in CHARACTER_ARCHETYPE_HINTS:
        if archetype == str(character_hint):
            return true
    for character_hint in CHARACTER_TAG_HINTS:
        if tag_set.has(str(character_hint)):
            return true

    var components: Dictionary = entity_data.get("components", {})
    return components.has("behavior") or components.has("needs")

func _add_entity_tree_item(parent_item: TreeItem, entity_data: Dictionary, entity_model: Dictionary) -> void:
    var entity_id := _extract_identifier(entity_data)
    var tree_item := _entity_tree.create_item(parent_item)
    tree_item.set_text(0, "%s [%s]" % [
        str(entity_data.get("name", entity_id)),
        str(entity_data.get("archetype", entity_data.get("entity_type", "entity")))
    ])
    tree_item.set_text(1, _summarize_entity_tree_row(entity_id, entity_data, entity_model))

    var tags := _variant_to_string_array(entity_data.get("tags", []))
    if not tags.is_empty():
        var tags_item := _entity_tree.create_item(tree_item)
        tags_item.set_text(0, "タグ")
        tags_item.set_text(1, _join_values(tags))

    for relationship_text in _build_entity_link_lines(entity_id, entity_model):
        var relationship_item := _entity_tree.create_item(tree_item)
        relationship_item.set_text(0, "関係")
        relationship_item.set_text(1, relationship_text)

    var components: Dictionary = entity_data.get("components", {})
    var component_names: Array = components.keys()
    component_names.sort()
    for component_name in component_names:
        var component_data = components[component_name]
        if component_data is Dictionary and not component_data.is_empty():
            var component_item := _entity_tree.create_item(tree_item)
            component_item.set_text(0, str(component_name))
            component_item.set_text(1, _format_variant_inline(component_data))

func _summarize_entity_tree_row(entity_id: String, entity_data: Dictionary, entity_model: Dictionary) -> String:
    var parts: Array[String] = []
    var link_lines := _build_entity_link_lines(entity_id, entity_model)
    if not link_lines.is_empty():
        parts.append(link_lines[0])

    var components: Dictionary = entity_data.get("components", {})
    var behavior: Dictionary = components.get("behavior", {})
    if behavior is Dictionary and behavior.has("current_task"):
        parts.append("作業=%s" % str(behavior.get("current_task")))

    var state: Dictionary = components.get("state", {})
    if state is Dictionary and not state.is_empty():
        parts.append(_format_variant_inline(state))

    return " | ".join(parts) if not parts.is_empty() else "id=%s" % entity_id

func _build_entity_link_lines(entity_id: String, entity_model: Dictionary) -> Array:
    var link_lines: Array = []
    var entity_names_by_id: Dictionary = entity_model.get("entity_names_by_id", {})
    var direct_entries: Array = entity_model.get("direct_links_by_entity", {}).get(entity_id, [])
    var reverse_entries: Array = entity_model.get("reverse_links_by_entity", {}).get(entity_id, [])

    for grouped_entry in _group_entity_links(direct_entries, entity_names_by_id):
        link_lines.append("%s: %s" % [str(grouped_entry.get("label", "関連先")), str(grouped_entry.get("value", ""))])
    for grouped_entry in _group_entity_links(reverse_entries, entity_names_by_id):
        link_lines.append("%s: %s" % [str(grouped_entry.get("label", "関連元")), str(grouped_entry.get("value", ""))])
    return link_lines

func _group_entity_links(entity_links: Array, entity_names_by_id: Dictionary) -> Array:
    var targets_by_label: Dictionary = {}
    for entity_link in entity_links:
        var label := str(entity_link.get("label", "関連先"))
        if not targets_by_label.has(label):
            targets_by_label[label] = []
        var targets: Array = targets_by_label[label]
        var target_id := str(entity_link.get("target_id", ""))
        var target_name := _get_entity_display_name(target_id, entity_names_by_id)
        if not targets.has(target_name):
            targets.append(target_name)
        targets_by_label[label] = targets

    var grouped_entries: Array = []
    var labels: Array = targets_by_label.keys()
    labels.sort()
    for label in labels:
        grouped_entries.append({
            "label": label,
            "value": _join_values(targets_by_label[label])
        })
    return grouped_entries

func _get_entity_display_name(entity_id: String, entity_names_by_id: Dictionary) -> String:
    var entity_name := str(entity_names_by_id.get(entity_id, entity_id))
    if entity_name == entity_id:
        return entity_id
    return "%s (%s)" % [entity_name, entity_id]

func _build_entity_relationship_summary_lines(entity_model: Dictionary) -> Array:
    var lines: Array = []
    var entity_names_by_id: Dictionary = entity_model.get("entity_names_by_id", {})
    var direct_links_by_entity: Dictionary = entity_model.get("direct_links_by_entity", {})
    var entity_ids: Array = direct_links_by_entity.keys()
    entity_ids.sort()
    for entity_id in entity_ids:
        var entity_links: Array = direct_links_by_entity[entity_id]
        for grouped_entry in _group_entity_links(entity_links, entity_names_by_id):
            lines.append("- %s | %s: %s" % [
                _get_entity_display_name(str(entity_id), entity_names_by_id),
                str(grouped_entry.get("label", "関連先")),
                str(grouped_entry.get("value", ""))
            ])
    return lines

func _format_entity_summary(entity_data: Variant, entity_model: Dictionary) -> String:
    if not (entity_data is Dictionary):
        return "- %s" % [str(entity_data)]

    var entity_id := _extract_identifier(entity_data)
    var lines: Array[String] = []
    lines.append("- %s [%s] (%s)" % [
        str(entity_data.get("name", entity_id)),
        str(entity_data.get("archetype", entity_data.get("entity_type", "entity"))),
        entity_id
    ])

    var tags := _variant_to_string_array(entity_data.get("tags", []))
    if not tags.is_empty():
        lines.append("  タグ: %s" % _join_values(tags))

    for relationship_text in _build_entity_link_lines(entity_id, entity_model):
        lines.append("  %s" % relationship_text)

    var components: Dictionary = entity_data.get("components", {})
    var component_names: Array = components.keys()
    component_names.sort()
    for component_name in component_names:
        var component_data = components[component_name]
        if component_data is Dictionary and not component_data.is_empty():
            lines.append("  %s: %s" % [str(component_name), _format_variant_inline(component_data)])
    return "\n".join(lines)

func _format_variant_inline(value: Variant) -> String:
    if value is Dictionary:
        var pairs: Array[String] = []
        var field_names: Array = value.keys()
        field_names.sort()
        for field_name in field_names:
            pairs.append("%s=%s" % [str(field_name), _format_variant_inline(value[field_name])])
        return _join_values(pairs)
    if value is Array:
        var items: Array[String] = []
        for entry in value:
            items.append(_format_variant_inline(entry))
        return "[%s]" % _join_values(items)
    return str(value)

func _format_event_entry(event_data: Variant) -> String:
    if event_data is Dictionary:
        var message := str(event_data.get("message", event_data.get("type", "event")))
        var details = event_data.get("details", {})
        if details is Dictionary and not details.is_empty():
            return "- %s | %s" % [message, JSON.stringify(details)]
        return "- %s" % message
    return "- %s" % [str(event_data)]

func _take_last_entries(source: Array, count: int) -> Array:
    if source.size() <= count:
        return source
    return source.slice(source.size() - count, source.size())

func _join_values(values: Array) -> String:
    var pieces: Array[String] = []
    for value in values:
        pieces.append(str(value))

    var joined := ""
    for index in range(pieces.size()):
        if index > 0:
            joined += ", "
        joined += pieces[index]
    return joined

func _append_log(message: String, payload: Variant = null) -> void:
    var log_entry := message
    if payload != null:
        log_entry += " | %s" % JSON.stringify(payload)
    _shell_log_lines.append(log_entry)
    _update_event_log_view()

func _simulate_task_submission(task_text: String) -> Dictionary:
    var template_id := "object_base"
    if task_text.find("所有") != -1:
        template_id = "ownership_links"
    elif task_text.find("収納") != -1 or task_text.find("入れ物") != -1:
        template_id = "storage_layout"

    var task_history = _fallback_snapshot.get("player_task_history", [])
    var result := {
        "status": "proposal_ready",
        "task_text": task_text,
        "proposals": [{"template_id": template_id, "title": str(TEMPLATE_UI_OVERRIDES.get(template_id, {}).get("name", template_id))}],
        "message": "フォールバックで関連テンプレート候補を生成しました。"
    }
    if task_history is Array:
        task_history.append(result.duplicate(true))
        _fallback_snapshot["player_task_history"] = task_history
    _append_fallback_event("player_task_submitted", "プレイヤーがタスクを送信しました。", {"task": task_text, "template_id": template_id})
    return result

func _simulate_template_install(template_data: Variant) -> Dictionary:
    var template_id := _extract_identifier(template_data)
    var rule_patch := _build_fallback_rule_patch(template_id)
    if rule_patch.is_empty():
        return {
            "status": "error",
            "message": "フォールバックではテンプレート '%s' を扱えません。" % template_id
        }

    var installed_rules: Dictionary = _fallback_snapshot.get("installed_rules", {})
    var rule_id := str(rule_patch.get("id", ""))
    if installed_rules.has(rule_id):
        return {
            "status": "already_installed",
            "rule": installed_rules[rule_id].duplicate(true)
        }

    installed_rules[rule_id] = rule_patch
    _fallback_snapshot["installed_rules"] = _refresh_fallback_rule_dependencies(installed_rules)
    _apply_fallback_template_entities(template_id)

    var concepts = _fallback_snapshot.get("concepts", [])
    var concept_id := str(rule_patch.get("concept", template_id))
    if concepts is Array and not concepts.has(concept_id):
        concepts.append(concept_id)
        _fallback_snapshot["concepts"] = concepts

    _append_fallback_event("rule_installed", "フォールバックテンプレート '%s' を導入しました。" % template_id, {"rule_id": rule_id})
    return {"status": "installed", "rule": rule_patch.duplicate(true)}

func _build_fallback_rule_patch(template_id: String) -> Dictionary:
    match template_id:
        "object_base":
            return {
                "id": "rule_object_base",
                "name": "オブジェクト基礎ルール",
                "concept": "objects",
                "enabled": true,
                "provides_rule_kinds": ["object-base"],
                "effects": []
            }
        "ownership_links":
            return {
                "id": "rule_ownership_links",
                "name": "所有関係ルール",
                "concept": "ownership",
                "enabled": true,
                "requires_rule_kinds": ["object-base"],
                "provides_rule_kinds": ["ownership-base"],
                "effects": []
            }
        "storage_layout":
            return {
                "id": "rule_storage_layout",
                "name": "収納配置ルール",
                "concept": "storage",
                "enabled": true,
                "requires_rule_kinds": ["object-base"],
                "provides_rule_kinds": ["storage-layout"],
                "effects": []
            }
    return {}

func _apply_fallback_template_entities(template_id: String) -> void:
    var entities: Dictionary = _fallback_snapshot.get("entities", {})
    match template_id:
        "object_base":
            if not entities.has("camp_kettle"):
                entities["camp_kettle"] = {
                    "id": "camp_kettle",
                    "name": "湯沸かしケトル",
                    "archetype": "item",
                    "tags": ["object", "portable"],
                    "location_id": "storehouse",
                    "components": {
                        "state": {
                            "condition": "使い込み",
                            "status": "水入り"
                        }
                    }
                }
        "ownership_links":
            if entities.has("camp_kettle"):
                var kettle: Dictionary = entities["camp_kettle"]
                kettle["owner_id"] = "aria"
                entities["camp_kettle"] = kettle
        "storage_layout":
            if entities.has("camp_kettle"):
                var kettle: Dictionary = entities["camp_kettle"]
                kettle["container_id"] = "tool_satchel"
                entities["camp_kettle"] = kettle
    _fallback_snapshot["entities"] = entities

func _simulate_rule_clone(rule_data: Variant) -> Dictionary:
    var installed_rules: Dictionary = _fallback_snapshot.get("installed_rules", {})
    var source_rule: Dictionary = {}
    if rule_data is Dictionary:
        source_rule = rule_data.duplicate(true)
    else:
        source_rule = {"id": str(rule_data), "name": str(rule_data)}

    var source_id := _extract_identifier(source_rule)
    var clone_id := "%s_clone_%d" % [source_id, installed_rules.size() + 1]
    var cloned_rule := source_rule.duplicate(true)
    cloned_rule["id"] = clone_id
    cloned_rule["name"] = "%s（複製）" % _get_rule_display_name(source_rule)
    installed_rules[clone_id] = cloned_rule
    _fallback_snapshot["installed_rules"] = _refresh_fallback_rule_dependencies(installed_rules)

    _append_fallback_event("rule_cloned", "フォールバックルール '%s' を複製しました。" % source_id, {"clone_id": clone_id})
    return {"status": "cloned", "rule": cloned_rule}

func _refresh_fallback_rule_dependencies(installed_rules: Dictionary) -> Dictionary:
    var normalized_rules: Dictionary = installed_rules.duplicate(true)
    var providers_by_kind: Dictionary = {}
    var rule_ids: Array = normalized_rules.keys()
    rule_ids.sort()

    for rule_id in rule_ids:
        var rule_data: Dictionary = normalized_rules[rule_id]
        var provided_kinds := _extract_rule_provided_kinds(rule_data)
        if provided_kinds.is_empty():
            continue
        for provided_kind in provided_kinds:
            if not providers_by_kind.has(provided_kind):
                providers_by_kind[provided_kind] = []
            var provider_ids: Array = providers_by_kind[provided_kind]
            if not provider_ids.has(rule_id):
                provider_ids.append(rule_id)
            providers_by_kind[provided_kind] = provider_ids

    for rule_id in rule_ids:
        var rule_data: Dictionary = normalized_rules[rule_id]
        var resolved_parent_rule_ids: Array = []
        for required_kind in _extract_rule_required_kinds(rule_data):
            for provider_id in Array(providers_by_kind.get(required_kind, [])):
                if str(provider_id) == rule_id or resolved_parent_rule_ids.has(provider_id):
                    continue
                resolved_parent_rule_ids.append(provider_id)
        if resolved_parent_rule_ids.is_empty():
            rule_data.erase("resolved_parent_rule_ids")
        else:
            rule_data["resolved_parent_rule_ids"] = resolved_parent_rule_ids
        normalized_rules[rule_id] = rule_data

    return normalized_rules

func _simulate_tick(delta_seconds: float) -> Dictionary:
    _fallback_snapshot["tick_index"] = int(_fallback_snapshot.get("tick_index", 0)) + 1
    _fallback_snapshot["elapsed_seconds"] = float(_fallback_snapshot.get("elapsed_seconds", 0.0)) + delta_seconds

    var entities: Dictionary = _fallback_snapshot.get("entities", {})
    var entity_ids: Array = entities.keys()
    entity_ids.sort()
    for entity_id in entity_ids:
        var entity: Dictionary = entities[entity_id]
        var components: Dictionary = entity.get("components", {})
        var needs: Dictionary = components.get("needs", {})
        needs["hunger"] = min(float(needs.get("hunger", 0.0)) + delta_seconds * 0.6, 100.0)
        needs["sleep"] = min(float(needs.get("sleep", 0.0)) + delta_seconds * 0.35, 100.0)
        components["needs"] = needs

        var stats: Dictionary = components.get("stats", {})
        stats["focus"] = max(float(stats.get("focus", 0.0)) - delta_seconds * 0.5, 0.0)
        stats["morale"] = max(min(float(stats.get("morale", 0.0)) + 0.1, 100.0), 0.0)
        components["stats"] = stats
        entity["components"] = components
        entities[entity_id] = entity
    _fallback_snapshot["entities"] = entities

    _append_fallback_event("tick_advanced", "フォールバック世界のステップを進めました。", {"delta_seconds": delta_seconds, "tick_index": _fallback_snapshot["tick_index"]})
    return {"tick_index": _fallback_snapshot["tick_index"], "delta_seconds": delta_seconds}

func _append_fallback_event(event_type: String, message: String, details: Dictionary) -> void:
    var event_log = _fallback_snapshot.get("event_log", [])
    if event_log is Array:
        event_log.append({
            "type": event_type,
            "message": message,
            "details": details.duplicate(true)
        })
        _fallback_snapshot["event_log"] = event_log
