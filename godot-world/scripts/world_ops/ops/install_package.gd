extends RefCounted
class_name WorldOpInstallPackage

const WorldOpResultScript = preload("res://scripts/world_ops/result.gd")
const CliActionsScript = preload("res://scripts/cli/cli_actions.gd")

const TYPE := "InstallPackage"


static func operation_type() -> String:
	return TYPE


static func validate(world: Object, request: Dictionary) -> Dictionary:
	var errors := PackedStringArray()
	var warnings := PackedStringArray()
	var package_id := String(request.get("package_id", "")).strip_edges()
	if package_id.is_empty():
		errors.append("InstallPackage.package_id must be a non-empty string.")
	elif world == null:
		errors.append("WorldState is not available.")
	else:
		var package_summary := _lookup_package(world, package_id)
		if package_summary.is_empty():
			errors.append("package '%s' is not available." % package_id)
		elif _has_installed_package(world, package_id):
			warnings.append("package '%s' already has installed rules in this world." % package_id)
	return {"errors": errors, "warnings": warnings}


static func dry_run(world: Object, request: Dictionary) -> Dictionary:
	var package_id := String(request.get("package_id", "")).strip_edges()
	var package_summary := _lookup_package(world, package_id)
	var display_name := String(package_summary.get("display_name", package_id))
	var already_installed := _has_installed_package(world, package_id)
	var lines := PackedStringArray()
	lines.append("[dry-run] would install package '%s' (%s)." % [package_id, display_name])
	var payload := {
		"package_id": package_id,
		"display_name": display_name,
		"already_installed": already_installed,
		"package": package_summary.duplicate(true)
	}
	return WorldOpResultScript.dry_run(TYPE, lines, payload, _build_diff(package_id, already_installed, true, ""), _rollback_hint(package_id, ""))


static func execute(world: Object, request: Dictionary) -> Dictionary:
	var package_id := String(request.get("package_id", "")).strip_edges()
	var already_installed := _has_installed_package(world, package_id)
	var action_result: Dictionary = CliActionsScript.install_package(world, package_id)
	var status := String(action_result.get("status", ""))
	if status == "installed":
		var installed_rule: Dictionary = action_result.get("rule", {})
		var rule_id := String(installed_rule.get("id", "")).strip_edges()
		var lines := PackedStringArray()
		if rule_id.is_empty():
			lines.append("package '%s' installed." % package_id)
		else:
			lines.append("package '%s' installed as rule '%s'." % [package_id, rule_id])
		var payload := action_result.duplicate(true)
		payload["package_id"] = package_id
		return WorldOpResultScript.ok(TYPE, lines, payload, _build_diff(package_id, already_installed, true, rule_id), _rollback_hint(package_id, rule_id))
	var error_lines := PackedStringArray()
	error_lines.append("InstallPackage failed: %s" % String(action_result.get("message", status)))
	return WorldOpResultScript.execution_error(TYPE, error_lines, action_result)


static func _lookup_package(world: Object, package_id: String) -> Dictionary:
	if world == null or package_id.is_empty() or not world.has_method("get_available_rule_packages"):
		return {}
	var packages_variant: Variant = world.call("get_available_rule_packages")
	if not (packages_variant is Array):
		return {}
	for entry in packages_variant:
		if not (entry is Dictionary):
			continue
		var package_summary: Dictionary = entry
		if String(package_summary.get("package_id", "")).strip_edges() == package_id:
			return package_summary
	return {}


static func _has_installed_package(world: Object, package_id: String) -> bool:
	if world == null or package_id.is_empty() or not world.has_method("get_world_snapshot"):
		return false
	var snapshot_variant: Variant = world.call("get_world_snapshot")
	if not (snapshot_variant is Dictionary):
		return false
	var installed_rules_by_id: Dictionary = (snapshot_variant as Dictionary).get("installed_rules_by_id", {})
	if not (installed_rules_by_id is Dictionary):
		return false
	for rule_variant in installed_rules_by_id.values():
		if not (rule_variant is Dictionary):
			continue
		var metadata: Dictionary = (rule_variant as Dictionary).get("metadata", {})
		if String(metadata.get("package_id", "")).strip_edges() == package_id:
			return true
	return false


static func _build_diff(package_id: String, before: bool, after: bool, rule_id: String) -> Dictionary:
	return {
		"package_id": package_id,
		"package_present_in_world": {"before": before, "after": after},
		"rule_id": rule_id
	}


static func _rollback_hint(package_id: String, rule_id: String) -> Dictionary:
	if not rule_id.is_empty():
		return {"supported": true, "hint": "Use rule disable %s or reload a snapshot taken before package install (%s)." % [rule_id, package_id]}
	return {"supported": false, "hint": "Reload a snapshot taken before package install (%s)." % package_id}
