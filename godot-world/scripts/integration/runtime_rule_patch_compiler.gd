extends RefCounted
class_name RuntimeRulePatchCompiler

func compile_package(rule_package: Dictionary) -> Dictionary:
    if rule_package.is_empty():
        return {
            "status": "error",
            "message": "Rule package was empty."
        }

    var patch_variant = rule_package.get("patch", null)
    if not (patch_variant is Dictionary):
        return {
            "status": "error",
            "message": "Rule package patch must be a dictionary."
        }
    var patch: Dictionary = patch_variant
    var operations_result := _validate_operations(patch.get("operations", []))
    if String(operations_result.get("status", "")) == "error":
        return operations_result
    var operations: Array = operations_result.get("operations", [])

    var patch_install_actions_result := _validate_install_actions(patch.get("install_actions", []))
    if String(patch_install_actions_result.get("status", "")) == "error":
        return patch_install_actions_result
    var patch_install_actions: Array = patch_install_actions_result.get("install_actions", [])

    var package_metadata := _build_package_metadata(rule_package)
    var aggregate_effects: Array = []
    var deferred_operations: Array = []
    var runtime_rules: Array = []
    var stat_definitions: Dictionary = {}

    for operation in operations:
        var op: Dictionary = operation
        match String(op.get("op", "")):
            "upsert_stat":
                var compiled_effect := _compile_stat_operation(op)
                var stat_id := String(compiled_effect.get("field", "value"))
                stat_definitions[stat_id] = {
                    "component": compiled_effect.get("component", "stats"),
                    "default": compiled_effect.get("default", 0.0)
                }
                if compiled_effect.has("min"):
                    stat_definitions[stat_id]["min"] = compiled_effect.get("min", 0.0)
                if compiled_effect.has("max"):
                    stat_definitions[stat_id]["max"] = compiled_effect.get("max", 0.0)
                aggregate_effects.append(compiled_effect)
            "upsert_rule":
                var operation_install_actions_result := _validate_install_actions(op.get("install_actions", []))
                if String(operation_install_actions_result.get("status", "")) == "error":
                    return operation_install_actions_result
                var operation_install_actions: Array = operation_install_actions_result.get("install_actions", [])
                var rule_type := String(op.get("rule_type", ""))
                if rule_type in ["runtime_rule", "tick_delta"]:
                    var compiled_runtime_rule := _compile_runtime_rule(op, stat_definitions, operation_install_actions, package_metadata)
                    if not compiled_runtime_rule.is_empty():
                        runtime_rules.append(compiled_runtime_rule)
                    if rule_type == "tick_delta":
                        var compiled_tick := _compile_tick_delta(op, stat_definitions)
                        if not compiled_tick.is_empty():
                            aggregate_effects.append(compiled_tick)
                        elif compiled_runtime_rule.is_empty():
                            deferred_operations.append(op.duplicate(true))
                    elif compiled_runtime_rule.is_empty():
                        deferred_operations.append(op.duplicate(true))
                elif rule_type in ["event_visual_effect"]:
                    deferred_operations.append(op.duplicate(true))
                else:
                    deferred_operations.append(op.duplicate(true))
            "add_event_binding", "add_relation":
                deferred_operations.append(op.duplicate(true))
            _:
                deferred_operations.append(op.duplicate(true))

    var baseline_runtime_rule := _build_baseline_runtime_rule(rule_package, patch, package_metadata, aggregate_effects, patch_install_actions)
    if not baseline_runtime_rule.is_empty():
        runtime_rules.push_front(baseline_runtime_rule)

    var package_id := String(rule_package.get("package_id", "custom.rule"))
    var concept := package_id.get_slice(".", package_id.count("."))
    var aggregate_runtime_patch := {
        "id": "compiled_%s" % package_id.replace(".", "_"),
        "name": "%s (Compiled)" % String(rule_package.get("display_name", package_id)),
        "concept": concept,
        "scope": String(patch.get("scope", "entity")),
        "target_tags": _normalize_string_array(patch.get("target_tags", ["mortal"])),
        "requires_rule_kinds": _normalize_string_array(patch.get("requires_rule_kinds", [])),
        "provides_rule_kinds": _normalize_string_array(patch.get("provides_rule_kinds", [])),
        "install_actions": patch_install_actions.duplicate(true),
        "effects": _duplicate_dictionary_array(aggregate_effects),
        "metadata": package_metadata.duplicate(true)
    }
    if not runtime_rules.is_empty():
        aggregate_runtime_patch["metadata"]["runtime_rule_ids"] = _extract_rule_ids(runtime_rules)

    var primary_runtime_patch := aggregate_runtime_patch
    if aggregate_effects.is_empty() and runtime_rules.size() == 1:
        primary_runtime_patch = runtime_rules[0].duplicate(true)

    var has_install_targets := not runtime_rules.is_empty() or not aggregate_effects.is_empty() or not patch_install_actions.is_empty()
    return {
        "status": "compiled",
        "runtime_patch": primary_runtime_patch,
        "runtime_rules": _duplicate_dictionary_array(runtime_rules),
        "deferred_operations": deferred_operations,
        "safe_to_apply_directly": deferred_operations.is_empty(),
        "has_install_targets": has_install_targets
    }

