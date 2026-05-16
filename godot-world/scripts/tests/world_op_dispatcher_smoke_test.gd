extends SceneTree

# Smoke test for the World Operation dispatcher.
# Covers: result shape contract, validate -> execution_error vs validation_error
# routing, dry_run vs execute, audit augmentation, unknown operation handling.

const WorldStateScript = preload("res://scripts/core/WorldState.gd")
const WorldOpDispatcherScript = preload("res://scripts/world_ops/dispatcher.gd")
const WorldOpInspectWorldScript = preload("res://scripts/world_ops/ops/inspect_world.gd")
const WorldOpListPackagesScript = preload("res://scripts/world_ops/ops/list_packages.gd")
const WorldOpInstallPackageScript = preload("res://scripts/world_ops/ops/install_package.gd")
const WorldOpEnableRuleScript = preload("res://scripts/world_ops/ops/enable_rule.gd")
const WorldOpDisableRuleScript = preload("res://scripts/world_ops/ops/disable_rule.gd")
const WorldOpEnablePackageScript = preload("res://scripts/world_ops/ops/enable_package.gd")
const WorldOpDisablePackageScript = preload("res://scripts/world_ops/ops/disable_package.gd")


class FakeRuleToggleWorld extends RefCounted:
	var _rule_snapshot: Dictionary
	var _status_by_enabled: Dictionary

	func _init(initial_enabled: bool, enabled_status: String, disabled_status: String) -> void:
		_rule_snapshot = {
			"installed_rules_by_id": {
				"fake_rule": {"enabled": initial_enabled}
			}
		}
		_status_by_enabled = {
			true: enabled_status,
			false: disabled_status
		}

	func get_world_snapshot() -> Dictionary:
		return _rule_snapshot.duplicate(true)

	func set_rule_enabled(rule_id: String, enabled: bool) -> Dictionary:
		if not _rule_snapshot.get("installed_rules_by_id", {}).has(rule_id):
			return {"status": "error", "message": "missing"}
		_rule_snapshot["installed_rules_by_id"][rule_id]["enabled"] = enabled
		return {"status": String(_status_by_enabled.get(enabled, "error"))}


class FakePackageToggleWorld extends RefCounted:
	var _package_snapshot: Dictionary
	var _status_by_enabled: Dictionary

	func _init(initial_state: String, enabled_status: String, disabled_status: String) -> void:
		_package_snapshot = {
			"installed_rule_packages_by_id": {
				"fake.package": {
					"state": initial_state,
					"enabled": initial_state != "disabled",
					"all_rules_enabled": initial_state == "enabled"
				}
			}
		}
		_status_by_enabled = {
			true: enabled_status,
			false: disabled_status
		}

	func get_world_snapshot() -> Dictionary:
		return _package_snapshot.duplicate(true)

	func set_package_enabled(package_id: String, enabled: bool) -> Dictionary:
		if not _package_snapshot.get("installed_rule_packages_by_id", {}).has(package_id):
			return {"status": "error", "message": "missing"}
		var state := "enabled" if enabled else "disabled"
		_package_snapshot["installed_rule_packages_by_id"][package_id]["state"] = state
		_package_snapshot["installed_rule_packages_by_id"][package_id]["enabled"] = enabled
		_package_snapshot["installed_rule_packages_by_id"][package_id]["all_rules_enabled"] = enabled
		return {"status": String(_status_by_enabled.get(enabled, "error"))}


const REQUIRED_RESULT_KEYS := [
	"operation_type", "status", "exit_code",
	"lines", "payload", "diff",
	"audit", "rollback", "validation"
]


