extends RefCounted
class_name SimulationRuntime

const DEFAULT_FIXED_STEP := 0.25
const WORLD_SNAPSHOT_TYPE := "godot_world_state_snapshot"
const WORLD_SNAPSHOT_VERSION := 1
const DEFAULT_THREE_D_CAMERA := {
	"position": {"x": 6.6, "y": 6.0, "z": -7.4},
	"look_at": {"x": 0.0, "y": 1.4, "z": 0.4},
	"fov_degrees": 60.0
}
const DEFAULT_THREE_D_LIGHTING := {
	"enabled": true,
	"shadows_enabled": true,
	"light_rotation_degrees": {"x": -58.0, "y": 36.0, "z": 0.0},
	"color": "#fff1cf",
	"intensity": 1.4
}
const DEFAULT_THREE_D_GRAVITY := {
	"enabled": false,
	"floor_y": 0.0,
	"acceleration": 9.8
}
const CHARACTER_ARCHETYPE_HINTS := ["actor", "character", "gm", "npc", "origin", "person", "villager"]
const CHARACTER_TAG_HINTS := ["agent", "character", "gm", "mortal", "npc", "person", "villager"]
const GM_ARCHETYPE_HINTS := ["director", "game_master", "gm"]
const GM_TAG_HINTS := ["director", "game_master", "gm"]

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
	_append_event("player_task_submitted", "プレイヤーがルール候補用のタスクを送信しました。", {"task": task_result.get("task_text", "")})


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
			template_rule["name"] = "%s (Installed)" % String(_template_index[rule_id].get("name", rule_id))
			return create_rule_from_patch(template_rule)

		return {
			"status": "error",
			"message": "ルール '%s' は未導入で、対応するテンプレートもありません。" % rule_id
		}

	var cloned_rule: Dictionary = installed_rules[rule_id].duplicate(true)
	var clone_id := _make_unique_rule_id("%s_clone" % rule_id)
	cloned_rule["id"] = clone_id
	cloned_rule["name"] = "%s (Clone)" % String(cloned_rule.get("name", rule_id))
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
	snapshot["world_mode"] = "three_d" if bool(_world_state.get("preview_3d", {}).get("enabled", false)) else "two_d"
	snapshot["tick"] = snapshot.get("tick_index", 0)
	snapshot["world_name"] = snapshot.get("world_name", "はじまりの広場")
	snapshot["characters"] = _build_character_list(snapshot.get("entities", {}))
	snapshot["objects"] = _build_object_list(snapshot.get("entities", {}))
	snapshot["three_d_preview"] = _build_three_d_preview(snapshot.get("entities", {}), snapshot.get("preview_3d", {}))
	snapshot["rule_tree"] = _build_rule_tree(installed_rules_by_id)
	var world_clock := _build_world_clock_summary(installed_rules_by_id, snapshot)
	if not world_clock.is_empty():
		snapshot["world_clock"] = world_clock
	snapshot["events"] = _build_event_messages(snapshot.get("event_log", []))
	return snapshot


func create_snapshot() -> Dictionary:
	var template_ids: Array = _template_index.keys()
	template_ids.sort()
	return {
		"snapshot_type": WORLD_SNAPSHOT_TYPE,
		"snapshot_version": WORLD_SNAPSHOT_VERSION,
		"runtime": {
			"fixed_step_seconds": fixed_step_seconds,
			"accumulator_seconds": _accumulator_seconds,
			"clone_sequence": _clone_sequence
		},
		"template_catalog": {
			"available_template_ids": template_ids.duplicate(true)
		},
		"world": _serialize_world_state()
	}


func restore_snapshot(snapshot_data: Dictionary) -> Dictionary:
	var normalized := _normalize_saved_snapshot(snapshot_data)
	if String(normalized.get("status", "")) == "error":
		return normalized

	fixed_step_seconds = float(normalized.get("fixed_step_seconds", DEFAULT_FIXED_STEP))
	_accumulator_seconds = float(normalized.get("accumulator_seconds", 0.0))
	_clone_sequence = int(normalized.get("clone_sequence", 0))
	_world_state = normalized.get("world_state", {}).duplicate(true)
	_world_state["fixed_step_seconds"] = fixed_step_seconds

	_refresh_rule_relationships()
	var installed_rules: Dictionary = _world_state.get("installed_rules", {})
	var rule_ids: Array = installed_rules.keys()
	rule_ids.sort()
	for rule_id in rule_ids:
		_initialize_rule_targets(installed_rules[rule_id])

	return {
		"status": "loaded",
		"snapshot": get_snapshot(),
		"saved_snapshot": create_snapshot()
	}


func save_snapshot(file_path: String) -> Dictionary:
	var normalized_path := String(file_path).strip_edges()
	if normalized_path.is_empty():
		return {
			"status": "error",
			"message": "保存先のパスが空です。"
		}

	var snapshot := create_snapshot()
	var file := FileAccess.open(normalized_path, FileAccess.WRITE)
	if file == null:
		var open_error := FileAccess.get_open_error()
		return {
			"status": "error",
			"message": "スナップショットを保存できませんでした: %s" % error_string(open_error),
			"path": normalized_path,
			"error_code": open_error
		}

	file.store_string("%s\n" % JSON.stringify(snapshot, "\t", true))
	return {
		"status": "saved",
		"path": normalized_path,
		"snapshot": snapshot
	}


