extends RefCounted
class_name CliActions

# Shared actuation surface used by both the headless CLI dispatcher
# (scripts/cli/main.gd) and the in-game C-key overlay
# (scripts/game/cli_inspect_overlay.gd). Keeps both call sites going through
# the same engine-safe WorldState API so they cannot drift.
#
# All entry points return Dictionary { "status": ..., "message": ..., ... }
# so call sites can render or print them uniformly.

const SNAPSHOT_DIR := "user://"
const SNAPSHOT_PREFIX := "cli_inspect_"
const SNAPSHOT_EXTENSION := ".json"


static func set_rule_enabled(world: Object, rule_id: String, enabled: bool) -> Dictionary:
	if world == null or not world.has_method("set_rule_enabled"):
		return _world_unavailable_result()
	var result_variant: Variant = world.call("set_rule_enabled", rule_id, enabled)
	if result_variant is Dictionary:
		return result_variant
	return {
		"status": "error",
		"message": "WorldState.set_rule_enabled returned an unexpected value."
	}


static func save_snapshot(world: Object, file_path: String) -> Dictionary:
	if world == null or not world.has_method("save_world_snapshot"):
		return _world_unavailable_result()
	var result_variant: Variant = world.call("save_world_snapshot", file_path)
	if result_variant is Dictionary:
		return result_variant
	return {
		"status": "error",
		"message": "WorldState.save_world_snapshot returned an unexpected value."
	}


static func load_snapshot(world: Object, file_path: String) -> Dictionary:
	if world == null or not world.has_method("load_world_snapshot"):
		return _world_unavailable_result()
	var result_variant: Variant = world.call("load_world_snapshot", file_path)
	if result_variant is Dictionary:
		return result_variant
	return {
		"status": "error",
		"message": "WorldState.load_world_snapshot returned an unexpected value."
	}


# List user://cli_inspect_*.json snapshots written by the overlay's save
# button (or any caller using the same prefix), sorted newest first.
static func list_user_snapshots() -> Array:
	var entries: Array = []
	var dir := DirAccess.open(SNAPSHOT_DIR)
	if dir == null:
		return entries
	dir.list_dir_begin()
	while true:
		var file_name := dir.get_next()
		if file_name.is_empty():
			break
		if dir.current_is_dir():
			continue
		if not file_name.begins_with(SNAPSHOT_PREFIX) or not file_name.ends_with(SNAPSHOT_EXTENSION):
			continue
		entries.append({
			"path": "%s%s" % [SNAPSHOT_DIR, file_name],
			"file_name": file_name,
			"absolute_path": ProjectSettings.globalize_path("%s%s" % [SNAPSHOT_DIR, file_name])
		})
	dir.list_dir_end()
	entries.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return String(a.get("file_name", "")) > String(b.get("file_name", ""))
	)
	return entries


# Build a default destination path for the overlay's save button. Uses an
# OS timestamp so multiple saves do not collide.
static func default_snapshot_path() -> String:
	var timestamp := Time.get_datetime_string_from_system(true).replace(":", "").replace("-", "").replace("T", "_")
	return "%s%s%s%s" % [SNAPSHOT_DIR, SNAPSHOT_PREFIX, timestamp, SNAPSHOT_EXTENSION]


static func _world_unavailable_result() -> Dictionary:
	return {
		"status": "error",
		"message": "WorldState is not available."
	}
