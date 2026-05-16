extends RefCounted
class_name CliActions

# Engine-safe actuation primitives. Operations wrap these with a uniform
# WorldOpResult so every surface (CLI, GUI, GM) gets the same shape. This
# layer only knows about WorldState and never about CLI string syntax or
# UI buttons.

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


static func set_package_enabled(world: Object, package_id: String, enabled: bool) -> Dictionary:
	if world == null or not world.has_method("set_package_enabled"):
		return _world_unavailable_result()
	var result_variant: Variant = world.call("set_package_enabled", package_id, enabled)
	if result_variant is Dictionary:
		return result_variant
	return {
		"status": "error",
		"message": "WorldState.set_package_enabled returned an unexpected value."
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


static func install_package(world: Object, package_id: String) -> Dictionary:
	if world == null or not world.has_method("create_rule_from_patch"):
		return _world_unavailable_result()
	var result_variant: Variant = world.call("create_rule_from_patch", {"package_id": package_id})
	if result_variant is Dictionary:
		return result_variant
	return {
		"status": "error",
		"message": "WorldState.create_rule_from_patch returned an unexpected value."
	}


static func _world_unavailable_result() -> Dictionary:
	return {
		"status": "error",
		"message": "WorldState is not available."
	}