func load_snapshot(file_path: String) -> Dictionary:
	var normalized_path := String(file_path).strip_edges()
	if normalized_path.is_empty():
		return {
			"status": "error",
			"message": "読み込み元のパスが空です。"
		}

	var file := FileAccess.open(normalized_path, FileAccess.READ)
	if file == null:
		var open_error := FileAccess.get_open_error()
		return {
			"status": "error",
			"message": "スナップショットを開けませんでした: %s" % error_string(open_error),
			"path": normalized_path,
			"error_code": open_error
		}

	var parser := JSON.new()
	var parse_error := parser.parse(file.get_as_text())
	if parse_error != OK:
		return {
			"status": "error",
			"message": "スナップショット JSON を解析できませんでした: %s" % parser.get_error_message(),
			"path": normalized_path,
			"line": parser.get_error_line()
		}

	if not (parser.data is Dictionary):
		return {
			"status": "error",
			"message": "スナップショットのルートは Dictionary である必要があります。",
			"path": normalized_path
		}

	var load_result := restore_snapshot(parser.data)
	load_result["path"] = normalized_path
	return load_result


func set_rule_enabled(rule_id: String, enabled: bool) -> Dictionary:
	var normalized_id := String(rule_id).strip_edges()
	if normalized_id.is_empty():
		return {
			"status": "error",
			"message": "ルール ID が空です。"
		}

	var installed_rules: Dictionary = _world_state.get("installed_rules", {})
	if not installed_rules.has(normalized_id):
		return {
			"status": "error",
			"message": "ルール '%s' は導入されていません。" % normalized_id,
			"rule_id": normalized_id
		}

	var rule: Dictionary = installed_rules[normalized_id]
	var previous_enabled := bool(rule.get("enabled", true))
	rule["enabled"] = enabled
	installed_rules[normalized_id] = rule
	_world_state["installed_rules"] = installed_rules

	if previous_enabled != enabled:
		var event_type := "rule_enabled" if enabled else "rule_disabled"
		var message := "ルール '%s' を有効化しました。" % normalized_id if enabled else "ルール '%s' を無効化しました。" % normalized_id
		_append_event(event_type, message, {"rule_id": normalized_id})

	return {
		"status": "enabled" if enabled else "disabled",
		"rule_id": normalized_id,
		"previous_enabled": previous_enabled,
		"enabled": enabled
	}


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
	var default_position := current_position if not current_position.is_empty() else {"x": 0.0, "y": 0.0, "z": 0.0}
	var next_position := _merge_dictionaries(current_position, position_patch)
	var normalized_position := _normalize_vector3_dict(next_position, default_position)
	for key in next_position.keys():
		if not normalized_position.has(key):
			normalized_position[key] = next_position[key]
	entity["position"] = normalized_position
	entities[entity_id] = entity
	_world_state["entities"] = entities
	return normalized_position.duplicate(true)


func _serialize_world_state() -> Dictionary:
	var serialized_world := _world_state.duplicate(true)
	serialized_world["fixed_step_seconds"] = fixed_step_seconds
	serialized_world["concepts"] = _normalize_string_array(_duplicate_array(serialized_world.get("concepts", [])))
	serialized_world["preview_3d"] = _serialize_preview_state(serialized_world.get("preview_3d", {}))
	serialized_world["entities"] = _serialize_entities(serialized_world.get("entities", {}))
	serialized_world["installed_rules"] = _serialize_installed_rules(serialized_world.get("installed_rules", {}))
	serialized_world["player_task_history"] = _duplicate_array(serialized_world.get("player_task_history", []))
	serialized_world["event_log"] = _duplicate_array(serialized_world.get("event_log", []))
	return serialized_world


func _normalize_saved_snapshot(snapshot_data: Dictionary) -> Dictionary:
	var snapshot_type := String(snapshot_data.get("snapshot_type", ""))
	if snapshot_type != WORLD_SNAPSHOT_TYPE:
		return {
			"status": "error",
			"message": "未対応のスナップショット形式です: %s" % snapshot_type
		}

	var snapshot_version := int(snapshot_data.get("snapshot_version", 0))
	if snapshot_version != WORLD_SNAPSHOT_VERSION:
		return {
			"status": "error",
			"message": "未対応のスナップショットバージョンです: %d" % snapshot_version
		}

	var runtime_data: Dictionary = snapshot_data.get("runtime", {}).duplicate(true) if snapshot_data.get("runtime", {}) is Dictionary else {}
	var world_data: Dictionary = snapshot_data.get("world", {}).duplicate(true) if snapshot_data.get("world", {}) is Dictionary else {}
	var next_fixed_step: float = max(0.001, float(runtime_data.get("fixed_step_seconds", world_data.get("fixed_step_seconds", DEFAULT_FIXED_STEP))))
	var next_world_state := _build_null_world_with_fixed_step(next_fixed_step)
	next_world_state = _merge_dictionaries(next_world_state, world_data)
	next_world_state["fixed_step_seconds"] = next_fixed_step
	next_world_state["concepts"] = _normalize_string_array(_duplicate_array(world_data.get("concepts", next_world_state.get("concepts", []))))
	next_world_state["preview_3d"] = _serialize_preview_state(world_data.get("preview_3d", next_world_state.get("preview_3d", {})))
	next_world_state["entities"] = _deserialize_entities(world_data.get("entities", next_world_state.get("entities", {})))
	next_world_state["installed_rules"] = _deserialize_installed_rules(world_data.get("installed_rules", next_world_state.get("installed_rules", {})))
	next_world_state["player_task_history"] = _duplicate_array(world_data.get("player_task_history", next_world_state.get("player_task_history", [])))
	next_world_state["event_log"] = _duplicate_array(world_data.get("event_log", next_world_state.get("event_log", [])))
	next_world_state["elapsed_seconds"] = max(0.0, float(world_data.get("elapsed_seconds", next_world_state.get("elapsed_seconds", 0.0))))
	next_world_state["tick_index"] = max(0, int(world_data.get("tick_index", next_world_state.get("tick_index", 0))))

	return {
		"status": "ok",
		"fixed_step_seconds": next_fixed_step,
		"accumulator_seconds": max(0.0, float(runtime_data.get("accumulator_seconds", 0.0))),
		"clone_sequence": max(0, int(runtime_data.get("clone_sequence", 0))),
		"world_state": next_world_state
	}


