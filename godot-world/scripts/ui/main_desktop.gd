extends Control

signal close_requested

const ThreeDPreviewRendererScript = preload("res://scripts/ui/three_d_preview_renderer.gd")
const GMDialogScript = preload("res://scripts/ui/gm_dialog.gd")
const WorldOpDispatcherScript = preload("res://scripts/world_ops/dispatcher.gd")
const FALLBACK_TEMPLATES: Array = [
    {
        "id": "starter-farming",
        "name": "農作業のたたき台",
        "description": "待機中の村人に簡単な農作業ルーチンを足します。"
    },
    {
        "id": "night-watch",
        "name": "夜警",
        "description": "日没後に警備巡回を入れます。"
    },
    {
        "id": "shared-kitchen",
        "name": "共同台所",
        "description": "共同の食事準備と片付けを導入します."
    }
]

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
    "parent_rule_kinds"
]
const RULE_PROVIDED_KIND_FIELDS: Array = [
    "provides_rule_kinds",
    "provided_rule_kinds",
    "rule_kinds",
    "kinds"
]
const ENTITY_REFERENCE_FIELDS: Dictionary = {
    "container_id": {"forward": "内包先", "reverse": "内包"},
    "equipped_by_entity_id": {"forward": "装備者", "reverse": "装備"},
    "held_by_entity_id": {"forward": "所持者", "reverse": "所持"},
    "holder_id": {"forward": "所持者", "reverse": "所持"},
    "home_entity_id": {"forward": "拠点", "reverse": "拠点対象"},
    "location_id": {"forward": "配置先", "reverse": "配置"},
    "owned_by_entity_id": {"forward": "所有者", "reverse": "所有"},
    "owner_entity_id": {"forward": "所有者", "reverse": "所有"},
    "owner_id": {"forward": "所有者", "reverse": "所有"},
    "parent_entity_id": {"forward": "親", "reverse": "子"},
    "parent_id": {"forward": "親", "reverse": "子"}
}
const ENTITY_COLLECTION_FIELDS: Dictionary = {
    "child_entity_ids": {"forward": "子", "reverse": "親"},
    "contained_entity_ids": {"forward": "内包", "reverse": "内包先"},
    "equipped_entity_ids": {"forward": "装備", "reverse": "装備者"},
    "inventory_entity_ids": {"forward": "所持品", "reverse": "所持者"},
    "inventory_ids": {"forward": "所持品", "reverse": "所持者"},
    "occupant_entity_ids": {"forward": "配置", "reverse": "配置先"},
    "owned_entity_ids": {"forward": "所有", "reverse": "所有者"}
}
const CHARACTER_ARCHETYPE_HINTS: Array = ["actor", "character", "npc", "origin", "person", "villager"]
const CHARACTER_TAG_HINTS: Array = ["agent", "character", "human", "mortal", "npc", "person", "villager"]
const OBJECT_ARCHETYPE_HINTS: Array = ["container", "item", "location", "object", "place", "prop", "resource", "structure", "tool"]
const OBJECT_TAG_HINTS: Array = ["container", "item", "location", "object", "portable", "prop", "resource", "structure", "tool"]
const PROPOSAL_REVIEW_DEBOUNCE_SECONDS := 0.35
const TAB_HOME := "統合画面"
const TAB_CHAT := "GM相談"
const TAB_REVIEW := "提案レビュー"
const TAB_RULES := "稼働ルール"
const TAB_WORLD := "世界・履歴"

var _world_state: Node = null
var _task_input: TextEdit
var _proposal_selector: OptionButton
var _proposal_review_summary_label: Label
var _proposal_metadata_view: TextEdit
var _proposal_editor: TextEdit
var _proposal_review_timer: Timer
var _reset_proposal_button: Button
var _approve_proposal_button: Button
var _install_proposal_button: Button
var _template_list: ItemList
var _install_template_button: Button
var _tick_amount: SpinBox
var _installed_rule_tree: Tree
var _installed_package_list: ItemList
var _package_enable_button: Button
var _package_disable_button: Button
var _installed_package_details_view: TextEdit
var _installed_rule_list: ItemList
var _clone_rule_button: Button
var _installed_rule_details_view: TextEdit
var _entity_tree: Tree
var _world_state_view: TextEdit
var _event_log_view: TextEdit
var _poc4_state_view: TextEdit
var _three_d_preview_renderer: Control
var _tabs: TabContainer
var _home_summary_label: Label
var _chat_view: Control

