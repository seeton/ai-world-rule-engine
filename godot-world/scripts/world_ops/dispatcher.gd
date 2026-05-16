extends RefCounted
class_name WorldOpDispatcher

# Single dispatch point for all World Operations.
#
# Surfaces (CLI parser, GUI, GM apply, Codex, automation) call dispatch()
# with a typed { operation_type, request } pair plus options. The dispatcher
# routes to the operation script, runs validate -> (dry_run | execute), and
# augments the result with audit metadata so every surface logs the same
# shape.
#
# This is the seam that #106 introduces. CLI string syntax, GUI button state,
# and GM proposal text all reduce to a request before reaching this layer.

const WorldOpResultScript = preload("res://scripts/world_ops/result.gd")

# Operation registry. Adding a new operation means dropping a script in
# scripts/world_ops/ops/ and adding it here. The scripts must expose static
# operation_type() / validate() / dry_run() / execute() methods.
const OPERATION_SCRIPTS: Array = [
	preload("res://scripts/world_ops/ops/inspect_world.gd"),
	preload("res://scripts/world_ops/ops/enable_rule.gd"),
	preload("res://scripts/world_ops/ops/disable_rule.gd"),
	preload("res://scripts/world_ops/ops/enable_package.gd"),
	preload("res://scripts/world_ops/ops/disable_package.gd"),
	preload("res://scripts/world_ops/ops/list_packages.gd"),
	preload("res://scripts/world_ops/ops/dump_snapshot.gd"),
	preload("res://scripts/world_ops/ops/load_snapshot.gd"),
]


static func known_operation_types() -> PackedStringArray:
	var types := PackedStringArray()
	for script in OPERATION_SCRIPTS:
		types.append(String(script.operation_type()))
	return types


static func dispatch(world: Object, operation_type: String, request: Dictionary, options: Dictionary = {}) -> Dictionary:
	var op_script = _find_operation_script(operation_type)
	if op_script == null:
		var errors := PackedStringArray()
		errors.append("Unknown operation_type: '%s'" % operation_type)
		var result: Dictionary = WorldOpResultScript.validation_error(operation_type, errors)
		result["audit"] = _build_audit(operation_type, options)
		return result

	var validation: Dictionary = op_script.validate(world, request)
	var validation_errors: PackedStringArray = validation.get("errors", PackedStringArray())
	if validation_errors.size() > 0:
		var result: Dictionary = WorldOpResultScript.validation_error(operation_type, validation_errors, validation.get("warnings", PackedStringArray()))
		result["audit"] = _build_audit(operation_type, options)
		return result

	var dry_run: bool = bool(options.get("dry_run", false))
	var inner_result: Dictionary
	if dry_run:
		inner_result = op_script.dry_run(world, request)
	else:
		inner_result = op_script.execute(world, request)

	if not (inner_result is Dictionary):
		var errors := PackedStringArray()
		errors.append("Operation '%s' returned a non-Dictionary result." % operation_type)
		var fallback_payload := {"message": errors[0]}
		var fallback: Dictionary = WorldOpResultScript.execution_error(operation_type, errors, fallback_payload)
		fallback["audit"] = _build_audit(operation_type, options)
		return fallback

	inner_result["audit"] = _build_audit(operation_type, options)
	# Carry through warnings from validate() into the operation's validation block.
	var validation_warnings: PackedStringArray = validation.get("warnings", PackedStringArray())
	if validation_warnings.size() > 0:
		var existing_validation: Dictionary = inner_result.get("validation", {})
		var existing_warnings: PackedStringArray = existing_validation.get("warnings", PackedStringArray())
		var merged: PackedStringArray = PackedStringArray()
		for w in existing_warnings:
			merged.append(String(w))
		for w in validation_warnings:
			merged.append(String(w))
		existing_validation["warnings"] = merged
		inner_result["validation"] = existing_validation
	return inner_result


static func _find_operation_script(operation_type: String) -> Object:
	for script in OPERATION_SCRIPTS:
		if String(script.operation_type()) == operation_type:
			return script
	return null


static func _build_audit(operation_type: String, options: Dictionary) -> Dictionary:
	var override_id := String(options.get("audit_id", ""))
	var override_timestamp := String(options.get("audit_timestamp", ""))
	var operation_id := override_id if not override_id.is_empty() else _generate_operation_id(operation_type)
	var timestamp := override_timestamp if not override_timestamp.is_empty() else Time.get_datetime_string_from_system(true)
	return {
		"operation_id": operation_id,
		"timestamp": timestamp
	}


static func _generate_operation_id(operation_type: String) -> String:
	var ticks := Time.get_ticks_usec()
	var random_suffix := randi() & 0xFFFFFF
	return "%s-%d-%06x" % [operation_type, ticks, random_suffix]
