extends Control

const FALLBACK_TEMPLATES: Array = [
    {
        "id": "starter-farming",
        "name": "Starter Farming",
        "description": "Adds a simple farming routine for idle villagers."
    },
    {
        "id": "night-watch",
        "name": "Night Watch",
        "description": "Schedules a guard patrol after dusk."
    },
    {
        "id": "shared-kitchen",
        "name": "Shared Kitchen",
        "description": "Introduces communal meal prep and cleanup."
    }
]

var _world_state: Node = null
var _task_input: TextEdit
var _template_list: ItemList
var _install_template_button: Button
var _tick_amount: SpinBox
var _installed_rule_list: ItemList
var _clone_rule_button: Button
var _installed_rule_details_view: TextEdit
var _world_state_view: TextEdit
var _event_log_view: TextEdit
var _status_label: Label

var _template_cache: Array = []
var _installed_rule_cache: Array = []
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
    subtitle.text = "Submit tasks, install templates, clone installed rules, inspect state, and step the simulation."
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

func _build_template_panel() -> Control:
    var panel := _make_panel_section("Install Rule Template", "Pick an available template package and install it into the current world.")
    var body := panel.get_meta("body") as VBoxContainer

    _template_list = ItemList.new()
    _template_list.custom_minimum_size = Vector2(0, 180)
    _template_list.select_mode = ItemList.SELECT_SINGLE
    _template_list.item_selected.connect(_on_template_selected)
    body.add_child(_template_list)

    _install_template_button = Button.new()
    _install_template_button.text = "Install Selected Template"
    _install_template_button.disabled = true
    _install_template_button.pressed.connect(_on_install_template_pressed)
    body.add_child(_install_template_button)

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

    var has_rules := not _installed_rule_cache.is_empty()
    _clone_rule_button.disabled = not has_rules
    if not has_rules:
        _installed_rule_details_view.text = "No rules installed yet. Install a template to seed the world, then clone a rule from this list."
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
    _status_label.text = "Data source: %s | Templates: %d | Installed rules: %d" % [source, _template_cache.size(), _installed_rule_cache.size()]

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

func _on_install_template_pressed() -> void:
    var selected_items := _template_list.get_selected_items()
    if selected_items.is_empty():
        _append_log("Install requested without a selected template.")
        return

    var template_data = _template_cache[selected_items[0]]
    var template_id := _extract_identifier(template_data)
    var result: Dictionary = {}
    if _world_state != null and _world_state.has_method("create_rule_from_patch"):
        result = _world_state.call("create_rule_from_patch", {"template_id": template_id})
    elif _world_state != null and _world_state.has_method("clone_rule"):
        result = _world_state.call("clone_rule", template_id)
    else:
        result = _simulate_template_install(template_data)

    _refresh_all()
    _append_log("Installed template: %s" % template_id, result)

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

func _on_template_selected(_index: int) -> void:
    _install_template_button.disabled = _template_list.get_selected_items().is_empty()

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
        for key in ["id", "rule_id", "template_id", "name"]:
            if data.has(key):
                return str(data.get(key))
    return str(data)

func _format_template_label(template_data: Variant) -> String:
    if template_data is Dictionary:
        return "%s — %s" % [
            str(template_data.get("name", _extract_identifier(template_data))),
            str(template_data.get("description", template_data.get("summary", "Ready to install")))
        ]
    return str(template_data)

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

func _append_log(message: String, payload: Variant = null) -> void:
    var log_entry := message
    if payload != null:
        log_entry += " | %s" % JSON.stringify(payload)
    _shell_log_lines.append(log_entry)
    _update_event_log_view()

func _simulate_task_submission(task_text: String) -> Dictionary:
    var task_history = _fallback_snapshot.get("player_task_history", [])
    var result := {
        "status": "proposal_ready",
        "task_text": task_text,
        "proposals": [{"template_id": "starter-farming", "title": "Starter Farming"}],
        "message": "Fallback generated a sample template proposal."
    }
    if task_history is Array:
        task_history.append(result.duplicate(true))
        _fallback_snapshot["player_task_history"] = task_history
    _append_fallback_event("player_task_submitted", "Player submitted a task.", {"task": task_text})
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
    installed_rules[rule_patch["id"]] = rule_patch
    _fallback_snapshot["installed_rules"] = installed_rules

    var concepts = _fallback_snapshot.get("concepts", [])
    if concepts is Array and not concepts.has(template_id):
        concepts.append(template_id)
        _fallback_snapshot["concepts"] = concepts

    _append_fallback_event("rule_installed", "Installed fallback template '%s'." % template_id, {"rule_id": rule_patch["id"]})
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
