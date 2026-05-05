extends RefCounted
class_name SimulationRuntime

const DEFAULT_FIXED_STEP := 0.25
const DEFAULT_LOCALE := "ja"

const TEXT := {
	"ja": {
		"time_rule_already_active": "時間のルールはすでに有効です。",
		"time_rule_installed": "時間のルールを作成しました。世界に戻ると右上に時計が表示されます。",
		"time_rule_install_failed": "時間のルールの適用に失敗しました: %s",
		"time_rule_load_failed": "時間のルール定義を読み込めませんでした。",
		"help_prompt": "時間のルールを作成しろ、と言ってください。",
		"player_name": "プレイヤー",
		"gm_name": "ゲームマスター",
		"player_task": "最初のルールを待っています",
		"gm_task": "プレイヤーの依頼を待っています",
		"world_bootstrap": "プレイヤーとゲームマスターがいる世界を初期化しました。"
	},
	"en": {
		"time_rule_already_active": "The time rule is already active.",
		"time_rule_installed": "The time rule has been created. Return to the world to see the clock in the top-right.",
		"time_rule_install_failed": "Failed to apply the time rule: %s",
		"time_rule_load_failed": "Failed to load the time rule definition.",
		"help_prompt": "Ask me to create the time rule.",
		"player_name": "Player",
		"gm_name": "Game Master",
		"player_task": "Waiting for the first rule",
		"gm_task": "Waiting for the player's request",
		"world_bootstrap": "Initialized the world with one player and one game master."
	}
}

var fixed_step_seconds: float = DEFAULT_FIXED_STEP
var _accumulator_seconds: float = 0.0
var _world_state: Dictionary = {}
var _template_index: Dictionary = {}
var _clone_sequence: int = 0
var _locale: String = DEFAULT_LOCALE


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


func talk_to_game_master(message: String) -> Dictionary:
	var normalized_message := message.strip_edges().to_lower()
	var conversation_log: Array = _world_state.get("conversation_log", [])
	
	conversation_log.append({
		"speaker": "player",
		"text": message
	})
	
	var gm_response := ""
	var action_taken := ""
	var time_rule_triggers := [
		"create time rule",
		"create the time rule",
		"make time rule",
		"install time rule",
		"add time rule",
		"時間のルールを作成",
		"時間のルールを作成しろ",
		"時間ルールを作成",
		"タイムルールを作成"
	]
	
	var matched := false
	for trigger in time_rule_triggers:
		if normalized_message.find(trigger.to_lower()) != -1:
			matched = true
			break
	
	if matched:
		var installed_rules: Dictionary = _world_state.get("installed_rules", {})
		if installed_rules.has("time_counter"):
			gm_response = _text("time_rule_already_active")
			action_taken = "none"
		else:
			var time_rule_patch: Dictionary = _load_time_rule_package()
			if not time_rule_patch.is_empty():
				var result := create_rule_from_patch(time_rule_patch)
				if result.get("status", "") == "installed":
					gm_response = _text("time_rule_installed")
					action_taken = "installed_time_rule"
				else:
					gm_response = _text("time_rule_install_failed") % result.get("message", "unknown error")
					action_taken = "error"
			else:
				gm_response = _text("time_rule_load_failed")
				action_taken = "error"
	else:
		gm_response = _text("help_prompt")
		action_taken = "none"
	
	conversation_log.append({
		"speaker": "gm",
		"text": gm_response
	})
	
	_world_state["conversation_log"] = conversation_log
	_append_event("gm_conversation", "Player talked to Game Master.", {"message": message, "response": gm_response})
	
	return {
		"status": "ok",
		"action": action_taken,
		"reply": gm_response,
		"gm_response": gm_response,
		"conversation_log": conversation_log.duplicate(true)
	}


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
	snapshot["installed_rules_by_id"] = installed_rules_by_id
	snapshot["installed_rules"] = installed_rules
	snapshot["tick"] = snapshot.get("tick_index", 0)
	snapshot["world_name"] = "Null World"
	snapshot["characters"] = _build_character_list(snapshot.get("entities", {}))
	snapshot["events"] = _build_event_messages(snapshot.get("event_log", []))
	snapshot["conversation_log"] = snapshot.get("conversation_log", []).duplicate(true)
	snapshot["clock"] = _build_clock_data(snapshot.get("entities", {}), installed_rules_by_id)
	return snapshot


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
		"world_clock": {},
		"entities": {
			"player_character": {
				"id": "player_character",
				"name": _text("player_name"),
				"archetype": "player",
				"tags": ["player", "mortal", "mutable"],
				"components": {
					"needs": {},
					"stats": {},
					"traits": {
						"curiosity": 1.0,
						"morale": 50.0,
						"focus": 50.0
					},
					"behavior": {
						"current_task": _text("player_task")
					}
				}
			},
			"game_master": {
				"id": "game_master",
				"name": _text("gm_name"),
				"archetype": "gm",
				"tags": ["gm", "immortal", "immutable"],
				"components": {
					"traits": {
						"authority": 100.0
					},
					"behavior": {
						"current_task": _text("gm_task")
					}
				}
			}
		},
		"installed_rules": {},
		"player_task_history": [],
		"conversation_log": [],
		"event_log": [
			{
				"type": "world_initialized",
				"message": _text("world_bootstrap"),
				"details": {}
			}
		]
	}


