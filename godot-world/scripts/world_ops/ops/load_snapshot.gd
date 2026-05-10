extends RefCounted
class_name WorldOpLoadSnapshot

# LoadSnapshot — replace the current world with a saved snapshot.
# Validation only checks the path is non-empty (full file validation happens
# inside WorldState.load_world_snapshot). dry_run does not touch the world;
# it just reports what would be loaded.

const WorldOpResultScript = preload("res://scripts/world_ops/result.gd")
const CliActionsScript = preload("res://scripts/cli/cli_actions.gd")

const TYPE := "LoadSnapshot"


static func operation_type() -> String:
	return TYPE


static func validate(_world: Object, request: Dictionary) -> Dictionary:
	var errors := PackedStringArray()
	var path := String(request.get("path", "")).strip_edges()
	if path.is_empty():
		errors.append("LoadSnapshot.path must be a non-empty string.")
	return {"errors": errors, "warnings": PackedStringArray()}


static func dry_run(_world: Object, request: Dictionary) -> Dictionary:
	var path := String(request.get("path", "")).strip_edges()
	var lines := PackedStringArray()
	lines.append("[dry-run] would load snapshot from %s and replace current world." % path)
	return WorldOpResultScript.dry_run(TYPE, lines, {"would_load_from": path}, {"snapshot_path": path}, {"supported": false, "hint": "Take a DumpSnapshot of the current world before LoadSnapshot to enable rollback."})


static func execute(world: Object, request: Dictionary) -> Dictionary:
	var path := String(request.get("path", "")).strip_edges()
	var action_result: Dictionary = CliActionsScript.load_snapshot(world, path)
	if String(action_result.get("status", "")) == "loaded":
		var lines := PackedStringArray()
		lines.append("snapshot loaded: %s" % path)
		var payload := {"path": String(action_result.get("path", path))}
		var diff := {"world_replaced_from": path}
		return WorldOpResultScript.ok(TYPE, lines, payload, diff, {"supported": false, "hint": "Take a DumpSnapshot of the current world *before* LoadSnapshot to enable rollback."})
	var error_lines := PackedStringArray()
	error_lines.append("LoadSnapshot failed: %s" % String(action_result.get("message", "")))
	return WorldOpResultScript.execution_error(TYPE, error_lines, action_result)
