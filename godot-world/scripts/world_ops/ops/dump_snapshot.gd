extends RefCounted
class_name WorldOpDumpSnapshot

# DumpSnapshot — write a deterministic world snapshot to disk.
# dry_run validates the path without writing.

const WorldOpResultScript = preload("res://scripts/world_ops/result.gd")
const CliActionsScript = preload("res://scripts/cli/cli_actions.gd")

const TYPE := "DumpSnapshot"


static func operation_type() -> String:
	return TYPE


static func validate(_world: Object, request: Dictionary) -> Dictionary:
	var errors := PackedStringArray()
	var path := String(request.get("path", "")).strip_edges()
	if path.is_empty():
		errors.append("DumpSnapshot.path must be a non-empty string.")
	return {"errors": errors, "warnings": PackedStringArray()}


static func dry_run(_world: Object, request: Dictionary) -> Dictionary:
	var path := String(request.get("path", "")).strip_edges()
	var lines := PackedStringArray()
	lines.append("[dry-run] would write snapshot to %s." % path)
	return WorldOpResultScript.dry_run(TYPE, lines, {"would_write_to": path}, {"snapshot_path": path}, {"supported": true, "hint": "Use LoadSnapshot path=%s to restore." % path})


static func execute(world: Object, request: Dictionary) -> Dictionary:
	var path := String(request.get("path", "")).strip_edges()
	var action_result: Dictionary = CliActionsScript.save_snapshot(world, path)
	if String(action_result.get("status", "")) == "saved":
		var lines := PackedStringArray()
		lines.append("snapshot saved: %s" % path)
		var payload := {"path": String(action_result.get("path", path))}
		var diff := {"snapshot_path": path}
		return WorldOpResultScript.ok(TYPE, lines, payload, diff, {"supported": true, "hint": "Inverse op: LoadSnapshot path=%s" % path})
	var error_lines := PackedStringArray()
	error_lines.append("DumpSnapshot failed: %s" % String(action_result.get("message", "")))
	return WorldOpResultScript.execution_error(TYPE, error_lines, action_result)
