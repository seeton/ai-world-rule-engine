extends RefCounted
class_name CliCommandParser

# Surface adapter (CLI). Tokenizes string args into a typed
# { operation_type, request } pair and forwards to WorldOpDispatcher.
#
# Per #106, the parser does NOT execute operations and does NOT touch
# WorldState directly. It only translates CLI syntax → operation request
# and renders the dispatcher's uniform result for the caller.
#
# GUI / GM / Codex surfaces will sit at the same level as this parser:
# different syntax, same dispatcher.

const WorldOpDispatcherScript = preload("res://scripts/world_ops/dispatcher.gd")

const EXIT_OK := 0
const EXIT_USAGE := 2
const EXIT_RUNTIME := 3


# Convenience: tokenize and dispatch in one call. Returns the dispatcher's
# uniform result Dictionary (plus a "directive" status for surface-only
# meta commands that don't reach the operation layer).
static func dispatch_string(world: Object, args: PackedStringArray, options: Dictionary = {}) -> Dictionary:
	if args.is_empty():
		return _surface_directive("usage_error", PackedStringArray(["コマンドを指定してください。'help' で一覧を表示します。"]))

	var command := String(args[0])
	var rest := _slice(args, 1)

	# Surface-only meta commands. These never reach WorldOpDispatcher because
	# they're about the surface's own UI (clear scrollback / show help).
	match command:
		"help", "?", "--help", "-h":
			return _help()
		"clear":
			return {
				"operation_type": "",
				"status": "directive",
				"exit_code": EXIT_OK,
				"lines": PackedStringArray(),
				"payload": {"directive": "clear"},
				"diff": {},
				"audit": {},
				"rollback": {"supported": false, "hint": ""},
				"validation": {"errors": PackedStringArray(), "warnings": PackedStringArray()}
			}

	var translation := translate(command, rest)
	if String(translation.get("status", "")) == "usage_error":
		return _surface_directive("usage_error", translation.get("lines", PackedStringArray()))

	var operation_type := String(translation.get("operation_type", ""))
	var request: Dictionary = translation.get("request", {})
	return WorldOpDispatcherScript.dispatch(world, operation_type, request, options)


# Translate a CLI subcommand + its arguments into an operation request.
# Keep this pure (no WorldState access) so the same translation is testable
# in isolation and reusable by other CLI-like surfaces (e.g. an HTTP API).
static func translate(command: String, args: PackedStringArray) -> Dictionary:
	match command:
		"inspect":
			return {
				"status": "ok",
				"operation_type": "InspectWorld",
				"request": {}
			}
		"rule":
			if args.size() < 2:
				return _usage_error("rule コマンドは <enable|disable> <rule_id> を要求します。")
			var action := String(args[0])
			var rule_id := String(args[1])
			match action:
				"enable":
					return {
						"status": "ok",
						"operation_type": "EnableRule",
						"request": {"rule_id": rule_id}
					}
				"disable":
					return {
						"status": "ok",
						"operation_type": "DisableRule",
						"request": {"rule_id": rule_id}
					}
				_:
					return _usage_error("rule のサブコマンドは 'enable' か 'disable' です。")
		"package":
			if args.is_empty():
				return _usage_error("package コマンドは <list|install> を要求します。")
			var action := String(args[0])
			match action:
				"list":
					if args.size() != 1:
						return _usage_error("package list は追加の引数を取りません。")
					return {
						"status": "ok",
						"operation_type": "ListPackages",
						"request": {}
					}
				"install":
					if args.size() < 2:
						return _usage_error("package install コマンドは <package_id> を要求します。")
					return {
						"status": "ok",
						"operation_type": "InstallPackage",
						"request": {"package_id": String(args[1])}
					}
				_:
					return _usage_error("package のサブコマンドは 'list' か 'install' です。")
		"snapshot":
			if args.size() < 2:
				return _usage_error("snapshot コマンドは <dump|load> <path> を要求します。")
			var action := String(args[0])
			var path := String(args[1])
			match action:
				"dump":
					return {
						"status": "ok",
						"operation_type": "DumpSnapshot",
						"request": {"path": path}
					}
				"load":
					return {
						"status": "ok",
						"operation_type": "LoadSnapshot",
						"request": {"path": path}
					}
				_:
					return _usage_error("snapshot のサブコマンドは 'dump' か 'load' です。")
		_:
			return _usage_error("未対応のコマンドです: '%s'。'help' を実行してください。" % command)


static func help_lines() -> PackedStringArray:
	var lines := PackedStringArray()
	lines.append("使用可能なコマンド:")
	lines.append("  inspect")
	lines.append("    -> InspectWorld: ワールドの状態を表示。")
	lines.append("  rule enable <rule_id>")
	lines.append("    -> EnableRule: 指定ルールを有効化。")
	lines.append("  rule disable <rule_id>")
	lines.append("    -> DisableRule: 指定ルールを無効化。")
	lines.append("  package list")
	lines.append("    -> ListPackages: インストール候補を列挙。")
	lines.append("  package install <package_id>")
	lines.append("    -> InstallPackage: 指定 package を現在 world に導入。")
	lines.append("  snapshot dump <path>")
	lines.append("    -> DumpSnapshot: 決定的スナップショットを書き出し。")
	lines.append("  snapshot load <path>")
	lines.append("    -> LoadSnapshot: スナップショットで現在世界を置換。")
	lines.append("  clear")
	lines.append("    overlay 専用: スクロールバックを消去。")
	lines.append("  help")
	lines.append("    このヘルプを表示。")
	lines.append("(各 CLI コマンドは World Operation API に翻訳されて dispatcher を経由します)")
	return lines


static func _help() -> Dictionary:
	return {
		"operation_type": "",
		"status": "directive",
		"exit_code": EXIT_OK,
		"lines": help_lines(),
		"payload": {"directive": "help"},
		"diff": {},
		"audit": {},
		"rollback": {"supported": false, "hint": ""},
		"validation": {"errors": PackedStringArray(), "warnings": PackedStringArray()}
	}


static func _usage_error(message: String) -> Dictionary:
	var lines := PackedStringArray()
	lines.append(message)
	return {
		"status": "usage_error",
		"operation_type": "",
		"request": {},
		"lines": lines
	}


static func _surface_directive(status: String, lines: PackedStringArray) -> Dictionary:
	var exit_code := EXIT_USAGE if status == "usage_error" else EXIT_OK
	return {
		"operation_type": "",
		"status": status,
		"exit_code": exit_code,
		"lines": lines,
		"payload": {"message": " / ".join(lines)},
		"diff": {},
		"audit": {},
		"rollback": {"supported": false, "hint": ""},
		"validation": {"errors": lines if status == "usage_error" else PackedStringArray(), "warnings": PackedStringArray()}
	}


static func _slice(args: PackedStringArray, start: int) -> PackedStringArray:
	var result := PackedStringArray()
	for index in range(start, args.size()):
		result.append(args[index])
	return result
