extends SceneTree

const WorldStateScript = preload("res://scripts/core/WorldState.gd")
const CliCommandParserScript = preload("res://scripts/cli/cli_command_parser.gd")


func _initialize() -> void:
	var exit_code := 0
	var failure_message := ""
	var nodes_to_release: Array = []

	var snapshot_path := "user://cli_command_parser_smoke.json"
	_remove_file(snapshot_path)

	var world := WorldStateScript.new()
	nodes_to_release.append(world)

	var help_result: Dictionary = CliCommandParserScript.dispatch_string(null, PackedStringArray(["help"]), {})
	if String(help_result.get("status", "")) != "directive":
		exit_code = 1
		failure_message = "help did not return directive: %s" % JSON.stringify(help_result)

	if exit_code == 0:
		var unknown_result: Dictionary = CliCommandParserScript.dispatch_string(world, PackedStringArray(["nope"]), {})
		if String(unknown_result.get("status", "")) != "usage_error" or int(unknown_result.get("exit_code", 0)) != 2:
			exit_code = 1
			failure_message = "unknown command did not produce usage_error/2: %s" % JSON.stringify(unknown_result)

	if exit_code == 0:
		var clear_result: Dictionary = CliCommandParserScript.dispatch_string(world, PackedStringArray(["clear"]), {})
		if String(clear_result.get("status", "")) != "directive":
			exit_code = 1
			failure_message = "clear did not return directive: %s" % JSON.stringify(clear_result)

	if exit_code == 0:
		var inspect_result: Dictionary = CliCommandParserScript.dispatch_string(world, PackedStringArray(["inspect"]), {})
		if String(inspect_result.get("status", "")) != "ok":
			exit_code = 1
			failure_message = "inspect failed: %s" % JSON.stringify(inspect_result)
		else:
			var payload: Dictionary = inspect_result.get("payload", {})
			var status: Dictionary = payload.get("world_status", {})
			var collapse: Array = status.get("collapse_signals", [])
			if not collapse.has("no_installed_rules"):
				exit_code = 1
				failure_message = "inspect did not include no_installed_rules: %s" % JSON.stringify(collapse)

	if exit_code == 0:
		var install_result: Dictionary = world.create_rule_from_patch({
			"template_id": "hunger",
			"id": "parser_smoke_rule",
			"metadata": {"package_id": "parser.smoke"}
		})
		if String(install_result.get("status", "")) != "installed":
			exit_code = 1
			failure_message = "rule install failed: %s" % JSON.stringify(install_result)

	if exit_code == 0:
		var disable_result: Dictionary = CliCommandParserScript.dispatch_string(world, PackedStringArray(["rule", "disable", "parser_smoke_rule"]), {})
		if String(disable_result.get("status", "")) != "ok":
			exit_code = 1
			failure_message = "rule disable did not succeed: %s" % JSON.stringify(disable_result)

	if exit_code == 0:
		var disable_missing: Dictionary = CliCommandParserScript.dispatch_string(world, PackedStringArray(["rule", "disable", "no_such"]), {})
		if String(disable_missing.get("status", "")) != "validation_error" or int(disable_missing.get("exit_code", 0)) != 2:
			exit_code = 1
			failure_message = "rule disable on missing did not produce validation_error/2: %s" % JSON.stringify(disable_missing)

	if exit_code == 0:
		var package_result: Dictionary = CliCommandParserScript.dispatch_string(world, PackedStringArray(["package", "list"]), {})
		var packages: Array = package_result.get("payload", {}).get("packages", [])
		if String(package_result.get("status", "")) != "ok" or packages.is_empty():
			exit_code = 1
			failure_message = "package list returned no packages: %s" % JSON.stringify(package_result)

	if exit_code == 0:
		var save_result: Dictionary = CliCommandParserScript.dispatch_string(world, PackedStringArray(["snapshot", "dump", snapshot_path]), {})
		if String(save_result.get("status", "")) != "ok":
			exit_code = 1
			failure_message = "snapshot dump failed: %s" % JSON.stringify(save_result)

	if exit_code == 0:
		var fresh_world := WorldStateScript.new()
		nodes_to_release.append(fresh_world)
		var load_result: Dictionary = CliCommandParserScript.dispatch_string(fresh_world, PackedStringArray(["snapshot", "load", snapshot_path]), {})
		if String(load_result.get("status", "")) != "ok":
			exit_code = 1
			failure_message = "snapshot load failed: %s" % JSON.stringify(load_result)
		else:
			var verify_result: Dictionary = CliCommandParserScript.dispatch_string(fresh_world, PackedStringArray(["inspect"]), {})
			var disabled_rules: Array = verify_result.get("payload", {}).get("disabled_rule_ids", [])
			if not disabled_rules.has("parser_smoke_rule"):
				exit_code = 1
				failure_message = "snapshot did not preserve disabled flag through parser path."

	for n in nodes_to_release:
		if is_instance_valid(n):
			n.free()

	_remove_file(snapshot_path)

	if exit_code != 0:
		push_error(failure_message)
	quit(exit_code)


func _remove_file(path: String) -> void:
	var absolute_path := ProjectSettings.globalize_path(path)
	if FileAccess.file_exists(absolute_path):
		DirAccess.remove_absolute(absolute_path)
