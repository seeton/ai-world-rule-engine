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
	var stat_definitions: Dictionary = {}

	for operation in operations:
		var op: Dictionary = operation
		match String(op.get("op", "")):
			"upsert_stat":
				var compiled_effect := _compile_stat_operation(op)
				var stat_id := String(op.get("stat_id", ""))
				stat_definitions[stat_id] = {
					"component": compiled_effect.get("component", "stats"),
					"default": compiled_effect.get("default", 0.0)
				}
				if compiled_effect.has("min"):
					stat_definitions[stat_id]["min"] = compiled_effect.get("min", 0.0)
				if compiled_effect.has("max"):
					stat_definitions[stat_id]["max"] = compiled_effect.get("max", 0.0)
				effects.append(compiled_effect)
			"upsert_rule":
				if String(op.get("rule_type", "")) == "tick_delta":
					var compiled_tick := _compile_tick_delta(op, stat_definitions)
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
			"scope": String(patch.get("scope", "entity")),
			"target_tags": _normalize_string_array(patch.get("target_tags", ["mortal"])),
			"requires_rule_kinds": _normalize_string_array(patch.get("requires_rule_kinds", [])),
			"provides_rule_kinds": _normalize_string_array(patch.get("provides_rule_kinds", [])),
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

func _resolve_component(stat_id: String, ui_group: String) -> String:
	if ui_group == "time" or stat_id in ["elapsed_seconds", "time_seconds"]:
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
