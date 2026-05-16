extends SceneTree

# Surface parity smoke test.
# Verifies that the same World Operation produces equivalent results when
# invoked from the CLI surface (string -> CliCommandParser -> dispatcher)
# and directly via WorldOpDispatcher (the path other surfaces — GUI / GM /
# automation — will use). Drift between surfaces is exactly what #106 set
# out to prevent.

const WorldStateScript = preload("res://scripts/core/WorldState.gd")
const WorldOpDispatcherScript = preload("res://scripts/world_ops/dispatcher.gd")
const CliCommandParserScript = preload("res://scripts/cli/cli_command_parser.gd")

# Fields whose values are intentionally per-call (audit metadata) and must
# not be compared between surfaces.
const NON_DETERMINISTIC_KEYS := ["audit"]


func _initialize() -> void:
	var exit_code := 0
	var failure_message := ""
	var nodes_to_release: Array = []

	var world := WorldStateScript.new()
	nodes_to_release.append(world)

	var install_result: Dictionary = world.create_rule_from_patch({
		"template_id": "hunger",
		"id": "parity_smoke_rule",
		"metadata": {"package_id": "parity.smoke"}
	})
	if String(install_result.get("status", "")) != "installed":
		exit_code = 1
		failure_message = "Rule install failed."

	# 1. inspect parity
	if exit_code == 0:
		var via_cli: Dictionary = CliCommandParserScript.dispatch_string(world, PackedStringArray(["inspect"]), {})
		var via_direct: Dictionary = WorldOpDispatcherScript.dispatch(world, "InspectWorld", {}, {})
		var diff_message := _compare_results(via_cli, via_direct)
		if not diff_message.is_empty():
			exit_code = 1
			failure_message = "inspect parity mismatch: %s" % diff_message

	# 2. inspect dry-run parity.
	if exit_code == 0:
		var via_cli: Dictionary = CliCommandParserScript.dispatch_string(world, PackedStringArray(["inspect"]), {"dry_run": true})
		var via_direct: Dictionary = WorldOpDispatcherScript.dispatch(world, "InspectWorld", {}, {"dry_run": true})
		var diff_message := _compare_results(via_cli, via_direct)
		if not diff_message.is_empty():
			exit_code = 1
			failure_message = "inspect dry-run parity mismatch: %s" % diff_message

	# 3. rule disable parity. Both surfaces target the same rule and use
	# dry_run so neither call mutates state between them; that way the
	# returned diff previews are guaranteed deterministic.
	if exit_code == 0:
		var via_cli: Dictionary = CliCommandParserScript.dispatch_string(
			world,
			PackedStringArray(["rule", "disable", "parity_smoke_rule"]),
			{"dry_run": true}
		)
		var via_direct: Dictionary = WorldOpDispatcherScript.dispatch(
			world,
			"DisableRule",
			{"rule_id": "parity_smoke_rule"},
			{"dry_run": true}
		)
		var diff_message := _compare_results(via_cli, via_direct)
		if not diff_message.is_empty():
			exit_code = 1
			failure_message = "rule disable dry-run parity mismatch: %s" % diff_message

	# 4. snapshot dump parity (dry_run; no file written).
	if exit_code == 0:
		var via_cli: Dictionary = CliCommandParserScript.dispatch_string(
			world,
			PackedStringArray(["snapshot", "dump", "user://parity.json"]),
			{"dry_run": true}
		)
		var via_direct: Dictionary = WorldOpDispatcherScript.dispatch(
			world,
			"DumpSnapshot",
			{"path": "user://parity.json"},
			{"dry_run": true}
		)
		var diff_message := _compare_results(via_cli, via_direct)
		if not diff_message.is_empty():
			exit_code = 1
			failure_message = "snapshot dump dry-run parity mismatch: %s" % diff_message

	# 5. package list parity.
	if exit_code == 0:
		var via_cli: Dictionary = CliCommandParserScript.dispatch_string(world, PackedStringArray(["package", "list"]), {})
		var via_direct: Dictionary = WorldOpDispatcherScript.dispatch(world, "ListPackages", {}, {})
		var diff_message := _compare_results(via_cli, via_direct)
		if not diff_message.is_empty():
			exit_code = 1
			failure_message = "package list parity mismatch: %s" % diff_message

	# 6. package list dry-run parity.
	if exit_code == 0:
		var via_cli: Dictionary = CliCommandParserScript.dispatch_string(world, PackedStringArray(["package", "list"]), {"dry_run": true})
		var via_direct: Dictionary = WorldOpDispatcherScript.dispatch(world, "ListPackages", {}, {"dry_run": true})
		var diff_message := _compare_results(via_cli, via_direct)
		if not diff_message.is_empty():
			exit_code = 1
			failure_message = "package list dry-run parity mismatch: %s" % diff_message

	# 7. package disable dry-run parity.
	if exit_code == 0:
		var via_cli: Dictionary = CliCommandParserScript.dispatch_string(
			world,
			PackedStringArray(["package", "disable", "parity.smoke"]),
			{"dry_run": true}
		)
		var via_direct: Dictionary = WorldOpDispatcherScript.dispatch(
			world,
			"DisablePackage",
			{"package_id": "parity.smoke"},
			{"dry_run": true}
		)
		var diff_message := _compare_results(via_cli, via_direct)
		if not diff_message.is_empty():
			exit_code = 1
			failure_message = "package disable dry-run parity mismatch: %s" % diff_message

	# 8. package enable dry-run parity.
	if exit_code == 0:
		var via_cli: Dictionary = CliCommandParserScript.dispatch_string(
			world,
			PackedStringArray(["package", "enable", "parity.smoke"]),
			{"dry_run": true}
		)
		var via_direct: Dictionary = WorldOpDispatcherScript.dispatch(
			world,
			"EnablePackage",
			{"package_id": "parity.smoke"},
			{"dry_run": true}
		)
		var diff_message := _compare_results(via_cli, via_direct)
		if not diff_message.is_empty():
			exit_code = 1
			failure_message = "package enable dry-run parity mismatch: %s" % diff_message

	for n in nodes_to_release:
		if is_instance_valid(n):
			n.free()

	if exit_code != 0:
		push_error(failure_message)
	quit(exit_code)


# Compare two operation results, ignoring fields that are intentionally
# non-deterministic between calls (audit operation_id / timestamp).
func _compare_results(a: Dictionary, b: Dictionary) -> String:
	var a_normalized := _strip_non_deterministic(a)
	var b_normalized := _strip_non_deterministic(b)
	var a_serialized := JSON.stringify(a_normalized, "", true)
	var b_serialized := JSON.stringify(b_normalized, "", true)
	if a_serialized != b_serialized:
		return "a=%s\n  b=%s" % [a_serialized, b_serialized]
	return ""


func _strip_non_deterministic(result: Dictionary) -> Dictionary:
	var copy: Dictionary = result.duplicate(true)
	for key in NON_DETERMINISTIC_KEYS:
		if copy.has(key):
			copy[key] = {}
	return copy
