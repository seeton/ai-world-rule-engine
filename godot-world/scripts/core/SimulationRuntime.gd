extends RefCounted
class_name SimulationRuntime

const DEFAULT_FIXED_STEP := 0.25
const SNAPSHOT_FORMAT_VERSION := 1

var fixed_step_seconds: float = DEFAULT_FIXED_STEP
var _accumulator_seconds: float = 0.0
var _world_state: Dictionary = {}
var _template_index: Dictionary = {}
var _clone_sequence: int = 0


func _init(rule_templates: Array = []) -> void:
	for template in rule_templates:
		var template_id := String(template.get("id", ""))
		if not template_id.is_empty():
			_template_index[template_id] = template.duplicate(true)

	_world_state = _build_null_world()


func record_player_task(task_result: Dictionary) -> void:
	var history: Array = _world_state.get("player_task_history", [])
	history.append(task_result.duplicate(true))
	_world_state["player_task_history"] = history
	_append_event("player_task_submitted", "Player submitted a task for rule proposal.", {"task": task_result.get("task_text", "")})


func create_rule_from_patch(rule_patch: Dictionary) -> Dictionary:
	var normalized_rule := _normalize_rule_patch(rule_patch)
	if normalized_rule.is_empty():
		return {
			"status": "error",
			"message": "Rule patch was empty or invalid."
		}

	var rule_id := String(normalized_rule.get("id", ""))
	var installed_rules: Dictionary = _world_state.get("installed_rules", {})
	if installed_rules.has(rule_id):
		return {
			"status": "error",
			"message": "Rule '%s' is already installed." % rule_id
		}

	installed_rules[rule_id] = normalized_rule
	_world_state["installed_rules"] = installed_rules
	_initialize_rule_targets(normalized_rule)
	_append_concept(normalized_rule.get("concept", rule_id))
	_append_event("rule_installed", "Installed rule '%s'." % rule_id, {"rule_id": rule_id})

	return {
		"status": "installed",
		"installed": true,
		"rule": normalized_rule.duplicate(true)
	}


func clone_rule(rule_id: String) -> Dictionary:
	var installed_rules: Dictionary = _world_state.get("installed_rules", {})
	if not installed_rules.has(rule_id):
		if _template_index.has(rule_id):
			var template_rule: Dictionary = _template_index[rule_id].get("rule_patch", {}).duplicate(true)
			template_rule["id"] = _make_unique_rule_id(String(template_rule.get("id", "rule_%s" % rule_id)))
			template_rule["name"] = "%s (Installed)" % String(_template_index[rule_id].get("name", rule_id))
			return create_rule_from_patch(template_rule)

		return {
			"status": "error",
			"message": "Rule '%s' is not installed and no matching template exists." % rule_id
		}

	var cloned_rule: Dictionary = installed_rules[rule_id].duplicate(true)
	var clone_id := _make_unique_rule_id("%s_clone" % rule_id)
	cloned_rule["id"] = clone_id
	cloned_rule["name"] = "%s (Clone)" % String(cloned_rule.get("name", rule_id))
	cloned_rule["source_rule_id"] = rule_id

	installed_rules[clone_id] = cloned_rule
	_world_state["installed_rules"] = installed_rules
	_initialize_rule_targets(cloned_rule)
	_append_event("rule_cloned", "Cloned rule '%s' into '%s'." % [rule_id, clone_id], {"rule_id": rule_id, "clone_id": clone_id})

	return {
		"status": "cloned",
		"installed": true,
		"rule": cloned_rule.duplicate(true),
		"source_rule_id": rule_id
	}


func get_snapshot() -> Dictionary:
	var snapshot := _world_state.duplicate(true)
	var installed_rules_by_id: Dictionary = snapshot.get("installed_rules", {}).duplicate(true)
	var installed_rule_ids: Array = installed_rules_by_id.keys()
	installed_rule_ids.sort()
	var installed_rules: Array = []
	for rule_id in installed_rule_ids:
		installed_rules.append(installed_rules_by_id[rule_id].duplicate(true))

	var template_ids: Array = _template_index.keys()
	template_ids.sort()

	snapshot["accumulator_seconds"] = _accumulator_seconds
	snapshot["available_template_ids"] = template_ids
	snapshot["clone_sequence"] = _clone_sequence
	snapshot["installed_rules_by_id"] = installed_rules_by_id
	snapshot["installed_rules"] = installed_rules
	snapshot["snapshot_format_version"] = SNAPSHOT_FORMAT_VERSION
	snapshot["tick"] = snapshot.get("tick_index", 0)
	snapshot["world_name"] = String(snapshot.get("world_name", "Null World"))
	snapshot["characters"] = _build_character_list(snapshot.get("entities", {}))
	snapshot["events"] = _build_event_messages(snapshot.get("event_log", []))
	return snapshot