func _run_tick(step_seconds: float) -> void:
	var entities: Dictionary = _world_state.get("entities", {})
	var installed_rules: Dictionary = _world_state.get("installed_rules", {})
	var entity_ids: Array = entities.keys()
	var rule_ids: Array = installed_rules.keys()
	entity_ids.sort()
	rule_ids.sort()

	for rule_id in rule_ids:
		var rule: Dictionary = installed_rules[rule_id]
		if not bool(rule.get("enabled", true)):
			continue
		
		var rule_scope := String(rule.get("scope", "entity"))
		if rule_scope == "world":
			_apply_world_rule(rule, step_seconds)

	for entity_id in entity_ids:
		var entity: Dictionary = entities[entity_id]
		for rule_id in rule_ids:
			var rule: Dictionary = installed_rules[rule_id]
			if not bool(rule.get("enabled", true)):
				continue
			var rule_scope := String(rule.get("scope", "entity"))
			if rule_scope != "entity":
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


func _apply_world_rule(rule: Dictionary, step_seconds: float) -> void:
	var world_clock: Dictionary = _world_state.get("world_clock", {})
	
	for effect in rule.get("effects", []):
		var component_name := String(effect.get("component", "world_clock"))
		if component_name != "world_clock":
			continue
		
		var field_name := String(effect.get("field", "value"))
		var current_value := float(world_clock.get(field_name, effect.get("default", 0.0)))
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
		
		world_clock[field_name] = snappedf(next_value, 0.0001)
	
	if world_clock.has("total_ticks"):
		world_clock["total_ticks"] = int(_world_state.get("tick_index", 0)) + 1
	
	_world_state["world_clock"] = world_clock


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
			"energy": max(0.0, 100.0 - float(needs.get("sleep", 0.0))),
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


func _load_time_rule_package() -> Dictionary:
	var time_package_path := "res://rules/packages/time.rule.json"
	if not FileAccess.file_exists(time_package_path):
		push_error("Time rule package not found at %s" % time_package_path)
		return {}
	
	var file := FileAccess.open(time_package_path, FileAccess.READ)
	if file == null:
		push_error("Failed to open time rule package: %s" % FileAccess.get_open_error())
		return {}
	
	var json_text := file.get_as_text()
	file.close()
	
	var json := JSON.new()
	var parse_result := json.parse(json_text)
	if parse_result != OK:
		push_error("Failed to parse time rule package JSON: %s" % json.get_error_message())
		return {}
	
	var package_data: Dictionary = json.data if json.data is Dictionary else {}
	return package_data.get("rule_patch", {})


func _build_clock_data(entities: Dictionary, installed_rules: Dictionary) -> Dictionary:
	var time_rule_active := installed_rules.has("time_counter")
	
	if not time_rule_active:
		return {
			"visible": false,
			"total_seconds": 0.0,
			"day": 0,
			"hour": 0,
			"minute": 0,
			"second": 0,
			"formatted": ""
		}
	
	var player_entity: Dictionary = entities.get("player_character", {})
	var components: Dictionary = player_entity.get("components", {})
	var time_component: Dictionary = components.get("time", {})
	var total_seconds := float(time_component.get("elapsed_seconds", 0.0))
	
	var total_int := int(total_seconds)
	var day := (total_int / 86400) + 1
	var remaining := total_int % 86400
	var hour := remaining / 3600
	remaining = remaining % 3600
	var minute := remaining / 60
	var second := remaining % 60
	
	var formatted := "%dd %02d:%02d:%02d" % [day, hour, minute, second]
	
	return {
		"visible": true,
		"total_seconds": total_seconds,
		"day": day,
		"hour": hour,
		"minute": minute,
		"second": second,
		"formatted": formatted
	}


func _text(key: String) -> String:
	var table: Dictionary = TEXT.get(_locale, TEXT[DEFAULT_LOCALE])
	return String(table.get(key, key))
