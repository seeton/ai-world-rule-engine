extends SceneTree

# Collapse-safe last-line-of-defense CLI for the rule engine.
# Runs in headless Godot via `--script`, isolates itself from the live world,
# and only touches engine-safe API on a fresh WorldState instance.

const WorldStateScript = preload("res://scripts/core/WorldState.gd")

const EXIT_OK := 0
const EXIT_USAGE := 2
const EXIT_RUNTIME := 3

var _json_output := false
var _snapshot_path := ""
var _world: Node = null


func _initialize() -> void:
	var positional: Array = []
	var argv := OS.get_cmdline_user_args()
	var index := 0
	while index < argv.size():
		var token := String(argv[index])
		match token:
			"--json":
				_json_output = true
			"--snapshot":
				index += 1
				if index >= argv.size():
					_die_usage("--snapshot requires a path argument.")
					return
				_snapshot_path = String(argv[index])
			"-h", "--help", "help":
				_print_usage()
				_quit_with(EXIT_OK)
				return
			_:
				positional.append(token)
		index += 1

	if positional.is_empty():
		_print_usage()
		_quit_with(EXIT_USAGE)
		return

	var command := String(positional[0])
	var rest := positional.slice(1)

	_world = WorldStateScript.new()

	if not _snapshot_path.is_empty():
		var load_result: Dictionary = _world.load_world_snapshot(_snapshot_path)
		if String(load_result.get("status", "")) != "loaded":
			_emit_log("Failed to load snapshot from %s: %s" % [_snapshot_path, JSON.stringify(load_result)])
			_quit_with(EXIT_RUNTIME)
			return

	match command:
		"inspect":
			_run_inspect()
		"rule":
			_run_rule(rest)
		"package":
			_run_package(rest)
		"snapshot":
			_run_snapshot(rest)
		_:
			_die_usage("Unknown command: %s" % command)


func _run_inspect() -> void:
	var snapshot: Dictionary = _world.get_world_snapshot()
	var installed_rules: Array = snapshot.get("installed_rules", [])
	var rule_summaries: Array = []
	var disabled_rule_ids: Array = []
	var rules_with_unmet_requirements: Array = []
	for rule in installed_rules:
		if not (rule is Dictionary):
			continue
		var rule_data: Dictionary = rule
		var rule_id := String(rule_data.get("id", ""))
		var enabled := bool(rule_data.get("enabled", true))
		var missing_kinds: Array = rule_data.get("missing_required_rule_kinds", [])
		rule_summaries.append({
			"rule_id": rule_id,
			"name": String(rule_data.get("name", rule_id)),
			"enabled": enabled,
			"package_id": String(rule_data.get("metadata", {}).get("package_id", "")),
			"requires_rule_kinds": rule_data.get("requires_rule_kinds", []).duplicate(true),
			"provides_rule_kinds": rule_data.get("provides_rule_kinds", []).duplicate(true),
			"resolved_parent_rule_ids": rule_data.get("resolved_parent_rule_ids", []).duplicate(true),
			"missing_required_rule_kinds": missing_kinds.duplicate(true)
		})
		if not enabled:
			disabled_rule_ids.append(rule_id)
		if not missing_kinds.is_empty():
			rules_with_unmet_requirements.append(rule_id)

	var packages: Array = []
	for package_summary in _world.get_available_rule_packages():
		packages.append(package_summary)

	var has_movement: bool = _has_kind_provider(installed_rules, "space")
	var has_input: bool = _has_kind_provider(installed_rules, "input")
	var world_clock_value: Variant = snapshot.get("world_clock", {})
	var has_world_clock: bool = (world_clock_value is Dictionary) and not (world_clock_value as Dictionary).is_empty()
	var collapse_signals: Array = []
	if installed_rules.is_empty():
		collapse_signals.append("no_installed_rules")
	if not rules_with_unmet_requirements.is_empty():
		collapse_signals.append("rules_with_unmet_requirements")
	if not disabled_rule_ids.is_empty():
		collapse_signals.append("disabled_rules_present")

	var report := {
		"world": {
			"world_id": snapshot.get("world_id", ""),
			"world_name": snapshot.get("world_name", ""),
			"world_mode": snapshot.get("world_mode", ""),
			"tick": int(snapshot.get("tick", 0)),
			"elapsed_seconds": float(snapshot.get("elapsed_seconds", 0.0))
		},
		"installed_rules": rule_summaries,
		"installed_rule_count": rule_summaries.size(),
		"disabled_rule_ids": disabled_rule_ids,
		"rules_with_unmet_requirements": rules_with_unmet_requirements,
		"installed_packages": packages,
		"installed_package_count": packages.size(),
		"world_status": {
			"has_world_clock": has_world_clock,
			"has_movement_provider": has_movement,
			"has_input_provider": has_input,
			"collapse_signals": collapse_signals
		},
		"snapshot_loaded_from": _snapshot_path
	}
	_emit_result(report)
	_quit_with(EXIT_OK)