func _initialize() -> void:
	var exit_code := 0
	var failure_message := ""
	var nodes_to_release: Array = []

	var snapshot_path := "user://world_op_dispatcher_smoke.json"
	_remove_file(snapshot_path)

	var world := WorldStateScript.new()
	nodes_to_release.append(world)

	# 1. InspectWorld returns a fully shaped result.
	var inspect_result: Dictionary = WorldOpDispatcherScript.dispatch(world, "InspectWorld", {}, {})
	if not _has_all_keys(inspect_result, REQUIRED_RESULT_KEYS):
		exit_code = 1
		failure_message = "InspectWorld result missing required keys: %s" % JSON.stringify(inspect_result.keys())

	if exit_code == 0:
		if String(inspect_result.get("operation_type", "")) != "InspectWorld":
			exit_code = 1
			failure_message = "InspectWorld result operation_type wrong."
		elif String(inspect_result.get("status", "")) != "ok":
			exit_code = 1
			failure_message = "InspectWorld did not return ok."
		elif int(inspect_result.get("exit_code", -1)) != 0:
			exit_code = 1
			failure_message = "InspectWorld exit_code != 0."
		elif String(inspect_result.get("audit", {}).get("operation_id", "")).is_empty():
			exit_code = 1
			failure_message = "InspectWorld audit.operation_id was empty."

	# 1b. InspectWorld dry_run must return dry_run without mutating semantics.
	if exit_code == 0:
		var inspect_dry_run: Dictionary = WorldOpDispatcherScript.dispatch(world, "InspectWorld", {}, {"dry_run": true})
		if String(inspect_dry_run.get("status", "")) != "dry_run":
			exit_code = 1
			failure_message = "InspectWorld dry_run did not return dry_run status."

	# 2. Unknown operation_type -> validation_error / exit 2.
	if exit_code == 0:
		var unknown_result: Dictionary = WorldOpDispatcherScript.dispatch(world, "NoSuchOp", {}, {})
		if String(unknown_result.get("status", "")) != "validation_error" or int(unknown_result.get("exit_code", 0)) != 2:
			exit_code = 1
			failure_message = "Unknown op did not produce validation_error/2: %s" % JSON.stringify(unknown_result)

	# 3. DisableRule on a missing rule -> validation_error (not execution_error)
	# because validate() pre-checks installed rules.
	if exit_code == 0:
		var missing_result: Dictionary = WorldOpDispatcherScript.dispatch(world, "DisableRule", {"rule_id": "missing_rule"}, {})
		if String(missing_result.get("status", "")) != "validation_error":
			exit_code = 1
			failure_message = "DisableRule on missing rule did not validation_error: %s" % JSON.stringify(missing_result)

	# Install a rule and test the actuation path.
	if exit_code == 0:
		var install_result: Dictionary = world.create_rule_from_patch({
			"template_id": "hunger",
			"id": "dispatcher_smoke_rule",
			"metadata": {"package_id": "dispatcher.smoke"}
		})
		if String(install_result.get("status", "")) != "installed":
			exit_code = 1
			failure_message = "Rule install failed."

	# 4. dry_run does not mutate; status reports dry_run; diff preview reflects intended change.
	if exit_code == 0:
		var dry_disable: Dictionary = WorldOpDispatcherScript.dispatch(world, "DisableRule", {"rule_id": "dispatcher_smoke_rule"}, {"dry_run": true})
		if String(dry_disable.get("status", "")) != "dry_run":
			exit_code = 1
			failure_message = "DisableRule dry_run did not return dry_run status."
		else:
			var diff: Dictionary = dry_disable.get("diff", {})
			var enabled: Dictionary = diff.get("enabled", {})
			if bool(enabled.get("after", true)) != false or bool(enabled.get("before", false)) != true:
				exit_code = 1
				failure_message = "Dry-run diff preview wrong: %s" % JSON.stringify(diff)
		# Confirm world was NOT mutated.
		var snapshot_after_dry: Dictionary = world.get_world_snapshot()
		var by_id: Dictionary = snapshot_after_dry.get("installed_rules_by_id", {})
		if not bool(by_id.get("dispatcher_smoke_rule", {}).get("enabled", false)):
			exit_code = 1
			failure_message = "Dry-run mutated WorldState (rule was disabled): %s" % JSON.stringify(by_id.get("dispatcher_smoke_rule", {}))

	# 5. execute mutates and reports diff before/after.
	if exit_code == 0:
		var disable_result: Dictionary = WorldOpDispatcherScript.dispatch(world, "DisableRule", {"rule_id": "dispatcher_smoke_rule"}, {})
		if String(disable_result.get("status", "")) != "ok":
			exit_code = 1
			failure_message = "DisableRule execute failed: %s" % JSON.stringify(disable_result)
		else:
			var diff_post: Dictionary = disable_result.get("diff", {})
			var enabled_post: Dictionary = diff_post.get("enabled", {})
			if bool(enabled_post.get("after", true)) != false or bool(enabled_post.get("before", false)) != true:
				exit_code = 1
				failure_message = "Execute diff wrong: %s" % JSON.stringify(diff_post)

	# 6. EnableRule on already-enabled rule produces a warning but still succeeds (it's idempotent toggle).
	# After we just disabled it, EnableRule should succeed with no warning.
	if exit_code == 0:
		var enable_again: Dictionary = WorldOpDispatcherScript.dispatch(world, "EnableRule", {"rule_id": "dispatcher_smoke_rule"}, {})
		if String(enable_again.get("status", "")) != "ok":
			exit_code = 1
			failure_message = "EnableRule failed: %s" % JSON.stringify(enable_again)

	# 7. DumpSnapshot dry_run does not write file.
	if exit_code == 0:
		var package_dry_disable: Dictionary = WorldOpDispatcherScript.dispatch(world, "DisablePackage", {"package_id": "dispatcher.smoke"}, {"dry_run": true})
		if String(package_dry_disable.get("status", "")) != "dry_run":
			exit_code = 1
			failure_message = "DisablePackage dry_run did not return dry_run status."
		else:
			var diff: Dictionary = package_dry_disable.get("diff", {})
			var state_diff: Dictionary = diff.get("state", {})
			if String(state_diff.get("before", "")) != "enabled" or String(state_diff.get("after", "")) != "disabled":
				exit_code = 1
				failure_message = "DisablePackage dry-run diff wrong: %s" % JSON.stringify(diff)
		var snapshot_after_package_dry: Dictionary = world.get_world_snapshot()
		if String(snapshot_after_package_dry.get("installed_rule_packages_by_id", {}).get("dispatcher.smoke", {}).get("state", "")) != "enabled":
			exit_code = 1
			failure_message = "DisablePackage dry_run mutated WorldState package state."

	# 8. execute package disable/enable round-trip.
	if exit_code == 0:
		var package_disable_result: Dictionary = WorldOpDispatcherScript.dispatch(world, "DisablePackage", {"package_id": "dispatcher.smoke"}, {})
		if String(package_disable_result.get("status", "")) != "ok":
			exit_code = 1
			failure_message = "DisablePackage execute failed: %s" % JSON.stringify(package_disable_result)
		elif String(world.get_world_snapshot().get("installed_rule_packages_by_id", {}).get("dispatcher.smoke", {}).get("state", "")) != "disabled":
			exit_code = 1
			failure_message = "DisablePackage did not update installed package state."

	if exit_code == 0:
		var package_enable_result: Dictionary = WorldOpDispatcherScript.dispatch(world, "EnablePackage", {"package_id": "dispatcher.smoke"}, {})
		if String(package_enable_result.get("status", "")) != "ok":
			exit_code = 1
			failure_message = "EnablePackage execute failed: %s" % JSON.stringify(package_enable_result)
		elif String(world.get_world_snapshot().get("installed_rule_packages_by_id", {}).get("dispatcher.smoke", {}).get("state", "")) != "enabled":
			exit_code = 1
			failure_message = "EnablePackage did not update installed package state."

	# 9. DumpSnapshot dry_run does not write file.
	if exit_code == 0:
		var dump_dry: Dictionary = WorldOpDispatcherScript.dispatch(world, "DumpSnapshot", {"path": snapshot_path}, {"dry_run": true})
		if String(dump_dry.get("status", "")) != "dry_run":
			exit_code = 1
			failure_message = "DumpSnapshot dry_run wrong status."
		var absolute_path := ProjectSettings.globalize_path(snapshot_path)
		if FileAccess.file_exists(absolute_path):
			exit_code = 1
			failure_message = "DumpSnapshot dry_run wrote a file: %s" % absolute_path

	# 10. DumpSnapshot execute writes file; LoadSnapshot reads it back.
	if exit_code == 0:
		var dump_real: Dictionary = WorldOpDispatcherScript.dispatch(world, "DumpSnapshot", {"path": snapshot_path}, {})
		if String(dump_real.get("status", "")) != "ok":
			exit_code = 1
			failure_message = "DumpSnapshot execute failed: %s" % JSON.stringify(dump_real)

	if exit_code == 0:
		var fresh_world := WorldStateScript.new()
		nodes_to_release.append(fresh_world)
		var load_result: Dictionary = WorldOpDispatcherScript.dispatch(fresh_world, "LoadSnapshot", {"path": snapshot_path}, {})
		if String(load_result.get("status", "")) != "ok":
			exit_code = 1
			failure_message = "LoadSnapshot failed: %s" % JSON.stringify(load_result)

	# 11. ListPackages returns the package set.
	if exit_code == 0:
		var packages_result: Dictionary = WorldOpDispatcherScript.dispatch(world, "ListPackages", {}, {})
		var packages: Array = packages_result.get("payload", {}).get("packages", [])
		if String(packages_result.get("status", "")) != "ok" or packages.is_empty():
			exit_code = 1
			failure_message = "ListPackages returned no packages: %s" % JSON.stringify(packages_result)

	# 12. ListPackages dry_run should preserve read-only semantics and status.
	if exit_code == 0:
		var packages_dry_run: Dictionary = WorldOpDispatcherScript.dispatch(world, "ListPackages", {}, {"dry_run": true})
		var packages: Array = packages_dry_run.get("payload", {}).get("packages", [])
		if String(packages_dry_run.get("status", "")) != "dry_run" or packages.is_empty():
			exit_code = 1
			failure_message = "ListPackages dry_run did not return dry_run with packages: %s" % JSON.stringify(packages_dry_run)

	# 13. InstallPackage dry_run / execute should route through the dispatcher.
	if exit_code == 0:
		var install_dry_run: Dictionary = WorldOpDispatcherScript.dispatch(world, "InstallPackage", {"package_id": "builtin.time"}, {"dry_run": true})
		if String(install_dry_run.get("status", "")) != "dry_run":
			exit_code = 1
			failure_message = "InstallPackage dry_run did not return dry_run: %s" % JSON.stringify(install_dry_run)

	if exit_code == 0:
		var install_execute: Dictionary = WorldOpDispatcherScript.dispatch(world, "InstallPackage", {"package_id": "builtin.time"}, {})
		if String(install_execute.get("status", "")) != "ok":
			exit_code = 1
			failure_message = "InstallPackage execute failed: %s" % JSON.stringify(install_execute)
		else:
			var install_payload: Dictionary = install_execute.get("payload", {})
			if String(install_payload.get("package_id", "")) != "builtin.time":
				exit_code = 1
				failure_message = "InstallPackage payload did not preserve package_id: %s" % JSON.stringify(install_execute)

	if exit_code == 0:
		var duplicate_install: Dictionary = WorldOpDispatcherScript.dispatch(world, "InstallPackage", {"package_id": "builtin.time"}, {})
		if String(duplicate_install.get("status", "")) != "validation_error" or int(duplicate_install.get("exit_code", 0)) != 2:
			exit_code = 1
			failure_message = "InstallPackage duplicate install did not validation_error/2: %s" % JSON.stringify(duplicate_install)

	# 14. EnableRule/DisableRule must reject unexpected terminal statuses.
	if exit_code == 0:
		var fake_enable_world := FakeRuleToggleWorld.new(false, "disabled", "disabled")
		var enable_result: Dictionary = WorldOpEnableRuleScript.execute(fake_enable_world, {"rule_id": "fake_rule"})
		if String(enable_result.get("status", "")) != "execution_error":
			exit_code = 1
			failure_message = "EnableRule accepted unexpected disabled status: %s" % JSON.stringify(enable_result)

	if exit_code == 0:
		var fake_disable_world := FakeRuleToggleWorld.new(true, "enabled", "enabled")
		var disable_result: Dictionary = WorldOpDisableRuleScript.execute(fake_disable_world, {"rule_id": "fake_rule"})
		if String(disable_result.get("status", "")) != "execution_error":
			exit_code = 1
			failure_message = "DisableRule accepted unexpected enabled status: %s" % JSON.stringify(disable_result)

	# 15. EnablePackage/DisablePackage must reject unexpected terminal statuses.
	if exit_code == 0:
		var fake_enable_package_world := FakePackageToggleWorld.new("disabled", "disabled", "disabled")
		var enable_package_result: Dictionary = WorldOpEnablePackageScript.execute(fake_enable_package_world, {"package_id": "fake.package"})
		if String(enable_package_result.get("status", "")) != "execution_error":
			exit_code = 1
			failure_message = "EnablePackage accepted unexpected disabled status: %s" % JSON.stringify(enable_package_result)

	if exit_code == 0:
		var fake_disable_package_world := FakePackageToggleWorld.new("enabled", "enabled", "enabled")
		var disable_package_result: Dictionary = WorldOpDisablePackageScript.execute(fake_disable_package_world, {"package_id": "fake.package"})
		if String(disable_package_result.get("status", "")) != "execution_error":
			exit_code = 1
			failure_message = "DisablePackage accepted unexpected enabled status: %s" % JSON.stringify(disable_package_result)

	# 15. Mixed package states must not claim automatic rollback safety.
	if exit_code == 0:
		var mixed_enable_world := FakePackageToggleWorld.new("mixed", "enabled", "disabled")
		var mixed_enable_dry_run: Dictionary = WorldOpEnablePackageScript.dry_run(mixed_enable_world, {"package_id": "fake.package"})
		if bool(mixed_enable_dry_run.get("rollback", {}).get("supported", true)):
			exit_code = 1
			failure_message = "EnablePackage incorrectly advertised automatic rollback for mixed state."

	if exit_code == 0:
		var mixed_disable_world := FakePackageToggleWorld.new("mixed", "enabled", "disabled")
		var mixed_disable_dry_run: Dictionary = WorldOpDisablePackageScript.dry_run(mixed_disable_world, {"package_id": "fake.package"})
		if bool(mixed_disable_dry_run.get("rollback", {}).get("supported", true)):
			exit_code = 1
			failure_message = "DisablePackage incorrectly advertised automatic rollback for mixed state."

	# 16. Direct dry_run helpers should return dry_run on read-only operations.
	if exit_code == 0:
		var inspect_direct_dry: Dictionary = WorldOpInspectWorldScript.dry_run(world, {})
		var packages_direct_dry: Dictionary = WorldOpListPackagesScript.dry_run(world, {})
		var install_direct_dry: Dictionary = WorldOpInstallPackageScript.dry_run(world, {"package_id": "builtin.time"})
		if String(inspect_direct_dry.get("status", "")) != "dry_run":
			exit_code = 1
			failure_message = "InspectWorld.dry_run did not return dry_run."
		elif String(packages_direct_dry.get("status", "")) != "dry_run":
			exit_code = 1
			failure_message = "ListPackages.dry_run did not return dry_run."
		elif String(install_direct_dry.get("status", "")) != "dry_run":
			exit_code = 1
			failure_message = "InstallPackage.dry_run did not return dry_run."

	# 17. audit_id override is honored (so callers can correlate operations).
	if exit_code == 0:
		var inspect_with_id: Dictionary = WorldOpDispatcherScript.dispatch(world, "InspectWorld", {}, {"audit_id": "test-id-123"})
		if String(inspect_with_id.get("audit", {}).get("operation_id", "")) != "test-id-123":
			exit_code = 1
			failure_message = "audit_id override not honored: %s" % JSON.stringify(inspect_with_id.get("audit", {}))

	for n in nodes_to_release:
		if is_instance_valid(n):
			n.free()
	_remove_file(snapshot_path)

	if exit_code != 0:
		push_error(failure_message)
	quit(exit_code)


func _has_all_keys(d: Dictionary, keys: Array) -> bool:
	for key in keys:
		if not d.has(key):
			return false
	return true


func _remove_file(path: String) -> void:
	var absolute_path := ProjectSettings.globalize_path(path)
	if FileAccess.file_exists(absolute_path):
		DirAccess.remove_absolute(absolute_path)
