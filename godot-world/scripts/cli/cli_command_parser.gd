extends RefCounted
class_name CliCommandParser

# Shared command parser / dispatcher for both the headless CLI
# (scripts/cli/main.gd) and the in-game text CLI overlay
# (scripts/game/cli_inspect_overlay.gd). Same syntax, same engine-safe
# code path; the only difference is how the caller renders the result.
#
# dispatch() returns a uniform shape:
#   {
#     "status":    "ok" | "error" | "usage_error" | "directive",
#     "exit_code": 0 | 2 | 3,            # for headless CLI
#     "lines":     PackedStringArray,    # human-readable, one per line
#     "payload":   Dictionary,           # structured result (used by --json)
#   }
#
# A "directive" status is used for overlay-only meta commands (e.g. clear)
# that the headless CLI ignores.

const InspectReportScript = preload("res://scripts/cli/inspect_report.gd")
const CliActionsScript = preload("res://scripts/cli/cli_actions.gd")

const EXIT_OK := 0
const EXIT_USAGE := 2
const EXIT_RUNTIME := 3


static func dispatch(world: Object, args: PackedStringArray, options: Dictionary = {}) -> Dictionary:
	if args.is_empty():
		return _usage_error("コマンドを指定してください。'help' で一覧を表示します。")

	var command := String(args[0])
	var rest := _slice(args, 1)

	match command:
		"help", "?", "--help", "-h":
			return _help()
		"clear":
			return {
				"status": "directive",
				"exit_code": EXIT_OK,
				"lines": PackedStringArray(),
				"payload": {"directive": "clear"}
			}
		"inspect":
			return _inspect(world, options)
		"rule":
			return _rule(world, rest)
		"package":
			return _package(world, rest)
		"snapshot":
			return _snapshot(world, rest)
		_:
			return _usage_error("未対応のコマンドです: '%s'。'help' を実行してください。" % command)


static func _help() -> Dictionary:
	var lines := PackedStringArray()
	lines.append("使用可能なコマンド:")
	lines.append("  inspect")
	lines.append("    ワールドの状態 (ルール件数 / 崩壊シグナル / 無効化中ルール) を表示します。")
	lines.append("  rule enable <rule_id>")
	lines.append("  rule disable <rule_id>")
	lines.append("    指定ルールの enabled フラグを engine-safe API 経由で操作します。")
	lines.append("  package list")
	lines.append("    インストール候補のルールパッケージを列挙します。")
	lines.append("  snapshot dump <path>")
	lines.append("  snapshot load <path>")
	lines.append("    決定的なワールドスナップショットを保存・読み込みします。")
	lines.append("  clear")
	lines.append("    overlay のスクロールバックを消去します (overlay 専用)。")
	lines.append("  help")
	lines.append("    このヘルプを表示します。")
	return {
		"status": "ok",
		"exit_code": EXIT_OK,
		"lines": lines,
		"payload": {"command": "help"}
	}


static func _inspect(world: Object, options: Dictionary) -> Dictionary:
	var snapshot_loaded_from := String(options.get("snapshot_loaded_from", ""))
	var report: Dictionary = InspectReportScript.build(world, snapshot_loaded_from)
	var lines := _format_inspect_lines(report)
	return {
		"status": "ok",
		"exit_code": EXIT_OK,
		"lines": lines,
		"payload": report
	}


static func _format_inspect_lines(report: Dictionary) -> PackedStringArray:
	var lines := PackedStringArray()
	var world_info: Dictionary = report.get("world", {})
	lines.append("world: %s (%s) mode=%s tick=%d elapsed=%.2fs" % [
		String(world_info.get("world_name", "")),
		String(world_info.get("world_id", "")),
		String(world_info.get("world_mode", "")),
		int(world_info.get("tick", 0)),
		float(world_info.get("elapsed_seconds", 0.0))
	])

	var status: Dictionary = report.get("world_status", {})
	var collapse_signals: Array = status.get("collapse_signals", [])
	var signals_text := ", ".join(_to_string_array(collapse_signals)) if not collapse_signals.is_empty() else "(none)"
	lines.append("collapse_signals: %s" % signals_text)
	lines.append("providers: world_clock=%s movement=%s input=%s" % [
		_yes_no(bool(status.get("has_world_clock", false))),
		_yes_no(bool(status.get("has_movement_provider", false))),
		_yes_no(bool(status.get("has_input_provider", false)))
	])

	lines.append("installed_rules: %d (packages: %d)" % [
		int(report.get("installed_rule_count", 0)),
		int(report.get("installed_package_count", 0))
	])

	var installed_rules: Array = report.get("installed_rules", [])
	if installed_rules.is_empty():
		lines.append("  (rules: none)")
	else:
		for rule in installed_rules:
			if not (rule is Dictionary):
				continue
			var rule_id := String(rule.get("rule_id", ""))
			var enabled := bool(rule.get("enabled", true))
			var package_id := String(rule.get("package_id", ""))
			var suffix := " [%s]" % package_id if not package_id.is_empty() else ""
			lines.append("  - %s%s = %s" % [rule_id, suffix, "enabled" if enabled else "disabled"])

	var disabled_rule_ids: Array = report.get("disabled_rule_ids", [])
	if not disabled_rule_ids.is_empty():
		lines.append("disabled: %s" % ", ".join(_to_string_array(disabled_rule_ids)))

	var unmet_rule_ids: Array = report.get("rules_with_unmet_requirements", [])
	if not unmet_rule_ids.is_empty():
		lines.append("unmet_requirements: %s" % ", ".join(_to_string_array(unmet_rule_ids)))

	return lines


