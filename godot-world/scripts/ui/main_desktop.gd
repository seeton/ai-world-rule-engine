extends Control

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
var _installed_rule_list: ItemList
var _clone_rule_button: Button
var _installed_rule_details_view: TextEdit
var _world_state_view: TextEdit
var _event_log_view: TextEdit
var _status_label: Label

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
        }
    },
    "event_log": [
        {
            "type": "world_initialized",
            "message": "Desktop shell fallback active.",
            "details": {}
        }
    ]
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
    right_column.add_child(_build_text_panel("World & Character State", "Shows the latest world snapshot and current entity values.", "world_state", 180))
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
    _proposal_metadata_view.read_only = true
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
    var panel := _make_panel_section("Installed Rules", "Review active rules, inspect details, and clone the selected installed rule.")
    var body := panel.get_meta("body") as VBoxContainer

    _installed_rule_list = ItemList.new()
    _installed_rule_list.custom_minimum_size = Vector2(0, 140)
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
    _installed_rule_details_view.read_only = true
    _installed_rule_details_view.custom_minimum_size = Vector2(0, 110)
    _installed_rule_details_view.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
    body.add_child(_installed_rule_details_view)

    return panel

func _build_text_panel(title_text: String, description: String, panel_key: String, min_height: float) -> Control:
    var panel := _make_panel_section(title_text, description)
    var body := panel.get_meta("body") as VBoxContainer

    var view := TextEdit.new()
    view.read_only = true
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

    var has_rules := not _installed_rule_cache.is_empty()
    _clone_rule_button.disabled = not has_rules
    if not has_rules:
        _installed_rule_details_view.text = "No rules installed yet. Install a package to seed the world, then clone a rule from this list."
        return

    _installed_rule_list.select(0)
    _update_installed_rule_details(0)

func _update_installed_rule_details(index: int) -> void:
    if index < 0 or index >= _installed_rule_cache.size():
        _installed_rule_details_view.text = ""
        _clone_rule_button.disabled = true
        return

    var rule_data = _installed_rule_cache[index]
    _clone_rule_button.disabled = false
    _installed_rule_details_view.text = JSON.stringify(rule_data, "	")

func _update_world_state_view() -> void:
    if _snapshot_cache.is_empty():
        _world_state_view.text = "World snapshot unavailable."
        return

    var lines: Array[String] = []
    lines.append("World: %s" % [str(_snapshot_cache.get("world_id", _snapshot_cache.get("world_name", "unknown")))])
    lines.append("Runtime: %s" % [str(_snapshot_cache.get("runtime_choice", "n/a"))])
    lines.append("Tick: %s" % [str(_snapshot_cache.get("tick_index", _snapshot_cache.get("tick", "?")))])
    lines.append("Elapsed seconds: %s" % [str(_snapshot_cache.get("elapsed_seconds", 0.0))])
    if _snapshot_cache.has("concepts"):
        lines.append("Concepts: %s" % [_join_values(Array(_snapshot_cache.get("concepts", [])))])

    var entities := _extract_entities(_snapshot_cache)
    lines.append("
Entities:")
    if entities.is_empty():
        lines.append("- No entities reported.")
    else:
        for entity_data in entities:
            lines.append(_format_entity_summary(entity_data))

    var task_history = _snapshot_cache.get("player_task_history", [])
    if task_history is Array and not task_history.is_empty():
        lines.append("
Recent task result:")
        lines.append(JSON.stringify(task_history[task_history.size() - 1], "	"))

    _world_state_view.text = "
".join(lines)

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

    _event_log_view.text = "
".join(lines) if not lines.is_empty() else "No events yet."
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

func _format_entity_summary(entity_data: Variant) -> String:
    if not (entity_data is Dictionary):
        return "- %s" % [str(entity_data)]

    var lines: Array[String] = []
    lines.append("- %s [%s]" % [
        str(entity_data.get("name", entity_data.get("id", "Unknown"))),
        str(entity_data.get("archetype", "entity"))
    ])
    if entity_data.has("tags"):
        lines.append("  tags: %s" % [_join_values(Array(entity_data.get("tags", [])))])

    var components: Dictionary = entity_data.get("components", {})
    var component_names: Array = components.keys()
    component_names.sort()
    for component_name in component_names:
        var component_data = components[component_name]
        if component_data is Dictionary and not component_data.is_empty():
            var pairs: Array[String] = []
            var field_names: Array = component_data.keys()
            field_names.sort()
            for field_name in field_names:
                pairs.append("%s=%s" % [str(field_name), str(component_data[field_name])])
            lines.append("  %s: %s" % [str(component_name), _join_values(pairs)])
    return "
".join(lines)

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
    installed_rules[rule_patch["id"]] = rule_patch
    _fallback_snapshot["installed_rules"] = installed_rules

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
    _fallback_snapshot["installed_rules"] = installed_rules

    _append_fallback_event("rule_cloned", "Cloned fallback rule '%s'." % source_id, {"clone_id": clone_id})
    return {"status": "cloned", "rule": cloned_rule}

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
