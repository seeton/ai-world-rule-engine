extends SceneTree

# Smoke test for the shared cli_actions surface.
# Verifies that overlay-style and CLI-dispatcher-style actuation against the
# same WorldState produce equivalent results, so the in-game C overlay
# (Tier 1) and the headless CLI (Tier 2) cannot drift.

const WorldStateScript = preload("res://scripts/core/WorldState.gd")
const CliActionsScript = preload("res://scripts/cli/cli_actions.gd")


func _initialize() -> void:
	var exit_code := 0
	var failure_message := ""
	var worlds_to_release: Array = []

	var snapshot_path := "user://cli_actions_smoke.json"
	_remove_file(snapshot_path)

	var world := WorldStateScript.new()
	worlds_to_release.append(world)

	var install_result: Dictionary = world.create_rule_from_patch({
		"template_id": "hunger",
		"id": "actions_smoke_rule",
		"metadata": {"package_id": "actions.smoke"}
	})
	if String(install_result.get("status", "")) != "installed":
		exit_code = 1
		failure_message = "Failed to install rule: %s" % JSON.stringify(install_result)
	else:
		var disable_result: Dictionary = CliActionsScript.set_rule_enabled(world, "actions_smoke_rule", false)
		if String(disable_result.get("status", "")) != "disabled":
			exit_code = 1
			failure_message = "set_rule_enabled disable did not return 'disabled': %s" % JSON.stringify(disable_result)
		else:
			var save_result: Dictionary = CliActionsScript.save_snapshot(world, snapshot_path)
			if String(save_result.get("status", "")) != "saved":
				exit_code = 1
				failure_message = "save_snapshot did not succeed: %s" % JSON.stringify(save_result)
			else:
				var listing: Array = CliActionsScript.list_user_snapshots()
				var saw_smoke := false
				for entry in listing:
					if String(entry.get("file_name", "")).find("cli_actions_smoke.json") != -1:
						saw_smoke = true
						break
				# list_user_snapshots only matches cli_inspect_*.json prefix on purpose, so
				# our cli_actions_smoke.json should NOT show up. Confirm we're filtering by prefix.
				if saw_smoke:
					exit_code = 1
					failure_message = "list_user_snapshots returned non-prefix file: %s" % JSON.stringify(listing)

				if exit_code == 0:
					var fresh_world := WorldStateScript.new()
					worlds_to_release.append(fresh_world)
					var load_result: Dictionary = CliActionsScript.load_snapshot(fresh_world, snapshot_path)
					if String(load_result.get("status", "")) != "loaded":
						exit_code = 1
						failure_message = "load_snapshot did not succeed: %s" % JSON.stringify(load_result)
					else:
						var snapshot: Dictionary = fresh_world.get_world_snapshot()
						var by_id: Dictionary = snapshot.get("installed_rules_by_id", {})
						var loaded_rule: Dictionary = by_id.get("actions_smoke_rule", {})
						if loaded_rule.is_empty():
							exit_code = 1
							failure_message = "Loaded snapshot missing actions_smoke_rule."
						elif bool(loaded_rule.get("enabled", true)) != false:
							exit_code = 1
							failure_message = "Loaded rule did not preserve disabled flag."

					if exit_code == 0:
						# Re-enable in original world via CliActions and confirm round-trip.
						var enable_result: Dictionary = CliActionsScript.set_rule_enabled(world, "actions_smoke_rule", true)
						if String(enable_result.get("status", "")) != "enabled":
							exit_code = 1
							failure_message = "set_rule_enabled re-enable failed: %s" % JSON.stringify(enable_result)

					if exit_code == 0:
						# Engine-safe error path: missing rule id should return error.
						var missing_result: Dictionary = CliActionsScript.set_rule_enabled(world, "no_such_rule", false)
						if String(missing_result.get("status", "")) != "error":
							exit_code = 1
							failure_message = "set_rule_enabled on missing rule did not error: %s" % JSON.stringify(missing_result)

					if exit_code == 0:
						var null_result: Dictionary = CliActionsScript.set_rule_enabled(null, "anything", false)
						if String(null_result.get("status", "")) != "error":
							exit_code = 1
							failure_message = "set_rule_enabled with null world did not error: %s" % JSON.stringify(null_result)

	for w in worlds_to_release:
		if is_instance_valid(w):
			w.free()

	_remove_file(snapshot_path)

	if exit_code != 0:
		push_error(failure_message)
	quit(exit_code)


func _remove_file(path: String) -> void:
	var absolute_path := ProjectSettings.globalize_path(path)
	if FileAccess.file_exists(absolute_path):
		DirAccess.remove_absolute(absolute_path)
