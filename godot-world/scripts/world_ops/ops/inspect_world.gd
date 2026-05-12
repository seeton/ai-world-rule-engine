extends RefCounted
class_name WorldOpInspectWorld

# InspectWorld — read-only observation of the current world.
# Always valid. dry_run == execute (no side effects either way).

const WorldOpResultScript = preload("res://scripts/world_ops/result.gd")
const InspectReportScript = preload("res://scripts/cli/inspect_report.gd")

const TYPE := "InspectWorld"


static func operation_type() -> String:
	return TYPE


static func validate(_world: Object, _request: Dictionary) -> Dictionary:
	return {"errors": PackedStringArray(), "warnings": PackedStringArray()}


static func dry_run(world: Object, request: Dictionary) -> Dictionary:
	var snapshot_loaded_from := String(request.get("snapshot_loaded_from", ""))
	var report: Dictionary = InspectReportScript.build(world, snapshot_loaded_from)
	var lines := _format_lines(report)
	return WorldOpResultScript.dry_run(TYPE, lines, report, {}, {"supported": true, "hint": "Re-run InspectWorld is idempotent (read-only)."})


static func execute(world: Object, request: Dictionary) -> Dictionary:
	var snapshot_loaded_from := String(request.get("snapshot_loaded_from", ""))
	var report: Dictionary = InspectReportScript.build(world, snapshot_loaded_from)
	var lines := _format_lines(report)
	return WorldOpResultScript.ok(TYPE, lines, report, {}, {"supported": true, "hint": "Re-run InspectWorld is idempotent (read-only)."})


static func _format_lines(report: Dictionary) -> PackedStringArray:
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
	var signals_text := ", ".join(_to_strings(collapse_signals)) if not collapse_signals.is_empty() else "(none)"
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
		lines.append("disabled: %s" % ", ".join(_to_strings(disabled_rule_ids)))

	var unmet: Array = report.get("rules_with_unmet_requirements", [])
	if not unmet.is_empty():
		lines.append("unmet_requirements: %s" % ", ".join(_to_strings(unmet)))

	return lines


static func _to_strings(values: Array) -> PackedStringArray:
	var result := PackedStringArray()
	for value in values:
		result.append(String(value))
	return result


static func _yes_no(value: bool) -> String:
	return "yes" if value else "no"