func restore_snapshot(snapshot: Dictionary) -> Dictionary:
	if snapshot.is_empty():
		return {
			"status": "error",
			"message": "Snapshot was empty."
		}

	if snapshot.has("snapshot_format_version"):
		var snapshot_version := int(snapshot.get("snapshot_format_version", 0))
		if snapshot_version != SNAPSHOT_FORMAT_VERSION:
			return {
				"status": "error",
				"message": "Unsupported snapshot format version '%s'." % snapshot_version
			}

	var restored_state := _build_restored_world_state(snapshot)
	if restored_state.is_empty():
		return {
			"status": "error",
			"message": "Snapshot did not contain a restorable world state."
		}

	fixed_step_seconds = max(float(restored_state.get("fixed_step_seconds", DEFAULT_FIXED_STEP)), 0.0001)
	restored_state["fixed_step_seconds"] = fixed_step_seconds
	_accumulator_seconds = max(float(snapshot.get("accumulator_seconds", 0.0)), 0.0)
	_clone_sequence = max(int(snapshot.get("clone_sequence", 0)), _estimate_clone_sequence(restored_state.get("installed_rules", {})))
	_world_state = restored_state
	for rule_id_variant in restored_state.get("installed_rules", {}).keys():
		_initialize_rule_targets(restored_state["installed_rules"][rule_id_variant])

	return {
		"status": "restored",
		"snapshot": get_snapshot()
	}


func advance_tick(delta_seconds: float) -> void:
	if delta_seconds <= 0.0:
		return

	_accumulator_seconds += delta_seconds
	while _accumulator_seconds >= fixed_step_seconds:
		_run_tick(fixed_step_seconds)
		_accumulator_seconds -= fixed_step_seconds


func _build_null_world() -> Dictionary:
	return {
		"world_id": "null-world",
		"world_name": "Null World",
		"runtime_choice": "godot-4-desktop",
		"elapsed_seconds": 0.0,
		"tick_index": 0,
		"fixed_step_seconds": fixed_step_seconds,
		"concepts": [],
		"entities": {
			"origin_entity": {
				"id": "origin_entity",
				"name": "Origin Entity",
				"archetype": "origin",
				"tags": ["origin", "mortal", "mutable"],
				"components": {
					"needs": {},
					"stats": {},
					"traits": {
						"curiosity": 1.0,
						"morale": 50.0,
						"focus": 50.0
					},
					"behavior": {
						"current_task": "Awaiting the first installed rule"
					}
				}
			}
		},
		"installed_rules": {},
		"player_task_history": [],
		"event_log": [
			{
				"type": "world_initialized",
				"message": "Bootstrapped a null world with one mutable origin entity.",
				"details": {}
			}
		]
	}


func _build_restored_world_state(snapshot: Dictionary) -> Dictionary:
	var restored_state := snapshot.duplicate(true)
	restored_state.erase("accumulator_seconds")
	restored_state.erase("available_rule_packages")
	restored_state.erase("available_template_ids")
	restored_state.erase("characters")
	restored_state.erase("clone_sequence")
	restored_state.erase("events")
	restored_state.erase("installed_rules_by_id")
	restored_state.erase("installed_rules")
	restored_state.erase("snapshot_format_version")
	restored_state.erase("tick")

	if not snapshot.get("entities", {}) is Dictionary:
		return {}

	restored_state["world_id"] = String(snapshot.get("world_id", "null-world"))
	restored_state["world_name"] = String(snapshot.get("world_name", "Null World"))
	restored_state["runtime_choice"] = String(snapshot.get("runtime_choice", "godot-4-desktop"))
	restored_state["elapsed_seconds"] = max(float(snapshot.get("elapsed_seconds", 0.0)), 0.0)
	restored_state["tick_index"] = max(int(snapshot.get("tick_index", snapshot.get("tick", 0))), 0)
	restored_state["fixed_step_seconds"] = max(float(snapshot.get("fixed_step_seconds", DEFAULT_FIXED_STEP)), 0.0001)
	restored_state["concepts"] = _duplicate_array(snapshot.get("concepts", []))
	restored_state["entities"] = snapshot.get("entities", {}).duplicate(true)
	restored_state["installed_rules"] = _normalize_snapshot_rules(snapshot)
	restored_state["player_task_history"] = _duplicate_array(snapshot.get("player_task_history", []))
	restored_state["event_log"] = _duplicate_array(snapshot.get("event_log", []))
	return restored_state


