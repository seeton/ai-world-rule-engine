extends SceneTree

const WorldStateScript = preload("res://scripts/core/WorldState.gd")
const SNAPSHOT_PATH := "user://world_snapshot_smoke.json"


func _initialize() -> void:
	var exit_code := 0
	var failure_message := ""
	var worlds_to_release: Array = []

	_cleanup_snapshot_file()

	var source_world := WorldStateScript.new()
	worlds_to_release.append(source_world)
	var fresh_snapshot := source_world.get_world_snapshot()
	var fresh_rules: Dictionary = fresh_snapshot.get("installed_rules_by_id", {})
	var fresh_packages: Dictionary = fresh_snapshot.get("installed_rule_packages_by_id", {})
	if not fresh_rules.has("default_package.foundation"):
		exit_code = 1
		failure_message = "Fresh world snapshot did not bootstrap default_package.foundation: %s" % JSON.stringify(fresh_snapshot)
	elif String(fresh_packages.get("builtin.default_package", {}).get("state", "")) != "enabled":
		exit_code = 1
		failure_message = "Fresh world snapshot did not report builtin.default_package as enabled: %s" % JSON.stringify(fresh_snapshot)

	if exit_code == 0:
		var install_result := source_world.create_rule_from_patch({
			"template_id": "hunger",
			"id": "snapshot_rule_hunger",
			"metadata": {
				"package_id": "snapshot.smoke",
				"save_marker": "world_snapshot_smoke_test"
			}
		})
		if String(install_result.get("status", "")) != "installed":
			exit_code = 1
			failure_message = "Failed to install smoke-test rule: %s" % JSON.stringify(install_result)
		else:
			source_world.set_entity_position("origin_entity", {
				"x": 4.5,
				"z": 1.25,
				"location": "snapshot_test_lane"
			})
			source_world.advance_tick(1.0)
			var saved_live_snapshot := source_world.get_world_snapshot()
			var saved_world_snapshot := source_world.create_world_snapshot()

			var restored_world := WorldStateScript.new()
			worlds_to_release.append(restored_world)
			var restore_result := restored_world.restore_world_snapshot(saved_world_snapshot)
			if String(restore_result.get("status", "")) != "loaded":
				exit_code = 1
				failure_message = "Failed to restore in-memory snapshot: %s" % JSON.stringify(restore_result)
			else:
				var compare_message := _compare_live_snapshots(saved_live_snapshot, restored_world.get_world_snapshot())
				if not compare_message.is_empty():
					exit_code = 1
					failure_message = "In-memory restore mismatch: %s" % compare_message
				else:
					var save_result := source_world.save_world_snapshot(SNAPSHOT_PATH)
					if String(save_result.get("status", "")) != "saved":
						exit_code = 1
						failure_message = "Failed to save snapshot file: %s" % JSON.stringify(save_result)
					else:
						var loaded_world := WorldStateScript.new()
						worlds_to_release.append(loaded_world)
						var load_result := loaded_world.load_world_snapshot(SNAPSHOT_PATH)
						if String(load_result.get("status", "")) != "loaded":
							exit_code = 1
							failure_message = "Failed to load snapshot file: %s" % JSON.stringify(load_result)
						else:
							var file_compare_message := _compare_live_snapshots(saved_live_snapshot, loaded_world.get_world_snapshot())
							if not file_compare_message.is_empty():
								exit_code = 1
								failure_message = "File restore mismatch: %s" % file_compare_message

	for world in worlds_to_release:
		if is_instance_valid(world):
			world.free()

	_cleanup_snapshot_file()

	if exit_code != 0:
		push_error(failure_message)
	quit(exit_code)


func _compare_live_snapshots(expected: Dictionary, actual: Dictionary) -> String:
	if int(actual.get("tick_index", -1)) != int(expected.get("tick_index", -1)):
		return "tick_index"
	if abs(float(actual.get("elapsed_seconds", -1.0)) - float(expected.get("elapsed_seconds", -1.0))) > 0.0001:
		return "elapsed_seconds"

	var expected_rules: Dictionary = expected.get("installed_rules_by_id", {})
	var actual_rules: Dictionary = actual.get("installed_rules_by_id", {})
	if actual_rules.size() != expected_rules.size():
		return "installed_rules_count"

	var expected_rule: Dictionary = expected_rules.get("snapshot_rule_hunger", {})
	var actual_rule: Dictionary = actual_rules.get("snapshot_rule_hunger", {})
	if actual_rule.is_empty():
		return "snapshot_rule_hunger_missing"
	if JSON.stringify(actual_rule.get("metadata", {}), "", true) != JSON.stringify(expected_rule.get("metadata", {}), "", true):
		return "rule_metadata"

	var expected_entity: Dictionary = expected.get("entities", {}).get("origin_entity", {})
	var actual_entity: Dictionary = actual.get("entities", {}).get("origin_entity", {})
	if JSON.stringify(actual_entity.get("position", {}), "", true) != JSON.stringify(expected_entity.get("position", {}), "", true):
		return "origin_position"

	var expected_hunger := _extract_character_hunger(expected, "origin_entity")
	var actual_hunger := _extract_character_hunger(actual, "origin_entity")
	if abs(actual_hunger - expected_hunger) > 0.0001:
		return "origin_hunger"

	return ""


func _extract_character_hunger(snapshot: Dictionary, entity_id: String) -> float:
	var entity: Dictionary = snapshot.get("entities", {}).get(entity_id, {})
	var components: Dictionary = entity.get("components", {})
	var needs: Dictionary = components.get("needs", {})
	return float(needs.get("hunger", 0.0))


func _cleanup_snapshot_file() -> void:
	var snapshot_absolute_path := ProjectSettings.globalize_path(SNAPSHOT_PATH)
	if FileAccess.file_exists(snapshot_absolute_path):
		DirAccess.remove_absolute(snapshot_absolute_path)
