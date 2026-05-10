extends SceneTree

# Tier 2 — collapse-safe headless CLI dispatcher.
# Runs in headless Godot via `--script`, isolates itself from the live world,
# and dispatches the same commands as the in-game text CLI overlay (Tier 1)
# through scripts/cli/cli_command_parser.gd so the two surfaces cannot drift.

const WorldStateScript = preload("res://scripts/core/WorldState.gd")
const CliCommandParserScript = preload("res://scripts/cli/cli_command_parser.gd")

const EXIT_OK := 0
const EXIT_USAGE := 2
const EXIT_RUNTIME := 3

var _json_output := false
var _snapshot_path := ""
var _world: Node = null


func _initialize() -> void:
	var positional := PackedStringArray()
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
			"-h", "--help":
				_dispatch_help()
				return
			_:
				positional.append(token)
		index += 1

	if positional.is_empty():
		_print_usage()
		_quit_with(EXIT_USAGE)
		return

	_world = WorldStateScript.new()

	if not _snapshot_path.is_empty():
		var load_result: Dictionary = _world.load_world_snapshot(_snapshot_path)
		if String(load_result.get("status", "")) != "loaded":
			_emit_log("Failed to load snapshot from %s: %s" % [_snapshot_path, JSON.stringify(load_result)])
			_quit_with(EXIT_RUNTIME)
			return

	var options := {
		"snapshot_loaded_from": _snapshot_path
	}
	var result: Dictionary = CliCommandParserScript.dispatch(_world, positional, options)
	_render_result(result)
	_quit_with(int(result.get("exit_code", EXIT_OK)))


func _dispatch_help() -> void:
	var result: Dictionary = CliCommandParserScript.dispatch(null, PackedStringArray(["help"]), {})
	_render_result(result)
	_quit_with(EXIT_OK)


func _render_result(result: Dictionary) -> void:
	if _json_output:
		var payload: Dictionary = result.get("payload", {})
		print(JSON.stringify(payload, "", true))
		return

	var lines: PackedStringArray = result.get("lines", PackedStringArray())
	var status := String(result.get("status", "ok"))
	if status == "usage_error" or status == "error":
		for line in lines:
			printerr(String(line))
	else:
		for line in lines:
			print(String(line))


func _emit_log(message: String) -> void:
	printerr(message)


func _print_usage() -> void:
	var help_result: Dictionary = CliCommandParserScript.dispatch(null, PackedStringArray(["help"]), {})
	for line in help_result.get("lines", PackedStringArray()):
		printerr(String(line))
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
