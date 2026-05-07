extends Node

const SimulationRuntimeScript = preload("res://scripts/core/SimulationRuntime.gd")
const RuleTemplatesScript = preload("res://scripts/core/RuleTemplates.gd")

var _runtime = null
var _available_templates: Array = []


func _ready() -> void:
	_reset_world()


func submit_player_task(task_text: String) -> Dictionary:
	_ensure_runtime()
	var normalized_task := task_text.strip_edges().to_lower()
	var proposals: Array = []

	for template in _available_templates:
		for keyword in template.get("keywords", []):
			if normalized_task.findn(String(keyword).to_lower()) != -1:
				proposals.append({
					"template_id": template.get("id", ""),
					"title": template.get("name", ""),
					"description": template.get("description", ""),
					"rule_patch": template.get("rule_patch", {}).duplicate(true)
				})
				break

	var result := {
		"status": "proposal_ready" if not proposals.is_empty() else "needs_rule_patch",
		"task_text": task_text,
		"proposals": proposals,
		"message": "Matched existing rule templates." if not proposals.is_empty() else "No matching template. Use create_rule_from_patch() with a dictionary patch."
	}
	_runtime.record_player_task(result)
	return result


func clone_rule(rule_id: String) -> Dictionary:
	_ensure_runtime()
	return _runtime.clone_rule(rule_id)


func create_rule_from_patch(rule_patch: Dictionary) -> Dictionary:
	_ensure_runtime()
	return _runtime.create_rule_from_patch(rule_patch)


func get_world_snapshot() -> Dictionary:
	_ensure_runtime()
	return _runtime.get_snapshot()


func get_available_rule_templates() -> Array:
	_ensure_runtime()
	var templates: Array = []
	for template in _available_templates:
		templates.append(template.duplicate(true))
	return templates


func advance_tick(delta_seconds: float) -> void:
	_ensure_runtime()
	_runtime.advance_tick(delta_seconds)


func set_entity_position(entity_id: String, position_patch: Dictionary) -> Dictionary:
	_ensure_runtime()
	return _runtime.set_entity_position(entity_id, position_patch)


func _reset_world() -> void:
	_available_templates = RuleTemplatesScript.get_templates()
	_runtime = SimulationRuntimeScript.new(_available_templates)


func _ensure_runtime() -> void:
	if _runtime == null:
		_reset_world()