func _run_tick(step_seconds: float) -> void:
	var entities: Dictionary = _world_state.get("entities", {})
	var installed_rules: Dictionary = _world_state.get("installed_rules", {})
	var entity_ids: Array = entities.keys()
	var rule_ids: Array = installed_rules.keys()
	entity_ids.sort()
	rule_ids.sort()

	for entity_id in entity_ids:
		var entity: Dictionary = entities[entity_id]
		for rule_id in rule_ids:
			var rule: Dictionary = installed_rules[rule_id]
			if not bool(rule.get("enabled", true)):
				continue
			if not _entity_matches_rule(entity, rule):
				continue
			_apply_rule(entity, rule, step_seconds)
		entities[entity_id] = entity

	_world_state["entities"] = entities
	_world_state["tick_index"] = int(_world_state.get("tick_index", 0)) + 1
	_world_state["elapsed_seconds"] = float(_world_state.get("elapsed_seconds", 0.0)) + step_seconds


func _entity_matches_rule(entity: Dictionary, rule: Dictionary) -> bool:
	var target_tags: Array = rule.get("target_tags", [])
	if target_tags.is_empty():
		return true

	var entity_tags: Array = entity.get("tags", [])
	for target_tag in target_tags:
		if not entity_tags.has(target_tag):
			return false
	return true


func _apply_rule(entity: Dictionary, rule: Dictionary, step_seconds: float) -> void:
	var components: Dictionary = entity.get("components", {})
	for effect in rule.get("effects", []):
		var component_name := String(effect.get("component", "stats"))
		var field_name := String(effect.get("field", "value"))
		if not components.has(component_name):
			components[component_name] = {}

		var component: Dictionary = components[component_name]
		var current_value := float(component.get(field_name, effect.get("default", 0.0)))
		var next_value := current_value
		var operation := String(effect.get("op", "add"))

		match operation:
			"set":
				next_value = float(effect.get("value", effect.get("default", 0.0)))
			"min":
				next_value = min(current_value, float(effect.get("value", current_value)))
			"max":
				next_value = max(current_value, float(effect.get("value", current_value)))
			_:
				next_value = current_value + float(effect.get("value_per_second", 0.0)) * step_seconds

		if effect.has("min"):
			next_value = max(next_value, float(effect["min"]))
		if effect.has("max"):
			next_value = min(next_value, float(effect["max"]))

		component[field_name] = snappedf(next_value, 0.0001)
		components[component_name] = component

	entity["components"] = components


func _normalize_rule_patch(rule_patch: Dictionary) -> Dictionary:
	var base_rule: Dictionary = {}
	var template_id := String(rule_patch.get("template_id", ""))
	if not template_id.is_empty() and _template_index.has(template_id):
		base_rule = _template_index[template_id].get("rule_patch", {}).duplicate(true)

	var merged_rule := _merge_dictionaries(base_rule, rule_patch)
	if merged_rule.is_empty():
		return {}

	var rule_id := String(merged_rule.get("id", ""))
	if rule_id.is_empty():
		rule_id = _make_unique_rule_id("rule_%d" % (int(_world_state.get("tick_index", 0)) + int(_world_state.get("installed_rules", {}).size()) + 1))
		merged_rule["id"] = rule_id

	merged_rule["enabled"] = bool(merged_rule.get("enabled", true))
	merged_rule["scope"] = String(merged_rule.get("scope", "entity"))
	var target_tags: Array = []
	for tag in merged_rule.get("target_tags", []):
		target_tags.append(tag)
	merged_rule["target_tags"] = target_tags

	var normalized_effects: Array = []
	for raw_effect in merged_rule.get("effects", []):
		var effect: Dictionary = raw_effect.duplicate(true)
		effect["component"] = String(effect.get("component", "stats"))
		effect["field"] = String(effect.get("field", "value"))
		effect["op"] = String(effect.get("op", "add"))
		effect["default"] = float(effect.get("default", 0.0))
		if effect.has("value_per_second"):
			effect["value_per_second"] = float(effect["value_per_second"])
		if effect.has("value"):
			effect["value"] = float(effect["value"])
		if effect.has("min"):
			effect["min"] = float(effect["min"])
		if effect.has("max"):
			effect["max"] = float(effect["max"])
		normalized_effects.append(effect)
	merged_rule["effects"] = normalized_effects

	return merged_rule


func _initialize_rule_targets(rule: Dictionary) -> void:
	var entities: Dictionary = _world_state.get("entities", {})
	var entity_ids: Array = entities.keys()
	entity_ids.sort()

	for entity_id in entity_ids:
		var entity: Dictionary = entities[entity_id]
		if not _entity_matches_rule(entity, rule):
			continue

		var components: Dictionary = entity.get("components", {})
		for effect in rule.get("effects", []):
			var component_name := String(effect.get("component", "stats"))
			var field_name := String(effect.get("field", "value"))
			if not components.has(component_name):
				components[component_name] = {}
			var component: Dictionary = components[component_name]
			if not component.has(field_name):
				component[field_name] = float(effect.get("default", 0.0))
			components[component_name] = component

		entity["components"] = components
		entities[entity_id] = entity

	_world_state["entities"] = entities


