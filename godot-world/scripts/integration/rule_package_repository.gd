extends RefCounted
class_name RulePackageRepository

const RULE_DIRECTORY := "res://rules/packages"
const RULE_EXTENSION := ".rule.json"
const RULE_SCHEMA_VERSION := "rule_package_v1"

var _packages_by_id: Dictionary = {}

func _init(rule_directory: String = RULE_DIRECTORY) -> void:
	_load_packages(rule_directory)

func list_available_rule_packages() -> Array:
	var summaries: Array = []
	for package_id in _packages_by_id.keys():
		summaries.append(_summarize_package(_packages_by_id[package_id]))
	summaries.sort_custom(Callable(self, "_sort_package_summaries"))
	return summaries

func get_rule_package(package_id: String) -> Dictionary:
	return _packages_by_id.get(package_id, {}).duplicate(true)

func resolve_clone_candidates(request_text: String, limit: int = 3) -> Array:
	var normalized_request := request_text.to_lower()
	var scored: Array = []

	for package_id in _packages_by_id.keys():
		var package: Dictionary = _packages_by_id[package_id]
		var score := _score_package_match(package, normalized_request)
		if score <= 0.0:
			continue

		var summary := _summarize_package(package)
		summary["match_score"] = score
		scored.append(summary)

	scored.sort_custom(Callable(self, "_sort_candidates"))
	if limit > 0 and scored.size() > limit:
		scored.resize(limit)
	return scored

func _load_packages(rule_directory: String) -> void:
	_packages_by_id.clear()

	var absolute_dir := ProjectSettings.globalize_path(rule_directory)
	if not DirAccess.dir_exists_absolute(absolute_dir):
		return

	var directory := DirAccess.open(rule_directory)
	if directory == null:
		return

	directory.list_dir_begin()
	while true:
		var file_name := directory.get_next()
		if file_name.is_empty():
			break
		if directory.current_is_dir() or not file_name.ends_with(RULE_EXTENSION):
			continue

		var package_path := "%s/%s" % [rule_directory, file_name]
		var package_data := _read_json(package_path)
		if _is_valid_package(package_data):
			_packages_by_id[package_data["package_id"]] = package_data
	directory.list_dir_end()

func _read_json(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}

	var raw_text := FileAccess.get_file_as_string(path)
	var parsed: Variant = JSON.parse_string(raw_text)
	if typeof(parsed) != TYPE_DICTIONARY:
		return {}
	return parsed

func _is_valid_package(package_data: Dictionary) -> bool:
	if package_data.is_empty():
		return false
	var required_keys := [
		"schema_version",
		"package_id",
		"display_name",
		"description",
		"version",
		"author",
		"source_repo",
		"source_ref",
		"package_dependencies",
		"patch"
	]
	for key in required_keys:
		if not package_data.has(key):
			return false
	if package_data.get("schema_version", "") != RULE_SCHEMA_VERSION:
		return false
	if typeof(package_data.get("patch", {})) != TYPE_DICTIONARY:
		return false
	if typeof(package_data.get("package_dependencies", [])) != TYPE_ARRAY:
		return false
	if package_data.has("runtime_contract") and typeof(package_data.get("runtime_contract")) != TYPE_DICTIONARY:
		return false
	return true

func _summarize_package(package_data: Dictionary) -> Dictionary:
	return {
		"package_id": package_data.get("package_id", ""),
		"package_tier": package_data.get("package_tier", ""),
		"display_name": package_data.get("display_name", ""),
		"description": package_data.get("description", ""),
		"version": package_data.get("version", ""),
		"author": package_data.get("author", ""),
		"source_repo": package_data.get("source_repo", ""),
		"source_ref": package_data.get("source_ref", ""),
		"package_dependencies": package_data.get("package_dependencies", []).duplicate(true),
		"forked_from": package_data.get("forked_from", null),
		"suggested_pr_target": package_data.get("suggested_pr_target", null),
		"tags": package_data.get("tags", []),
		"match_phrases": package_data.get("match_phrases", []),
		"community": package_data.get("community", {}),
		"runtime_contract": package_data.get("runtime_contract", {}).duplicate(true) if package_data.get("runtime_contract", {}) is Dictionary else {}
	}

func _score_package_match(package_data: Dictionary, normalized_request: String) -> float:
	var score := 0.0

	for tag in package_data.get("tags", []):
		var normalized_tag := String(tag).to_lower()
		if normalized_request.find(normalized_tag) != -1:
			score += 1.0

	for phrase in package_data.get("match_phrases", []):
		var normalized_phrase := String(phrase).to_lower()
		if normalized_request.find(normalized_phrase) != -1:
			score += 1.5

	var description_words := String(package_data.get("description", "")).to_lower().split(" ", false)
	for word in description_words:
		if word.length() < 4:
			continue
		if normalized_request.find(word) != -1:
			score += 0.2

	var normalized_max_score := float(max(1, package_data.get("tags", []).size() + package_data.get("match_phrases", []).size()))
	return score / normalized_max_score

func _sort_package_summaries(a: Dictionary, b: Dictionary) -> bool:
	return String(a.get("package_id", "")) < String(b.get("package_id", ""))

func _sort_candidates(a: Dictionary, b: Dictionary) -> bool:
	var a_score := float(a.get("match_score", 0.0))
	var b_score := float(b.get("match_score", 0.0))
	if is_equal_approx(a_score, b_score):
		return String(a.get("package_id", "")) < String(b.get("package_id", ""))
	return a_score > b_score