func _build_null_world_with_fixed_step(step_seconds: float) -> Dictionary:
	var previous_fixed_step := fixed_step_seconds
	fixed_step_seconds = step_seconds
	var world_state := _build_null_world()
	fixed_step_seconds = previous_fixed_step
	world_state["fixed_step_seconds"] = step_seconds
	return world_state


func _serialize_preview_state(raw_preview: Variant) -> Dictionary:
	var merged_preview := _build_default_three_d_preview_state()
	if raw_preview is Dictionary:
		merged_preview = _merge_dictionaries(merged_preview, raw_preview)

	var enabled := bool(merged_preview.get("enabled", false))
	merged_preview["enabled"] = enabled
	merged_preview["lighting"] = _normalize_preview_lighting(merged_preview.get("lighting", {}), enabled)
	merged_preview["gravity"] = _normalize_preview_gravity(merged_preview.get("gravity", {}), enabled)
	merged_preview["camera"] = _normalize_preview_camera(merged_preview.get("camera", {}))
	return merged_preview


func _serialize_entities(raw_entities: Variant) -> Array:
	var serialized_entities: Array = []
	if not (raw_entities is Dictionary):
		return serialized_entities

	var entity_ids: Array = raw_entities.keys()
	entity_ids.sort()
	for entity_id in entity_ids:
		if not (raw_entities[entity_id] is Dictionary):
			continue
		var entity_data: Dictionary = raw_entities[entity_id].duplicate(true)
		if String(entity_data.get("id", "")).is_empty():
			entity_data["id"] = String(entity_id)
		var normalized_entity := _normalize_entity(entity_data)
		if not normalized_entity.is_empty():
			serialized_entities.append(normalized_entity)
	return serialized_entities


func _serialize_installed_rules(raw_rules: Variant) -> Array:
	var serialized_rules: Array = []
	if not (raw_rules is Dictionary):
		return serialized_rules

	var rule_ids: Array = raw_rules.keys()
	rule_ids.sort()
	for rule_id in rule_ids:
		if not (raw_rules[rule_id] is Dictionary):
			continue
		var rule_data: Dictionary = raw_rules[rule_id].duplicate(true)
		if String(rule_data.get("id", "")).is_empty():
			rule_data["id"] = String(rule_id)
		serialized_rules.append(rule_data)
	return serialized_rules


func _deserialize_entities(raw_entities: Variant) -> Dictionary:
	var entities: Dictionary = {}
	if raw_entities is Dictionary:
		var entity_ids: Array = raw_entities.keys()
		entity_ids.sort()
		for entity_id in entity_ids:
			if not (raw_entities[entity_id] is Dictionary):
				continue
			var entity_data: Dictionary = raw_entities[entity_id].duplicate(true)
			if String(entity_data.get("id", "")).is_empty():
				entity_data["id"] = String(entity_id)
			var normalized_entity := _normalize_entity(entity_data)
			if not normalized_entity.is_empty():
				entities[String(normalized_entity.get("id", entity_id))] = normalized_entity
	elif raw_entities is Array:
		for raw_entity in raw_entities:
			if not (raw_entity is Dictionary):
				continue
			var normalized_entity := _normalize_entity(raw_entity.duplicate(true))
			if not normalized_entity.is_empty():
				entities[String(normalized_entity.get("id", ""))] = normalized_entity
	return entities


func _deserialize_installed_rules(raw_rules: Variant) -> Dictionary:
	var installed_rules: Dictionary = {}
	if raw_rules is Dictionary:
		var rule_ids: Array = raw_rules.keys()
		rule_ids.sort()
		for rule_id in rule_ids:
			if not (raw_rules[rule_id] is Dictionary):
				continue
			var rule_data: Dictionary = raw_rules[rule_id].duplicate(true)
			if String(rule_data.get("id", "")).is_empty():
				rule_data["id"] = String(rule_id)
			var normalized_rule := _normalize_rule_patch(rule_data, false)
			if not normalized_rule.is_empty():
				installed_rules[String(normalized_rule.get("id", rule_id))] = normalized_rule
	elif raw_rules is Array:
		for raw_rule in raw_rules:
			if not (raw_rule is Dictionary):
				continue
			var normalized_rule := _normalize_rule_patch(raw_rule.duplicate(true), false)
			if not normalized_rule.is_empty():
				installed_rules[String(normalized_rule.get("id", ""))] = normalized_rule
	return installed_rules