func _build_baseline_runtime_rule(rule_package: Dictionary, patch: Dictionary, package_metadata: Dictionary, effects: Array, install_actions: Array) -> Dictionary:
    var requires_rule_kinds := _normalize_string_array(patch.get("requires_rule_kinds", []))
    var provides_rule_kinds := _normalize_string_array(patch.get("provides_rule_kinds", []))
    if effects.is_empty() and install_actions.is_empty() and requires_rule_kinds.is_empty() and provides_rule_kinds.is_empty():
        return {}

    var package_id := String(rule_package.get("package_id", "custom.rule"))
    var concept := package_id.get_slice(".", package_id.count("."))
    return {
        "id": "compiled_%s_baseline" % package_id.replace(".", "_"),
        "name": "%s (Baseline)" % String(rule_package.get("display_name", package_id)),
        "concept": concept,
        "scope": String(patch.get("scope", "entity")),
        "target_tags": _normalize_string_array(patch.get("target_tags", ["mortal"])),
        "requires_rule_kinds": requires_rule_kinds,
        "provides_rule_kinds": provides_rule_kinds,
        "install_actions": install_actions.duplicate(true),
        "effects": _duplicate_dictionary_array(effects),
        "metadata": package_metadata.duplicate(true)
    }

func _build_package_metadata(rule_package: Dictionary) -> Dictionary:
    var metadata := {
        "package_id": rule_package.get("package_id", ""),
        "package_display_name": rule_package.get("display_name", rule_package.get("package_id", "")),
        "package_version": rule_package.get("version", ""),
        "source_repo": rule_package.get("source_repo", ""),
        "source_ref": rule_package.get("source_ref", ""),
        "forked_from": rule_package.get("forked_from", null),
        "suggested_pr_target": rule_package.get("suggested_pr_target", null),
        "package_dependencies": _normalize_string_array(rule_package.get("package_dependencies", []))
    }
    if rule_package.get("runtime_contract", {}) is Dictionary:
        metadata["runtime_contract"] = rule_package.get("runtime_contract", {}).duplicate(true)
    return metadata

func _compile_stat_operation(operation: Dictionary) -> Dictionary:
    var stat_id := String(operation.get("stat_id", "value"))
    var effect := {
        "component": _resolve_component(stat_id, String(operation.get("ui_group", ""))),
        "field": stat_id,
        "op": "add",
        "default": float(operation.get("default", 0.0)),
        "value_per_second": 0.0
    }
    if operation.has("min"):
        effect["min"] = float(operation.get("min", 0.0))
    if operation.has("max"):
        effect["max"] = float(operation.get("max", 0.0))
    return effect