var _template_cache: Array = []
var _latest_task_result: Dictionary = {}
var _proposal_cache: Array = []
var _proposal_signature: String = ""
var _selected_proposal_index: int = -1
var _loaded_proposal_key: String = ""
var _selected_proposal_original_text := ""
var _approved_proposal_text := ""
var _current_proposal_review: Dictionary = {}
var _is_updating_proposal_editor := false
var _installed_package_cache: Array = []
var _installed_rule_cache: Array = []
var _snapshot_cache: Dictionary = {}
var _poc4_state_cache: Dictionary = {}
var _poc4_apply_result_cache: Dictionary = {}
var _shell_log_lines: Array[String] = []
var _fallback_snapshot: Dictionary = {
    "world_id": "fallback-world",
    "runtime_choice": "gm-overlay-preview",
    "elapsed_seconds": 0.0,
    "tick_index": 0,
    "concepts": [],
    "installed_rules": {},
    "entities": {
        "aria": {
            "id": "aria",
            "name": "アリア",
            "archetype": "villager",
            "tags": ["mortal", "mutable"],
            "components": {
                "behavior": {
                    "current_task": "集めた物資を整理中"
                },
                "needs": {
                    "hunger": 12.0,
                    "sleep": 8.0
                },
                "stats": {
                    "morale": 61.0,
                    "focus": 52.0
                },
                "traits": {
                    "curiosity": 1.0
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
                    "condition": "sturdy",
                    "slot": "shoulder"
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
                    "condition": "dry",
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
    "event_log": [
        {
            "type": "world_initialized",
            "message": "GM会話画面のフォールバック表示を有効化しました。",
            "details": {}
        }
    ],
    "three_d_preview": {
        "enabled": true,
        "renderables": [
            {
                "id": "gm_preview",
                "name": "GM",
                "kind": "gm",
                "flags": ["gm"],
                "position": [-2.8, 1.05, -1.6],
                "size": [1.2, 2.1, 1.2],
                "color": "#7a60ff"
            },
            {
                "id": "aria",
                "name": "アリア",
                "kind": "character",
                "flags": ["character"],
                "position": [0.0, 0.9, 0.4],
                "size": [0.9, 1.8, 0.9],
                "color": "#4fb8f7"
            },
            {
                "id": "storehouse",
                "name": "倉庫",
                "kind": "object",
                "position": [2.8, 1.1, 0.0],
                "size": [2.6, 2.2, 2.6],
                "color": "#be9a66"
            },
            {
                "id": "water_jar",
                "name": "水瓶",
                "kind": "object",
                "flags": ["falling"],
                "position": [1.3, 3.0, -1.4],
                "size": [0.8, 1.2, 0.8],
                "color": "#8dd0ff"
            }
        ],
        "lighting": {
            "enabled": true,
            "shadows_enabled": true,
            "direction": [-0.65, -1.0, -0.35]
        },
        "gravity": {
            "enabled": true,
            "floor_y": 0.0
        },
        "camera": {
            "target": [0.5, 1.0, 0.0],
            "yaw_degrees": -38.0,
            "pitch_degrees": -22.0,
            "distance": 10.5,
            "fov": 62.0
        }
    }
}

func _ready() -> void:
    set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
    _refresh_world_state_reference()
    _build_ui()
    _refresh_all()
    _append_log("GM会話用UIを起動しました。", {"world_state_connected": _world_state != null})

func _build_ui() -> void:
    var root_margin := MarginContainer.new()
    root_margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
    root_margin.add_theme_constant_override("margin_left", 0)
    root_margin.add_theme_constant_override("margin_top", 0)
    root_margin.add_theme_constant_override("margin_right", 0)
    root_margin.add_theme_constant_override("margin_bottom", 0)
    add_child(root_margin)

    _tabs = TabContainer.new()
    _tabs.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    _tabs.size_flags_vertical = Control.SIZE_EXPAND_FILL
    _tabs.drag_to_rearrange_enabled = false
    root_margin.add_child(_tabs)

    _tabs.add_child(_build_home_tab())
    _tabs.add_child(_build_chat_tab())
    _tabs.add_child(_build_review_tab())
    _tabs.add_child(_build_rules_tab())
    _tabs.add_child(_build_world_tab())

func _build_home_tab() -> Control:
    var tab := VBoxContainer.new()
    tab.name = TAB_HOME
    tab.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    tab.size_flags_vertical = Control.SIZE_EXPAND_FILL
    tab.add_theme_constant_override("separation", 12)

    _home_summary_label = Label.new()
    _home_summary_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
    _home_summary_label.add_theme_font_size_override("font_size", 16)
    tab.add_child(_home_summary_label)

    var cards := GridContainer.new()
    cards.columns = 2
    cards.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    cards.size_flags_vertical = Control.SIZE_EXPAND_FILL
    cards.add_theme_constant_override("separation", 12)
    tab.add_child(cards)

    cards.add_child(_build_home_card("GM相談", "世界ルールの相談と PoC4 proposal の作成を行います。", TAB_CHAT))
    cards.add_child(_build_home_card("提案レビュー", "生成された提案を確認・承認してからゲームへ適用します。", TAB_REVIEW))
    cards.add_child(_build_home_card("稼働ルール", "現在のルール依存ツリーを現行UIのまま確認します。", TAB_RULES))
    cards.add_child(_build_home_card("世界・履歴", "エンティティ関係ツリー、スナップショット、イベント履歴を確認します。", TAB_WORLD))

    var return_button := Button.new()
    return_button.text = "世界へ戻って観察"
    return_button.pressed.connect(_emit_close_requested)
    tab.add_child(return_button)
    return tab

func _build_home_card(title_text: String, description: String, target_tab_name: String) -> Control:
    var panel := _make_panel_section(title_text, description)
    panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
    var body := panel.get_meta("body") as VBoxContainer
    var button := Button.new()
    button.text = "開く"
    button.pressed.connect(func() -> void:
        _select_tab_by_name(target_tab_name)
    )
    body.add_child(button)
    return panel

func _build_chat_tab() -> Control:
    var host := Control.new()
    host.name = TAB_CHAT
    host.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    host.size_flags_vertical = Control.SIZE_EXPAND_FILL
    _chat_view = GMDialogScript.new()
    _chat_view.set("compact_mode", true)
    _chat_view.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
    if _chat_view.has_signal("closed"):
        _chat_view.closed.connect(_emit_close_requested)
    host.add_child(_chat_view)
    return host

func _build_review_tab() -> Control:
    var scroll := _make_tab_scroll(TAB_REVIEW)
    var body := scroll.get_child(0) as VBoxContainer
    body.add_child(_build_task_panel())
    body.add_child(_build_proposal_panel())
    body.add_child(_build_poc4_admin_panel())
    return scroll

func _build_rules_tab() -> Control:
    var scroll := _make_tab_scroll(TAB_RULES)
    var body := scroll.get_child(0) as VBoxContainer
    body.add_child(_build_installed_rules_panel())
    body.add_child(_build_template_panel())
    body.add_child(_build_tick_panel())
    body.add_child(_build_three_d_preview_panel())
    return scroll

func _build_world_tab() -> Control:
    var scroll := _make_tab_scroll(TAB_WORLD)
    var body := scroll.get_child(0) as VBoxContainer
    body.add_child(_build_world_state_panel())
    body.add_child(_build_text_panel("会話ログと世界イベント", "GM会話中の操作履歴と最近の世界イベントを表示します。", "event_log", 180))
    return scroll

func _make_tab_scroll(tab_name: String) -> ScrollContainer:
    var scroll := ScrollContainer.new()
    scroll.name = tab_name
    scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
    var body := VBoxContainer.new()
    body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    body.add_theme_constant_override("separation", 10)
    scroll.add_child(body)
    return scroll

func _select_tab_by_name(tab_name: String) -> void:
    if _tabs == null:
        return
    for index in range(_tabs.get_child_count()):
        var child := _tabs.get_child(index)
        if child.name == tab_name:
            _tabs.current_tab = index
            return

func _build_task_panel() -> Control:
    var panel := _make_panel_section("GMへの相談", "ここでは既存テンプレート候補や即時に試せる方針を確認します。PoC4 の Codex proposal 生成は、プレイヤー向けの GM 会話画面から行ってください。")
    var body := panel.get_meta("body") as VBoxContainer

    _task_input = TextEdit.new()
    _task_input.custom_minimum_size = Vector2(0, 88)
    _task_input.placeholder_text = "例: 夜になったら灯りがつくようにしたい。"
    _task_input.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
    body.add_child(_task_input)

    var button_row := HBoxContainer.new()
    button_row.add_theme_constant_override("separation", 8)
    body.add_child(button_row)

    var submit_button := Button.new()
    submit_button.text = "相談を送る"
    submit_button.pressed.connect(_on_submit_pressed)
    button_row.add_child(submit_button)

    var refresh_button := Button.new()
    refresh_button.text = "情報を更新"
    refresh_button.pressed.connect(_refresh_all)
    button_row.add_child(refresh_button)

    return panel

func _build_poc4_admin_panel() -> Control:
    var panel := _make_panel_section("PoC4 proposal / apply 状態", "pending proposal、review 状態、apply 結果、backend error を read-only で確認します。")
    var body := panel.get_meta("body") as VBoxContainer

    _poc4_state_view = TextEdit.new()
    _poc4_state_view.editable = false
    _poc4_state_view.custom_minimum_size = Vector2(0, 170)
    _poc4_state_view.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
    body.add_child(_poc4_state_view)

    return panel

func _build_proposal_panel() -> Control:
    var panel := _make_panel_section("提案パッチのレビュー", "最新の提案パッケージ JSON を確認・編集し、承認してから導入します。")
    var body := panel.get_meta("body") as VBoxContainer

    _proposal_review_summary_label = Label.new()
    _proposal_review_summary_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
    body.add_child(_proposal_review_summary_label)

    _proposal_selector = OptionButton.new()
    _proposal_selector.item_selected.connect(_on_proposal_selected)
    body.add_child(_proposal_selector)

    _proposal_metadata_view = TextEdit.new()
    _proposal_metadata_view.editable = false
    _proposal_metadata_view.custom_minimum_size = Vector2(0, 120)
    _proposal_metadata_view.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
    body.add_child(_proposal_metadata_view)

    var action_row := HBoxContainer.new()
    action_row.add_theme_constant_override("separation", 8)
    body.add_child(action_row)

    _reset_proposal_button = Button.new()
    _reset_proposal_button.text = "下書きを元に戻す"
    _reset_proposal_button.disabled = true
    _reset_proposal_button.pressed.connect(_on_reset_proposal_pressed)
    action_row.add_child(_reset_proposal_button)

    _approve_proposal_button = Button.new()
    _approve_proposal_button.text = "提案を承認"
    _approve_proposal_button.disabled = true
    _approve_proposal_button.pressed.connect(_on_approve_proposal_pressed)
    action_row.add_child(_approve_proposal_button)

    _install_proposal_button = Button.new()
    _install_proposal_button.text = "承認済み提案を導入"
    _install_proposal_button.disabled = true
    _install_proposal_button.pressed.connect(_on_install_proposal_pressed)
    action_row.add_child(_install_proposal_button)

    _proposal_editor = TextEdit.new()
    _proposal_editor.custom_minimum_size = Vector2(0, 220)
    _proposal_editor.placeholder_text = "相談を送ると、ここに編集可能なルールパッケージ JSON が表示されます。"
    _proposal_editor.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
    _proposal_editor.text_changed.connect(_on_proposal_editor_changed)
    body.add_child(_proposal_editor)

    _proposal_review_timer = Timer.new()
    _proposal_review_timer.one_shot = true
    _proposal_review_timer.wait_time = PROPOSAL_REVIEW_DEBOUNCE_SECONDS
    _proposal_review_timer.timeout.connect(_on_proposal_review_timer_timeout)
    body.add_child(_proposal_review_timer)

    return panel

func _build_template_panel() -> Control:
    var panel := _make_panel_section("追加できるルール", "GMが提案できるテンプレートを選び、この会話中に世界へ反映します。")
    var body := panel.get_meta("body") as VBoxContainer

    _template_list = ItemList.new()
    _template_list.custom_minimum_size = Vector2(0, 136)
    _template_list.select_mode = ItemList.SELECT_SINGLE
    _template_list.item_selected.connect(_on_template_selected)
    body.add_child(_template_list)

    _install_template_button = Button.new()
    _install_template_button.text = "選択したルールを追加"
    _install_template_button.disabled = true
    _install_template_button.pressed.connect(_on_install_template_pressed)
    body.add_child(_install_template_button)

    return panel

func _build_tick_panel() -> Control:
    var panel := _make_panel_section("時間操作", "GM視点で時間を進め、ルールによる変化をこの場で確認します。")
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
    tick_button.text = "この秒数だけ進める"
    tick_button.pressed.connect(_on_tick_pressed)
    row.add_child(tick_button)

    return panel

func _build_installed_rules_panel() -> Control:
    var panel := _make_panel_section("稼働中のルール", "現在動いているルールを確認し、依存関係や詳細をGM視点で点検します。")
    var body := panel.get_meta("body") as VBoxContainer

    var package_label := Label.new()
    package_label.text = "導入済みパッケージ"
    body.add_child(package_label)

    _installed_package_list = ItemList.new()
    _installed_package_list.custom_minimum_size = Vector2(0, 76)
    _installed_package_list.select_mode = ItemList.SELECT_SINGLE
    _installed_package_list.item_selected.connect(_on_installed_package_selected)
    body.add_child(_installed_package_list)

    var package_action_row := HBoxContainer.new()
    package_action_row.add_theme_constant_override("separation", 8)
    body.add_child(package_action_row)

    _package_enable_button = Button.new()
    _package_enable_button.text = "選択パッケージを有効化"
    _package_enable_button.disabled = true
    _package_enable_button.pressed.connect(_on_package_enable_pressed)
    package_action_row.add_child(_package_enable_button)

    _package_disable_button = Button.new()
    _package_disable_button.text = "選択パッケージを無効化"
    _package_disable_button.disabled = true
    _package_disable_button.pressed.connect(_on_package_disable_pressed)
    package_action_row.add_child(_package_disable_button)

    _installed_package_details_view = TextEdit.new()
    _installed_package_details_view.editable = false
    _installed_package_details_view.custom_minimum_size = Vector2(0, 88)
    _installed_package_details_view.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
    body.add_child(_installed_package_details_view)

    var tree_label := Label.new()
    tree_label.text = "依存ツリー"
    body.add_child(tree_label)

    _installed_rule_tree = Tree.new()
    _installed_rule_tree.columns = 2
    _installed_rule_tree.column_titles_visible = true
    _installed_rule_tree.hide_root = true
    _installed_rule_tree.custom_minimum_size = Vector2(0, 132)
    _installed_rule_tree.size_flags_vertical = Control.SIZE_EXPAND_FILL
    _installed_rule_tree.set_column_title(0, "ルール")
    _installed_rule_tree.set_column_title(1, "親 / 依存状態")
    _installed_rule_tree.item_selected.connect(_on_rule_tree_selected)
    body.add_child(_installed_rule_tree)

    var list_label := Label.new()
    list_label.text = "一覧"
    body.add_child(list_label)

    _installed_rule_list = ItemList.new()
    _installed_rule_list.custom_minimum_size = Vector2(0, 88)
    _installed_rule_list.select_mode = ItemList.SELECT_SINGLE
    _installed_rule_list.item_selected.connect(_on_installed_rule_selected)
    body.add_child(_installed_rule_list)

    var action_row := HBoxContainer.new()
    action_row.add_theme_constant_override("separation", 8)
    body.add_child(action_row)

    _clone_rule_button = Button.new()
    _clone_rule_button.text = "選択ルールを複製して試す"
    _clone_rule_button.disabled = true
    _clone_rule_button.pressed.connect(_on_clone_rule_pressed)
    action_row.add_child(_clone_rule_button)

    _installed_rule_details_view = TextEdit.new()
    _installed_rule_details_view.editable = false
    _installed_rule_details_view.custom_minimum_size = Vector2(0, 96)
    _installed_rule_details_view.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
    body.add_child(_installed_rule_details_view)

    return panel

func _build_world_state_panel() -> Control:
    var panel := _make_panel_section("世界状態の確認", "3D世界のキャラクタ・物体・所有関係・内包関係を、GM向けの要約として表示します。")
    var body := panel.get_meta("body") as VBoxContainer

    var tree_label := Label.new()
    tree_label.text = "エンティティ関係ツリー"
    body.add_child(tree_label)

    _entity_tree = Tree.new()
    _entity_tree.columns = 2
    _entity_tree.column_titles_visible = true
    _entity_tree.hide_root = true
    _entity_tree.custom_minimum_size = Vector2(0, 132)
    _entity_tree.size_flags_vertical = Control.SIZE_EXPAND_FILL
    _entity_tree.set_column_title(0, "対象")
    _entity_tree.set_column_title(1, "状態 / 所有")
    body.add_child(_entity_tree)

    var summary_label := Label.new()
    summary_label.text = "スナップショット要約"
    body.add_child(summary_label)

    _world_state_view = TextEdit.new()
    _world_state_view.editable = false
    _world_state_view.custom_minimum_size = Vector2(0, 96)
    _world_state_view.size_flags_vertical = Control.SIZE_EXPAND_FILL
    _world_state_view.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
    body.add_child(_world_state_view)

    return panel

func _build_three_d_preview_panel() -> Control:
    var panel := _make_panel_section(
        "GM用3D化メモ",
        "主画面は2Dから始まり、GMが3D化を適用すると世界本体が3Dへ切り替わります。"
    )
    panel.size_flags_vertical = Control.SIZE_FILL
    var body := panel.get_meta("body") as VBoxContainer

    var intro := Label.new()
    intro.text = "この項目から3D化を適用できます。光ルールや重力ルールは3D化後の確認用です。"
    intro.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
    body.add_child(intro)

    var action_row := HBoxContainer.new()
    action_row.add_theme_constant_override("separation", 8)
    body.add_child(action_row)

    _add_quick_3d_button(action_row, "3D化を適用", "three_d_preview_rule")
    _add_quick_3d_button(action_row, "光ルールを追加", "three_d_light_rule")
    _add_quick_3d_button(action_row, "重力ルールを追加", "three_d_gravity_rule")

    _three_d_preview_renderer = ThreeDPreviewRendererScript.new()
    _three_d_preview_renderer.custom_minimum_size = Vector2(0, 176)
    _three_d_preview_renderer.size_flags_vertical = Control.SIZE_FILL
    body.add_child(_three_d_preview_renderer)
    return panel

func _add_quick_3d_button(container: Container, button_text: String, template_id: String) -> void:
    var button := Button.new()
    button.text = button_text
    button.pressed.connect(_on_quick_3d_template_pressed.bind(template_id))
    container.add_child(button)

func _on_quick_3d_template_pressed(template_id: String) -> void:
    _install_template_by_id(template_id)

func _find_template_index_by_id(template_id: String) -> int:
    for index in range(_template_cache.size()):
        if _extract_identifier(_template_cache[index]) == template_id:
            return index
    return -1

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
    panel.size_flags_vertical = Control.SIZE_SHRINK_BEGIN

    var margin := MarginContainer.new()
    margin.add_theme_constant_override("margin_left", 10)
    margin.add_theme_constant_override("margin_top", 10)
    margin.add_theme_constant_override("margin_right", 10)
    margin.add_theme_constant_override("margin_bottom", 10)
    panel.add_child(margin)

    var body := VBoxContainer.new()
    body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    body.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
    body.add_theme_constant_override("separation", 6)
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
    _latest_task_result = _extract_latest_task_result(_snapshot_cache)
    _proposal_cache = _extract_task_proposals(_latest_task_result)
    _refresh_poc4_state()
    _installed_package_cache = _extract_installed_packages(_snapshot_cache)
    _installed_rule_cache = _extract_installed_rules(_snapshot_cache)
    _update_template_list()
    _update_proposal_panel()
    _update_installed_rules_panel()
    _update_three_d_preview()
    _update_poc4_state_view()
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

func _refresh_poc4_state() -> void:
    var merged_state := _merge_poc4_state(_snapshot_cache.get("poc4", {}))
    if _world_state != null and _world_state.has_method("get_pending_rule_proposal"):
        var pending_state = _world_state.call("get_pending_rule_proposal")
        if pending_state is Dictionary:
            merged_state = _merge_poc4_state(pending_state)

    var apply_result: Dictionary = merged_state.get("apply_result", {}).duplicate(true)
    if _world_state != null and _world_state.has_method("get_last_rule_apply_result"):
        var last_apply = _world_state.call("get_last_rule_apply_result")
        if last_apply is Dictionary and not last_apply.is_empty():
            apply_result = last_apply.duplicate(true)

    _poc4_state_cache = merged_state
    _poc4_apply_result_cache = apply_result
    _poc4_state_cache["apply_result"] = _poc4_apply_result_cache.duplicate(true)

func _update_template_list() -> void:
    _template_list.clear()
    for template_data in _template_cache:
        _template_list.add_item(_format_template_label(template_data))
    _install_template_button.disabled = _template_cache.is_empty()
    if not _template_cache.is_empty():
        _template_list.select(0)

func _update_proposal_panel() -> void:
    if _proposal_selector == null:
        return

    var previous_key := _build_proposal_key(_current_selected_proposal(), _selected_proposal_index)
    var task_signature := _build_task_result_signature(_latest_task_result)
    var task_changed := task_signature != _proposal_signature
    _proposal_signature = task_signature

    _proposal_selector.clear()
    for index in range(_proposal_cache.size()):
        _proposal_selector.add_item(_format_proposal_option_label(_proposal_cache[index], index))

    if _proposal_cache.is_empty():
        if _proposal_review_timer != null:
            _proposal_review_timer.stop()
        _selected_proposal_index = -1
        _loaded_proposal_key = ""
        _selected_proposal_original_text = ""
        _approved_proposal_text = ""
        _current_proposal_review = {}
        _proposal_review_summary_label.text = "まだ提案はありません。相談を送るとレビュー導線が開きます。"
        _proposal_metadata_view.text = "最新の相談結果がここに表示されます。clone / fork メタデータ、保留中の操作、導入準備状況を確認できます。"
        _set_proposal_editor_text("")
        _reset_proposal_button.disabled = true
        _approve_proposal_button.disabled = true
        _install_proposal_button.disabled = true
        return

    var selection_index := 0
    if not task_changed:
        var matched_index := _find_proposal_index_by_key(previous_key)
        if matched_index != -1:
            selection_index = matched_index
        elif _selected_proposal_index >= 0 and _selected_proposal_index < _proposal_cache.size():
            selection_index = _selected_proposal_index
    selection_index = min(max(selection_index, 0), _proposal_cache.size() - 1)
    _selected_proposal_index = selection_index
    _proposal_selector.select(selection_index)

    var selected_key := _build_proposal_key(_proposal_cache[selection_index], selection_index)
    if task_changed or selected_key != _loaded_proposal_key:
        _load_selected_proposal_into_editor()
        return

    _current_proposal_review = _refresh_current_proposal_review(false)
    _update_proposal_views()

func _load_selected_proposal_into_editor() -> void:
    if _proposal_review_timer != null:
        _proposal_review_timer.stop()
    var proposal := _current_selected_proposal()
    _loaded_proposal_key = _build_proposal_key(proposal, _selected_proposal_index)
    _approved_proposal_text = ""

    var rule_package := _proposal_to_rule_package(proposal)
    if rule_package.is_empty():
        _selected_proposal_original_text = ""
        _current_proposal_review = {
            "status": "error",
            "message": "選択した提案には編集可能なルールパッケージが含まれていません。"
        }
        _set_proposal_editor_text("")
        _update_proposal_views()
        return

    var proposal_text := JSON.stringify(rule_package, "	")
    _selected_proposal_original_text = proposal_text
    _approved_proposal_text = proposal_text if String(rule_package.get("patch", {}).get("review_status", "")) == "approved" else ""
    _set_proposal_editor_text(proposal_text)
    _current_proposal_review = _refresh_current_proposal_review(false)
    _update_proposal_views()

func _set_proposal_editor_text(value: String) -> void:
    _is_updating_proposal_editor = true
    _proposal_editor.text = value
    _is_updating_proposal_editor = false

func _refresh_current_proposal_review(append_errors: bool) -> Dictionary:
    var parsed_result := _parse_editor_rule_package()
    if String(parsed_result.get("status", "")) == "error":
        if append_errors:
            _append_log("提案レビューに失敗しました。", parsed_result)
        return parsed_result

    var rule_package: Dictionary = parsed_result.get("rule_package", {})
    if _world_state != null and _world_state.has_method("review_rule_package_proposal"):
        var review_result = _world_state.call("review_rule_package_proposal", rule_package)
        if review_result is Dictionary:
            if append_errors and String(review_result.get("status", "")) == "error":
                _append_log("提案レビューに失敗しました。", review_result)
            return review_result
    return _build_local_proposal_review(rule_package)

func _build_editor_change_review_state() -> Dictionary:
    var parsed_result := _parse_editor_rule_package()
    if String(parsed_result.get("status", "")) == "error":
        return parsed_result

    var rule_package: Dictionary = parsed_result.get("rule_package", {})
    var patch_variant = rule_package.get("patch", null)
    if not (patch_variant is Dictionary):
        return {
            "status": "error",
            "message": "ルールパッケージ patch は辞書型である必要があります。",
            "rule_package": rule_package.duplicate(true)
        }
    var patch: Dictionary = patch_variant
    if _world_state == null or not _world_state.has_method("review_rule_package_proposal"):
        return _build_local_proposal_review(rule_package)

    return {
        "status": "review_pending",
        "message": "入力停止後に提案レビューを更新します。",
        "review_status": String(patch.get("review_status", "draft")),
        "rule_package": rule_package.duplicate(true)
    }

func _parse_editor_rule_package() -> Dictionary:
    var raw_text := _proposal_editor.text.strip_edges()
    if raw_text.is_empty():
        return {
            "status": "error",
            "message": "提案エディタが空です。"
        }

    var parser := JSON.new()
    var parse_result := parser.parse(raw_text)
    if parse_result != OK:
        return {
            "status": "error",
            "message": "提案 JSON が不正です。",
            "line": parser.get_error_line(),
            "details": parser.get_error_message()
        }
    if not (parser.data is Dictionary):
        return {
            "status": "error",
            "message": "提案 JSON は辞書型である必要があります。"
        }
    return {
        "status": "parsed",
        "rule_package": parser.data
    }

func _build_local_proposal_review(rule_package: Dictionary) -> Dictionary:
    if rule_package.is_empty():
        return {
            "status": "error",
            "message": "ルールパッケージが空です。"
        }
    if not _looks_like_rule_package(rule_package):
        return {
            "status": "error",
            "message": "ルールパッケージに必要な schema_version または patch がありません。",
            "rule_package": rule_package.duplicate(true)
        }

    var patch = rule_package.get("patch", {})
    var operations = patch.get("operations", [])
    if not (operations is Array):
        return {
            "status": "error",
            "message": "ルールパッケージ patch.operations は配列である必要があります。",
            "rule_package": rule_package.duplicate(true)
        }

    var deferred_operations: Array = []
    for operation_variant in operations:
        if not (operation_variant is Dictionary):
            deferred_operations.append(operation_variant)
            continue
        var operation: Dictionary = operation_variant
        var op_name := String(operation.get("op", ""))
        var supported_directly := op_name == "upsert_stat" or (
            op_name == "upsert_rule" and String(operation.get("rule_type", "")) == "tick_delta"
        )
        if not supported_directly:
            deferred_operations.append(operation.duplicate(true))

    var warnings: Array = []
    if operations.is_empty():
        warnings.append("導入対象の操作がまだありません。")
    if not deferred_operations.is_empty():
        warnings.append("一部の操作はランタイム対応待ちのため保留されます。")

    var review_status := String(patch.get("review_status", "draft"))
    return {
        "status": "ready_for_install" if review_status == "approved" else "needs_approval",
        "package_id": rule_package.get("package_id", ""),
        "display_name": rule_package.get("display_name", rule_package.get("package_id", "")),
        "review_status": review_status,
        "operation_count": operations.size(),
        "safe_to_apply_directly": deferred_operations.is_empty(),
        "deferred_operations": deferred_operations,
        "forked_from": rule_package.get("forked_from", null),
        "suggested_pr_target": rule_package.get("suggested_pr_target", null),
        "warnings": warnings,
        "rule_package": rule_package.duplicate(true)
    }

func _update_proposal_views() -> void:
    var proposal := _current_selected_proposal()
    if proposal.is_empty():
        _proposal_review_summary_label.text = "提案未選択です。"
        _proposal_metadata_view.text = "レビューする提案を選んでください。"
        _reset_proposal_button.disabled = true
        _approve_proposal_button.disabled = true
        _install_proposal_button.disabled = true
        return

    var rule_package := _proposal_to_rule_package(proposal)
    var review_status := String(_current_proposal_review.get("review_status", ""))
    if review_status.is_empty() and not rule_package.is_empty():
        review_status = String(rule_package.get("patch", {}).get("review_status", "draft"))

    var summary_segments: Array[String] = []
    summary_segments.append("最新相談: %s" % str(_latest_task_result.get("status", "proposal_ready")))
    summary_segments.append("レビュー: %s" % (review_status if not review_status.is_empty() else "未取得"))
    if _proposal_editor_is_dirty():
        summary_segments.append("編集中")
    if _proposal_requires_reapproval():
        summary_segments.append("再承認が必要")
    if String(_current_proposal_review.get("status", "")) == "review_pending":
        summary_segments.append("レビュー更新待ち")
    if String(_current_proposal_review.get("status", "")) == "error":
        summary_segments.append("JSON要修正")
    _proposal_review_summary_label.text = " | ".join(summary_segments)

    var metadata_lines: Array[String] = []
    metadata_lines.append("相談: %s" % str(_latest_task_result.get("task_text", "(未送信)")))
    metadata_lines.append("解決方針: %s" % str(_latest_task_result.get("resolution", _latest_task_result.get("status", "unknown"))))
    metadata_lines.append("メッセージ: %s" % str(_latest_task_result.get("message", "要約はありません。")))
    if not rule_package.is_empty():
        metadata_lines.append("")
        metadata_lines.append("パッケージ: %s" % str(rule_package.get("package_id", "")))
        metadata_lines.append("表示名: %s" % str(rule_package.get("display_name", "")))
        metadata_lines.append("説明: %s" % str(rule_package.get("description", "")))
        metadata_lines.append("ソース: %s @ %s" % [
            str(rule_package.get("source_repo", "")),
            str(rule_package.get("source_ref", ""))
        ])
        metadata_lines.append("clone / fork 元: %s" % _format_variant_for_text(rule_package.get("forked_from", null)))
        metadata_lines.append("提案PR先: %s" % _format_variant_for_text(rule_package.get("suggested_pr_target", null)))
        metadata_lines.append("タグ: %s" % _format_variant_for_text(rule_package.get("tags", [])))
        metadata_lines.append("コミュニティ: %s" % _format_variant_for_text(rule_package.get("community", {})))
        var install_actions = rule_package.get("patch", {}).get("install_actions", [])
        if install_actions is Array and not install_actions.is_empty():
            metadata_lines.append("宣言的な導入アクション (%d): %s" % [
                install_actions.size(),
                JSON.stringify(install_actions, "	")
            ])
    else:
        metadata_lines.append("")
        metadata_lines.append("この提案には完全なパッケージ JSON が含まれないため、ここから編集・導入できません。")

    if _current_proposal_review.has("operation_count"):
        metadata_lines.append("操作数: %s" % str(_current_proposal_review.get("operation_count", 0)))
    if _current_proposal_review.has("safe_to_apply_directly"):
        metadata_lines.append("直接適用可能: %s" % str(_current_proposal_review.get("safe_to_apply_directly", false)))
    if _current_proposal_review.has("compiled_runtime_patch"):
        metadata_lines.append("コンパイル済みランタイムパッチ: %s" % _format_variant_for_text(_current_proposal_review.get("compiled_runtime_patch", {})))
    if _current_proposal_review.has("deferred_operations"):
        var deferred_operations = _current_proposal_review.get("deferred_operations", [])
        if deferred_operations is Array and not deferred_operations.is_empty():
            metadata_lines.append("保留中の操作 (%d): %s" % [
                deferred_operations.size(),
                JSON.stringify(deferred_operations, "	")
            ])

    var warnings = _current_proposal_review.get("warnings", [])
    if warnings is Array and not warnings.is_empty():
        metadata_lines.append("警告: %s" % _format_variant_for_text(warnings))

    if _latest_task_result.has("workflow"):
        metadata_lines.append("ワークフロー: %s" % _format_variant_for_text(_latest_task_result.get("workflow", {})))

    if String(_current_proposal_review.get("status", "")) == "error":
        metadata_lines.append("レビューエラー: %s" % str(_current_proposal_review.get("message", "不明なレビューエラーです。")))
    elif String(_current_proposal_review.get("status", "")) == "review_pending":
        metadata_lines.append("レビュー状態: %s" % str(_current_proposal_review.get("message", "入力停止後にレビューを更新します。")))
    elif _proposal_requires_reapproval():
        metadata_lines.append("承認状態: 承認後に内容が変わりました。再承認してから導入してください。")
    elif not _approved_proposal_text.is_empty():
        metadata_lines.append("承認状態: 現在の JSON は導入可能として承認済みです。")
    elif review_status == "approved":
        metadata_lines.append("承認状態: UI 上でも承認ボタンを押すと、この提案の導入が解放されます。")

    _proposal_metadata_view.text = "\n".join(metadata_lines)

    var review_failed := String(_current_proposal_review.get("status", "")) == "error"
    var has_editable_package := not rule_package.is_empty()
    _reset_proposal_button.disabled = not has_editable_package or not _proposal_editor_is_dirty()
    _approve_proposal_button.disabled = not has_editable_package or review_failed
    _install_proposal_button.disabled = (
        not has_editable_package
        or review_failed
        or review_status != "approved"
        or _approved_proposal_text.is_empty()
        or _proposal_requires_reapproval()
    )

func _update_installed_rules_panel() -> void:
    _installed_package_list.clear()
    for package_data in _installed_package_cache:
        _installed_package_list.add_item(_format_package_list_label(package_data))

    var has_packages := not _installed_package_cache.is_empty()
    _package_enable_button.disabled = true
    _package_disable_button.disabled = true
    if not has_packages:
        _installed_package_details_view.text = "まだパッケージ由来の導入ルールはありません。package_id 付きのルールを導入すると、ここから一括ON/OFFできます。"
    else:
        _installed_package_list.select(0)
        _update_installed_package_details(0)

    _installed_rule_list.clear()
    for rule_data in _installed_rule_cache:
        _installed_rule_list.add_item(_format_rule_list_label(rule_data))
    _update_installed_rule_tree()

    var has_rules := not _installed_rule_cache.is_empty()
    _clone_rule_button.disabled = not has_rules
    if not has_rules:
        _installed_rule_details_view.text = "まだルールはありません。テンプレートを追加すると、親ルールや未解決の依存を確認できます。"
        return

    if has_packages:
        _select_first_rule_for_package(_extract_identifier(_installed_package_cache[0]))
    if _installed_rule_list.get_selected_items().is_empty():
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
            var candidate_ids := Array(dependency_model.get("providers_by_kind", {}).get(required_kind, []))
            if candidate_ids.is_empty():
                summary_lines.append("- %s (提供元なし)" % required_kind)
            else:
                summary_lines.append("- %s (候補: %s)" % [
                    required_kind,
                    _format_rule_reference_list(candidate_ids, dependency_model)
                ])

    _clone_rule_button.disabled = false
    summary_lines.append("")
    summary_lines.append("生JSON:")
    summary_lines.append(JSON.stringify(rule_data, "	"))
    _installed_rule_details_view.text = "\n".join(summary_lines)

func _update_installed_package_details(index: int) -> void:
    if index < 0 or index >= _installed_package_cache.size():
        _installed_package_details_view.text = ""
        _package_enable_button.disabled = true
        _package_disable_button.disabled = true
        return

    var package_data = _installed_package_cache[index]
    var package_id := _extract_identifier(package_data)
    var package_state := str(package_data.get("state", "disabled"))
    var lines: Array[String] = []
    lines.append("パッケージ: %s" % _format_package_list_label(package_data))
    lines.append("状態: %s" % _format_package_state_label(package_state))
    lines.append("ルール数: %d (有効 %d / 無効 %d)" % [
        int(package_data.get("rule_count", 0)),
        int(package_data.get("enabled_rule_count", 0)),
        int(package_data.get("disabled_rule_count", 0))
    ])
    var version := str(package_data.get("version", ""))
    if not version.is_empty():
        lines.append("バージョン: %s" % version)
    var source_repo := str(package_data.get("source_repo", ""))
    if not source_repo.is_empty():
        lines.append("ソース: %s" % source_repo)
    var source_ref := str(package_data.get("source_ref", ""))
    if not source_ref.is_empty():
        lines.append("参照: %s" % source_ref)
    var rule_ids: Array = package_data.get("rule_ids", [])
    if not rule_ids.is_empty():
        lines.append("対象ルール: %s" % _join_values(rule_ids))
    lines.append("")
    lines.append("生JSON:")
    lines.append(JSON.stringify(package_data, "	"))
    _installed_package_details_view.text = "\n".join(lines)

    _package_enable_button.disabled = package_state == "enabled"
    _package_disable_button.disabled = package_state == "disabled"
    _select_first_rule_for_package(package_id)

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
    var world_clock: Variant = _snapshot_cache.get("world_clock", {})
    if world_clock is Dictionary and not world_clock.is_empty():
        var source_field := str(world_clock.get("source_field", "elapsed_seconds"))
        var source_label := str(world_clock.get("source_package_id", world_clock.get("source_rule_id", "")))
        if source_label.is_empty():
            lines.append("ワールド時計: %.2f秒を表示中 (WorldState.%s)" % [
                float(world_clock.get("elapsed_seconds", _snapshot_cache.get("elapsed_seconds", 0.0))),
                source_field
            ])
        else:
            lines.append("ワールド時計: %.2f秒を表示中 (%s → WorldState.%s)" % [
                float(world_clock.get("elapsed_seconds", _snapshot_cache.get("elapsed_seconds", 0.0))),
                source_label,
                source_field
            ])
    var preview_summary: Variant = _snapshot_cache.get("three_d_preview", null)
    if preview_summary is Dictionary:
        var renderable_count := 0
        var renderables = preview_summary.get("renderables", [])
        if renderables is Array:
            renderable_count = renderables.size()
        lines.append("GM用3D化メモ: %s (%d件の描画対象)" % [
            "有効" if bool(preview_summary.get("enabled", false)) else "無効",
            renderable_count
        ])
    else:
        lines.append("GM用3D化メモ: スナップショット未報告")
    if _snapshot_cache.has("world_mode"):
        lines.append("現在の世界モード: %s" % [str(_snapshot_cache.get("world_mode", "two_d"))])
    if _snapshot_cache.has("concepts"):
        lines.append("概念: %s" % [_join_values(Array(_snapshot_cache.get("concepts", [])))])
    var installed_packages := _extract_installed_packages(_snapshot_cache)
    if not installed_packages.is_empty():
        lines.append("導入済みパッケージ:")
        for package_data in installed_packages:
            lines.append("- %s" % _format_package_list_label(package_data))

    lines.append("")
    lines.append("所有・内包:")
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
    if entities.is_empty():
        lines.append("- エンティティはありません。")

    var task_history = _snapshot_cache.get("player_task_history", [])
    if task_history is Array and not task_history.is_empty():
        lines.append("")
        lines.append("直近の相談結果:")
        lines.append(JSON.stringify(task_history[task_history.size() - 1], "	"))

    _world_state_view.text = "\n".join(lines)

func _update_three_d_preview() -> void:
    if _three_d_preview_renderer == null:
        return
    if _three_d_preview_renderer.has_method("update_from_snapshot"):
        _three_d_preview_renderer.call("update_from_snapshot", _snapshot_cache)

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
        lines.append("GM会話操作:")
        for log_line in _take_last_entries(_shell_log_lines, 8):
            lines.append(str(log_line))

    _event_log_view.text = "\n".join(lines) if not lines.is_empty() else "まだイベントはありません。"
    _event_log_view.scroll_vertical = _event_log_view.get_line_count()

func _update_poc4_state_view() -> void:
    if _poc4_state_view == null:
        return

    var proposal: Dictionary = _poc4_state_cache.get("proposal", {})
    var summary: Dictionary = _poc4_state_cache.get("summary", {})
    var review: Dictionary = _poc4_state_cache.get("review", {})
    var issue_preview: Dictionary = _poc4_state_cache.get("issue_preview", {})
    var apply_result: Dictionary = _poc4_apply_result_cache if not _poc4_apply_result_cache.is_empty() else _poc4_state_cache.get("apply_result", {})
    var last_error: Dictionary = _poc4_state_cache.get("last_error", {})
    var execution: Dictionary = _poc4_state_cache.get("execution", {})
    var codex: Dictionary = _poc4_state_cache.get("codex", {})
    var lines: Array[String] = []

    lines.append("Execution:")
    lines.append("- status: %s" % str(execution.get("status", "idle")))
    if execution.has("phase"):
        lines.append("- phase: %s" % str(execution.get("phase", "")))
    if execution.has("message") and not String(execution.get("message", "")).is_empty():
        lines.append("- message: %s" % str(execution.get("message", "")))
    lines.append("")

    lines.append("PoC4 pending proposal:")
    if proposal.is_empty():
        lines.append("- なし")
    else:
        lines.append("- proposal_title: %s" % str(summary.get("title", issue_preview.get("title", proposal.get("proposal_title", "n/a")))))
        lines.append("- proposal 要約: %s" % str(summary.get("player_request_summary", proposal.get("player_request_summary", "n/a"))))
        lines.append("- package_id: %s" % str(summary.get("package_id", proposal.get("package_id", "n/a"))))
        lines.append("- operation_count: %d" % int(summary.get("operation_count", 0)))
        var operation_types := Array(summary.get("operation_types", []))
        lines.append("- operation_types: %s" % (_join_values(operation_types) if not operation_types.is_empty() else "-"))
        lines.append("- stats: %s" % _bool_text(bool(summary.get("has_stat_changes", false))))
        lines.append("- rules: %s" % _bool_text(bool(summary.get("has_rule_changes", false))))
        lines.append("- event_bindings: %s" % _bool_text(bool(summary.get("has_event_binding_changes", false))))
        lines.append("- relations: %s" % _bool_text(bool(summary.get("has_relation_changes", false))))
        lines.append("- review_status: %s" % str(summary.get("review_status", proposal.get("review_status", "n/a"))))
        lines.append("- validation_status: %s" % str(summary.get("validation_status", proposal.get("validation", {}).get("status", "n/a"))))
        lines.append("- suggested_pr_target: %s" % _format_poc4_submission_target(summary.get("suggested_pr_target", null), apply_result))

    lines.append("")
    lines.append("Review:")
    lines.append("- required: %s" % _bool_text(bool(review.get("required", false))))
    lines.append("- acknowledged: %s" % _bool_text(bool(review.get("acknowledged", review.get("granted", false)))))
    lines.append("- status: %s" % str(review.get("status", "not_requested")))

    var last_request_text := String(_poc4_state_cache.get("last_request_text", "")).strip_edges()
    if not last_request_text.is_empty():
        lines.append("- request: %s" % last_request_text)

    lines.append("")
    lines.append("Apply result:")
    if apply_result.is_empty():
        lines.append("- まだありません")
    else:
        lines.append("- status: %s" % str(apply_result.get("status", "unknown")))
        if apply_result.has("message"):
            lines.append("- message: %s" % str(apply_result.get("message", "")))
        if apply_result.has("package_id"):
            lines.append("- package_id: %s" % str(apply_result.get("package_id", "")))
        if apply_result.has("proposal_title"):
            lines.append("- proposal_title: %s" % str(apply_result.get("proposal_title", "")))
        if apply_result.has("runtime_rule_id"):
            lines.append("- runtime_rule_id: %s" % str(apply_result.get("runtime_rule_id", "")))
        if apply_result.has("applied_operation_count"):
            lines.append("- applied_operation_count: %s" % str(apply_result.get("applied_operation_count", "")))
        if apply_result.has("deferred_operation_count"):
            lines.append("- deferred_operation_count: %s" % str(apply_result.get("deferred_operation_count", "")))

    if not last_error.is_empty():
        lines.append("")
        lines.append("Last error:")
        lines.append("- error_code: %s" % str(last_error.get("error_code", "unknown")))
        lines.append("- message: %s" % str(last_error.get("message", "")))
        var details: Dictionary = last_error.get("details", {})
        if not details.is_empty():
            lines.append("- details: %s" % _format_variant_inline(details))

    _append_poc4_codex_lines(lines, codex)

    var history: Array = _poc4_state_cache.get("history", [])
    if not history.is_empty():
        lines.append("")
        lines.append("Recent history:")
        for entry in _take_last_entries(history, 5):
            lines.append("- %s" % _format_variant_inline(entry))

    _poc4_state_view.text = "\n".join(lines)

func _update_status_label() -> void:
    var source := "WorldState 自動読み込み" if _world_state != null else "会話用フォールバック表示"
    var poc4_status := _describe_poc4_status()
    var summary := "GM会話データ元: %s | 候補テンプレート: %d | レビュー提案: %d | 導入済みパッケージ: %d | 稼働ルール: %d | PoC4: %s" % [source, _template_cache.size(), _proposal_cache.size(), _installed_package_cache.size(), _installed_rule_cache.size(), poc4_status]
    if _home_summary_label != null:
        _home_summary_label.text = summary
    if _tabs != null and _tabs.get_tab_count() >= 5:
        _tabs.set_tab_title(0, "◐ 統合画面")
        _tabs.set_tab_title(1, "✎ GM相談")
        _tabs.set_tab_title(2, "▤ 提案レビュー (%d)" % _proposal_cache.size())
        _tabs.set_tab_title(3, "⌥ 稼働ルール (%d)" % _installed_rule_cache.size())
        _tabs.set_tab_title(4, "▦ 世界・履歴")

func _emit_close_requested() -> void:
    close_requested.emit()

func _on_submit_pressed() -> void:
    var task_text := _task_input.text.strip_edges()
    if task_text.is_empty():
        _append_log("空の相談は無視しました。")
        return

    var result: Dictionary = {}
    if _world_state != null and _world_state.has_method("submit_player_task"):
        result = _world_state.call("submit_player_task", task_text)
    else:
        result = _simulate_task_submission(task_text)

    if String(result.get("status", "")) == "needs_rule_patch":
        result["message"] = "既存テンプレートでは解決できません。PoC4 proposal を作る場合は、プレイヤー向け GM 会話画面から依頼してください。"

    _task_input.clear()
    _refresh_all()
    _append_log("相談を送信しました: %s" % task_text, result)

func _on_proposal_selected(index: int) -> void:
    _selected_proposal_index = index
    _load_selected_proposal_into_editor()

func _on_proposal_editor_changed() -> void:
    if _is_updating_proposal_editor:
        return
    _current_proposal_review = _build_editor_change_review_state()
    _update_proposal_views()
    if _proposal_review_timer != null and String(_current_proposal_review.get("status", "")) != "error":
        _proposal_review_timer.start()

func _on_proposal_review_timer_timeout() -> void:
    _current_proposal_review = _refresh_current_proposal_review(false)
    _update_proposal_views()

func _on_reset_proposal_pressed() -> void:
    if _selected_proposal_original_text.is_empty():
        _append_log("編集対象の提案がないまま元に戻そうとしました。")
        return

    _set_proposal_editor_text(_selected_proposal_original_text)
    _current_proposal_review = _refresh_current_proposal_review(false)
    _approved_proposal_text = _proposal_editor.text if String(_current_proposal_review.get("review_status", "")) == "approved" else ""
    _update_proposal_views()
    _append_log("提案 JSON を選択時の下書きへ戻しました。", {
        "package_id": _current_proposal_review.get("package_id", _build_proposal_key(_current_selected_proposal(), _selected_proposal_index))
    })

func _on_approve_proposal_pressed() -> void:
    var parsed_result := _parse_editor_rule_package()
    if String(parsed_result.get("status", "")) == "error":
        _append_log("提案の承認に失敗しました。", parsed_result)
        _current_proposal_review = parsed_result
        _update_proposal_views()
        return

    var rule_package: Dictionary = parsed_result.get("rule_package", {}).duplicate(true)
    var patch = rule_package.get("patch", {})
    if not (patch is Dictionary):
        var error_result := {
            "status": "error",
            "message": "承認前に patch が辞書型である必要があります。"
        }
        _append_log("提案の承認に失敗しました。", error_result)
        _current_proposal_review = error_result
        _update_proposal_views()
        return

    patch["review_status"] = "approved"
    rule_package["patch"] = patch
    _set_proposal_editor_text(JSON.stringify(rule_package, "	"))
    _current_proposal_review = _refresh_current_proposal_review(true)
    if String(_current_proposal_review.get("status", "")) == "error":
        _update_proposal_views()
        return

    _approved_proposal_text = _proposal_editor.text
    _update_proposal_views()
    _append_log("提案を承認しました。", {
        "package_id": _current_proposal_review.get("package_id", ""),
        "safe_to_apply_directly": _current_proposal_review.get("safe_to_apply_directly", false),
        "deferred_operation_count": Array(_current_proposal_review.get("deferred_operations", [])).size()
    })

func _on_install_proposal_pressed() -> void:
    _current_proposal_review = _refresh_current_proposal_review(true)
    if String(_current_proposal_review.get("status", "")) == "error":
        _update_proposal_views()
        return
    if String(_current_proposal_review.get("review_status", "")) != "approved":
        _append_log("提案が承認されるまで導入できません。", {
            "package_id": _current_proposal_review.get("package_id", ""),
            "review_status": _current_proposal_review.get("review_status", "draft")
        })
        _update_proposal_views()
        return
    if _approved_proposal_text.is_empty():
        _append_log("UI 上の承認ステップを完了するまで導入できません。", {
            "package_id": _current_proposal_review.get("package_id", "")
        })
        _update_proposal_views()
        return
    if _proposal_requires_reapproval():
        _append_log("承認後に内容が変わったため、再承認が必要です。", {
            "package_id": _current_proposal_review.get("package_id", "")
        })
        _update_proposal_views()
        return

    var parsed_result := _parse_editor_rule_package()
    if String(parsed_result.get("status", "")) == "error":
        _append_log("ランタイムへ渡す前の提案検証に失敗しました。", parsed_result)
        _current_proposal_review = parsed_result
        _update_proposal_views()
        return

    var rule_package: Dictionary = parsed_result.get("rule_package", {})
    var package_id := str(rule_package.get("package_id", _build_proposal_key(_current_selected_proposal(), _selected_proposal_index)))
    var result: Dictionary = {}
    if _world_state != null and _world_state.has_method("create_rule_from_patch"):
        result = _world_state.call("create_rule_from_patch", rule_package)
    else:
        result = _simulate_package_install(rule_package)
        result["approved_rule_package"] = rule_package.duplicate(true)

    _refresh_all()
    _append_log("レビュー済み提案を導入しました: %s" % package_id, result)

func _on_install_template_pressed() -> void:
    var selected_items := _template_list.get_selected_items()
    if selected_items.is_empty():
        _append_log("テンプレート未選択のまま追加しようとしました。")
        return

    var template_data = _template_cache[selected_items[0]]
    var template_id := _extract_identifier(template_data)
    _install_template_by_id(template_id)

func _on_clone_rule_pressed() -> void:
    var selected_items := _installed_rule_list.get_selected_items()
    if selected_items.is_empty():
        _append_log("インストール済みルール未選択のまま複製しようとしました。")
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

func _on_installed_package_selected(index: int) -> void:
    _update_installed_package_details(index)

func _on_package_enable_pressed() -> void:
    _set_selected_package_enabled(true)

func _on_package_disable_pressed() -> void:
    _set_selected_package_enabled(false)

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

func _extract_installed_packages(snapshot: Dictionary) -> Array:
    var raw_packages = snapshot.get("installed_rule_packages", [])
    if raw_packages is Array and not raw_packages.is_empty():
        return raw_packages.duplicate(true)
    if raw_packages is Dictionary:
        var packages: Array = []
        var package_ids: Array = raw_packages.keys()
        package_ids.sort()
        for package_id in package_ids:
            packages.append(raw_packages[package_id])
        if not packages.is_empty():
            return packages
    return _derive_installed_packages_from_rules(_extract_installed_rules(snapshot))

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
        for key in ["package_id", "id", "rule_id", "template_id", "display_name", "name", "title"]:
            if data.has(key):
                return str(data.get(key))
    return str(data)

func _format_template_label(template_data: Variant) -> String:
    if template_data is Dictionary:
        return "%s — %s" % [
            str(template_data.get("name", _extract_identifier(template_data))),
            str(template_data.get("description", template_data.get("summary", "追加準備完了")))
        ]
    return str(template_data)

func _format_rule_list_label(rule_data: Variant) -> String:
    if rule_data is Dictionary:
        var label := "%s (%s)" % [
            str(rule_data.get("name", _extract_identifier(rule_data))),
            _extract_identifier(rule_data)
        ]
        var package_id := _extract_rule_package_id(rule_data)
        if not package_id.is_empty():
            label += " [%s]" % package_id
        return label
    return str(rule_data)

func _format_package_list_label(package_data: Variant) -> String:
    if package_data is Dictionary:
        return "%s (%s) [%s]" % [
            str(package_data.get("display_name", _extract_identifier(package_data))),
            _extract_identifier(package_data),
            _format_package_state_label(str(package_data.get("state", "disabled")))
        ]
    return str(package_data)

func _format_package_state_label(state: String) -> String:
    match state:
        "enabled":
            return "有効"
        "mixed":
            return "一部有効"
        _:
            return "無効"

func _find_package_index_by_id(package_id: String) -> int:
    for index in range(_installed_package_cache.size()):
        if _extract_identifier(_installed_package_cache[index]) == package_id:
            return index
    return -1

func _select_first_rule_for_package(package_id: String) -> void:
    if package_id.is_empty() or _installed_rule_list == null:
        return
    for index in range(_installed_rule_cache.size()):
        if _extract_rule_package_id(_installed_rule_cache[index]) != package_id:
            continue
        _installed_rule_list.deselect_all()
        _installed_rule_list.select(index)
        _update_installed_rule_details(index)
        return

func _find_rule_index_by_id(rule_id: String) -> int:
    for index in range(_installed_rule_cache.size()):
        if _extract_identifier(_installed_rule_cache[index]) == rule_id:
            return index
    return -1

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
        resolved_group.set_text(0, "解決済みの根")
        resolved_group.set_text(1, "解決済みの親がないルール")
        for rule_id in root_rule_ids:
            _add_rule_tree_item(resolved_group, str(rule_id), dependency_model, [], displayed_rule_ids)

    var unresolved_rule_ids: Array = dependency_model.get("unresolved_rule_ids", [])
    if not unresolved_rule_ids.is_empty():
        var unresolved_group := _installed_rule_tree.create_item(root_item)
        unresolved_group.set_text(0, "親リンク待ち")
        unresolved_group.set_text(1, "必要な親種別がまだ解決されていません")
        for rule_id in unresolved_rule_ids:
            _add_rule_tree_item(unresolved_group, str(rule_id), dependency_model, [], displayed_rule_ids)

    var overflow_group: TreeItem = null
    var rule_ids: Array = dependency_model.get("rule_ids", [])
    for rule_id in rule_ids:
        if displayed_rule_ids.has(rule_id):
            continue
        if overflow_group == null:
            overflow_group = _installed_rule_tree.create_item(root_item)
            overflow_group.set_text(0, "追加の連結ルール")
            overflow_group.set_text(1, "隠れた依存循環を避けるためここに表示します")
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
        cycle_item.set_text(0, "循環を検出")
        cycle_item.set_text(1, rule_id)
        return

    var rules_by_id: Dictionary = dependency_model.get("rules_by_id", {})
    if not rules_by_id.has(rule_id):
        var missing_item := _installed_rule_tree.create_item(parent_item)
        missing_item.set_text(0, rule_id)
        missing_item.set_text(1, "スナップショット内にルールがありません")
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
        extra_parent_item.set_text(0, "別の親にも接続")
        extra_parent_item.set_text(1, _format_rule_reference_list(resolved_parent_ids.slice(1, resolved_parent_ids.size()), dependency_model))

    for required_kind in _get_rule_unresolved_required_kinds(rule_id, dependency_model):
        var unresolved_item := _installed_rule_tree.create_item(rule_item)
        unresolved_item.set_text(0, "必要な親種別")
        var candidate_ids: Array = Array(dependency_model.get("providers_by_kind", {}).get(required_kind, []))
        if candidate_ids.is_empty():
            unresolved_item.set_text(1, str(required_kind))
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
        parts.append("根ルール" if _get_rule_unresolved_required_kinds(rule_id, dependency_model).is_empty() else "親リンク待ち")
    else:
        parts.append("親: %s" % _format_rule_reference_list(resolved_parent_ids, dependency_model))

    var child_ids: Array = dependency_model.get("children_by_parent", {}).get(rule_id, [])
    if not child_ids.is_empty():
        parts.append("子ルール %d 件" % child_ids.size())

    var provided_kinds: Array = dependency_model.get("provided_kinds_by_rule", {}).get(rule_id, [])
    if not provided_kinds.is_empty():
        parts.append("提供: %s" % _join_values(provided_kinds))

    var unresolved_required_kinds := _get_rule_unresolved_required_kinds(rule_id, dependency_model)
    if not unresolved_required_kinds.is_empty():
        parts.append("必要: %s" % _join_values(unresolved_required_kinds))

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

func _extract_rule_parent_ids(rule_data: Variant) -> Array:
    return _extract_string_list_from_keys(
        rule_data,
        RULE_PARENT_ID_FIELDS,
        ["resolved_parent_rule_id", "parent_rule_id", "resolved_parent_id", "parent_id"]
    )

func _extract_rule_required_kinds(rule_data: Variant) -> Array:
    return _extract_string_list_from_keys(
        rule_data,
        RULE_REQUIRED_KIND_FIELDS,
        ["required_parent_rule_kind", "required_rule_kind", "requires_rule_kind", "parent_rule_kind"]
    )

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
            if not text.is_empty() and not values.has(text):
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
        empty_item.set_text(1, "ワールドスナップショットに対象がありません。")
        return

    var character_entities := _filter_entities_by_kind(entities, true)
    if not character_entities.is_empty():
        var character_group := _entity_tree.create_item(root_item)
        character_group.set_text(0, "キャラクタ / エージェント")
        character_group.set_text(1, "%d件" % character_entities.size())
        for entity_data in character_entities:
            _add_entity_tree_item(character_group, entity_data, entity_model)

    var object_entities := _filter_entities_by_kind(entities, false)
    if not object_entities.is_empty():
        var object_group := _entity_tree.create_item(root_item)
        object_group.set_text(0, "物体 / ワールド要素")
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
                str(entity_link.get("reverse_label", "逆関連")),
                str(entity_link.get("label", "関連")),
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
                    str(field_spec.get("forward", "関連")),
                    str(field_spec.get("reverse", "逆関連")),
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
                    str(field_spec.get("forward", "関連")),
                    str(field_spec.get("reverse", "逆関連")),
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
        parts.append("task=%s" % str(behavior.get("current_task")))

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
        link_lines.append("%s: %s" % [str(grouped_entry.get("label", "関連")), str(grouped_entry.get("value", ""))])
    for grouped_entry in _group_entity_links(reverse_entries, entity_names_by_id):
        link_lines.append("%s: %s" % [str(grouped_entry.get("label", "関連")), str(grouped_entry.get("value", ""))])
    return link_lines

func _group_entity_links(entity_links: Array, entity_names_by_id: Dictionary) -> Array:
    var targets_by_label: Dictionary = {}
    for entity_link in entity_links:
        var label := str(entity_link.get("label", "関連"))
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
                str(grouped_entry.get("label", "関連")),
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

func _merge_poc4_state(source: Variant) -> Dictionary:
    if not (source is Dictionary):
        return {
            "proposal": {},
            "summary": {},
            "issue_preview": {},
            "review": {},
            "apply_result": {},
            "last_error": {},
            "execution": {},
            "codex": {},
            "last_request_text": "",
            "history": []
        }

    var state: Dictionary = source
    return {
        "proposal": state.get("proposal", state.get("pending_proposal", {})).duplicate(true) if state.get("proposal", state.get("pending_proposal", {})) is Dictionary else {},
        "summary": state.get("summary", state.get("proposal_summary", {})).duplicate(true) if state.get("summary", state.get("proposal_summary", {})) is Dictionary else {},
        "issue_preview": state.get("issue_preview", {}).duplicate(true) if state.get("issue_preview", {}) is Dictionary else {},
        "review": state.get("review", {}).duplicate(true) if state.get("review", {}) is Dictionary else {},
        "apply_result": state.get("apply_result", {}).duplicate(true) if state.get("apply_result", {}) is Dictionary else {},
        "last_error": state.get("last_error", {}).duplicate(true) if state.get("last_error", {}) is Dictionary else {},
        "execution": state.get("execution", {}).duplicate(true) if state.get("execution", {}) is Dictionary else {},
        "codex": state.get("codex", {}).duplicate(true) if state.get("codex", {}) is Dictionary else {},
        "last_request_text": String(state.get("last_request_text", "")),
        "history": Array(state.get("history", [])).duplicate(true)
    }


func _describe_poc4_status() -> String:
    var proposal: Dictionary = _poc4_state_cache.get("proposal", {})
    var review: Dictionary = _poc4_state_cache.get("review", {})
    var apply_result: Dictionary = _poc4_apply_result_cache if not _poc4_apply_result_cache.is_empty() else _poc4_state_cache.get("apply_result", {})
    var last_error: Dictionary = _poc4_state_cache.get("last_error", {})
    var execution: Dictionary = _poc4_state_cache.get("execution", {})
    if not last_error.is_empty():
        return "error:%s" % str(last_error.get("error_code", "unknown"))
    if String(execution.get("status", "idle")) == "running":
        return "running"
    if String(apply_result.get("status", "")) in ["applied", "applied_with_warnings"]:
        return String(apply_result.get("status", "applied"))
    if proposal.is_empty():
        return "idle"
    if bool(review.get("acknowledged", review.get("granted", false))):
        return "reviewed"
    return "pending_review"

func _format_poc4_submission_target(suggested_target: Variant, apply_result: Dictionary) -> String:
    if suggested_target is Dictionary:
        return "%s @ %s (%s)" % [
            str(suggested_target.get("repo", "")),
            str(suggested_target.get("base_ref", "")),
            str(suggested_target.get("package_id", ""))
        ]
    if not String(apply_result.get("runtime_rule_id", "")).is_empty():
        return "runtime:%s" % str(apply_result.get("runtime_rule_id", ""))
    return "runtime install"

func _append_poc4_codex_lines(lines: Array, codex: Dictionary) -> void:
    if codex.is_empty():
        return

    lines.append("")
    lines.append("Codex detail:")
    lines.append("- session id: %s" % _format_poc4_codex_value(codex.get("session_id", "")))
    lines.append("- model: %s" % _format_poc4_codex_value(codex.get("model", "")))
    lines.append("- workdir: %s" % _format_poc4_codex_value(codex.get("workdir", "")))
    lines.append("- approval: %s" % _format_poc4_codex_value(codex.get("approval", "")))
    lines.append("- sandbox: %s" % _format_poc4_codex_value(codex.get("sandbox", "")))

    var excerpt := String(codex.get("cli_output_excerpt", "")).strip_edges()
    if excerpt.is_empty():
        excerpt = String(codex.get("cli_output", "")).strip_edges()
    if excerpt.length() > 280:
        excerpt = excerpt.substr(0, 280).strip_edges() + "…"
    if not excerpt.is_empty():
        lines.append("- cli 抜粋: %s" % excerpt.replace("\n", " / "))

func _format_poc4_codex_value(value: Variant) -> String:
    var text := str(value).strip_edges()
    return text if not text.is_empty() else "-"

func _bool_text(value: bool) -> String:
    return "あり" if value else "なし"

func _extract_latest_task_result(snapshot: Dictionary) -> Dictionary:
    var task_history = snapshot.get("player_task_history", [])
    if task_history is Array and not task_history.is_empty():
        var latest_result = task_history[task_history.size() - 1]
        return latest_result.duplicate(true) if latest_result is Dictionary else {}
    return {}

func _extract_task_proposals(task_result: Dictionary) -> Array:
    var proposals = task_result.get("proposals", [])
    if proposals is Array:
        var normalized: Array = []
        for proposal_data in proposals:
            if proposal_data is Dictionary:
                normalized.append(proposal_data.duplicate(true))
        return normalized
    return []

func _looks_like_rule_package(candidate: Dictionary) -> bool:
    return (
        String(candidate.get("schema_version", "")) == "rule_package_v1"
        and candidate.get("patch", {}) is Dictionary
    )

func _build_task_result_signature(task_result: Dictionary) -> String:
    if task_result.is_empty():
        return ""

    var proposal_keys: Array[String] = []
    var proposals = task_result.get("proposals", [])
    if proposals is Array:
        for index in range(proposals.size()):
            var proposal_data = proposals[index]
            if proposal_data is Dictionary:
                proposal_keys.append(_build_proposal_key(proposal_data, index))

    return JSON.stringify({
        "task_text": task_result.get("task_text", ""),
        "status": task_result.get("status", ""),
        "resolution": task_result.get("resolution", ""),
        "proposal_keys": proposal_keys
    })

func _build_proposal_key(proposal_data: Dictionary, index: int) -> String:
    var rule_package := _proposal_to_rule_package(proposal_data)
    if not rule_package.is_empty():
        return str(rule_package.get("package_id", "proposal_%d" % index))
    var identifier := _extract_identifier(proposal_data)
    return identifier if not identifier.is_empty() else "proposal_%d" % index

func _find_proposal_index_by_key(proposal_key: String) -> int:
    if proposal_key.is_empty():
        return -1
    for index in range(_proposal_cache.size()):
        var proposal_data = _proposal_cache[index]
        if proposal_data is Dictionary and _build_proposal_key(proposal_data, index) == proposal_key:
            return index
    return -1

func _format_proposal_option_label(proposal_data: Variant, index: int) -> String:
    if proposal_data is Dictionary:
        var rule_package := _proposal_to_rule_package(proposal_data)
        var label_source: Dictionary = rule_package if not rule_package.is_empty() else proposal_data
        var package_id := str(label_source.get("package_id", _build_proposal_key(proposal_data, index)))
        var display_name := str(label_source.get("display_name", label_source.get("name", package_id)))
        var review_status := str(label_source.get("patch", {}).get("review_status", proposal_data.get("review_status", "")))
        if review_status.is_empty():
            return "%s (%s)" % [display_name, package_id]
        return "%s (%s) — %s" % [display_name, package_id, review_status]
    return "提案 %d" % (index + 1)

func _proposal_editor_is_dirty() -> bool:
    return not _selected_proposal_original_text.is_empty() and _proposal_editor.text != _selected_proposal_original_text

func _proposal_requires_reapproval() -> bool:
    return not _approved_proposal_text.is_empty() and _approved_proposal_text != _proposal_editor.text

func _current_selected_proposal() -> Dictionary:
    if _selected_proposal_index < 0 or _selected_proposal_index >= _proposal_cache.size():
        return {}
    var proposal = _proposal_cache[_selected_proposal_index]
    return proposal.duplicate(true) if proposal is Dictionary else {}

func _proposal_to_rule_package(proposal_data: Dictionary) -> Dictionary:
    if _looks_like_rule_package(proposal_data):
        return proposal_data.duplicate(true)
    var nested_package = proposal_data.get("rule_package", {})
    if nested_package is Dictionary and _looks_like_rule_package(nested_package):
        return nested_package.duplicate(true)
    return {}

func _format_variant_for_text(value: Variant) -> String:
    if value is Dictionary or value is Array:
        return JSON.stringify(value, "	")
    return str(value)

func _append_log(message: String, payload: Variant = null) -> void:
    var log_entry := message
    if payload != null:
        log_entry += " | %s" % JSON.stringify(payload)
    _shell_log_lines.append(log_entry)
    _update_event_log_view()

func _simulate_task_submission(task_text: String) -> Dictionary:
    var task_history = _fallback_snapshot.get("player_task_history", [])
    var draft_package := {
        "schema_version": "rule_package_v1",
        "package_id": "fallback.custom_review",
        "display_name": "フォールバックのレビュー下書き",
        "description": task_text,
        "version": "0.1.0-draft",
        "author": "fallback-shell",
        "source_repo": "local://fallback-preview",
        "source_ref": "draft",
        "package_dependencies": [],
        "forked_from": {
            "package_id": "fallback.starter_farming",
            "source_repo": "local://fallback-preview",
            "source_ref": "main"
        },
        "suggested_pr_target": {
            "repo": "github.com/godot-world/rule-library",
            "base_ref": "main",
            "package_id": "fallback.custom_review"
        },
        "tags": ["fallback", "custom", "review"],
        "match_phrases": [task_text],
        "community": {
            "likes": 0,
            "dislikes": 0,
            "alternative_package_ids": []
        },
        "patch": {
            "format": "rule_patch_v1",
            "review_status": "needs_design_review",
            "operations": [
                {
                    "op": "upsert_stat",
                    "stat_id": "fallback_focus",
                    "value_type": "float",
                    "default": 25.0,
                    "min": 0.0,
                    "max": 100.0,
                    "ui_group": "custom"
                },
                {
                    "op": "upsert_rule",
                    "rule_id": "fallback.review_required",
                    "rule_type": "designer_review_required",
                    "design_prompt": task_text
                }
            ]
        }
    }
    var result := {
        "status": "needs_rule_patch",
        "resolution": "draft_custom_rule_patch",
        "task_text": task_text,
        "proposals": [{
            "package_id": draft_package.get("package_id", ""),
            "display_name": draft_package.get("display_name", ""),
            "description": draft_package.get("description", ""),
            "source_repo": draft_package.get("source_repo", ""),
            "source_ref": draft_package.get("source_ref", ""),
            "forked_from": draft_package.get("forked_from", null),
            "suggested_pr_target": draft_package.get("suggested_pr_target", null),
            "rule_package": draft_package.duplicate(true),
            "safe_to_apply_directly": false,
            "deferred_operations": draft_package.get("patch", {}).get("operations", []).duplicate(true)
        }],
        "workflow": {
            "review_status": "needs_design_review",
            "forked_from": draft_package.get("forked_from", null),
            "suggested_pr_target": draft_package.get("suggested_pr_target", null)
        },
        "message": "フォールバックが編集可能なルールパッケージ案を生成しました。"
    }
    if task_history is Array:
        task_history.append(result.duplicate(true))
        _fallback_snapshot["player_task_history"] = task_history
    _append_fallback_event("player_task_submitted", "プレイヤーが相談を送信しました。", {"task": task_text})
    return result

func _simulate_template_install(template_data: Variant) -> Dictionary:
    var template_id := _extract_identifier(template_data)
    var installed_rules: Dictionary = _fallback_snapshot.get("installed_rules", {})
    var template_name := template_id
    if template_data is Dictionary:
        template_name = str(template_data.get("name", template_id))

    var rule_patch := {
        "id": "rule_%s" % template_id,
        "name": template_name,
        "concept": template_id,
        "enabled": true,
        "effects": [
            {
                "component": "stats",
                "field": template_id,
                "op": "add",
                "default": 0.0,
                "value_per_second": 0.2,
                "min": 0.0,
                "max": 100.0
            }
        ]
    }
    rule_patch.merge(_build_fallback_rule_dependency_profile(template_id), true)
    installed_rules[rule_patch["id"]] = rule_patch
    _fallback_snapshot["installed_rules"] = _refresh_fallback_rule_dependencies(installed_rules)

    var concepts = _fallback_snapshot.get("concepts", [])
    if concepts is Array and not concepts.has(template_id):
        concepts.append(template_id)
        _fallback_snapshot["concepts"] = concepts

    _append_fallback_event("rule_installed", "フォールバックテンプレート '%s' を導入しました。" % template_id, {"rule_id": rule_patch["id"]})
    return {"status": "installed", "rule": rule_patch}

func _simulate_package_install(package_data: Variant) -> Dictionary:
    var package_id := _extract_identifier(package_data)
    var installed_rules: Dictionary = _fallback_snapshot.get("installed_rules", {})
    var package_name := package_id
    var package_version := ""
    var source_repo := ""
    var source_ref := ""
    if package_data is Dictionary:
        package_name = str(package_data.get("display_name", package_data.get("name", package_id)))
        package_version = str(package_data.get("version", ""))
        source_repo = str(package_data.get("source_repo", ""))
        source_ref = str(package_data.get("source_ref", ""))

    var rule_patch := {
        "id": "compiled_%s" % package_id.replace(".", "_"),
        "name": "%s (Compiled)" % package_name,
        "concept": package_id,
        "enabled": true,
        "metadata": {
            "package_id": package_id,
            "package_display_name": package_name,
            "package_version": package_version,
            "source_repo": source_repo,
            "source_ref": source_ref
        },
        "effects": [
            {
                "component": "stats",
                "field": package_id,
                "op": "add",
                "default": 0.0,
                "value_per_second": 0.2,
                "min": 0.0,
                "max": 100.0
            }
        ]
    }
    rule_patch.merge(_build_fallback_rule_dependency_profile(package_id), true)
    installed_rules[rule_patch["id"]] = rule_patch
    _fallback_snapshot["installed_rules"] = _refresh_fallback_rule_dependencies(installed_rules)

    var concepts = _fallback_snapshot.get("concepts", [])
    if concepts is Array and not concepts.has(package_id):
        concepts.append(package_id)
        _fallback_snapshot["concepts"] = concepts

    _append_fallback_event("rule_installed", "フォールバック提案 '%s' を導入しました。" % package_id, {"rule_id": rule_patch["id"]})
    return {"status": "installed", "rule": rule_patch}

func _set_selected_package_enabled(enabled: bool) -> void:
    var selected_items := _installed_package_list.get_selected_items()
    if selected_items.is_empty():
        _append_log("導入済みパッケージ未選択のまま状態変更しようとしました。")
        return

    var package_data = _installed_package_cache[selected_items[0]]
    var package_id := _extract_identifier(package_data)
    var result: Dictionary = {}
    if _world_state != null:
        var operation_type := "EnablePackage" if enabled else "DisablePackage"
        result = WorldOpDispatcherScript.dispatch(_world_state, operation_type, {"package_id": package_id}, {})
    else:
        result = _simulate_package_enabled(package_id, enabled)

    _refresh_all()
    _append_log("パッケージ状態を更新しました: %s" % package_id, result)
    var package_index := _find_package_index_by_id(package_id)
    if package_index != -1:
        _installed_package_list.deselect_all()
        _installed_package_list.select(package_index)
        _update_installed_package_details(package_index)
        _select_first_rule_for_package(package_id)

func _simulate_package_enabled(package_id: String, enabled: bool) -> Dictionary:
    var installed_rules: Dictionary = _fallback_snapshot.get("installed_rules", {})
    var changed_rule_ids: Array = []
    var matched_rule_ids: Array = []
    var rule_ids: Array = installed_rules.keys()
    rule_ids.sort()
    for rule_id in rule_ids:
        var rule_data: Dictionary = installed_rules.get(rule_id, {})
        if _extract_rule_package_id(rule_data) != package_id:
            continue
        matched_rule_ids.append(rule_id)
        var was_enabled := bool(rule_data.get("enabled", true))
        if was_enabled != enabled:
            changed_rule_ids.append(rule_id)
        rule_data["enabled"] = enabled
        installed_rules[rule_id] = rule_data

    if matched_rule_ids.is_empty():
        return {"status": "error", "message": "package not installed", "package_id": package_id}

    _fallback_snapshot["installed_rules"] = _refresh_fallback_rule_dependencies(installed_rules)
    _append_fallback_event(
        "rule_package_enabled" if enabled else "rule_package_disabled",
        "フォールバックパッケージ '%s' を%sしました。" % [package_id, "有効化" if enabled else "無効化"],
        {"package_id": package_id, "rule_ids": matched_rule_ids.duplicate(true), "changed_rule_ids": changed_rule_ids.duplicate(true)}
    )
    return {
        "status": "enabled" if enabled else "disabled",
        "package_id": package_id,
        "rule_ids": matched_rule_ids.duplicate(true),
        "changed_rule_ids": changed_rule_ids.duplicate(true)
    }

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
    cloned_rule["name"] = "%s (複製)" % str(cloned_rule.get("name", source_id))
    installed_rules[clone_id] = cloned_rule
    _fallback_snapshot["installed_rules"] = _refresh_fallback_rule_dependencies(installed_rules)

    _append_fallback_event("rule_cloned", "フォールバックルール '%s' を複製しました。" % source_id, {"clone_id": clone_id})
    return {"status": "cloned", "rule": cloned_rule}

func _build_fallback_rule_dependency_profile(template_id: String) -> Dictionary:
    match template_id:
        "starter-farming":
            return {
                "provides_rule_kinds": ["food.production", "settlement.foundation"]
            }
        "night-watch":
            return {
                "provides_rule_kinds": ["security.patrol"],
                "requires_rule_kinds": ["settlement.foundation"]
            }
        "shared-kitchen":
            return {
                "provides_rule_kinds": ["food.preparation"],
                "requires_rule_kinds": ["food.production"]
            }
    return {}

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

func _derive_installed_packages_from_rules(rules: Array) -> Array:
    var packages_by_id: Dictionary = {}
    for rule_data in rules:
        if not (rule_data is Dictionary):
            continue
        var package_id := _extract_rule_package_id(rule_data)
        if package_id.is_empty():
            continue
        if not packages_by_id.has(package_id):
            packages_by_id[package_id] = {
                "package_id": package_id,
                "display_name": str(rule_data.get("metadata", {}).get("package_display_name", package_id)),
                "version": str(rule_data.get("metadata", {}).get("package_version", "")),
                "source_repo": str(rule_data.get("metadata", {}).get("source_repo", "")),
                "source_ref": str(rule_data.get("metadata", {}).get("source_ref", "")),
                "rule_ids": [],
                "enabled_rule_count": 0,
                "disabled_rule_count": 0,
                "rule_count": 0
            }
        var package_data: Dictionary = packages_by_id[package_id]
        var rule_ids: Array = package_data.get("rule_ids", [])
        rule_ids.append(_extract_identifier(rule_data))
        rule_ids.sort()
        package_data["rule_ids"] = rule_ids
        package_data["rule_count"] = int(package_data.get("rule_count", 0)) + 1
        if bool(rule_data.get("enabled", true)):
            package_data["enabled_rule_count"] = int(package_data.get("enabled_rule_count", 0)) + 1
        else:
            package_data["disabled_rule_count"] = int(package_data.get("disabled_rule_count", 0)) + 1
        packages_by_id[package_id] = package_data

    var package_ids: Array = packages_by_id.keys()
    package_ids.sort()
    var packages: Array = []
    for package_id in package_ids:
        var package_data: Dictionary = packages_by_id[package_id]
        var enabled_rule_count := int(package_data.get("enabled_rule_count", 0))
        var rule_count := int(package_data.get("rule_count", 0))
        var state := "disabled"
        if rule_count > 0 and enabled_rule_count == rule_count:
            state = "enabled"
        elif enabled_rule_count > 0:
            state = "mixed"
        package_data["state"] = state
        package_data["enabled"] = enabled_rule_count > 0
        package_data["all_rules_enabled"] = rule_count > 0 and enabled_rule_count == rule_count
        packages.append(package_data)
    return packages

func _extract_rule_package_id(rule_data: Variant) -> String:
    if rule_data is Dictionary:
        return str(rule_data.get("metadata", {}).get("package_id", ""))
    return ""

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
        for rule_data in _extract_installed_rules(_fallback_snapshot):
            if not (rule_data is Dictionary):
                continue
            if not bool(rule_data.get("enabled", true)):
                continue
            for effect in rule_data.get("effects", []):
                if effect is Dictionary and String(effect.get("component", "")) == "stats":
                    var field_name := String(effect.get("field", "value"))
                    stats[field_name] = min(
                        float(stats.get(field_name, effect.get("default", 0.0))) + float(effect.get("value_per_second", 0.0)) * delta_seconds,
                        float(effect.get("max", 100.0))
                    )
        components["stats"] = stats
        entity["components"] = components
        entities[entity_id] = entity
    _fallback_snapshot["entities"] = entities
    _update_fallback_three_d_preview(delta_seconds)

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

func _update_fallback_three_d_preview(delta_seconds: float) -> void:
    var preview_data = _fallback_snapshot.get("three_d_preview", {})
    if not (preview_data is Dictionary):
        return

    var gravity_data: Variant = preview_data.get("gravity", {})
    var floor_y := float(gravity_data.get("floor_y", 0.0)) if gravity_data is Dictionary else 0.0
    var renderables = preview_data.get("renderables", [])
    if not (renderables is Array):
        return

    for index in range(renderables.size()):
        var renderable = renderables[index]
        if not (renderable is Dictionary):
            continue

        var flags := _variant_to_string_array(renderable.get("flags", []))
        var is_falling := flags.has("falling") or str(renderable.get("id", "")).findn("jar") != -1
        if not is_falling:
            continue

        var size: Variant = renderable.get("size", [1.0, 1.0, 1.0])
        var size_y := float(size[1]) if size is Array and size.size() >= 2 else 1.0
        var position: Variant = renderable.get("position", [0.0, floor_y + size_y * 0.5, 0.0])
        if position is Array and position.size() >= 3:
            var next_y := float(position[1]) - delta_seconds * 1.5
            position[1] = max(floor_y + size_y * 0.5, next_y)
            if is_equal_approx(float(position[1]), floor_y + size_y * 0.5):
                position[1] = floor_y + size_y * 0.5 + 2.6
            renderable["position"] = position
            renderables[index] = renderable

    preview_data["renderables"] = renderables
    _fallback_snapshot["three_d_preview"] = preview_data
