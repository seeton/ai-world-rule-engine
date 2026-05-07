extends RefCounted
class_name RuleCompiler

const STRONG_MATCH_THRESHOLD := 0.34
const CUSTOM_PACKAGE_PREFIX := "draft.custom."

var _repository = null

func _init(repository = null) -> void:
	_repository = repository if repository != null else load("res://scripts/integration/rule_package_repository.gd").new()

func list_available_rule_packages() -> Array:
	return _repository.list_available_rule_packages()

func resolve_player_task(task: Dictionary) -> Dictionary:
	var request_text := _task_text(task)
	var resolution_preference := String(task.get("resolution_preference", "clone_or_create"))
	var clone_candidates: Array = _repository.resolve_clone_candidates(request_text, 3)
	var best_candidate: Dictionary = clone_candidates[0] if not clone_candidates.is_empty() else {}
	var force_custom := resolution_preference == "force_custom" or resolution_preference == "fork_existing"

	if not force_custom and not best_candidate.is_empty() and float(best_candidate.get("match_score", 0.0)) >= STRONG_MATCH_THRESHOLD:
		return {
			"resolution": "clone_candidate",
			"task": task.duplicate(true),
			"candidate": best_candidate,
			"alternatives": clone_candidates.slice(1),
			"workflow": _build_clone_workflow(best_candidate)
		}

	return {
		"resolution": "draft_custom_rule_patch",
		"task": task.duplicate(true),
		"draft_package": _build_custom_draft(task, request_text, best_candidate),
		"workflow": _build_custom_workflow(task, best_candidate)
	}

func _build_clone_workflow(candidate: Dictionary) -> Dictionary:
	return {
		"like_action": {
			"package_id": candidate.get("package_id", ""),
			"sentiment": "like"
		},
		"dislike_action": {
			"package_id": candidate.get("package_id", ""),
			"sentiment": "dislike"
		},
		"alternative_action": {
			"resolution_preference": "fork_existing",
			"forked_from": {
				"package_id": candidate.get("package_id", ""),
				"source_repo": candidate.get("source_repo", ""),
				"source_ref": candidate.get("source_ref", "")
			},
			"suggested_pr_target": candidate.get("suggested_pr_target", null)
		},
		"clone_origin": {
			"source_repo": candidate.get("source_repo", ""),
			"source_ref": candidate.get("source_ref", "")
		}
	}

func _build_custom_workflow(task: Dictionary, best_candidate: Dictionary) -> Dictionary:
	var fork_target = _normalize_fork_target(task.get("forked_from", null), best_candidate, String(task.get("resolution_preference", "")) == "fork_existing")

	return {
		"review_status": "needs_design_review",
		"forked_from": fork_target,
		"suggested_pr_target": _resolve_pr_target(task, best_candidate),
		"upstream_submission_ready": false
	}

func _build_custom_draft(task: Dictionary, request_text: String, best_candidate: Dictionary) -> Dictionary:
	var slug := _slugify(String(task.get("title", request_text)))
	if slug.is_empty():
		slug = "untitled_rule"

	var stat_id := _slugify(_extract_focus_term(request_text))
	if stat_id.is_empty():
		stat_id = slug

	var forked_from = _normalize_fork_target(task.get("forked_from", null), best_candidate, String(task.get("resolution_preference", "")) == "fork_existing")

	return {
		"schema_version": "rule_package_v1",
		"package_id": "%s%s" % [CUSTOM_PACKAGE_PREFIX, slug],
		"display_name": _title_case(slug),
		"description": String(task.get("prompt", "Custom rule drafted from a player request.")),
		"version": "0.1.0-draft",
		"author": String(task.get("author", "player")),
		"source_repo": String(task.get("source_repo", "local://player-drafts")),
		"source_ref": String(task.get("source_ref", "draft")),
		"forked_from": forked_from,
		"suggested_pr_target": _resolve_pr_target(task, best_candidate),
		"tags": _draft_tags(request_text),
		"match_phrases": _draft_match_phrases(request_text),
		"community": {
			"likes": 0,
			"dislikes": 0,
			"alternative_package_ids": []
		},
		"patch": {
			"format": "rule_patch_v1",
			"review_status": "needs_design_review",
			"operations": [
				{
					"op": "upsert_stat",
					"stat_id": stat_id,
					"value_type": "float",
					"default": 50.0,
					"min": 0.0,
					"max": 100.0,
					"ui_group": "custom"
				},
				{
					"op": "upsert_rule",
					"rule_id": "%s.core_loop" % stat_id,
					"rule_type": "designer_review_required",
					"design_prompt": String(task.get("prompt", request_text)),
					"safety_notes": [
						"Replace placeholder rule_type during review.",
						"Keep generated changes declarative.",
						"Do not attach scripts or arbitrary code."
					]
				}
			]
		}
	}

