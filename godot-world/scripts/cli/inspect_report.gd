extends RefCounted
class_name InspectReport

# Engine-safe primitive: builds the "inspect" report Dictionary that
# operations and surfaces use when they need the world's observable state.
# This is below the Operation layer (#106) and above WorldState. Operations
# wrap this with a uniform result; surfaces never call it directly.

static func build(world: Object, snapshot_loaded_from: String = "") -> Dictionary:
	if world == null:
		return _empty_report(snapshot_loaded_from)

	var snapshot: Dictionary = {}
	if world.has_method("get_world_snapshot"):
		var snapshot_variant: Variant = world.call("get_world_snapshot")
		if snapshot_variant is Dictionary:
			snapshot = snapshot_variant

	var packages: Array = []
	if world.has_method("get_installed_rule_packages"):
		var packages_variant: Variant = world.call("get_installed_rule_packages")
		if packages_variant is Array:
			packages = packages_variant
	elif world.has_method("get_available_rule_packages"):
		var packages_variant: Variant = world.call("get_available_rule_packages")
		if packages_variant is Array:
			packages = packages_variant

	return build_from_snapshot(snapshot, packages, snapshot_loaded_from)


static func build_from_snapshot(snapshot: Dictionary, packages: Array, snapshot_loaded_from: String = "") -> Dictionary:
	var installed_rules_variant: Variant = snapshot.get("installed_rules", [])
	var installed_rules: Array = installed_rules_variant if installed_rules_variant is Array else []

	var rule_summaries: Array = []
	var disabled_rule_ids: Array = []
	var rules_with_unmet_requirements: Array = []
	for rule in installed_rules:
		if not (rule is Dictionary):
			continue
		var rule_data: Dictionary = rule
		var rule_id := String(rule_data.get("id", ""))
		var enabled := bool(rule_data.get("enabled", true))
		var missing_kinds_variant: Variant = rule_data.get("missing_required_rule_kinds", [])
		var missing_kinds: Array = missing_kinds_variant if missing_kinds_variant is Array else []
		var metadata_variant: Variant = rule_data.get("metadata", {})
		var metadata: Dictionary = metadata_variant if metadata_variant is Dictionary else {}
		rule_summaries.append({
			"rule_id": rule_id,
			"name": String(rule_data.get("name", rule_id)),
			"enabled": enabled,
			"package_id": String(metadata.get("package_id", "")),
			"requires_rule_kinds": _coerce_array(rule_data.get("requires_rule_kinds", [])),
			"provides_rule_kinds": _coerce_array(rule_data.get("provides_rule_kinds", [])),
			"resolved_parent_rule_ids": _coerce_array(rule_data.get("resolved_parent_rule_ids", [])),
			"missing_required_rule_kinds": missing_kinds.duplicate(true)
		})
		if not enabled:
			disabled_rule_ids.append(rule_id)
		if not missing_kinds.is_empty():
			rules_with_unmet_requirements.append(rule_id)

	var has_movement: bool = _has_any_kind_provider(installed_rules, ["world.movement", "movement", "world.space", "space"])
	var has_input: bool = _has_any_kind_provider(installed_rules, ["input"])
	var world_clock_value: Variant = snapshot.get("world_clock", {})
	var has_world_clock: bool = (world_clock_value is Dictionary) and not (world_clock_value as Dictionary).is_empty()

	var collapse_signals: Array = []
	if installed_rules.is_empty():
		collapse_signals.append("no_installed_rules")
	if not rules_with_unmet_requirements.is_empty():
		collapse_signals.append("rules_with_unmet_requirements")
	if not disabled_rule_ids.is_empty():
		collapse_signals.append("disabled_rules_present")

	return {
		"world": {
			"world_id": snapshot.get("world_id", ""),
			"world_name": snapshot.get("world_name", ""),
			"world_mode": snapshot.get("world_mode", ""),
			"tick": int(snapshot.get("tick", 0)),
			"elapsed_seconds": float(snapshot.get("elapsed_seconds", 0.0))
		},
		"installed_rules": rule_summaries,
		"installed_rule_count": rule_summaries.size(),
		"disabled_rule_ids": disabled_rule_ids,
		"rules_with_unmet_requirements": rules_with_unmet_requirements,
		"installed_packages": packages.duplicate(true),
		"installed_package_count": packages.size(),
		"world_status": {
			"has_world_clock": has_world_clock,
			"has_movement_provider": has_movement,
			"has_input_provider": has_input,
			"collapse_signals": collapse_signals
		},
		"snapshot_loaded_from": snapshot_loaded_from
	}


static func _has_kind_provider(installed_rules: Array, required_kind: String) -> bool:
	for rule in installed_rules:
		if not (rule is Dictionary):
			continue
		if not bool(rule.get("enabled", true)):
			continue
		if bool(rule.get("blocked", false)) or bool(rule.get("inactive", false)):
			continue
		for kind in rule.get("provides_rule_kinds", []):
			if String(kind) == required_kind:
				return true
	return false


static func _has_any_kind_provider(installed_rules: Array, required_kinds: Array) -> bool:
	for required_kind_variant in required_kinds:
		if _has_kind_provider(installed_rules, String(required_kind_variant)):
			return true
	return false


static func _coerce_array(value: Variant) -> Array:
	if value is Array:
		return (value as Array).duplicate(true)
	return []


static func _empty_report(snapshot_loaded_from: String) -> Dictionary:
	return {
		"world": {
			"world_id": "",
			"world_name": "",
			"world_mode": "",
			"tick": 0,
			"elapsed_seconds": 0.0
		},
		"installed_rules": [],
		"installed_rule_count": 0,
		"disabled_rule_ids": [],
		"rules_with_unmet_requirements": [],
		"installed_packages": [],
		"installed_package_count": 0,
		"world_status": {
			"has_world_clock": false,
			"has_movement_provider": false,
			"has_input_provider": false,
			"collapse_signals": ["world_state_unavailable"]
		},
		"snapshot_loaded_from": snapshot_loaded_from
	}