func _run_rule(args: Array) -> void:
	if args.size() < 2:
		_die_usage("rule subcommand requires <enable|disable> <rule_id>.")
		return
	var action := String(args[0])
	var rule_id := String(args[1])
	var enabled: bool
	match action:
		"enable":
			enabled = true
		"disable":
			enabled = false
		_:
			_die_usage("rule subcommand action must be 'enable' or 'disable'.")
			return

	var result: Dictionary = _world.set_rule_enabled(rule_id, enabled)
	var status := String(result.get("status", ""))
	_emit_result(result)
	if status == "enabled" or status == "disabled":
		_quit_with(EXIT_OK)
	else:
		_quit_with(EXIT_RUNTIME)


func _run_package(args: Array) -> void:
	if args.is_empty():
		_die_usage("package subcommand requires an action (list).")
		return
	var action := String(args[0])
	if action != "list":
		_die_usage("package subcommand only supports 'list' in Phase 1.")
		return
	var packages: Array = _world.get_available_rule_packages()
	_emit_result({
		"packages": packages,
		"package_count": packages.size()
	})
	_quit_with(EXIT_OK)


func _run_snapshot(args: Array) -> void:
	if args.size() < 2:
		_die_usage("snapshot subcommand requires <dump|load> <path>.")
		return
	var action := String(args[0])
	var path := String(args[1])
	match action:
		"dump":
			var save_result: Dictionary = _world.save_world_snapshot(path)
			_emit_result({
				"status": save_result.get("status", ""),
				"path": save_result.get("path", path),
				"message": save_result.get("message", "")
			})
			if String(save_result.get("status", "")) == "saved":
				_quit_with(EXIT_OK)
			else:
				_quit_with(EXIT_RUNTIME)
		"load":
			var load_result: Dictionary = _world.load_world_snapshot(path)
			_emit_result({
				"status": load_result.get("status", ""),
				"path": load_result.get("path", path),
				"message": load_result.get("message", "")
			})
			if String(load_result.get("status", "")) == "loaded":
				_quit_with(EXIT_OK)
			else:
				_quit_with(EXIT_RUNTIME)
		_:
			_die_usage("snapshot subcommand action must be 'dump' or 'load'.")


func _has_kind_provider(installed_rules: Array, required_kind: String) -> bool:
	for rule in installed_rules:
		if not (rule is Dictionary):
			continue
		if not bool(rule.get("enabled", true)):
			continue
		for kind in rule.get("provides_rule_kinds", []):
			if String(kind) == required_kind:
				return true
	return false


func _emit_result(result: Variant) -> void:
	if _json_output:
		print(JSON.stringify(result, "", true))
		return
	if result is Dictionary:
		_print_dictionary_pretty(result, 0)
	else:
		print(JSON.stringify(result, "\t", true))


func _print_dictionary_pretty(value: Dictionary, indent_level: int) -> void:
	var indent := "  ".repeat(indent_level)
	var keys: Array = value.keys()
	keys.sort()
	for key in keys:
		var entry: Variant = value[key]
		if entry is Dictionary:
			print("%s%s:" % [indent, key])
			_print_dictionary_pretty(entry, indent_level + 1)
		elif entry is Array:
			print("%s%s: %s" % [indent, key, JSON.stringify(entry, "", true)])
		else:
			print("%s%s: %s" % [indent, key, str(entry)])


func _emit_log(message: String) -> void:
	printerr(message)


func _print_usage() -> void:
	printerr("Usage: godot --headless --script res://scripts/cli/main.gd -- <command> [args] [--json] [--snapshot <path>]")
	printerr("Commands:")
	printerr("  inspect")
	printerr("    Print installed rules / packages / collapse signals.")
	printerr("  rule enable <rule_id>")
	printerr("  rule disable <rule_id>")
	printerr("    Toggle a rule's enabled flag via engine-safe API.")
	printerr("  package list")
	printerr("    List installed rule packages discovered under the project's rules/packages directory.")
	printerr("  snapshot dump <path>")
	printerr("  snapshot load <path>")
	printerr("    Save / load a deterministic world snapshot via SimulationRuntime.")
	printerr("Global flags:")
	printerr("  --json            Emit machine-parseable JSON on stdout (one line).")
	printerr("  --snapshot <path> Load a saved snapshot before running the command.")


func _die_usage(message: String) -> void:
	_emit_log(message)
	_print_usage()
	_quit_with(EXIT_USAGE)


func _quit_with(code: int) -> void:
	if _world != null and is_instance_valid(_world):
		_world.free()
		_world = null
	quit(code)
