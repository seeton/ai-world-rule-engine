extends SceneTree

# Smoke test for the collapse-safe CLI surface.
# Exercises the pieces the CLI dispatcher relies on directly against
# WorldState / SimulationRuntime, without spawning a child Godot process:
# - rule disable/enable round-trip via set_rule_enabled
# - tick respects the disabled flag (no effect application)
# - snapshot dump+load preserves the disabled flag

const WorldStateScript = preload("res://scripts/core/WorldState.gd")
const SNAPSHOT_PATH := "user://cli_smoke_snapshot.json"


func _initialize() -> void:
	var exit_code := 0
	var failure_message := ""
	var worlds_to_release: Array = []

	_cleanup_snapshot_file()

	var world := WorldStateScript.new()
	worlds_to_release.append(world)

	var install_result: Dictionary = world.create_rule_from_patch({
		"template_id": "hunger",
		"id": "cli_smoke_rule",
		"metadata": {"package_id": "cli.smoke"}
	})
	if String(install_result.get("status", "")) != "installed":
		exit_code = 1
		failure_message = "Failed to install smoke rule: %s" % JSON.stringify(install_result)
	else:
		# Drive a tick so the hunger rule populates a baseline value.
		world.advance_tick(1.0)
		var baseline_snapshot: Dictionary = world.get_world_snapshot()
		var baseline_hunger := _extract_hunger(baseline_snapshot)

		var disable_result: Dictionary = world.set_rule_enabled("cli_smoke_rule", false)
		if String(disable_result.get("status", "")) != "disabled":
			exit_code = 1
			failure_message = "Disable did not return 'disabled': %s" % JSON.stringify(disable_result)
		else:
			var snapshot_after_disable: Dictionary = world.get_world_snapshot()
			if not _rule_has_enabled(snapshot_after_disable, "cli_smoke_rule", false):
				exit_code = 1
				failure_message = "Snapshot did not reflect disabled flag after disable."
			else:
				world.advance_tick(2.0)
				var hunger_after_disable := _extract_hunger(world.get_world_snapshot())
				if abs(hunger_after_disable - baseline_hunger) > 0.0001:
					exit_code = 1
					failure_message = "Hunger advanced (%s -> %s) while rule was disabled." % [baseline_hunger, hunger_after_disable]
				else:
					var save_result: Dictionary = world.save_world_snapshot(SNAPSHOT_PATH)
					if String(save_result.get("status", "")) != "saved":
						exit_code = 1
						failure_message = "Failed to dump snapshot: %s" % JSON.stringify(save_result)
					else:
						var loaded_world := WorldStateScript.new()
						worlds_to_release.append(loaded_world)
						var load_result: Dictionary = loaded_world.load_world_snapshot(SNAPSHOT_PATH)
						if String(load_result.get("status", "")) != "loaded":
							exit_code = 1
							failure_message = "Failed to load snapshot: %s" % JSON.stringify(load_result)
						elif not _rule_has_enabled(loaded_world.get_world_snapshot(), "cli_smoke_rule", false):
							exit_code = 1
							failure_message = "Disabled flag did not survive snapshot round-trip."
						else:
							var enable_result: Dictionary = loaded_world.set_rule_enabled("cli_smoke_rule", true)
							if String(enable_result.get("status", "")) != "enabled":
								exit_code = 1
								failure_message = "Enable did not return 'enabled': %s" % JSON.stringify(enable_result)
							elif not _rule_has_enabled(loaded_world.get_world_snapshot(), "cli_smoke_rule", true):
								exit_code = 1
								failure_message = "Snapshot did not reflect enabled flag after re-enable."

	for w in worlds_to_release:
		if is_instance_valid(w):
			w.free()

	_cleanup_snapshot_file()

	if exit_code != 0:
		push_error(failure_message)
	quit(exit_code)


func _extract_hunger(snapshot: Dictionary) -> float:
	var entities: Dictionary = snapshot.get("entities", {})
	var entity: Dictionary = entities.get("origin_entity", {})
	var components: Dictionary = entity.get("components", {})
	var needs: Dictionary = components.get("needs", {})
	return float(needs.get("hunger", 0.0))


func _rule_has_enabled(snapshot: Dictionary, rule_id: String, expected_enabled: bool) -> bool:
	var by_id: Dictionary = snapshot.get("installed_rules_by_id", {})
	var rule: Dictionary = by_id.get(rule_id, {})
	if rule.is_empty():
		return false
	return bool(rule.get("enabled", true)) == expected_enabled


func _cleanup_snapshot_file() -> void:
	var snapshot_absolute_path := ProjectSettings.globalize_path(SNAPSHOT_PATH)
	if FileAccess.file_exists(snapshot_absolute_path):
		DirAccess.remove_absolute(snapshot_absolute_path)