static func _rule(world: Object, args: PackedStringArray) -> Dictionary:
	if args.size() < 2:
		return _usage_error("rule コマンドは <enable|disable> <rule_id> を要求します。")
	var action := String(args[0])
	var rule_id := String(args[1])
	var enabled: bool
	match action:
		"enable":
			enabled = true
		"disable":
			enabled = false
		_:
			return _usage_error("rule のサブコマンドは 'enable' か 'disable' です。")

	var result: Dictionary = CliActionsScript.set_rule_enabled(world, rule_id, enabled)
	var status := String(result.get("status", ""))
	var lines := PackedStringArray()
	if status == "enabled" or status == "disabled":
		lines.append("rule %s: %s" % [rule_id, status])
		return {
			"status": "ok",
			"exit_code": EXIT_OK,
			"lines": lines,
			"payload": result
		}
	lines.append("rule %s: error %s" % [rule_id, String(result.get("message", ""))])
	return {
		"status": "error",
		"exit_code": EXIT_RUNTIME,
		"lines": lines,
		"payload": result
	}


static func _package(world: Object, args: PackedStringArray) -> Dictionary:
	if args.is_empty():
		return _usage_error("package コマンドは 'list' を要求します。")
	var action := String(args[0])
	if action != "list":
		return _usage_error("package で対応しているのは 'list' のみです (Phase 1)。")

	var packages: Array = []
	if world != null and world.has_method("get_available_rule_packages"):
		var packages_variant: Variant = world.call("get_available_rule_packages")
		if packages_variant is Array:
			packages = packages_variant

	var lines := PackedStringArray()
	lines.append("available packages: %d" % packages.size())
	for package in packages:
		if not (package is Dictionary):
			continue
		var package_id := String(package.get("package_id", ""))
		var display := String(package.get("display_name", package_id))
		lines.append("  - %s — %s" % [package_id, display])
	return {
		"status": "ok",
		"exit_code": EXIT_OK,
		"lines": lines,
		"payload": {
			"packages": packages,
			"package_count": packages.size()
		}
	}


static func _snapshot(world: Object, args: PackedStringArray) -> Dictionary:
	if args.size() < 2:
		return _usage_error("snapshot コマンドは <dump|load> <path> を要求します。")
	var action := String(args[0])
	var path := String(args[1])
	match action:
		"dump":
			var save_result: Dictionary = CliActionsScript.save_snapshot(world, path)
			return _format_snapshot_result(save_result, path, "saved", "snapshot saved: %s")
		"load":
			var load_result: Dictionary = CliActionsScript.load_snapshot(world, path)
			return _format_snapshot_result(load_result, path, "loaded", "snapshot loaded: %s")
		_:
			return _usage_error("snapshot のサブコマンドは 'dump' か 'load' です。")


static func _format_snapshot_result(result: Dictionary, path: String, success_status: String, success_message_format: String) -> Dictionary:
	var lines := PackedStringArray()
	if String(result.get("status", "")) == success_status:
		lines.append(success_message_format % path)
		return {
			"status": "ok",
			"exit_code": EXIT_OK,
			"lines": lines,
			"payload": {
				"status": success_status,
				"path": String(result.get("path", path)),
				"message": String(result.get("message", ""))
			}
		}
	lines.append("snapshot error: %s" % String(result.get("message", "")))
	return {
		"status": "error",
		"exit_code": EXIT_RUNTIME,
		"lines": lines,
		"payload": {
			"status": String(result.get("status", "error")),
			"path": String(result.get("path", path)),
			"message": String(result.get("message", ""))
		}
	}


static func _usage_error(message: String) -> Dictionary:
	var lines := PackedStringArray()
	lines.append(message)
	return {
		"status": "usage_error",
		"exit_code": EXIT_USAGE,
		"lines": lines,
		"payload": {"message": message}
	}


static func _slice(args: PackedStringArray, start: int) -> PackedStringArray:
	var result := PackedStringArray()
	for index in range(start, args.size()):
		result.append(args[index])
	return result


static func _to_string_array(values: Array) -> PackedStringArray:
	var result := PackedStringArray()
	for value in values:
		result.append(String(value))
	return result


static func _yes_no(value: bool) -> String:
	return "yes" if value else "no"
