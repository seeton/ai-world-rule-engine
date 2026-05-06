extends RefCounted
class_name RuntimeRulePatchCompiler

func compile_package(rule_package: Dictionary) -> Dictionary:
	if rule_package.is_empty():
		return {
			"status": "error",
			"message": "Rule package was empty."
		}

	var patch: Dictionary = rule_package.get("patch", {})
	var operations: Array = patch.get("operations", [])
	var effects: Array = []
	var deferred_operations: Array = []
	var stat_components: Dictionary = {}

	for operation in operations:
		var op: Dictionary = operation
		match String(op.get("op", "")):
			"upsert_stat":
				var compiled_effect := _compile_stat_operation(op)
				stat_components[String(op.get("stat_id", ""))] = compiled_effect.get("component", "stats")
				effects.append(compiled_effect)
			"upsert_rule":
				if String(op.get("rule_type", "")) == "tick_delta":
					var compiled_tick := _compile_tick_delta(op, stat_components)
					if not compiled_tick.is_empty():
						effects.append(compiled_tick)
					else:
						deferred_operations.append(op.duplicate(true))
				else:
					deferred_operations.append(op.duplicate(true))
			_:
				deferred_operations.append(op.duplicate(true))

	var package_id := String(rule_package.get("package_id", "custom.rule"))
	var concept := package_id.get_slice(".", package_id.count("."))
	return {
		"status": "compiled",
		"runtime_patch": {
			"id": "compiled_%s" % package_id.replace(".", "_"),
			"name": "%s (Compiled)" % String(rule_package.get("display_name", package_id)),
			"concept": concept,
			"scope": "entity",
			"target_tags": ["mortal"],
			"requires_rule_kinds": _normalize_string_array(patch.get("requires_rule_kinds", [])),
			"provides_rule_kinds": _normalize_string_array(patch.get("provides_rule_kinds", [])),
			"install_actions": _duplicate_install_actions(patch.get("install_actions", [])),
			"effects": effects,
			"metadata": {
				"package_id": package_id,
				"source_repo": rule_package.get("source_repo", ""),
				"source_ref": rule_package.get("source_ref", ""),
				"forked_from": rule_package.get("forked_from", null),
				"suggested_pr_target": rule_package.get("suggested_pr_target", null)
			}
		},
		"deferred_operations": deferred_operations,
		"safe_to_apply_directly": deferred_operations.is_empty()
	}

func _compile_stat_operation(operation: Dictionary) -> Dictionary:
	var stat_id := String(operation.get("stat_id", "value"))
	return {
		"component": _resolve_component(stat_id, String(operation.get("ui_group", ""))),
		"field": stat_id,
		"op": "add",
		"default": float(operation.get("default", 0.0)),
		"value_per_second": 0.0,
		"min": float(operation.get("min", 0.0)),
		"max": float(operation.get("max", 100.0))
	}

func _compile_tick_delta(operation: Dictionary, stat_components: Dictionary) -> Dictionary:
	var stat_id := String(operation.get("target_stat", ""))
	if stat_id.is_empty():
		return {}

	var interval_seconds: float = max(float(operation.get("interval_seconds", 1.0)), 0.001)
	return {
		"component": stat_components.get(stat_id, _resolve_component(stat_id, "")),
		"field": stat_id,
		"op": "add",
		"default": 0.0,
		"value_per_second": float(operation.get("delta", 0.0)) / interval_seconds,
		"min": float(operation.get("min", 0.0)),
		"max": float(operation.get("max", 100.0))
	}

func _resolve_component(stat_id: String, ui_group: String) -> String:
	if ui_group == "needs":
		return "needs"
	if stat_id in ["hunger", "sleep", "energy"]:
		return "needs"
	return "stats"


func _normalize_string_array(values: Array) -> Array:
	var normalized: Array = []
	for value in values:
		var text := String(value).strip_edges()
		if text.is_empty() or normalized.has(text):
			continue
		normalized.append(text)
	return normalized


func _duplicate_install_actions(raw_actions: Array) -> Array:
	var duplicated_actions: Array = []
	for raw_action in raw_actions:
		if raw_action is Dictionary:
			duplicated_actions.append(raw_action.duplicate(true))
	return duplicated_actions