func _compile_tick_delta(operation: Dictionary, stat_definitions: Dictionary) -> Dictionary:
    var stat_id := String(operation.get("target_stat", ""))
    if stat_id.is_empty():
        return {}

    var interval_seconds: float = maxf(float(operation.get("interval_seconds", 1.0)), 0.001)
    var stat_definition: Dictionary = stat_definitions.get(stat_id, {})
    var effect := {
        "component": stat_definition.get("component", _resolve_component(stat_id, "")),
        "field": stat_id,
        "op": "add",
        "default": float(stat_definition.get("default", 0.0)),
        "value_per_second": float(operation.get("delta", 0.0)) / interval_seconds
    }
    if operation.has("min"):
        effect["min"] = float(operation.get("min", 0.0))
    elif bool(operation.get("clamp_to_stat_bounds", false)) and stat_definition.has("min"):
        effect["min"] = float(stat_definition.get("min", 0.0))
    if operation.has("max"):
        effect["max"] = float(operation.get("max", 0.0))
    elif bool(operation.get("clamp_to_stat_bounds", false)) and stat_definition.has("max"):
        effect["max"] = float(stat_definition.get("max", 0.0))
    return effect

func _compile_runtime_rule(operation: Dictionary, stat_definitions: Dictionary, install_actions: Array, package_metadata: Dictionary) -> Dictionary:
    var rule_id := String(operation.get("rule_id", operation.get("id", ""))).strip_edges()
    if rule_id.is_empty():
        return {}

    var rule_type := String(operation.get("rule_type", "")).strip_edges()
    if rule_type not in ["runtime_rule", "tick_delta"]:
        return {}

    var compiled_effects: Array = []
    if rule_type == "tick_delta":
        var compiled_tick := _compile_tick_delta(operation, stat_definitions)
        if not compiled_tick.is_empty():
            compiled_effects.append(compiled_tick)

    for raw_effect in operation.get("effects", []):
        var normalized_effect := _normalize_runtime_effect(raw_effect, stat_definitions)
        if not normalized_effect.is_empty():
            compiled_effects.append(normalized_effect)

    var default_target_tags: Array = []
    if not compiled_effects.is_empty():
        default_target_tags = ["mortal"]

    return {
        "id": rule_id,
        "name": String(operation.get("name", rule_id)),
        "concept": String(operation.get("concept", _infer_rule_concept(rule_id))),
        "enabled": bool(operation.get("enabled", true)),
        "scope": String(operation.get("scope", "entity")),
        "target_tags": _normalize_string_array(operation.get("target_tags", default_target_tags)),
        "effects": _duplicate_dictionary_array(compiled_effects),
        "requires_rule_kinds": _normalize_string_array(operation.get("requires_rule_kinds", [])),
        "provides_rule_kinds": _normalize_string_array(operation.get("provides_rule_kinds", [])),
        "install_actions": install_actions.duplicate(true),
        "metadata": package_metadata.duplicate(true)
    }

func _normalize_runtime_effect(raw_effect: Variant, stat_definitions: Dictionary) -> Dictionary:
    if not (raw_effect is Dictionary):
        return {}

    var effect: Dictionary = raw_effect.duplicate(true)
    var field := String(effect.get("field", effect.get("stat_id", "value"))).strip_edges()
    if field.is_empty():
        return {}

    var stat_definition: Dictionary = stat_definitions.get(field, {})
    effect["field"] = field
    effect["component"] = String(effect.get("component", stat_definition.get("component", _resolve_component(field, ""))))
    effect["op"] = String(effect.get("op", "add"))
    effect["default"] = float(effect.get("default", stat_definition.get("default", 0.0)))
    if effect.has("value_per_second"):
        effect["value_per_second"] = float(effect.get("value_per_second", 0.0))
    if effect.has("value"):
        effect["value"] = float(effect.get("value", 0.0))
    if effect.has("min"):
        effect["min"] = float(effect.get("min", stat_definition.get("min", 0.0)))
    if effect.has("max"):
        effect["max"] = float(effect.get("max", stat_definition.get("max", 100.0)))
    return effect

func _resolve_component(stat_id: String, ui_group: String) -> String:
    if ui_group == "time" or stat_id in ["elapsed_seconds", "elapsed_time_seconds", "time_seconds"]:
        return "time"
    if ui_group == "needs":
        return "needs"
    if stat_id in ["hunger", "sleep", "energy"]:
        return "needs"
    return "stats"

func _normalize_string_array(value: Variant) -> Array:
    var values: Array = []
    if value is Array:
        for entry in value:
            var text := String(entry).strip_edges()
            if not text.is_empty() and not values.has(text):
                values.append(text)
    elif value is PackedStringArray:
        for entry in value:
            var text := String(entry).strip_edges()
            if not text.is_empty() and not values.has(text):
                values.append(text)
    elif value is String:
        var text := String(value).strip_edges()
        if not text.is_empty():
            values.append(text)
    return values

