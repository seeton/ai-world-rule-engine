extends RefCounted
class_name SimulationRuntime

const DEFAULT_FIXED_STEP := 0.25
const DEFAULT_LOCALE := "ja"

const TEXT := {
		"ja": {
			"time_rule_already_active": "時間のルールはすでに有効です。",
			"time_rule_installed": "事前定義済みの時間ルール time_counter を適用しました。世界に戻ると右上に時計が表示されます。",
			"time_rule_install_failed": "時間のルールの適用に失敗しました: %s",
			"time_rule_load_failed": "時間のルール定義を読み込めませんでした。",
		"object_rule_already_active": "オブジェクトルールはすでに有効です。",
		"object_rule_installed": "オブジェクトルールを適用しました。物体一覧とルールツリーにオブジェクト基礎が反映されます。",
		"object_rule_install_failed": "オブジェクトルールの適用に失敗しました: %s",
			"ownership_rule_already_active": "所有ルールはすでに有効です。",
			"ownership_rule_installed": "所有ルールを適用しました。物体の所有者情報と親子ルール関係が更新されます。",
			"ownership_rule_install_failed": "所有ルールの適用に失敗しました: %s",
			"parent_tree_rule_already_active": "親子ツリールールはすでに有効です。",
			"parent_tree_rule_installed": "親子ツリールールを適用しました。ベリー束→道具袋、水瓶→倉庫 の関係がルールツリーと物体状態に反映されます。",
			"parent_tree_rule_install_failed": "親子ツリールールの適用に失敗しました: %s",
			"help_prompt": "「時間のルールを作成しろ」「オブジェクトルールを作成しろ」「所有ルールを作成しろ」「親子ツリーを作成しろ」と言ってください。",
			"player_name": "プレイヤー",
			"gm_name": "ゲームマスター",
			"player_task": "最初のルールを待っています",
			"gm_task": "プレイヤーの依頼を待っています",
			"world_bootstrap": "プレイヤーとゲームマスターがいる世界を初期化しました。"
	},
	"en": {
		"time_rule_already_active": "The time rule is already active.",
		"time_rule_installed": "Applied the predefined time rule 'time_counter'. Return to the world to see the clock in the top-right.",
		"time_rule_install_failed": "Failed to apply the time rule: %s",
		"time_rule_load_failed": "Failed to load the time rule definition.",
		"object_rule_already_active": "The object rule is already active.",
		"object_rule_installed": "Applied the object rule. The object list and rule tree now include the object-base capability.",
			"object_rule_install_failed": "Failed to apply the object rule: %s",
			"ownership_rule_already_active": "The ownership rule is already active.",
			"ownership_rule_installed": "Applied the ownership rule. Object ownership data and rule parent-child links were updated.",
			"ownership_rule_install_failed": "Failed to apply the ownership rule: %s",
			"parent_tree_rule_already_active": "The parent-child tree rule is already active.",
			"parent_tree_rule_installed": "Applied the parent-child tree rule. Berry bundle → satchel and water jar → storehouse links now appear in the rule tree and object state.",
			"parent_tree_rule_install_failed": "Failed to apply the parent-child tree rule: %s",
			"help_prompt": "Ask me to create the time rule, object rule, ownership rule, or parent-child tree rule.",
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
	_append_event("player_task_submitted", "プレイヤーがルール提案タスクを送信しました。", {"task": task_result.get("task_text", "")})


func talk_to_game_master(message: String) -> Dictionary:
	var normalized_message := message.strip_edges().to_lower()
	var conversation_log: Array = _world_state.get("conversation_log", [])

	conversation_log.append({
		"speaker": "player",
		"text": message
	})

	var gm_response := ""
	var action_taken := "none"
	var installed_rule_id := ""
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
	var object_rule_triggers := [
		"create object rule",
		"make object rule",
		"install object rule",
		"add object rule",
		"create object base",
		"install object base",
		"オブジェクトルールを作成",
		"オブジェクトルールを作成しろ",
		"オブジェクトルールを追加",
		"オブジェクト基礎を作成",
		"物体ルールを作成"
	]
	var ownership_rule_triggers := [
		"create ownership rule",
		"make ownership rule",
		"install ownership rule",
		"add ownership rule",
		"オーナーシップルールを作成",
		"所有ルールを作成",
		"所有ルールを作成しろ",
		"所有ルールを追加",
		"所有関係ルールを作成"
	]
	var parent_tree_rule_triggers := [
		"create parent tree rule",
		"create parent-child rule",
		"install parent tree rule",
		"install parent-child rule",
		"add parent tree rule",
		"親子ツリーを作成",
		"親子ツリーを作成しろ",
		"親子ルールを作成",
		"親子ルールを追加",
		"ツリーを作成"
	]

	if _message_has_trigger(normalized_message, parent_tree_rule_triggers):
		var parent_tree_rule_result := _install_template_rule(
			"parent_child_tree",
			"rule_parent_child_tree",
			"parent_tree_rule_already_active",
			"parent_tree_rule_installed",
			"parent_tree_rule_install_failed",
			"installed_parent_tree_rule"
		)
		gm_response = String(parent_tree_rule_result.get("reply", ""))
		action_taken = String(parent_tree_rule_result.get("action", "error"))
		installed_rule_id = String(parent_tree_rule_result.get("installed_rule_id", ""))
	elif _message_has_trigger(normalized_message, ownership_rule_triggers):
		var ownership_rule_result := _install_template_rule(
			"ownership_links",
			"rule_ownership_links",
			"ownership_rule_already_active",
			"ownership_rule_installed",
			"ownership_rule_install_failed",
			"installed_ownership_rule"
		)
		gm_response = String(ownership_rule_result.get("reply", ""))
		action_taken = String(ownership_rule_result.get("action", "error"))
		installed_rule_id = String(ownership_rule_result.get("installed_rule_id", ""))
	elif _message_has_trigger(normalized_message, object_rule_triggers):
		var object_rule_result := _install_template_rule(
			"object_base",
			"rule_object_base",
			"object_rule_already_active",
			"object_rule_installed",
			"object_rule_install_failed",
			"installed_object_rule"
		)
		gm_response = String(object_rule_result.get("reply", ""))
		action_taken = String(object_rule_result.get("action", "error"))
		installed_rule_id = String(object_rule_result.get("installed_rule_id", ""))
	elif _message_has_trigger(normalized_message, time_rule_triggers):
		var installed_rules: Dictionary = _world_state.get("installed_rules", {})
		if installed_rules.has("time_counter"):
			gm_response = _text("time_rule_already_active")
		else:
			var time_rule_patch: Dictionary = _load_time_rule_package()
			if not time_rule_patch.is_empty():
				var result := create_rule_from_patch(time_rule_patch)
				if result.get("status", "") == "installed":
					gm_response = _text("time_rule_installed")
					action_taken = "installed_time_rule"
					installed_rule_id = "time_counter"
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
	_append_event("gm_conversation", "プレイヤーがゲームマスターに話しかけました。", {"message": message, "response": gm_response})

	return {
		"status": "ok",
		"action": action_taken,
		"reply": gm_response,
		"gm_response": gm_response,
		"installed_rule_id": installed_rule_id,
		"conversation_log": conversation_log.duplicate(true)
	}


func _message_has_trigger(normalized_message: String, triggers: Array) -> bool:
	for trigger in triggers:
		if normalized_message.find(String(trigger).to_lower()) != -1:
			return true
	return false


func _install_template_rule(
	template_id: String,
	rule_id: String,
	already_active_text_key: String,
	installed_text_key: String,
	failed_text_key: String,
	action_name: String
) -> Dictionary:
	var installed_rules: Dictionary = _world_state.get("installed_rules", {})
	if installed_rules.has(rule_id):
		return {
			"reply": _text(already_active_text_key),
			"action": "none",
			"installed_rule_id": ""
		}

	var result := create_rule_from_patch({"template_id": template_id})
	if String(result.get("status", "")) == "installed":
		return {
			"reply": _text(installed_text_key),
			"action": action_name,
			"installed_rule_id": rule_id
		}

	return {
		"reply": _text(failed_text_key) % result.get("message", "unknown error"),
		"action": "error",
		"installed_rule_id": "",
		"result": result
	}


func create_rule_from_patch(rule_patch: Dictionary) -> Dictionary:
	var normalized_rule := _normalize_rule_patch(rule_patch)
	if normalized_rule.is_empty():
		return {
			"status": "error",
			"message": "ルールパッチが空、または不正です。"
		}

	return _install_normalized_rule(normalized_rule)


func clone_rule(rule_id: String) -> Dictionary:
	var installed_rules: Dictionary = _world_state.get("installed_rules", {})
	if not installed_rules.has(rule_id):
		if _template_index.has(rule_id):
			var template_rule: Dictionary = _template_index[rule_id].get("rule_patch", {}).duplicate(true)
			template_rule["id"] = _make_unique_rule_id(String(template_rule.get("id", "rule_%s" % rule_id)))
			template_rule["name"] = "%s（導入済み）" % String(_template_index[rule_id].get("name", rule_id))
			return create_rule_from_patch(template_rule)

		return {
			"status": "error",
			"message": "ルール '%s' は未導入で、対応するテンプレートもありません。" % rule_id
		}

	var cloned_rule: Dictionary = installed_rules[rule_id].duplicate(true)
	var clone_id := _make_unique_rule_id("%s_clone" % rule_id)
	cloned_rule["id"] = clone_id
	cloned_rule["name"] = "%s（複製）" % String(cloned_rule.get("name", rule_id))
	cloned_rule["source_rule_id"] = rule_id

	var install_result := create_rule_from_patch(cloned_rule)
	if String(install_result.get("status", "")) == "installed":
		install_result["status"] = "cloned"
		install_result["source_rule_id"] = rule_id
		_append_event("rule_cloned", "ルール '%s' を '%s' として複製しました。" % [rule_id, clone_id], {"rule_id": rule_id, "clone_id": clone_id})
	return install_result


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
	snapshot["objects"] = _build_object_list(snapshot.get("entities", {}))
	snapshot["rule_tree"] = _build_rule_tree(installed_rules_by_id)
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


func set_entity_position(entity_id: String, position_patch: Dictionary) -> Dictionary:
	if entity_id.is_empty():
		return {}
	var entities: Dictionary = _world_state.get("entities", {})
	if not entities.has(entity_id):
		return {}
	var entity: Dictionary = entities[entity_id].duplicate(true)
	var current_position: Dictionary = entity.get("position", {}).duplicate(true) if entity.get("position", {}) is Dictionary else {}
	entity["position"] = _merge_dictionaries(current_position, position_patch)
	entities[entity_id] = entity
	_world_state["entities"] = entities
	return entity.get("position", {}).duplicate(true)


func _install_normalized_rule(normalized_rule: Dictionary) -> Dictionary:
	var rule_id := String(normalized_rule.get("id", ""))
	var installed_rules: Dictionary = _world_state.get("installed_rules", {})
	if installed_rules.has(rule_id):
		return {
			"status": "error",
			"message": "ルール '%s' はすでに導入済みです。" % rule_id
		}

	var parent_resolution := _resolve_parent_rule_links(normalized_rule, installed_rules)
	if String(parent_resolution.get("status", "")) == "error":
		_append_event(
			"rule_waiting_for_parent",
			String(parent_resolution.get("message", "Missing required parent rule kinds.")),
			{
				"rule_id": rule_id,
				"missing_required_rule_kinds": parent_resolution.get("missing_required_rule_kinds", []).duplicate(true)
			}
		)
		return parent_resolution

	normalized_rule["resolved_parent_rule_ids"] = parent_resolution.get("resolved_parent_rule_ids", []).duplicate(true)
	normalized_rule["resolved_parent_rule_links"] = parent_resolution.get("resolved_parent_rule_links", []).duplicate(true)
	normalized_rule["missing_required_rule_kinds"] = []

	installed_rules[rule_id] = normalized_rule
	_world_state["installed_rules"] = installed_rules
	_apply_install_actions(normalized_rule)
	_initialize_rule_targets(normalized_rule)
	_append_concept(normalized_rule.get("concept", rule_id))
	_refresh_rule_relationships()
	_append_event("rule_installed", "ルール '%s' を導入しました。" % rule_id, {"rule_id": rule_id})

	return {
		"status": "installed",
		"installed": true,
		"rule": normalized_rule.duplicate(true)
	}


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
	merged_rule["requires_rule_kinds"] = _normalize_string_array(_extract_rule_array_metadata(merged_rule, "requires_rule_kinds"))
	merged_rule["provides_rule_kinds"] = _normalize_string_array(_extract_rule_array_metadata(merged_rule, "provides_rule_kinds"))
	merged_rule["install_actions"] = _normalize_install_actions(_extract_rule_array_metadata(merged_rule, "install_actions"))
	merged_rule["resolved_parent_rule_ids"] = []
	merged_rule["resolved_parent_rule_links"] = []
	merged_rule["missing_required_rule_kinds"] = []
	var target_tags: Array = []
	for tag in merged_rule.get("target_tags", []):
		target_tags.append(String(tag))
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


func _resolve_parent_rule_links(rule: Dictionary, installed_rules: Dictionary) -> Dictionary:
	var required_rule_kinds: Array = rule.get("requires_rule_kinds", [])
	var missing_rule_kinds: Array = []
	var resolved_parent_rule_ids: Array = []
	var resolved_parent_rule_links: Array = []
	var installed_rule_ids: Array = installed_rules.keys()
	installed_rule_ids.sort()
	var rule_id := String(rule.get("id", ""))

	for required_kind_variant in required_rule_kinds:
		var required_kind := String(required_kind_variant).strip_edges()
		if required_kind.is_empty():
			continue

		var matching_rule_ids: Array = []
		for installed_rule_id in installed_rule_ids:
			var candidate_rule: Dictionary = installed_rules[installed_rule_id]
			if String(candidate_rule.get("id", installed_rule_id)) == rule_id:
				continue
			if _rule_provides_kind(candidate_rule, required_kind):
				matching_rule_ids.append(installed_rule_id)
				if not resolved_parent_rule_ids.has(installed_rule_id):
					resolved_parent_rule_ids.append(installed_rule_id)
		matching_rule_ids.sort()
		resolved_parent_rule_links.append({
			"required_kind": required_kind,
			"rule_ids": matching_rule_ids.duplicate(true)
		})
		if matching_rule_ids.is_empty():
			missing_rule_kinds.append(required_kind)

	resolved_parent_rule_ids.sort()
	if not missing_rule_kinds.is_empty():
		return {
			"status": "error",
			"message": "ルール '%s' は親ルール種別 [%s] の導入後でないと適用できません。" % [rule_id, ", ".join(missing_rule_kinds)],
			"rule_id": rule_id,
			"requires_rule_kinds": required_rule_kinds.duplicate(true),
			"missing_required_rule_kinds": missing_rule_kinds.duplicate(true)
		}

	return {
		"status": "resolved",
		"resolved_parent_rule_ids": resolved_parent_rule_ids.duplicate(true),
		"resolved_parent_rule_links": resolved_parent_rule_links.duplicate(true),
		"missing_required_rule_kinds": []
	}


func _rule_provides_kind(rule: Dictionary, required_kind: String) -> bool:
	for provided_kind_variant in rule.get("provides_rule_kinds", []):
		if String(provided_kind_variant).strip_edges() == required_kind:
			return true
	return false


func _apply_install_actions(rule: Dictionary) -> void:
	var entities: Dictionary = _world_state.get("entities", {})
	for raw_action in rule.get("install_actions", []):
		if not (raw_action is Dictionary):
			continue
		var action: Dictionary = raw_action
		if String(action.get("op", "")) != "upsert_entities":
			continue
		for raw_entity_patch in action.get("entities", []):
			if not (raw_entity_patch is Dictionary):
				continue
			var entity_patch: Dictionary = raw_entity_patch
			var entity_id := String(entity_patch.get("id", ""))
			if entity_id.is_empty():
				continue
			var existing_entity: Dictionary = entities.get(entity_id, {})
			var merged_entity := _merge_dictionaries(existing_entity, entity_patch)
			entities[entity_id] = _normalize_entity(merged_entity)
	_world_state["entities"] = entities


func _refresh_rule_relationships() -> void:
	var installed_rules: Dictionary = _world_state.get("installed_rules", {})
	var rule_ids: Array = installed_rules.keys()
	rule_ids.sort()

	for rule_id in rule_ids:
		var rule: Dictionary = installed_rules[rule_id]
		var parent_resolution := _resolve_parent_rule_links(rule, installed_rules)
		rule["resolved_parent_rule_ids"] = parent_resolution.get("resolved_parent_rule_ids", []).duplicate(true)
		rule["resolved_parent_rule_links"] = parent_resolution.get("resolved_parent_rule_links", []).duplicate(true)
		rule["missing_required_rule_kinds"] = parent_resolution.get("missing_required_rule_kinds", []).duplicate(true)
		installed_rules[rule_id] = rule

	_world_state["installed_rules"] = installed_rules


func _initialize_rule_targets(rule: Dictionary) -> void:
	if String(rule.get("scope", "entity")) == "world":
		return

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


func _build_object_list(entities: Dictionary) -> Array:
	var objects_by_id: Dictionary = {}
	var entity_ids: Array = entities.keys()
	entity_ids.sort()

	for entity_id in entity_ids:
		var entity: Dictionary = entities[entity_id]
		var entity_tags: Array = entity.get("tags", [])
		if not entity_tags.has("object"):
			continue
		var components: Dictionary = entity.get("components", {})
		var ownership: Dictionary = components.get("ownership", {})
		objects_by_id[entity_id] = {
			"id": entity.get("id", entity_id),
			"name": entity.get("name", entity_id),
			"material": entity.get("material", ""),
			"weight": entity.get("weight", 0.0),
			"position": entity.get("position", {}).duplicate(true) if entity.get("position", {}) is Dictionary else entity.get("position", {}),
			"portability": entity.get("portability", {}).duplicate(true) if entity.get("portability", {}) is Dictionary else entity.get("portability", {}),
			"state": entity.get("state", {}).duplicate(true) if entity.get("state", {}) is Dictionary else entity.get("state", {}),
			"owner": ownership.duplicate(true) if ownership is Dictionary else {},
			"container_id": "",
			"location_id": "",
			"child_ids": []
		}

	for entity_id in entity_ids:
		var entity: Dictionary = entities[entity_id]
		var entity_tags: Array = entity.get("tags", [])
		if not entity_tags.has("object") or not objects_by_id.has(entity_id):
			continue

		var components: Dictionary = entity.get("components", {})
		var containment: Dictionary = components.get("containment", {})
		var placement: Dictionary = components.get("placement", {})
		var position_value = entity.get("position", {})
		var position: Dictionary = {}
		if position_value is Dictionary:
			position = position_value.duplicate(true)
		var container_id := String(containment.get("container_entity_id", ""))
		var location_id := String(placement.get("location_entity_id", position.get("location", "")))
		var object_entry: Dictionary = objects_by_id[entity_id]
		object_entry["container_id"] = container_id
		object_entry["location_id"] = location_id
		objects_by_id[entity_id] = object_entry

		if not container_id.is_empty() and objects_by_id.has(container_id):
			var container_entry: Dictionary = objects_by_id[container_id]
			var container_child_ids: Array = container_entry.get("child_ids", [])
			if not container_child_ids.has(entity_id):
				container_child_ids.append(entity_id)
				container_child_ids.sort()
			container_entry["child_ids"] = container_child_ids
			objects_by_id[container_id] = container_entry

		if not location_id.is_empty() and objects_by_id.has(location_id):
			var location_entry: Dictionary = objects_by_id[location_id]
			var location_child_ids: Array = location_entry.get("child_ids", [])
			if not location_child_ids.has(entity_id):
				location_child_ids.append(entity_id)
				location_child_ids.sort()
			location_entry["child_ids"] = location_child_ids
			objects_by_id[location_id] = location_entry

	var objects: Array = []
	for entity_id in entity_ids:
		if objects_by_id.has(entity_id):
			objects.append(objects_by_id[entity_id])
	return objects


func _build_rule_tree(installed_rules_by_id: Dictionary) -> Dictionary:
	var rule_ids: Array = installed_rules_by_id.keys()
	rule_ids.sort()
	var nodes_by_rule_id: Dictionary = {}
	var root_rule_ids: Array = []

	for rule_id in rule_ids:
		var rule: Dictionary = installed_rules_by_id[rule_id]
		nodes_by_rule_id[rule_id] = {
			"rule_id": rule_id,
			"name": rule.get("name", rule_id),
			"requires_rule_kinds": rule.get("requires_rule_kinds", []).duplicate(true),
			"provides_rule_kinds": rule.get("provides_rule_kinds", []).duplicate(true),
			"resolved_parent_rule_ids": rule.get("resolved_parent_rule_ids", []).duplicate(true),
			"child_rule_ids": []
		}

	for rule_id in rule_ids:
		var parent_rule_ids: Array = installed_rules_by_id[rule_id].get("resolved_parent_rule_ids", [])
		if parent_rule_ids.is_empty():
			root_rule_ids.append(rule_id)
		for parent_rule_id in parent_rule_ids:
			if not nodes_by_rule_id.has(parent_rule_id):
				continue
			var parent_node: Dictionary = nodes_by_rule_id[parent_rule_id]
			var child_rule_ids: Array = parent_node.get("child_rule_ids", [])
			if not child_rule_ids.has(rule_id):
				child_rule_ids.append(rule_id)
				child_rule_ids.sort()
			parent_node["child_rule_ids"] = child_rule_ids
			nodes_by_rule_id[parent_rule_id] = parent_node

	root_rule_ids.sort()
	var roots: Array = []
	for root_rule_id in root_rule_ids:
		roots.append(_build_rule_tree_node(root_rule_id, nodes_by_rule_id, []))

	return {
		"root_rule_ids": root_rule_ids,
		"nodes_by_rule_id": nodes_by_rule_id,
		"roots": roots
	}


func _build_rule_tree_node(rule_id: String, nodes_by_rule_id: Dictionary, ancestry: Array) -> Dictionary:
	var node: Dictionary = nodes_by_rule_id.get(rule_id, {}).duplicate(true)
	if ancestry.has(rule_id):
		node["children"] = []
		return node

	var next_ancestry := ancestry.duplicate(true)
	next_ancestry.append(rule_id)
	var children: Array = []
	for child_rule_id in node.get("child_rule_ids", []):
		children.append(_build_rule_tree_node(String(child_rule_id), nodes_by_rule_id, next_ancestry))
	node["children"] = children
	return node


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


func _extract_rule_array_metadata(rule: Dictionary, key: String) -> Array:
	if rule.has(key) and rule[key] is Array:
		return rule[key]
	var metadata: Dictionary = rule.get("metadata", {})
	if metadata.has(key) and metadata[key] is Array:
		return metadata[key]
	return []


func _normalize_string_array(values: Array) -> Array:
	var normalized: Array = []
	for value in values:
		var normalized_value := String(value).strip_edges()
		if normalized_value.is_empty() or normalized.has(normalized_value):
			continue
		normalized.append(normalized_value)
	return normalized


func _normalize_install_actions(raw_actions: Array) -> Array:
	var normalized_actions: Array = []
	for raw_action in raw_actions:
		if not raw_action is Dictionary:
			continue
		var action: Dictionary = raw_action.duplicate(true)
		action["op"] = String(action.get("op", ""))
		var normalized_entities: Array = []
		for raw_entity in action.get("entities", []):
			if raw_entity is Dictionary:
				normalized_entities.append(raw_entity.duplicate(true))
		action["entities"] = normalized_entities
		if not String(action.get("op", "")).is_empty():
			normalized_actions.append(action)
	return normalized_actions


func _normalize_entity(entity: Dictionary) -> Dictionary:
	var normalized_entity := entity.duplicate(true)
	var entity_id := String(normalized_entity.get("id", ""))
	if entity_id.is_empty():
		return {}

	normalized_entity["id"] = entity_id
	normalized_entity["name"] = String(normalized_entity.get("name", entity_id))
	normalized_entity["archetype"] = String(normalized_entity.get("archetype", "entity"))
	normalized_entity["tags"] = _normalize_string_array(normalized_entity.get("tags", []))
	if not normalized_entity.has("components") or not (normalized_entity["components"] is Dictionary):
		normalized_entity["components"] = {}
	return normalized_entity


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