func _build_null_world() -> Dictionary:
	return {
		"world_id": "starter-plaza",
		"world_name": "はじまりの広場",
		"runtime_choice": "godot-4-desktop",
		"elapsed_seconds": 0.0,
		"tick_index": 0,
		"fixed_step_seconds": fixed_step_seconds,
		"concepts": ["main_scene_2d_start", "gm_in_world"],
		"preview_3d": _build_default_three_d_preview_state(),
		"entities": {
			"origin_entity": {
				"id": "origin_entity",
				"name": "プレイヤー",
				"archetype": "origin",
				"tags": ["origin", "mortal", "mutable", "character", "player"],
				"position": {
					"x": 0.0,
					"y": 0.9,
					"z": -4.2,
					"location": "starter_path"
				},
				"render_3d": {
					"kind": "character",
					"size": {
						"x": 0.9,
						"y": 1.8,
						"z": 0.9
					},
					"color": "#5b8cff"
				},
				"components": {
					"needs": {},
					"stats": {},
					"traits": {
						"curiosity": 1.0,
						"morale": 50.0,
						"focus": 50.0
					},
					"behavior": {
						"current_task": "ゲームマスターのところへ歩いて相談する"
					},
					"physics": {
						"dynamic": false,
						"grounded": true,
						"gravity_scale": 0.0,
						"floor_offset_y": 0.9,
						"velocity": {"x": 0.0, "y": 0.0, "z": 0.0}
					}
				}
			},
			"gm_entity": {
				"id": "gm_entity",
				"name": "ゲームマスター",
				"archetype": "gm",
				"tags": ["character", "gm", "director", "mortal"],
				"position": {
					"x": -1.8,
					"y": 1.1,
					"z": 1.4,
					"location": "gm_dais"
				},
				"render_3d": {
					"kind": "gm",
					"size": {"x": 1.1, "y": 2.2, "z": 1.1},
					"color": "#f3c969"
				},
				"components": {
					"behavior": {
						"current_task": "プレイヤーからの相談を待機中"
					},
					"physics": {
						"dynamic": false,
						"grounded": true,
						"gravity_scale": 0.0,
						"floor_offset_y": 1.1,
						"velocity": {"x": 0.0, "y": 0.0, "z": 0.0}
					}
				}
			},
			"rule_board": {
				"id": "rule_board",
				"name": "相談ボード",
				"archetype": "structure",
				"tags": ["object", "structure"],
				"position": {
					"x": 2.2,
					"y": 1.1,
					"z": 0.1,
					"location": "plaza_edge"
				},
				"render_3d": {
					"kind": "object",
					"size": {"x": 2.4, "y": 2.2, "z": 0.4},
					"color": "#7e8794"
				},
				"components": {
					"state": {
						"status": "GMへ相談すると管理画面を開けます"
					}
				}
			},
			"supply_crate": {
				"id": "supply_crate",
				"name": "補給箱",
				"archetype": "object",
				"tags": ["object", "portable"],
				"position": {
					"x": 3.1,
					"y": 0.6,
					"z": 2.3,
					"location": "supply_corner"
				},
				"render_3d": {
					"kind": "crate",
					"size": {"x": 1.2, "y": 1.2, "z": 1.2},
					"color": "#b67a45"
				},
				"components": {
					"state": {
						"status": "PoC3用の小道具"
					}
				}
			},
			"rest_stone": {
				"id": "rest_stone",
				"name": "腰掛け石",
				"archetype": "object",
				"tags": ["object", "structure"],
				"position": {
					"x": -4.0,
					"y": 0.55,
					"z": -1.1,
					"location": "rest_corner"
				},
				"render_3d": {
					"kind": "object",
					"size": {"x": 1.8, "y": 1.1, "z": 1.8},
					"color": "#8f939a"
				},
				"components": {
					"state": {
						"status": "広場の目印"
					}
				}
			}
		},
		"installed_rules": {},
		"player_task_history": [],
		"event_log": [
			{
				"type": "world_initialized",
				"message": "プレイヤーとGMが同じ2D広場にいる初期ワールドを起動しました。GM会話で3D化できます。",
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

	_apply_gravity(entities, step_seconds)
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


func _install_normalized_rule(normalized_rule: Dictionary) -> Dictionary:
	var rule_id := String(normalized_rule.get("id", ""))
	var installed_rules: Dictionary = _world_state.get("installed_rules", {})
	if installed_rules.has(rule_id):
		return {
			"status": "error",
			"message": "ルール '%s' はすでに導入されています。" % rule_id
		}

	var parent_resolution := _resolve_parent_rule_links(normalized_rule, installed_rules)
	if String(parent_resolution.get("status", "")) == "error":
		return parent_resolution

	normalized_rule["resolved_parent_rule_ids"] = parent_resolution.get("resolved_parent_rule_ids", []).duplicate(true)
	normalized_rule["resolved_parent_rule_links"] = parent_resolution.get("resolved_parent_rule_links", []).duplicate(true)
	normalized_rule["missing_required_rule_kinds"] = []

	installed_rules[rule_id] = normalized_rule
	_world_state["installed_rules"] = installed_rules
	_apply_install_actions(normalized_rule)
	_initialize_rule_targets(normalized_rule)
	_refresh_rule_relationships()
	_append_concept(normalized_rule.get("concept", rule_id))
	_append_event(
		"rule_installed",
		"ルール '%s' を導入しました。" % rule_id,
		{
			"rule_id": rule_id,
			"requires_rule_kinds": normalized_rule.get("requires_rule_kinds", []),
			"provides_rule_kinds": normalized_rule.get("provides_rule_kinds", []),
			"resolved_parent_rule_ids": _world_state.get("installed_rules", {}).get(rule_id, {}).get("resolved_parent_rule_ids", [])
		}
	)

	return {
		"status": "installed",
		"installed": true,
		"rule": _world_state.get("installed_rules", {}).get(rule_id, {}).duplicate(true)
	}


func _normalize_rule_patch(rule_patch: Dictionary, merge_template: bool = true) -> Dictionary:
	var base_rule: Dictionary = {}
	var template_id := String(rule_patch.get("template_id", ""))
	if merge_template and not template_id.is_empty() and _template_index.has(template_id):
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
			"message": "ルール '%s' には、導入済みの親ルール種別 [%s] が必要です。先に対応するルールを入れてください。" % [rule_id, ", ".join(missing_rule_kinds)],
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
		match String(action.get("op", "")):
			"upsert_entities":
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
			"merge_world_state":
				_apply_world_state_merge_action(action)
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


func _build_world_clock_summary(installed_rules_by_id: Dictionary, snapshot: Dictionary) -> Dictionary:
	var provider := _find_world_clock_provider(installed_rules_by_id)
	if provider.is_empty():
		return {}
	var source_field := String(provider.get("source_field", "elapsed_seconds"))
	return {
		"elapsed_seconds": float(snapshot.get("elapsed_seconds", 0.0)),
		"total_ticks": int(snapshot.get("tick_index", 0)),
		"source_field": source_field,
		"source_package_id": String(provider.get("source_package_id", "")),
		"source_rule_id": String(provider.get("source_rule_id", "")),
		"description": String(provider.get("description", "WorldState.%s をプレイヤー向けの時計として見える化します。" % source_field))
	}


func _find_world_clock_provider(installed_rules_by_id: Dictionary) -> Dictionary:
	for rule in installed_rules_by_id.values():
		if not (rule is Dictionary):
			continue
		var rule_data: Dictionary = rule
		var metadata: Dictionary = rule_data.get("metadata", {})
		var package_id := String(metadata.get("package_id", ""))
		var rule_id := String(rule_data.get("id", ""))
		var source_field := ""
		for effect in rule_data.get("effects", []):
			if not (effect is Dictionary):
				continue
			var effect_data: Dictionary = effect
			if String(effect_data.get("component", "")) == "time":
				source_field = String(effect_data.get("field", ""))
				if source_field == "elapsed_seconds":
					break
		if package_id == "builtin.time":
			if source_field.is_empty():
				source_field = "elapsed_seconds"
			return {
				"source_field": source_field,
				"source_package_id": package_id,
				"source_rule_id": rule_id,
				"description": "builtin.time は WorldState.%s をプレイヤー向けの時計として見える化します。" % source_field
			}
		for provided_kind in rule_data.get("provides_rule_kinds", []):
			if String(provided_kind) == "world-clock":
				if source_field.is_empty():
					source_field = "elapsed_seconds"
				var provider_id := package_id if not package_id.is_empty() else rule_id
				return {
					"source_field": source_field,
					"source_package_id": package_id,
					"source_rule_id": rule_id,
					"description": "%s は WorldState.%s をプレイヤー向けの時計として見える化します。" % [provider_id if not provider_id.is_empty() else "このルール", source_field]
				}
		if source_field == "elapsed_seconds":
			var provider_id := package_id if not package_id.is_empty() else rule_id
			return {
				"source_field": source_field,
				"source_package_id": package_id,
				"source_rule_id": rule_id,
				"description": "%s は WorldState.%s をプレイヤー向けの時計として見える化します。" % [provider_id if not provider_id.is_empty() else "このルール", source_field]
			}
	return {}


func _build_default_three_d_preview_state() -> Dictionary:
	return {
		"enabled": false,
		"lighting": DEFAULT_THREE_D_LIGHTING.duplicate(true),
		"gravity": DEFAULT_THREE_D_GRAVITY.duplicate(true),
		"camera": DEFAULT_THREE_D_CAMERA.duplicate(true)
	}


func _build_three_d_preview(entities: Dictionary, preview_state: Variant) -> Dictionary:
	var merged_preview := _build_default_three_d_preview_state()
	if preview_state is Dictionary:
		merged_preview = _merge_dictionaries(merged_preview, preview_state)

	var enabled := bool(merged_preview.get("enabled", false))
	var lighting := _normalize_preview_lighting(merged_preview.get("lighting", {}), enabled)
	var gravity := _normalize_preview_gravity(merged_preview.get("gravity", {}), enabled)
	var camera := _normalize_preview_camera(merged_preview.get("camera", {}))

	return {
		"enabled": enabled,
		"renderables": _build_three_d_renderables(entities, gravity) if enabled else [],
		"lighting": lighting,
		"gravity": gravity,
		"camera": camera
	}


func _normalize_preview_lighting(raw_lighting: Variant, preview_enabled: bool) -> Dictionary:
	var lighting := DEFAULT_THREE_D_LIGHTING.duplicate(true)
	if raw_lighting is Dictionary:
		lighting = _merge_dictionaries(lighting, raw_lighting)
	lighting["enabled"] = preview_enabled and bool(lighting.get("enabled", false))
	lighting["shadows_enabled"] = bool(lighting.get("enabled", false)) and bool(lighting.get("shadows_enabled", false))
	lighting["light_rotation_degrees"] = _normalize_vector3_dict(lighting.get("light_rotation_degrees", {}), DEFAULT_THREE_D_LIGHTING["light_rotation_degrees"])
	lighting["intensity"] = float(lighting.get("intensity", DEFAULT_THREE_D_LIGHTING["intensity"]))
	lighting["color"] = String(lighting.get("color", DEFAULT_THREE_D_LIGHTING["color"]))
	return lighting


func _normalize_preview_gravity(raw_gravity: Variant, preview_enabled: bool) -> Dictionary:
	var gravity := DEFAULT_THREE_D_GRAVITY.duplicate(true)
	if raw_gravity is Dictionary:
		gravity = _merge_dictionaries(gravity, raw_gravity)
	gravity["enabled"] = preview_enabled and bool(gravity.get("enabled", false))
	gravity["floor_y"] = float(gravity.get("floor_y", DEFAULT_THREE_D_GRAVITY["floor_y"]))
	gravity["acceleration"] = max(0.0, float(gravity.get("acceleration", DEFAULT_THREE_D_GRAVITY["acceleration"])))
	return gravity


func _normalize_preview_camera(raw_camera: Variant) -> Dictionary:
	var camera := DEFAULT_THREE_D_CAMERA.duplicate(true)
	if raw_camera is Dictionary:
		camera = _merge_dictionaries(camera, raw_camera)
	camera["position"] = _normalize_vector3_dict(camera.get("position", {}), DEFAULT_THREE_D_CAMERA["position"])
	camera["look_at"] = _normalize_vector3_dict(camera.get("look_at", {}), DEFAULT_THREE_D_CAMERA["look_at"])
	camera["fov_degrees"] = float(camera.get("fov_degrees", DEFAULT_THREE_D_CAMERA["fov_degrees"]))
	return camera


func _build_three_d_renderables(entities: Dictionary, gravity: Dictionary) -> Array:
	var renderables: Array = []
	var entity_ids: Array = entities.keys()
	entity_ids.sort()

	for entity_id in entity_ids:
		var entity: Dictionary = entities[entity_id]
		if not _entity_is_three_d_renderable(entity):
			continue
		renderables.append(_build_three_d_renderable(String(entity_id), entity, gravity))

	return renderables


func _build_three_d_renderable(entity_id: String, entity: Dictionary, gravity: Dictionary) -> Dictionary:
	var render_data: Dictionary = entity.get("render_3d", {}).duplicate(true) if entity.get("render_3d", {}) is Dictionary else {}
	var is_gm := _is_gm_entity(entity)
	var is_character := _is_character_entity(entity)
	var kind := String(render_data.get("kind", ""))
	if kind.is_empty():
		if is_gm:
			kind = "gm"
		elif is_character:
			kind = "character"
		else:
			kind = String(entity.get("archetype", "object"))

	var size := _normalize_vector3_dict(render_data.get("size", entity.get("size", {})), _default_renderable_size(is_character, is_gm))
	var position := _normalize_vector3_dict(render_data.get("position", entity.get("position", {})), _default_renderable_position(entity_id, size, gravity))
	var physics := _extract_entity_physics(entity)
	var state := _extract_entity_state(entity)
	var renderable := {
		"id": String(entity.get("id", entity_id)),
		"name": String(entity.get("name", entity_id)),
		"kind": kind,
		"is_character": is_character,
		"is_gm": is_gm,
		"position": position,
		"size": size,
		"color": _resolve_renderable_color(entity, render_data, is_character, is_gm)
	}
	if not physics.is_empty():
		renderable["physics"] = physics
	if not state.is_empty():
		renderable["state"] = state
	return renderable


func _entity_is_three_d_renderable(entity: Dictionary) -> bool:
	return _is_character_entity(entity) or _is_gm_entity(entity) or Array(entity.get("tags", [])).has("object") or (entity.get("render_3d", {}) is Dictionary and not entity.get("render_3d", {}).is_empty())


func _is_character_entity(entity: Dictionary) -> bool:
	for tag_variant in entity.get("tags", []):
		var tag := String(tag_variant).to_lower()
		if CHARACTER_TAG_HINTS.has(tag):
			return true
	var archetype := String(entity.get("archetype", "")).to_lower()
	return CHARACTER_ARCHETYPE_HINTS.has(archetype)


func _is_gm_entity(entity: Dictionary) -> bool:
	for tag_variant in entity.get("tags", []):
		var tag := String(tag_variant).to_lower()
		if GM_TAG_HINTS.has(tag):
			return true
	var archetype := String(entity.get("archetype", "")).to_lower()
	return GM_ARCHETYPE_HINTS.has(archetype)


func _default_renderable_size(is_character: bool, is_gm: bool) -> Dictionary:
	if is_gm:
		return {"x": 1.1, "y": 2.2, "z": 1.1}
	if is_character:
		return {"x": 0.9, "y": 1.8, "z": 0.9}
	return {"x": 1.0, "y": 1.0, "z": 1.0}


func _default_renderable_position(entity_id: String, size: Dictionary, gravity: Dictionary) -> Dictionary:
	var floor_y := float(gravity.get("floor_y", DEFAULT_THREE_D_GRAVITY["floor_y"]))
	var contact_y := floor_y + (float(size.get("y", 1.0)) * 0.5)
	if entity_id == "origin_entity":
		return {"x": 0.0, "y": contact_y, "z": 0.0}
	return {"x": 0.0, "y": contact_y, "z": 0.0}


func _resolve_renderable_color(entity: Dictionary, render_data: Dictionary, is_character: bool, is_gm: bool) -> String:
	if render_data.has("color"):
		return String(render_data.get("color", "#9aa3b2"))
	if entity.has("color"):
		return String(entity.get("color", "#9aa3b2"))
	if is_gm:
		return "#f3c969"
	if is_character:
		return "#5b8cff"
	if Array(entity.get("tags", [])).has("structure"):
		return "#6f7984"
	return "#9a7b5f"


func _extract_entity_physics(entity: Dictionary) -> Dictionary:
	var components: Dictionary = entity.get("components", {})
	if components.has("physics") and components["physics"] is Dictionary:
		return components["physics"].duplicate(true)
	return {}


func _extract_entity_state(entity: Dictionary) -> Dictionary:
	var state: Dictionary = {}
	var top_level_state: Variant = entity.get("state", {})
	if top_level_state is Dictionary:
		state = _merge_dictionaries(state, top_level_state)
	var components: Dictionary = entity.get("components", {})
	var component_state: Variant = components.get("state", {})
	if component_state is Dictionary:
		state = _merge_dictionaries(state, component_state)
	return state


func _apply_world_state_merge_action(action: Dictionary) -> void:
	var path := String(action.get("path", "")).strip_edges()
	var value: Variant = action.get("value", {})
	if path.is_empty():
		if value is Dictionary:
			_world_state = _merge_dictionaries(_world_state, value)
		return
	_world_state = _merge_value_at_path(_world_state, path.split("."), value)


func _merge_value_at_path(container: Dictionary, path_segments: PackedStringArray, value: Variant, index: int = 0) -> Dictionary:
	var merged_container := container.duplicate(true)
	if index >= path_segments.size():
		return merged_container

	var key := String(path_segments[index]).strip_edges()
	if key.is_empty():
		return merged_container

	if index == path_segments.size() - 1:
		if value is Dictionary and merged_container.get(key, {}) is Dictionary:
			merged_container[key] = _merge_dictionaries(merged_container.get(key, {}), value)
		elif value is Dictionary:
			merged_container[key] = value.duplicate(true)
		elif value is Array:
			merged_container[key] = value.duplicate(true)
		else:
			merged_container[key] = value
		return merged_container

	var nested_value: Variant = merged_container.get(key, {})
	var nested_container: Dictionary = nested_value.duplicate(true) if nested_value is Dictionary else {}
	merged_container[key] = _merge_value_at_path(nested_container, path_segments, value, index + 1)
	return merged_container


func _apply_gravity(entities: Dictionary, step_seconds: float) -> void:
	var preview_state: Dictionary = _world_state.get("preview_3d", {})
	var gravity := _normalize_preview_gravity(preview_state.get("gravity", {}), bool(preview_state.get("enabled", false)))
	if not bool(gravity.get("enabled", false)):
		return

	var acceleration := float(gravity.get("acceleration", DEFAULT_THREE_D_GRAVITY["acceleration"]))
	var floor_y := float(gravity.get("floor_y", DEFAULT_THREE_D_GRAVITY["floor_y"]))
	var entity_ids: Array = entities.keys()
	entity_ids.sort()

	for entity_id in entity_ids:
		var entity: Dictionary = entities[entity_id]
		var components: Dictionary = entity.get("components", {})
		var physics_value: Variant = components.get("physics", {})
		if not (physics_value is Dictionary):
			continue
		var physics: Dictionary = physics_value
		if not bool(physics.get("dynamic", false)):
			continue

		var position := _normalize_vector3_dict(entity.get("position", {}), {"x": 0.0, "y": floor_y + 0.5, "z": 0.0})
		var render_data: Dictionary = entity.get("render_3d", {}).duplicate(true) if entity.get("render_3d", {}) is Dictionary else {}
		var size := _normalize_vector3_dict(render_data.get("size", entity.get("size", {})), _default_renderable_size(_is_character_entity(entity), _is_gm_entity(entity)))
		var velocity := _normalize_vector3_dict(physics.get("velocity", {}), {"x": 0.0, "y": 0.0, "z": 0.0})
		var gravity_scale: float = max(0.0, float(physics.get("gravity_scale", 1.0)))
		var floor_offset_y := float(physics.get("floor_offset_y", float(size.get("y", 1.0)) * 0.5))
		var target_floor_y := floor_y + floor_offset_y
		var was_grounded := bool(physics.get("grounded", false))

		velocity["y"] = float(velocity.get("y", 0.0)) - (acceleration * gravity_scale * step_seconds)
		position["y"] = float(position.get("y", target_floor_y)) + (float(velocity.get("y", 0.0)) * step_seconds)

		var is_grounded := false
		if float(position.get("y", target_floor_y)) <= target_floor_y:
			position["y"] = target_floor_y
			velocity["y"] = 0.0
			is_grounded = true

		position["y"] = snappedf(float(position.get("y", target_floor_y)), 0.0001)
		velocity["y"] = snappedf(float(velocity.get("y", 0.0)), 0.0001)
		physics["velocity"] = velocity
		physics["grounded"] = is_grounded
		components["physics"] = physics
		entity["components"] = components
		entity["position"] = position
		entities[entity_id] = entity

		if is_grounded and not was_grounded:
			_append_event("gravity_landed", "プレビュー床に '%s' が着地しました。" % String(entity.get("name", entity_id)), {"entity_id": entity_id, "floor_y": target_floor_y})


func _normalize_vector3_dict(raw_value: Variant, default_value: Dictionary) -> Dictionary:
	var normalized := default_value.duplicate(true)
	if raw_value is Dictionary:
		for axis in ["x", "y", "z"]:
			if raw_value.has(axis):
				normalized[axis] = float(raw_value.get(axis, default_value.get(axis, 0.0)))
	return normalized


func _build_character_list(entities: Dictionary) -> Array:
	var characters: Array = []
	var entity_ids: Array = entities.keys()
	entity_ids.sort()

	for entity_id in entity_ids:
		var entity: Dictionary = entities[entity_id]
		var entity_tags: Array = entity.get("tags", [])
		if not entity_tags.has("mortal"):
			continue
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
			"current_task": behavior.get("current_task", "次の世界ルールを待機中")
		})

	return characters


func _build_object_list(entities: Dictionary) -> Array:
	var objects: Array = []
	var entity_ids: Array = entities.keys()
	entity_ids.sort()

	for entity_id in entity_ids:
		var entity: Dictionary = entities[entity_id]
		var entity_tags: Array = entity.get("tags", [])
		if not entity_tags.has("object"):
			continue
		var components: Dictionary = entity.get("components", {})
		var ownership: Dictionary = components.get("ownership", {})
		objects.append({
			"id": entity.get("id", entity_id),
			"name": entity.get("name", entity_id),
			"material": entity.get("material", ""),
			"weight": entity.get("weight", 0.0),
			"position": entity.get("position", {}).duplicate(true) if entity.get("position", {}) is Dictionary else entity.get("position", {}),
			"portability": entity.get("portability", {}).duplicate(true) if entity.get("portability", {}) is Dictionary else entity.get("portability", {}),
			"state": entity.get("state", {}).duplicate(true) if entity.get("state", {}) is Dictionary else entity.get("state", {}),
			"owner": ownership.duplicate(true) if ownership is Dictionary else entity.get("owner", null)
		})
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


func _duplicate_array(raw_value: Variant) -> Array:
	var duplicated: Array = []
	if not (raw_value is Array):
		return duplicated

	for item in raw_value:
		if item is Dictionary:
			duplicated.append(item.duplicate(true))
		elif item is Array:
			duplicated.append(item.duplicate(true))
		else:
			duplicated.append(item)
	return duplicated


func _normalize_entity(entity: Dictionary) -> Dictionary:
	var normalized_entity := entity.duplicate(true)
	var entity_id := String(normalized_entity.get("id", ""))
	if entity_id.is_empty():
		return {}

	normalized_entity["id"] = entity_id
	normalized_entity["name"] = String(normalized_entity.get("name", entity_id))
	normalized_entity["archetype"] = String(normalized_entity.get("archetype", "entity"))
	normalized_entity["tags"] = _normalize_string_array(normalized_entity.get("tags", []))
	var components: Dictionary = normalized_entity.get("components", {}).duplicate(true) if normalized_entity.get("components", {}) is Dictionary else {}
	if components.has("physics") and components["physics"] is Dictionary:
		var physics: Dictionary = components["physics"].duplicate(true)
		physics["dynamic"] = bool(physics.get("dynamic", false))
		physics["grounded"] = bool(physics.get("grounded", false))
		physics["gravity_scale"] = float(physics.get("gravity_scale", 1.0))
		physics["velocity"] = _normalize_vector3_dict(physics.get("velocity", {}), {"x": 0.0, "y": 0.0, "z": 0.0})
		if physics.has("floor_offset_y"):
			physics["floor_offset_y"] = float(physics.get("floor_offset_y", 0.0))
		components["physics"] = physics
	for component_name in ["needs", "stats", "traits", "behavior"]:
		if not components.has(component_name) or not (components[component_name] is Dictionary):
			components[component_name] = {}
	normalized_entity["components"] = components
	if normalized_entity.has("position") and normalized_entity["position"] is Dictionary:
		var position_data: Dictionary = normalized_entity["position"].duplicate(true)
		var normalized_position := _normalize_vector3_dict(position_data, {"x": 0.0, "y": 0.0, "z": 0.0})
		for key in position_data.keys():
			if not normalized_position.has(key):
				normalized_position[key] = position_data[key]
		normalized_entity["position"] = normalized_position
	if normalized_entity.has("render_3d") and normalized_entity["render_3d"] is Dictionary:
		var render_data: Dictionary = normalized_entity["render_3d"].duplicate(true)
		if render_data.has("position") and render_data["position"] is Dictionary:
			render_data["position"] = _normalize_vector3_dict(render_data["position"], {"x": 0.0, "y": 0.0, "z": 0.0})
		if render_data.has("size") and render_data["size"] is Dictionary:
			render_data["size"] = _normalize_vector3_dict(render_data["size"], {"x": 1.0, "y": 1.0, "z": 1.0})
		if render_data.has("color"):
			render_data["color"] = String(render_data.get("color", "#9aa3b2"))
		normalized_entity["render_3d"] = render_data
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