func _append_concept(concept_name: Variant) -> void:
	var concept := String(concept_name)
	if concept.is_empty():
		return

	var concepts: Array = _world_state.get("concepts", [])
	if not concepts.has(concept):
		concepts.append(concept)
	_world_state["concepts"] = concepts


func _append_event(event_type: String, message: String, details: Dictionary = {}) -> void:
	var event_log: Array = _world_state.get("event_log", [])
	event_log.append({
		"type": event_type,
		"message": message,
		"details": details.duplicate(true)
	})
	_world_state["event_log"] = event_log


func _build_character_list(entities: Dictionary) -> Array:
	var characters: Array = []
	var entity_ids: Array = entities.keys()
	entity_ids.sort()

	for entity_id in entity_ids:
		var entity: Dictionary = entities[entity_id]
		var components: Dictionary = entity.get("components", {})
		var needs: Dictionary = components.get("needs", {})
		var stats: Dictionary = components.get("stats", {})
		var traits: Dictionary = components.get("traits", {})
		var behavior: Dictionary = components.get("behavior", {})

		characters.append({
			"id": entity.get("id", entity_id),
			"name": entity.get("name", entity_id),
			"hunger": needs.get("hunger", 0.0),
			"health": stats.get("health", 100.0),
			"energy": max(0.0, float(needs.get("energy", 100.0 - float(needs.get("sleep", 0.0))))),
			"morale": traits.get("morale", 50.0),
			"focus": traits.get("focus", 50.0),
			"current_task": behavior.get("current_task", "Awaiting the next world rule")
		})

	return characters


func _build_event_messages(event_log: Array) -> Array:
	var messages: Array = []
	for event in event_log:
		if event is Dictionary:
			messages.append(String(event.get("message", event.get("type", "event"))))
		else:
			messages.append(String(event))
	return messages


func _normalize_snapshot_rules(snapshot: Dictionary) -> Dictionary:
	var raw_rules: Variant = snapshot.get("installed_rules_by_id", snapshot.get("installed_rules", {}))
	var normalized_rules: Dictionary = {}

	if raw_rules is Array:
		for raw_rule in raw_rules:
			if not raw_rule is Dictionary:
				continue
			var rule_data: Dictionary = raw_rule.duplicate(true)
			var rule_id := String(rule_data.get("id", ""))
			if rule_id.is_empty():
				continue
			normalized_rules[rule_id] = _normalize_rule_patch(rule_data)
	elif raw_rules is Dictionary:
		for rule_id_variant in raw_rules.keys():
			var rule_id := String(rule_id_variant)
			var raw_rule = raw_rules[rule_id_variant]
			if not raw_rule is Dictionary:
				continue
			var rule_data: Dictionary = raw_rule.duplicate(true)
			rule_data["id"] = rule_id
			normalized_rules[rule_id] = _normalize_rule_patch(rule_data)

	return normalized_rules


func _duplicate_array(value: Variant) -> Array:
	if value is Array:
		return value.duplicate(true)
	return []


func _estimate_clone_sequence(installed_rules: Dictionary) -> int:
	var max_sequence := 0
	for rule_id_variant in installed_rules.keys():
		var rule_id := String(rule_id_variant)
		var suffix_index := rule_id.rfind("_")
		if suffix_index == -1:
			continue
		var suffix := rule_id.substr(suffix_index + 1)
		if suffix.is_valid_int():
			max_sequence = max(max_sequence, int(suffix))
	return max_sequence


func _make_unique_rule_id(base_id: String) -> String:
	var installed_rules: Dictionary = _world_state.get("installed_rules", {})
	var candidate := base_id
	while installed_rules.has(candidate):
		_clone_sequence += 1
		candidate = "%s_%d" % [base_id, _clone_sequence]
	return candidate


func _merge_dictionaries(base_value: Dictionary, patch_value: Dictionary) -> Dictionary:
	var merged := base_value.duplicate(true)
	for key in patch_value.keys():
		var incoming = patch_value[key]
		if merged.has(key) and merged[key] is Dictionary and incoming is Dictionary:
			merged[key] = _merge_dictionaries(merged[key], incoming)
		else:
			if incoming is Dictionary:
				merged[key] = incoming.duplicate(true)
			elif incoming is Array:
				merged[key] = incoming.duplicate(true)
			else:
				merged[key] = incoming
	return merged
