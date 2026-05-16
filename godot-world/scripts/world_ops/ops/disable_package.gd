extends RefCounted
class_name WorldOpDisablePackage

const WorldOpResultScript = preload("res://scripts/world_ops/result.gd")
const CliActionsScript = preload("res://scripts/cli/cli_actions.gd")

const TYPE := "DisablePackage"


static func operation_type() -> String:
	return TYPE


static func validate(world: Object, request: Dictionary) -> Dictionary:
	var errors := PackedStringArray()
	var warnings := PackedStringArray()
	var package_id := String(request.get("package_id", "")).strip_edges()
	if package_id.is_empty():
		errors.append("DisablePackage.package_id must be a non-empty string.")
	elif world != null:
		var package_summary := _lookup_package(world, package_id)
		if package_summary.is_empty():
			errors.append("package '%s' is not installed." % package_id)
		elif String(package_summary.get("state", "disabled")) == "disabled":
			warnings.append("package '%s' is already disabled." % package_id)
	return {"errors": errors, "warnings": warnings}


static func dry_run(world: Object, request: Dictionary) -> Dictionary:
	var package_id := String(request.get("package_id", "")).strip_edges()
	var package_summary := _lookup_package(world, package_id)
	var previous_state := String(package_summary.get("state", "disabled"))
	var lines := PackedStringArray()
	lines.append("[dry-run] would set package '%s' enabled=false (was %s)." % [package_id, previous_state])
	var preview_diff := _build_diff(package_id, previous_state, "disabled")
	return WorldOpResultScript.dry_run(TYPE, lines, {"package_id": package_id, "would_set_enabled": false, "previous_state": previous_state}, preview_diff, _rollback_hint(package_id, previous_state))


static func execute(world: Object, request: Dictionary) -> Dictionary:
	var package_id := String(request.get("package_id", "")).strip_edges()
	var package_before := _lookup_package(world, package_id)
	var previous_state := String(package_before.get("state", "disabled"))
	var action_result: Dictionary = CliActionsScript.set_package_enabled(world, package_id, false)
	var status := String(action_result.get("status", ""))
	if status == "disabled":
		var lines := PackedStringArray()
		lines.append("package '%s' disabled (was %s)." % [package_id, previous_state])
		var diff := _build_diff(package_id, previous_state, "disabled")
		var payload := {
			"package_id": package_id,
			"previous_state": previous_state,
			"enabled": false,
			"rule_ids": action_result.get("rule_ids", []),
			"changed_rule_ids": action_result.get("changed_rule_ids", [])
		}
		return WorldOpResultScript.ok(TYPE, lines, payload, diff, _rollback_hint(package_id, previous_state))
	var error_lines := PackedStringArray()
	error_lines.append("DisablePackage failed: %s" % String(action_result.get("message", status)))
	return WorldOpResultScript.execution_error(TYPE, error_lines, action_result)


static func _lookup_package(world: Object, package_id: String) -> Dictionary:
	if world == null or package_id.is_empty() or not world.has_method("get_world_snapshot"):
		return {}
	var snapshot_variant: Variant = world.call("get_world_snapshot")
	if not (snapshot_variant is Dictionary):
		return {}
	var by_id: Dictionary = (snapshot_variant as Dictionary).get("installed_rule_packages_by_id", {})
	if not (by_id is Dictionary):
		return {}
	var package_variant: Variant = by_id.get(package_id, {})
	return package_variant if package_variant is Dictionary else {}


static func _build_diff(package_id: String, before: String, after: String) -> Dictionary:
	return {
		"package_id": package_id,
		"state": {"before": before, "after": after}
	}


static func _rollback_hint(package_id: String, previous_state: String) -> Dictionary:
	if previous_state == "enabled":
		return {"supported": true, "hint": "Inverse op: EnablePackage package_id=%s" % package_id}
	return {
		"supported": false,
		"hint": "Mixed/already-disabled package states require manual per-rule rollback for package_id=%s." % package_id
	}
