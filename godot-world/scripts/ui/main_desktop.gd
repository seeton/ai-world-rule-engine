extends Control

const ThreeDPreviewRendererScript = preload("res://scripts/ui/three_d_preview_renderer.gd")
const FALLBACK_RULE_PACKAGES: Array = [
    {
        "package_id": "fallback.starter_farming",
        "display_name": "Starter Farming",
        "description": "Adds a simple farming routine for idle villagers."
    },
    {
        "package_id": "fallback.night_watch",
        "display_name": "Night Watch",
        "description": "Schedules a guard patrol after dusk."
    },
    {
        "package_id": "fallback.shared_kitchen",
        "display_name": "Shared Kitchen",
        "description": "Introduces communal meal prep and cleanup."
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
    "container_id": {"forward": "in", "reverse": "contains"},
    "equipped_by_entity_id": {"forward": "equipped by", "reverse": "equips"},
    "held_by_entity_id": {"forward": "held by", "reverse": "holds"},
    "holder_id": {"forward": "held by", "reverse": "holds"},
    "home_entity_id": {"forward": "home", "reverse": "home for"},
    "location_id": {"forward": "at", "reverse": "hosts"},
    "owned_by_entity_id": {"forward": "owned by", "reverse": "owns"},
    "owner_entity_id": {"forward": "owned by", "reverse": "owns"},
    "owner_id": {"forward": "owned by", "reverse": "owns"},
    "parent_entity_id": {"forward": "child of", "reverse": "children"},
    "parent_id": {"forward": "child of", "reverse": "children"}
}
const ENTITY_COLLECTION_FIELDS: Dictionary = {
    "child_entity_ids": {"forward": "children", "reverse": "child of"},
    "contained_entity_ids": {"forward": "contains", "reverse": "in"},
    "equipped_entity_ids": {"forward": "equips", "reverse": "equipped by"},
    "inventory_entity_ids": {"forward": "inventory", "reverse": "carried by"},
    "inventory_ids": {"forward": "inventory", "reverse": "carried by"},
    "occupant_entity_ids": {"forward": "hosts", "reverse": "at"},
    "owned_entity_ids": {"forward": "owns", "reverse": "owned by"}
}
const CHARACTER_ARCHETYPE_HINTS: Array = ["actor", "character", "npc", "origin", "person", "villager"]
const CHARACTER_TAG_HINTS: Array = ["agent", "character", "human", "mortal", "npc", "person", "villager"]
const OBJECT_ARCHETYPE_HINTS: Array = ["container", "item", "location", "object", "place", "prop", "resource", "structure", "tool"]
const OBJECT_TAG_HINTS: Array = ["container", "item", "location", "object", "portable", "prop", "resource", "structure", "tool"]

var _world_state: Node = null
var _task_input: TextEdit
var _proposal_selector: OptionButton
var _proposal_review_summary_label: Label
var _proposal_metadata_view: TextEdit
var _proposal_editor: TextEdit
var _reset_proposal_button: Button
var _approve_proposal_button: Button
var _install_proposal_button: Button
var _package_list: ItemList
var _install_package_button: Button
var _tick_amount: SpinBox
var _installed_rule_tree: Tree
var _installed_rule_list: ItemList
var _clone_rule_button: Button
var _installed_rule_details_view: TextEdit
var _entity_tree: Tree
var _world_state_view: TextEdit
var _event_log_view: TextEdit
var _status_label: Label
var _three_d_preview_renderer: Control

var _available_package_cache: Array = []
var _installed_rule_cache: Array = []
var _latest_task_result: Dictionary = {}
var _proposal_cache: Array = []
var _proposal_signature: String = ""
var _selected_proposal_index: int = -1
var _loaded_proposal_key: String = ""
var _selected_proposal_original_text := ""
var _approved_proposal_text := ""
var _current_proposal_review: Dictionary = {}
var _is_updating_proposal_editor := false
var _snapshot_cache: Dictionary = {}
var _shell_log_lines: Array[String] = []
var _fallback_snapshot: Dictionary = {
    "world_id": "fallback-world",
    "runtime_choice": "desktop-shell-preview",
    "elapsed_seconds": 0.0,
    "tick_index": 0,
    "concepts": [],
    "installed_rules": {},
    "entities": {
        "aria": {
            "id": "aria",
            "name": "Aria",
            "archetype": "villager",
            "tags": ["mortal", "mutable"],
            "components": {
                "behavior": {
                    "current_task": "Sorting gathered supplies"
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
            "name": "Tool Satchel",
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
            "name": "Berry Bundle",
            "archetype": "item",
            "tags": ["food", "object"],
            "container_id": "tool_satchel",
            "components": {
                "state": {
                    "freshness": "picked",
                    "servings": 3
                }
            }
        },
        "storehouse": {
            "id": "storehouse",
            "name": "Storehouse",
            "archetype": "structure",
            "tags": ["location", "object", "structure"],
            "components": {
                "state": {
                    "condition": "dry",
                    "status": "stocked"
                }
            }
        },
        "water_jar": {
            "id": "water_jar",
            "name": "Water Jar",
            "archetype": "item",
            "tags": ["container", "object"],
            "location_id": "storehouse",
            "owner_id": "aria",
            "components": {
                "state": {
                    "fill": "half",
                    "sealed": true
                }
            }
        }
    },
    "event_log": [
        {
            "type": "world_initialized",
            "message": "Desktop shell fallback active.",
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
                "name": "Aria",
                "kind": "character",
                "flags": ["character"],
                "position": [0.0, 0.9, 0.4],
                "size": [0.9, 1.8, 0.9],
                "color": "#4fb8f7"
            },
            {
                "id": "storehouse",
                "name": "Storehouse",
                "kind": "object",
                "position": [2.8, 1.1, 0.0],
                "size": [2.6, 2.2, 2.6],
                "color": "#be9a66"
            },
            {
                "id": "water_jar",
                "name": "Water Jar",
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
    _append_log("UI shell ready.", {"world_state_connected": _world_state != null})

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
    title.text = "World Desktop Shell"
    title.add_theme_font_size_override("font_size", 24)
    header.add_child(title)

    var subtitle := Label.new()
    subtitle.text = "Submit tasks, install rule packages, clone installed rules, inspect state, and step the simulation."
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
    left_column.add_child(_build_proposal_panel())
    left_column.add_child(_build_package_panel())
    left_column.add_child(_build_tick_panel())

    var right_column := VBoxContainer.new()
    right_column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    right_column.size_flags_vertical = Control.SIZE_EXPAND_FILL
    right_column.add_theme_constant_override("separation", 12)
    split.add_child(right_column)

    right_column.add_child(_build_installed_rules_panel())
    right_column.add_child(_build_three_d_preview_panel())
    right_column.add_child(_build_world_state_panel())
    right_column.add_child(_build_text_panel("Event Log", "Recent world events plus desktop shell actions.", "event_log", 170))

func _build_task_panel() -> Control:
    var panel := _make_panel_section("Player Task", "Describe what the player wants the settlement to do next.")
    var body := panel.get_meta("body") as VBoxContainer

    _task_input = TextEdit.new()
    _task_input.custom_minimum_size = Vector2(0, 110)
    _task_input.placeholder_text = "Example: Add a hunger rule and ask Aria to gather berries."
    _task_input.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
    body.add_child(_task_input)

    var button_row := HBoxContainer.new()
    button_row.add_theme_constant_override("separation", 8)
    body.add_child(button_row)

    var submit_button := Button.new()
    submit_button.text = "Submit Task"
    submit_button.pressed.connect(_on_submit_pressed)
    button_row.add_child(submit_button)

    var refresh_button := Button.new()
    refresh_button.text = "Refresh Snapshot"
    refresh_button.pressed.connect(_refresh_all)
    button_row.add_child(refresh_button)

    return panel

func _build_proposal_panel() -> Control:
    var panel := _make_panel_section("Proposal Review", "Inspect the latest task proposal, edit the rule package JSON, approve it, and then install it.")
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
    _reset_proposal_button.text = "Reset Draft"
    _reset_proposal_button.disabled = true
    _reset_proposal_button.pressed.connect(_on_reset_proposal_pressed)
    action_row.add_child(_reset_proposal_button)

    _approve_proposal_button = Button.new()
    _approve_proposal_button.text = "Approve Draft"
    _approve_proposal_button.disabled = true
    _approve_proposal_button.pressed.connect(_on_approve_proposal_pressed)
    action_row.add_child(_approve_proposal_button)

    _install_proposal_button = Button.new()
    _install_proposal_button.text = "Install Approved Draft"
    _install_proposal_button.disabled = true
    _install_proposal_button.pressed.connect(_on_install_proposal_pressed)
    action_row.add_child(_install_proposal_button)

    _proposal_editor = TextEdit.new()
    _proposal_editor.custom_minimum_size = Vector2(0, 220)
    _proposal_editor.placeholder_text = "Submit a task to load a proposal here, then review and edit the package JSON."
    _proposal_editor.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
    _proposal_editor.text_changed.connect(_on_proposal_editor_changed)
    body.add_child(_proposal_editor)

    return panel

func _build_package_panel() -> Control:
    var panel := _make_panel_section("Install Rule Package", "Pick an available package from the catalog and install it into the current world.")
    var body := panel.get_meta("body") as VBoxContainer

    _package_list = ItemList.new()
    _package_list.custom_minimum_size = Vector2(0, 180)
    _package_list.select_mode = ItemList.SELECT_SINGLE
    _package_list.item_selected.connect(_on_package_selected)
    body.add_child(_package_list)

    _install_package_button = Button.new()
    _install_package_button.text = "Install Selected Package"
    _install_package_button.disabled = true
    _install_package_button.pressed.connect(_on_install_package_pressed)
    body.add_child(_install_package_button)

    return panel

func _build_tick_panel() -> Control:
    var panel := _make_panel_section("Simulation Controls", "Advance time manually to observe rule-driven stat changes.")
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
    tick_button.text = "Advance Tick"
    tick_button.pressed.connect(_on_tick_pressed)
    row.add_child(tick_button)

    return panel

func _build_installed_rules_panel() -> Control:
    var panel := _make_panel_section("Installed Rules", "Review active rules, inspect details, inspect PoC2 parent/child relationships, and clone the selected installed rule.")
    var body := panel.get_meta("body") as VBoxContainer

    var tree_label := Label.new()
    tree_label.text = "Dependency Tree"
    body.add_child(tree_label)

    _installed_rule_tree = Tree.new()
    _installed_rule_tree.columns = 2
    _installed_rule_tree.column_titles_visible = true
    _installed_rule_tree.hide_root = true
    _installed_rule_tree.custom_minimum_size = Vector2(0, 170)
    _installed_rule_tree.size_flags_vertical = Control.SIZE_EXPAND_FILL
    _installed_rule_tree.set_column_title(0, "Rule")
    _installed_rule_tree.set_column_title(1, "Parent / dependency state")
    _installed_rule_tree.item_selected.connect(_on_rule_tree_selected)
    body.add_child(_installed_rule_tree)

    var list_label := Label.new()
    list_label.text = "Flat Inspection List"
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
    _clone_rule_button.text = "Clone Selected Rule"
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
    var panel := _make_panel_section("World & Object State", "Groups characters and objects, highlights ownership/containment, and keeps a text summary of the current snapshot.")
    var body := panel.get_meta("body") as VBoxContainer

    var tree_label := Label.new()
    tree_label.text = "Entity Ownership Tree"
    body.add_child(tree_label)

    _entity_tree = Tree.new()
    _entity_tree.columns = 2
    _entity_tree.column_titles_visible = true
    _entity_tree.hide_root = true
    _entity_tree.custom_minimum_size = Vector2(0, 180)
    _entity_tree.size_flags_vertical = Control.SIZE_EXPAND_FILL
    _entity_tree.set_column_title(0, "Entity")
    _entity_tree.set_column_title(1, "State / ownership")
    body.add_child(_entity_tree)

    var summary_label := Label.new()
    summary_label.text = "Snapshot Summary"
    body.add_child(summary_label)

    _world_state_view = TextEdit.new()
    _world_state_view.editable = false
    _world_state_view.custom_minimum_size = Vector2(0, 120)
    _world_state_view.size_flags_vertical = Control.SIZE_EXPAND_FILL
    _world_state_view.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
    body.add_child(_world_state_view)

    return panel

func _build_three_d_preview_panel() -> Control:
    var panel := _make_panel_section(
        "3D Preview",
        "Embeds an experimental 3D world view using snapshot[\"three_d_preview\"] renderables, lighting, gravity, and camera hints."
    )
    panel.size_flags_vertical = Control.SIZE_FILL
    var body := panel.get_meta("body") as VBoxContainer

    _three_d_preview_renderer = ThreeDPreviewRendererScript.new()
    _three_d_preview_renderer.custom_minimum_size = Vector2(0, 280)
    _three_d_preview_renderer.size_flags_vertical = Control.SIZE_FILL
    body.add_child(_three_d_preview_renderer)
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
    _refresh_available_packages()
    _refresh_snapshot()
    _latest_task_result = _extract_latest_task_result(_snapshot_cache)
    _proposal_cache = _extract_task_proposals(_latest_task_result)
    _installed_rule_cache = _extract_installed_rules(_snapshot_cache)
    _update_package_list()
    _update_proposal_panel()
    _update_installed_rules_panel()
    _update_three_d_preview()
    _update_world_state_view()
    _update_event_log_view()
    _update_status_label()

func _refresh_world_state_reference() -> void:
    _world_state = get_node_or_null("/root/WorldState")

func _refresh_available_packages() -> void:
    if _world_state != null:
        if _world_state.has_method("get_available_rule_packages"):
            var packages = _world_state.call("get_available_rule_packages")
            _available_package_cache = packages if packages is Array else []
            return

        if _world_state.has_method("get_available_rule_templates"):
            var legacy_packages = _world_state.call("get_available_rule_templates")
            _available_package_cache = legacy_packages if legacy_packages is Array else []
            return

    _available_package_cache = FALLBACK_RULE_PACKAGES.duplicate(true)

func _refresh_snapshot() -> void:
    if _world_state != null and _world_state.has_method("get_world_snapshot"):
        var snapshot = _world_state.call("get_world_snapshot")
        _snapshot_cache = snapshot if snapshot is Dictionary else {}
    else:
        _snapshot_cache = _fallback_snapshot.duplicate(true)

func _update_package_list() -> void:
    _package_list.clear()
    for package_data in _available_package_cache:
        _package_list.add_item(_format_package_label(package_data))
    _install_package_button.disabled = _available_package_cache.is_empty()
    if not _available_package_cache.is_empty():
        _package_list.select(0)

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
        _selected_proposal_index = -1
        _loaded_proposal_key = ""
        _selected_proposal_original_text = ""
        _approved_proposal_text = ""
        _current_proposal_review = {}
        _proposal_review_summary_label.text = "No task proposals yet. Submit a task to open the review flow."
        _proposal_metadata_view.text = "The latest task result will appear here with clone/fork metadata, deferred-operation warnings, and install readiness."
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
    var proposal := _current_selected_proposal()
    _loaded_proposal_key = _build_proposal_key(proposal, _selected_proposal_index)
    _approved_proposal_text = ""

    var rule_package := _proposal_to_rule_package(proposal)
    if rule_package.is_empty():
        _selected_proposal_original_text = ""
        _current_proposal_review = {
            "status": "error",
            "message": "Selected proposal does not include editable rule package data."
        }
        _set_proposal_editor_text("")
        _update_proposal_views()
        return

    var proposal_text := JSON.stringify(rule_package, "\t")
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
            _append_log("Proposal review failed.", parsed_result)
        return parsed_result

    var rule_package: Dictionary = parsed_result.get("rule_package", {})
    if _world_state != null and _world_state.has_method("review_rule_package_proposal"):
        var review_result = _world_state.call("review_rule_package_proposal", rule_package)
        if review_result is Dictionary:
            if append_errors and String(review_result.get("status", "")) == "error":
                _append_log("Proposal review failed.", review_result)
            return review_result
    return _build_local_proposal_review(rule_package)

func _parse_editor_rule_package() -> Dictionary:
    var raw_text := _proposal_editor.text.strip_edges()
    if raw_text.is_empty():
        return {
            "status": "error",
            "message": "Proposal editor is empty."
        }

    var parser := JSON.new()
    var parse_result := parser.parse(raw_text)
    if parse_result != OK:
        return {
            "status": "error",
            "message": "Proposal JSON is invalid.",
            "line": parser.get_error_line(),
            "details": parser.get_error_message()
        }
    if not (parser.data is Dictionary):
        return {
            "status": "error",
            "message": "Proposal JSON must decode to a dictionary."
        }
    return {
        "status": "parsed",
        "rule_package": parser.data
    }

func _build_local_proposal_review(rule_package: Dictionary) -> Dictionary:
    if rule_package.is_empty():
        return {
            "status": "error",
            "message": "Rule package was empty."
        }
    if not _looks_like_rule_package(rule_package):
        return {
            "status": "error",
            "message": "Rule package is missing the expected schema or patch fields.",
            "rule_package": rule_package.duplicate(true)
        }

    var patch = rule_package.get("patch", {})
    var operations = patch.get("operations", [])
    if not (operations is Array):
        return {
            "status": "error",
            "message": "Rule package patch operations must be an array.",
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
        warnings.append("Rule package has no operations to install.")
    if not deferred_operations.is_empty():
        warnings.append("Some operations are deferred until runtime support exists.")

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
        _proposal_review_summary_label.text = "No proposal selected."
        _proposal_metadata_view.text = "Select a proposal to review."
        _reset_proposal_button.disabled = true
        _approve_proposal_button.disabled = true
        _install_proposal_button.disabled = true
        return

    var rule_package := _proposal_to_rule_package(proposal)
    var review_status := String(_current_proposal_review.get("review_status", ""))
    if review_status.is_empty() and not rule_package.is_empty():
        review_status = String(rule_package.get("patch", {}).get("review_status", "draft"))

    var summary_segments: Array[String] = []
    summary_segments.append("Latest task: %s" % str(_latest_task_result.get("status", "proposal_ready")))
    summary_segments.append("Review: %s" % (review_status if not review_status.is_empty() else "unavailable"))
    if _proposal_editor_is_dirty():
        summary_segments.append("edited")
    if _proposal_requires_reapproval():
        summary_segments.append("re-approval required")
    if String(_current_proposal_review.get("status", "")) == "error":
        summary_segments.append("fix proposal JSON")
    _proposal_review_summary_label.text = " | ".join(summary_segments)

    var metadata_lines: Array[String] = []
    metadata_lines.append("Task: %s" % str(_latest_task_result.get("task_text", "(none)")))
    metadata_lines.append("Resolution: %s" % str(_latest_task_result.get("resolution", _latest_task_result.get("status", "unknown"))))
    metadata_lines.append("Message: %s" % str(_latest_task_result.get("message", "No summary provided.")))
    if not rule_package.is_empty():
        metadata_lines.append("")
        metadata_lines.append("Package: %s" % str(rule_package.get("package_id", "")))
        metadata_lines.append("Display name: %s" % str(rule_package.get("display_name", "")))
        metadata_lines.append("Description: %s" % str(rule_package.get("description", "")))
        metadata_lines.append("Source: %s @ %s" % [
            str(rule_package.get("source_repo", "")),
            str(rule_package.get("source_ref", ""))
        ])
        metadata_lines.append("Forked from: %s" % _format_variant_for_text(rule_package.get("forked_from", null)))
        metadata_lines.append("Suggested PR target: %s" % _format_variant_for_text(rule_package.get("suggested_pr_target", null)))
        metadata_lines.append("Tags: %s" % _format_variant_for_text(rule_package.get("tags", [])))
        metadata_lines.append("Community: %s" % _format_variant_for_text(rule_package.get("community", {})))
    else:
        metadata_lines.append("")
        metadata_lines.append("This proposal does not include full package JSON, so it cannot be edited or installed from the review panel.")

    if _current_proposal_review.has("operation_count"):
        metadata_lines.append("Operations: %s" % str(_current_proposal_review.get("operation_count", 0)))
    if _current_proposal_review.has("safe_to_apply_directly"):
        metadata_lines.append("Safe to apply directly: %s" % str(_current_proposal_review.get("safe_to_apply_directly", false)))
    if _current_proposal_review.has("deferred_operations"):
        var deferred_operations = _current_proposal_review.get("deferred_operations", [])
        if deferred_operations is Array and not deferred_operations.is_empty():
            metadata_lines.append("Deferred operations (%d): %s" % [
                deferred_operations.size(),
                JSON.stringify(deferred_operations, "\t")
            ])

    var warnings = _current_proposal_review.get("warnings", [])
    if warnings is Array and not warnings.is_empty():
        metadata_lines.append("Warnings: %s" % _format_variant_for_text(warnings))

    if _latest_task_result.has("workflow"):
        metadata_lines.append("Workflow: %s" % _format_variant_for_text(_latest_task_result.get("workflow", {})))

    if String(_current_proposal_review.get("status", "")) == "error":
        metadata_lines.append("Review error: %s" % str(_current_proposal_review.get("message", "Unknown review error.")))
    elif _proposal_requires_reapproval():
        metadata_lines.append("Approval state: the editor content changed after approval. Approve again before installing.")
    elif not _approved_proposal_text.is_empty():
        metadata_lines.append("Approval state: current editor content is approved for install.")
    elif review_status == "approved":
        metadata_lines.append("Approval state: press Approve Draft to confirm this package before installing it from the shell.")

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
    return "Proposal %d" % (index + 1)

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

func _update_installed_rules_panel() -> void:
    _installed_rule_list.clear()
    for rule_data in _installed_rule_cache:
        _installed_rule_list.add_item(_format_rule_list_label(rule_data))
    _update_installed_rule_tree()

    var has_rules := not _installed_rule_cache.is_empty()
    _clone_rule_button.disabled = not has_rules
    if not has_rules:
        _installed_rule_details_view.text = "No rules installed yet. Install a package to seed the world, then use the dependency tree to inspect resolved parents or unmet required parent kinds."
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
    summary_lines.append("Rule: %s" % _format_rule_list_label(rule_data))

    var resolved_parent_ids: Array = dependency_model.get("resolved_parents_by_rule", {}).get(rule_id, [])
    summary_lines.append("Resolved parents: %s" % [
        _format_rule_reference_list(resolved_parent_ids, dependency_model) if not resolved_parent_ids.is_empty() else "none"
    ])

    var child_ids: Array = dependency_model.get("children_by_parent", {}).get(rule_id, [])
    summary_lines.append("Child rules: %s" % [
        _format_rule_reference_list(child_ids, dependency_model) if not child_ids.is_empty() else "none"
    ])

    var provided_kinds := _extract_rule_provided_kinds(rule_data)
    if not provided_kinds.is_empty():
        summary_lines.append("Provides kinds: %s" % _join_values(provided_kinds))

    var required_kinds := _extract_rule_required_kinds(rule_data)
    if not required_kinds.is_empty():
        summary_lines.append("Requires parent kinds: %s" % _join_values(required_kinds))

    var unresolved_kinds := _get_rule_unresolved_required_kinds(rule_id, dependency_model)
    if unresolved_kinds.is_empty():
        summary_lines.append("Parent requirement status: all resolved or not declared")
    else:
        summary_lines.append("Unmet required parent kinds:")
        for required_kind in unresolved_kinds:
            var candidate_ids := Array(dependency_model.get("providers_by_kind", {}).get(required_kind, []))
            if candidate_ids.is_empty():
                summary_lines.append("- %s (no installed provider)" % required_kind)
            else:
                summary_lines.append("- %s (candidate providers: %s)" % [
                    required_kind,
                    _format_rule_reference_list(candidate_ids, dependency_model)
                ])

    _clone_rule_button.disabled = false
    summary_lines.append("")
    summary_lines.append("Raw JSON:")
    summary_lines.append(JSON.stringify(rule_data, "	"))
    _installed_rule_details_view.text = "\n".join(summary_lines)

func _update_world_state_view() -> void:
    if _snapshot_cache.is_empty():
        _update_entity_tree([], {})
        _world_state_view.text = "World snapshot unavailable."
        return

    var lines: Array[String] = []
    var entities := _extract_entities(_snapshot_cache)
    var entity_model := _build_entity_relationship_model(entities)
    _update_entity_tree(entities, entity_model)

    lines.append("World: %s" % [str(_snapshot_cache.get("world_id", _snapshot_cache.get("world_name", "unknown")))])
    lines.append("Runtime: %s" % [str(_snapshot_cache.get("runtime_choice", "n/a"))])
    lines.append("Tick: %s" % [str(_snapshot_cache.get("tick_index", _snapshot_cache.get("tick", "?")))])
    lines.append("Elapsed seconds: %s" % [str(_snapshot_cache.get("elapsed_seconds", 0.0))])
    var preview_summary: Variant = _snapshot_cache.get("three_d_preview", null)
    if preview_summary is Dictionary:
        var renderable_count := 0
        var renderables = preview_summary.get("renderables", [])
        if renderables is Array:
            renderable_count = renderables.size()
        lines.append("3D preview: %s (%d renderables)" % [
            "enabled" if bool(preview_summary.get("enabled", false)) else "disabled",
            renderable_count
        ])
    else:
        lines.append("3D preview: not reported in snapshot")
    if _snapshot_cache.has("concepts"):
        lines.append("Concepts: %s" % [_join_values(Array(_snapshot_cache.get("concepts", [])))])

    lines.append("")
    lines.append("Ownership & containment:")
    var relationship_lines := _build_entity_relationship_summary_lines(entity_model)
    if relationship_lines.is_empty():
        lines.append("- No ownership or containment links reported.")
    else:
        for relationship_line in relationship_lines:
            lines.append(str(relationship_line))

    lines.append("")
    lines.append("Characters & agents:")
    var character_entities := _filter_entities_by_kind(entities, true)
    if character_entities.is_empty():
        lines.append("- No character-style entities reported.")
    else:
        for entity_data in character_entities:
            lines.append(_format_entity_summary(entity_data, entity_model))

    lines.append("")
    lines.append("Objects & world entities:")
    var object_entities := _filter_entities_by_kind(entities, false)
    if object_entities.is_empty():
        lines.append("- No object-style entities reported.")
    else:
        for entity_data in object_entities:
            lines.append(_format_entity_summary(entity_data, entity_model))

    lines.append("")
    lines.append("All entities: %d" % entities.size())
    if entities.is_empty():
        lines.append("- No entities reported.")

    var task_history = _snapshot_cache.get("player_task_history", [])
    if task_history is Array and not task_history.is_empty():
        lines.append("")
        lines.append("Recent task result:")
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
        lines.append("World events:")
        for event_data in _take_last_entries(world_events, 8):
            lines.append(_format_event_entry(event_data))

    if not _shell_log_lines.is_empty():
        if not lines.is_empty():
            lines.append("")
        lines.append("Desktop shell actions:")
        for log_line in _take_last_entries(_shell_log_lines, 8):
            lines.append(str(log_line))

    _event_log_view.text = "\n".join(lines) if not lines.is_empty() else "No events yet."
    _event_log_view.scroll_vertical = _event_log_view.get_line_count()

func _update_status_label() -> void:
    var source := "WorldState autoload" if _world_state != null else "fallback preview"
    _status_label.text = "Data source: %s | Packages: %d | Installed rules: %d" % [source, _available_package_cache.size(), _installed_rule_cache.size()]

func _on_submit_pressed() -> void:
    var task_text := _task_input.text.strip_edges()
    if task_text.is_empty():
        _append_log("Ignored empty task submission.")
        return

    var result: Dictionary = {}
    if _world_state != null and _world_state.has_method("submit_player_task"):
        result = _world_state.call("submit_player_task", task_text)
    else:
        result = _simulate_task_submission(task_text)

    _task_input.clear()
    _refresh_all()
    _append_log("Submitted task: %s" % task_text, result)

func _on_proposal_selected(index: int) -> void:
    _selected_proposal_index = index
    _load_selected_proposal_into_editor()

func _on_proposal_editor_changed() -> void:
    if _is_updating_proposal_editor:
        return
    _current_proposal_review = _refresh_current_proposal_review(false)
    _update_proposal_views()

func _on_reset_proposal_pressed() -> void:
    if _selected_proposal_original_text.is_empty():
        _append_log("Reset requested without an editable proposal.")
        return

    _set_proposal_editor_text(_selected_proposal_original_text)
    _current_proposal_review = _refresh_current_proposal_review(false)
    _approved_proposal_text = _proposal_editor.text if String(_current_proposal_review.get("review_status", "")) == "approved" else ""
    _update_proposal_views()
    _append_log("Reset proposal editor to the selected draft.", {
        "package_id": _current_proposal_review.get("package_id", _build_proposal_key(_current_selected_proposal(), _selected_proposal_index))
    })

func _on_approve_proposal_pressed() -> void:
    var parsed_result := _parse_editor_rule_package()
    if String(parsed_result.get("status", "")) == "error":
        _append_log("Proposal approval failed.", parsed_result)
        _current_proposal_review = parsed_result
        _update_proposal_views()
        return

    var rule_package: Dictionary = parsed_result.get("rule_package", {}).duplicate(true)
    var patch = rule_package.get("patch", {})
    if not (patch is Dictionary):
        var error_result := {
            "status": "error",
            "message": "Rule package patch must be a dictionary before approval."
        }
        _append_log("Proposal approval failed.", error_result)
        _current_proposal_review = error_result
        _update_proposal_views()
        return

    patch["review_status"] = "approved"
    rule_package["patch"] = patch
    _set_proposal_editor_text(JSON.stringify(rule_package, "\t"))
    _current_proposal_review = _refresh_current_proposal_review(true)
    if String(_current_proposal_review.get("status", "")) == "error":
        _update_proposal_views()
        return

    _approved_proposal_text = _proposal_editor.text
    _update_proposal_views()
    _append_log("Approved proposal for installation.", {
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
        _append_log("Install blocked until the proposal is approved.", {
            "package_id": _current_proposal_review.get("package_id", ""),
            "review_status": _current_proposal_review.get("review_status", "draft")
        })
        _update_proposal_views()
        return
    if _approved_proposal_text.is_empty():
        _append_log("Install blocked until the shell approval step is completed.", {
            "package_id": _current_proposal_review.get("package_id", "")
        })
        _update_proposal_views()
        return
    if _proposal_requires_reapproval():
        _append_log("Install blocked because the proposal changed after approval.", {
            "package_id": _current_proposal_review.get("package_id", "")
        })
        _update_proposal_views()
        return

    var parsed_result := _parse_editor_rule_package()
    if String(parsed_result.get("status", "")) == "error":
        _append_log("Proposal install failed before reaching the runtime.", parsed_result)
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
    _append_log("Installed reviewed proposal: %s" % package_id, result)

func _on_install_package_pressed() -> void:
    var selected_items := _package_list.get_selected_items()
    if selected_items.is_empty():
        _append_log("Install requested without a selected package.")
        return

    var package_data = _available_package_cache[selected_items[0]]
    var package_id := _extract_identifier(package_data)
    if package_id.is_empty():
        _append_log("Install requested for a package without an identifier.", package_data)
        return

    var result: Dictionary = {}
    if _world_state != null and _world_state.has_method("create_rule_from_patch"):
        var install_request: Variant = package_data if package_data is Dictionary else {"package_id": package_id}
        result = _world_state.call("create_rule_from_patch", install_request)
    elif _world_state != null and _world_state.has_method("clone_rule"):
        result = _world_state.call("clone_rule", package_id)
    else:
        result = _simulate_package_install(package_data)

    _refresh_all()
    _append_log("Installed package: %s" % package_id, result)

func _on_clone_rule_pressed() -> void:
    var selected_items := _installed_rule_list.get_selected_items()
    if selected_items.is_empty():
        _append_log("Clone requested without a selected installed rule.")
        return

    var rule_data = _installed_rule_cache[selected_items[0]]
    var rule_id := _extract_identifier(rule_data)
    var result: Dictionary = {}
    if _world_state != null and _world_state.has_method("clone_rule"):
        result = _world_state.call("clone_rule", rule_id)
    else:
        result = _simulate_rule_clone(rule_data)

    _refresh_all()
    _append_log("Cloned installed rule: %s" % rule_id, result)

func _on_tick_pressed() -> void:
    var delta_seconds := _tick_amount.value
    if _world_state != null and _world_state.has_method("advance_tick"):
        _world_state.call("advance_tick", delta_seconds)
        _refresh_all()
        _append_log("Advanced simulation tick.", {"delta_seconds": delta_seconds})
        return

    var result := _simulate_tick(delta_seconds)
    _refresh_all()
    _append_log("Advanced fallback simulation tick.", result)

func _on_package_selected(_index: int) -> void:
    _install_package_button.disabled = _package_list.get_selected_items().is_empty()

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
        for key in ["package_id", "id", "rule_id", "template_id", "display_name", "name", "title"]:
            if data.has(key):
                return str(data.get(key))
    return str(data)

func _format_package_label(package_data: Variant) -> String:
    if package_data is Dictionary:
        var package_id := str(package_data.get("package_id", _extract_identifier(package_data)))
        var package_name := str(package_data.get("display_name", package_data.get("name", package_id)))
        var description := str(package_data.get("description", package_data.get("summary", "Ready to install")))
        if not package_id.is_empty() and package_name != package_id:
            return "%s (%s) — %s" % [package_name, package_id, description]
        return "%s — %s" % [package_name, description]
    return str(package_data)

func _format_rule_list_label(rule_data: Variant) -> String:
    if rule_data is Dictionary:
        return "%s (%s)" % [
            str(rule_data.get("name", _extract_identifier(rule_data))),
            _extract_identifier(rule_data)
        ]
    return str(rule_data)

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
        empty_item.set_text(0, "No installed rules")
        empty_item.set_text(1, "Install a template to populate the dependency tree.")
        return

    var dependency_model := _build_rule_dependency_model()
    var displayed_rule_ids: Array = []

    var root_rule_ids: Array = dependency_model.get("root_rule_ids", [])
    if not root_rule_ids.is_empty():
        var resolved_group := _installed_rule_tree.create_item(root_item)
        resolved_group.set_text(0, "Resolved tree roots")
        resolved_group.set_text(1, "Rules with no resolved parents")
        for rule_id in root_rule_ids:
            _add_rule_tree_item(resolved_group, str(rule_id), dependency_model, [], displayed_rule_ids)

    var unresolved_rule_ids: Array = dependency_model.get("unresolved_rule_ids", [])
    if not unresolved_rule_ids.is_empty():
        var unresolved_group := _installed_rule_tree.create_item(root_item)
        unresolved_group.set_text(0, "Waiting for parent links")
        unresolved_group.set_text(1, "Required parent kinds still need resolution")
        for rule_id in unresolved_rule_ids:
            _add_rule_tree_item(unresolved_group, str(rule_id), dependency_model, [], displayed_rule_ids)

    var overflow_group: TreeItem = null
    var rule_ids: Array = dependency_model.get("rule_ids", [])
    for rule_id in rule_ids:
        if displayed_rule_ids.has(rule_id):
            continue
        if overflow_group == null:
            overflow_group = _installed_rule_tree.create_item(root_item)
            overflow_group.set_text(0, "Additional linked rules")
            overflow_group.set_text(1, "Displayed here to avoid hidden dependency cycles")
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
        cycle_item.set_text(0, "Cycle detected")
        cycle_item.set_text(1, rule_id)
        return

    var rules_by_id: Dictionary = dependency_model.get("rules_by_id", {})
    if not rules_by_id.has(rule_id):
        var missing_item := _installed_rule_tree.create_item(parent_item)
        missing_item.set_text(0, rule_id)
        missing_item.set_text(1, "Rule not present in snapshot")
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
        extra_parent_item.set_text(0, "Also linked under")
        extra_parent_item.set_text(1, _format_rule_reference_list(resolved_parent_ids.slice(1, resolved_parent_ids.size()), dependency_model))

    for required_kind in _get_rule_unresolved_required_kinds(rule_id, dependency_model):
        var unresolved_item := _installed_rule_tree.create_item(rule_item)
        unresolved_item.set_text(0, "Needs parent kind")
        var candidate_ids: Array = Array(dependency_model.get("providers_by_kind", {}).get(required_kind, []))
        if candidate_ids.is_empty():
            unresolved_item.set_text(1, str(required_kind))
        else:
            unresolved_item.set_text(1, "%s (candidates: %s)" % [
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
        parts.append("root" if _get_rule_unresolved_required_kinds(rule_id, dependency_model).is_empty() else "awaiting parent links")
    else:
        parts.append("parents: %s" % _format_rule_reference_list(resolved_parent_ids, dependency_model))

    var child_ids: Array = dependency_model.get("children_by_parent", {}).get(rule_id, [])
    if not child_ids.is_empty():
        parts.append("%d child rule(s)" % child_ids.size())

    var provided_kinds: Array = dependency_model.get("provided_kinds_by_rule", {}).get(rule_id, [])
    if not provided_kinds.is_empty():
        parts.append("provides %s" % _join_values(provided_kinds))

    var unresolved_required_kinds := _get_rule_unresolved_required_kinds(rule_id, dependency_model)
    if not unresolved_required_kinds.is_empty():
        parts.append("needs %s" % _join_values(unresolved_required_kinds))

    return _join_values(parts) if not parts.is_empty() else "No dependency metadata"

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
        empty_item.set_text(0, "No entities")
        empty_item.set_text(1, "World snapshot did not report any entities.")
        return

    var character_entities := _filter_entities_by_kind(entities, true)
    if not character_entities.is_empty():
        var character_group := _entity_tree.create_item(root_item)
        character_group.set_text(0, "Characters & agents")
        character_group.set_text(1, "%d entity(s)" % character_entities.size())
        for entity_data in character_entities:
            _add_entity_tree_item(character_group, entity_data, entity_model)

    var object_entities := _filter_entities_by_kind(entities, false)
    if not object_entities.is_empty():
        var object_group := _entity_tree.create_item(root_item)
        object_group.set_text(0, "Objects & world entities")
        object_group.set_text(1, "%d entity(s)" % object_entities.size())
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
                str(entity_link.get("reverse_label", "linked from")),
                str(entity_link.get("label", "linked to")),
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
                    str(field_spec.get("forward", "linked to")),
                    str(field_spec.get("reverse", "linked from")),
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
                    str(field_spec.get("forward", "linked to")),
                    str(field_spec.get("reverse", "linked from")),
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
        tags_item.set_text(0, "tags")
        tags_item.set_text(1, _join_values(tags))

    for relationship_text in _build_entity_link_lines(entity_id, entity_model):
        var relationship_item := _entity_tree.create_item(tree_item)
        relationship_item.set_text(0, "relationship")
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
        link_lines.append("%s: %s" % [str(grouped_entry.get("label", "linked to")), str(grouped_entry.get("value", ""))])
    for grouped_entry in _group_entity_links(reverse_entries, entity_names_by_id):
        link_lines.append("%s: %s" % [str(grouped_entry.get("label", "linked to")), str(grouped_entry.get("value", ""))])
    return link_lines

func _group_entity_links(entity_links: Array, entity_names_by_id: Dictionary) -> Array:
    var targets_by_label: Dictionary = {}
    for entity_link in entity_links:
        var label := str(entity_link.get("label", "linked to"))
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
                str(grouped_entry.get("label", "linked to")),
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
        lines.append("  tags: %s" % _join_values(tags))

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

func _format_variant_for_text(value: Variant) -> String:
    if value is Dictionary or value is Array:
        return JSON.stringify(value, "\t")
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
        "display_name": "Fallback Review Draft",
        "description": task_text,
        "version": "0.1.0-draft",
        "author": "fallback-shell",
        "source_repo": "local://fallback-preview",
        "source_ref": "draft",
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
        "message": "Fallback generated a sample editable rule package proposal."
    }
    if task_history is Array:
        task_history.append(result.duplicate(true))
        _fallback_snapshot["player_task_history"] = task_history
    _append_fallback_event("player_task_submitted", "Player submitted a task.", {"task": task_text})
    return result

func _simulate_package_install(package_data: Variant) -> Dictionary:
    var package_id := _extract_identifier(package_data)
    var installed_rules: Dictionary = _fallback_snapshot.get("installed_rules", {})
    var package_name := package_id
    if package_data is Dictionary:
        package_name = str(package_data.get("display_name", package_data.get("name", package_id)))

    var rule_patch := {
        "id": "compiled_%s" % package_id.replace(".", "_"),
        "name": "%s (Compiled)" % package_name,
        "concept": package_id,
        "enabled": true,
        "metadata": {
            "package_id": package_id
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

    _append_fallback_event("rule_installed", "Installed fallback package '%s'." % package_id, {"rule_id": rule_patch["id"]})
    return {"status": "installed", "rule": rule_patch}

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
    cloned_rule["name"] = "%s (Clone)" % str(cloned_rule.get("name", source_id))
    installed_rules[clone_id] = cloned_rule
    _fallback_snapshot["installed_rules"] = _refresh_fallback_rule_dependencies(installed_rules)

    _append_fallback_event("rule_cloned", "Cloned fallback rule '%s'." % source_id, {"clone_id": clone_id})
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

    _append_fallback_event("tick_advanced", "Advanced fallback world tick.", {"delta_seconds": delta_seconds, "tick_index": _fallback_snapshot["tick_index"]})
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
