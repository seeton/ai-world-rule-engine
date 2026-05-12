extends RefCounted
class_name WorldOpEnableRule

# EnableRule — flip the engine-safe enabled flag on an installed rule.
# Validation requires a non-empty rule_id and that the rule actually exists.
# dry_run reports the would-be transition without mutating WorldState.

const WorldOpResultScript = preload("res://scripts/world_ops/result.gd")
const CliActionsScript = preload("res://scripts/cli/cli_actions.gd")

const TYPE := "EnableRule"


static func operation_type() -> String:
	return TYPE


static func validate(world: Object, request: Dictionary) -> Dictionary:
	var errors := PackedStringArray()
	var warnings := PackedStringArray()
	var rule_id := String(request.get("rule_id", "")).strip_edges()
	if rule_id.is_empty():
		errors.append("EnableRule.rule_id must be a non-empty string.")
	elif world != null:
		var rule := _lookup_rule(world, rule_id)
		if rule.is_empty():
			errors.append("rule '%s' is not installed." % rule_id)
		elif bool(rule.get("enabled", true)):
			warnings.append("rule '%s' is already enabled." % rule_id)
	return {"errors": errors, "warnings": warnings}


static func dry_run(world: Object, request: Dictionary) -> Dictionary:
	var rule_id := String(request.get("rule_id", "")).strip_edges()
	var rule := _lookup_rule(world, rule_id)
	var was_enabled := bool(rule.get("enabled", true))
	var lines := PackedStringArray()
	lines.append("[dry-run] would set rule '%s' enabled=true (was %s)." % [rule_id, "true" if was_enabled else "false"])
	var preview_diff := _build_diff(rule_id, was_enabled, true)
	return WorldOpResultScript.dry_run(TYPE, lines, {"rule_id": rule_id, "would_set_enabled": true, "previous_enabled": was_enabled}, preview_diff, _rollback_hint(rule_id))


static func execute(world: Object, request: Dictionary) -> Dictionary:
	var rule_id := String(request.get("rule_id", "")).strip_edges()
	var rule_before := _lookup_rule(world, rule_id)
	var was_enabled := bool(rule_before.get("enabled", true))
	var action_result: Dictionary = CliActionsScript.set_rule_enabled(world, rule_id, true)
	var status := String(action_result.get("status", ""))
	if status == "enabled":
		var lines := PackedStringArray()
		lines.append("rule '%s' enabled (was %s)." % [rule_id, "true" if was_enabled else "false"])
		var diff := _build_diff(rule_id, was_enabled, true)
		var payload := {"rule_id": rule_id, "previous_enabled": was_enabled, "enabled": true}
		return WorldOpResultScript.ok(TYPE, lines, payload, diff, _rollback_hint(rule_id))
	var error_lines := PackedStringArray()
	error_lines.append("EnableRule failed: %s" % String(action_result.get("message", status)))
	return WorldOpResultScript.execution_error(TYPE, error_lines, action_result)


static func _lookup_rule(world: Object, rule_id: String) -> Dictionary:
	if world == null or rule_id.is_empty() or not world.has_method("get_world_snapshot"):
		return {}
	var snapshot_variant: Variant = world.call("get_world_snapshot")
	if not (snapshot_variant is Dictionary):
		return {}
	var by_id: Dictionary = (snapshot_variant as Dictionary).get("installed_rules_by_id", {})
	if not (by_id is Dictionary):
		return {}
	var rule_variant: Variant = by_id.get(rule_id, {})
	return rule_variant if rule_variant is Dictionary else {}


static func _build_diff(rule_id: String, before: bool, after: bool) -> Dictionary:
	return {
		"rule_id": rule_id,
		"enabled": {"before": before, "after": after}
	}


static func _rollback_hint(rule_id: String) -> Dictionary:
	return {"supported": true, "hint": "Inverse op: DisableRule rule_id=%s" % rule_id}