func _duplicate_dictionary_array(values: Array) -> Array:
    var duplicated: Array = []
    for value in values:
        if value is Dictionary:
            duplicated.append(value.duplicate(true))
        else:
            duplicated.append(value)
    return duplicated

func _extract_rule_ids(runtime_rules: Array) -> Array:
    var rule_ids: Array = []
    for runtime_rule in runtime_rules:
        if not (runtime_rule is Dictionary):
            continue
        var rule_id := String(runtime_rule.get("id", "")).strip_edges()
        if not rule_id.is_empty():
            rule_ids.append(rule_id)
    return rule_ids

func _validate_install_actions(raw_actions: Variant) -> Dictionary:
    if raw_actions == null:
        return {
            "status": "ok",
            "install_actions": []
        }
    if not (raw_actions is Array):
        return {
            "status": "error",
            "message": "Rule package patch.install_actions must be an array."
        }

    var validated_actions: Array = []
    for action_index in range(raw_actions.size()):
        var raw_action = raw_actions[action_index]
        if not (raw_action is Dictionary):
            return {
                "status": "error",
                "message": "Rule package patch.install_actions[%d] must be a dictionary." % action_index
            }

        var action: Dictionary = raw_action.duplicate(true)
        var op := String(action.get("op", "")).strip_edges()
        if op.is_empty():
            return {
                "status": "error",
                "message": "Rule package patch.install_actions[%d] must include a non-empty op." % action_index
            }

        match op:
            "merge_world_state":
                if action.has("path") and not (action.get("path", "") is String):
                    return {
                        "status": "error",
                        "message": "Rule package patch.install_actions[%d].path must be a string when provided." % action_index
                    }
                if String(action.get("path", "")).strip_edges().is_empty() and not (action.get("value", {}) is Dictionary):
                    return {
                        "status": "error",
                        "message": "Rule package patch.install_actions[%d] must provide a dictionary value when path is omitted." % action_index
                    }
            "upsert_entities":
                var entities = action.get("entities", null)
                if not (entities is Array):
                    return {
                        "status": "error",
                        "message": "Rule package patch.install_actions[%d].entities must be an array." % action_index
                    }
                for entity_index in range(entities.size()):
                    var raw_entity = entities[entity_index]
                    if not (raw_entity is Dictionary):
                        return {
                            "status": "error",
                            "message": "Rule package patch.install_actions[%d].entities[%d] must be a dictionary." % [action_index, entity_index]
                        }
                    if String(raw_entity.get("id", "")).strip_edges().is_empty():
                        return {
                            "status": "error",
                            "message": "Rule package patch.install_actions[%d].entities[%d] must include a non-empty id." % [action_index, entity_index]
                        }
            _:
                return {
                    "status": "error",
                    "message": "Rule package patch.install_actions[%d] uses unsupported op '%s'." % [action_index, op]
                }

        action["op"] = op
        validated_actions.append(action)

    return {
        "status": "ok",
        "install_actions": validated_actions
    }

func _validate_operations(raw_operations: Variant) -> Dictionary:
    if not (raw_operations is Array):
        return {
            "status": "error",
            "message": "Rule package patch operations must be an array."
        }

    var operations: Array = raw_operations
    for operation_index in range(operations.size()):
        var raw_operation = operations[operation_index]
        if not (raw_operation is Dictionary):
            return {
                "status": "error",
                "message": "Rule package patch.operations[%d] must be a dictionary." % operation_index
            }

        var operation: Dictionary = raw_operation
        if String(operation.get("op", "")).strip_edges().is_empty():
            return {
                "status": "error",
                "message": "Rule package patch.operations[%d] must include a non-empty op." % operation_index
            }

    return {
        "status": "ok",
        "operations": operations
    }

func _infer_rule_concept(rule_id: String) -> String:
    var normalized_rule_id := rule_id.strip_edges()
    if normalized_rule_id.is_empty():
        return "rule"
    var segments := normalized_rule_id.split(".", false)
    return String(segments[segments.size() - 1]) if not segments.is_empty() else normalized_rule_id
