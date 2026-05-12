extends RefCounted
class_name WorldOpListPackages

# ListPackages — read-only enumeration of available rule packages.

const WorldOpResultScript = preload("res://scripts/world_ops/result.gd")

const TYPE := "ListPackages"


static func operation_type() -> String:
	return TYPE


static func validate(_world: Object, _request: Dictionary) -> Dictionary:
	return {"errors": PackedStringArray(), "warnings": PackedStringArray()}


static func dry_run(world: Object, request: Dictionary) -> Dictionary:
	var packages: Array = []
	if world != null and world.has_method("get_available_rule_packages"):
		var packages_variant: Variant = world.call("get_available_rule_packages")
		if packages_variant is Array:
			packages = packages_variant

	var lines := PackedStringArray()
	lines.append("available packages: %d" % packages.size())
	for package in packages:
		if not (package is Dictionary):
			continue
		var package_id := String(package.get("package_id", ""))
		var display := String(package.get("display_name", package_id))
		lines.append("  - %s — %s" % [package_id, display])

	return WorldOpResultScript.dry_run(TYPE, lines, {"packages": packages, "package_count": packages.size()}, {}, {"supported": true, "hint": "Read-only operation, no rollback needed."})


static func execute(world: Object, _request: Dictionary) -> Dictionary:
	var packages: Array = []
	if world != null and world.has_method("get_available_rule_packages"):
		var packages_variant: Variant = world.call("get_available_rule_packages")
		if packages_variant is Array:
			packages = packages_variant

	var lines := PackedStringArray()
	lines.append("available packages: %d" % packages.size())
	for package in packages:
		if not (package is Dictionary):
			continue
		var package_id := String(package.get("package_id", ""))
		var display := String(package.get("display_name", package_id))
		lines.append("  - %s — %s" % [package_id, display])

	return WorldOpResultScript.ok(TYPE, lines, {"packages": packages, "package_count": packages.size()}, {}, {"supported": true, "hint": "Read-only operation, no rollback needed."})
