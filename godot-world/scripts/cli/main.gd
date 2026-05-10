extends SceneTree

# Tier 2 — collapse-safe headless CLI dispatcher.
# Per #106, this is a thin surface adapter: it parses argv, hands the
# tokenized command to scripts/cli/cli_command_parser.gd which translates
# to a World Operation request and dispatches via WorldOpDispatcher.
# The CLI never touches WorldState directly.

const WorldStateScript = preload("res://scripts/core/WorldState.gd")
const CliCommandParserScript = preload("res://scripts/cli/cli_command_parser.gd")

const EXIT_OK := 0
const EXIT_USAGE := 2
const EXIT_RUNTIME := 3

var _json_output := false
var _dry_run := false
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
			"--dry-run":
				_dry_run = true
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
		"dry_run": _dry_run
	}
	var result: Dictionary = CliCommandParserScript.dispatch_string(_world, positional, options)
	_render_result(result)
	_quit_with(int(result.get("exit_code", EXIT_OK)))


func _dispatch_help() -> void:
	for line in CliCommandParserScript.help_lines():
		print(String(line))
	_quit_with(EXIT_OK)


func _render_result(result: Dictionary) -> void:
	if _json_output:
		var envelope := {
			"operation_type": String(result.get("operation_type", "")),
			"status": String(result.get("status", "")),
			"exit_code": int(result.get("exit_code", EXIT_OK)),
			"payload": result.get("payload", {}),
			"diff": result.get("diff", {}),
			"audit": result.get("audit", {}),
			"rollback": result.get("rollback", {}),
			"validation": result.get("validation", {})
		}
		print(JSON.stringify(envelope, "", true))
		return

	var status := String(result.get("status", ""))
	var lines: PackedStringArray = result.get("lines", PackedStringArray())
	if status == "usage_error" or status == "execution_error" or status == "validation_error":
		for line in lines:
			printerr(String(line))
	else:
		for line in lines:
			print(String(line))

	var validation: Dictionary = result.get("validation", {})
	for warning in validation.get("warnings", PackedStringArray()):
		printerr("warning: %s" % String(warning))


func _emit_log(message: String) -> void:
	printerr(message)


func _print_usage() -> void:
	for line in CliCommandParserScript.help_lines():
		printerr(String(line))
	printerr("Global flags:")
	printerr("  --json            Emit machine-parseable JSON envelope on stdout (one line).")
	printerr("  --dry-run         Run validate + dry_run only; do not mutate world state.")
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