func _resolve_pr_target(task: Dictionary, best_candidate: Dictionary):
	if task.has("suggested_pr_target"):
		return task.get("suggested_pr_target")
	if not best_candidate.is_empty():
		return best_candidate.get("suggested_pr_target", null)
	return {
		"repo": "github.com/godot-world/rule-library",
		"base_ref": "main",
		"package_id": ""
	}

func _normalize_fork_target(forked_from, best_candidate: Dictionary, prefer_best_candidate: bool):
	if typeof(forked_from) == TYPE_DICTIONARY:
		return forked_from
	if typeof(forked_from) == TYPE_STRING and not String(forked_from).is_empty():
		var package_id := String(forked_from)
		var package: Dictionary = _repository.get_rule_package(package_id)
		if not package.is_empty():
			return {
				"package_id": package.get("package_id", ""),
				"source_repo": package.get("source_repo", ""),
				"source_ref": package.get("source_ref", "")
			}
		return {
			"package_id": package_id,
			"source_repo": "",
			"source_ref": ""
		}
	if prefer_best_candidate and not best_candidate.is_empty():
		return {
			"package_id": best_candidate.get("package_id", ""),
			"source_repo": best_candidate.get("source_repo", ""),
			"source_ref": best_candidate.get("source_ref", "")
		}
	return null

func _task_text(task: Dictionary) -> String:
	var segments: Array[String] = []
	for key in ["title", "prompt", "summary", "mechanic"]:
		var value := String(task.get(key, ""))
		if not value.is_empty():
			segments.append(value)
	return " ".join(segments).strip_edges().to_lower()

func _extract_focus_term(request_text: String) -> String:
	var words := request_text.split(" ", false)
	for word in words:
		var candidate := _slugify(word)
		if candidate.length() >= 4:
			return candidate
	return words[0] if not words.is_empty() else "custom_stat"

func _draft_tags(request_text: String) -> Array:
	var tags: Array = ["custom", "player-authored"]
	for word in request_text.split(" ", false):
		var cleaned := _slugify(word)
		if cleaned.length() >= 4 and not tags.has(cleaned):
			tags.append(cleaned)
		if tags.size() >= 6:
			break
	return tags

func _draft_match_phrases(request_text: String) -> Array:
	if request_text.is_empty():
		return []
	return [request_text]

func _slugify(value: String) -> String:
	var lowered := value.to_lower()
	var buffer := ""
	var last_was_separator := false
	for character in lowered:
		var code := character.unicode_at(0)
		var is_alphanumeric := (code >= 97 and code <= 122) or (code >= 48 and code <= 57)
		if is_alphanumeric:
			buffer += character
			last_was_separator = false
		elif not last_was_separator and not buffer.is_empty():
			buffer += "_"
			last_was_separator = true

	while buffer.begins_with("_"):
		buffer = buffer.substr(1)
	while buffer.ends_with("_"):
		buffer = buffer.substr(0, buffer.length() - 1)
	return buffer

func _title_case(value: String) -> String:
	var words := value.replace("_", " ").split(" ", false)
	var titled_words: Array[String] = []
	for word in words:
		if word.is_empty():
			continue
		titled_words.append(word.substr(0, 1).to_upper() + word.substr(1))
	return " ".join(titled_words)
