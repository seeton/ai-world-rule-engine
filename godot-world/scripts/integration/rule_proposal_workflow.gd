extends RefCounted
class_name RuleProposalWorkflow

const RulePackageRepositoryScript = preload("res://scripts/integration/rule_package_repository.gd")

const RULE_PROPOSAL_SCHEMA_PATH := "res://rules/schema/rule_proposal.schema.json"
const WORKSPACE_RUNTIME_DIR := "user://.poc4_runtime"
const CODEX_OUTPUT_FILE_NAME := "rule_proposal_output.json"
const CODEX_PROMPT_FILE_NAME := "rule_proposal_prompt.txt"
const VALIDATION_STATUSES := ["valid", "repairable", "needs_human_review", "rejected"]
const REVIEW_STATUSES := ["needs_design_review", "repair_required", "rejected"]
const ALLOWED_OPERATION_TYPES := ["upsert_stat", "upsert_rule", "add_event_binding", "add_relation"]

var _repository = null
func describe_codex_execution() -> Dictionary:
	_ensure_dependencies()
	var executable: Dictionary = _resolve_codex_executable()
	if String(executable.get("status", "")) != "ok":
		return executable

	var codex := _build_codex_details(executable, ProjectSettings.globalize_path("res://"))
	codex["status"] = "running"
	if String(codex.get("session_id", "")).strip_edges().is_empty():
		codex["session_id"] = "starting"
	if String(codex.get("model", "")).strip_edges().is_empty():
		codex["model"] = "default"
	if String(codex.get("cli_output_excerpt", "")).strip_edges().is_empty():
		codex["cli_output_excerpt"] = "Codex proposal generation is running."
	return codex


func generate_proposal(player_request: String) -> Dictionary:
	_ensure_dependencies()
	var trimmed_request := player_request.strip_edges()
	if trimmed_request.is_empty():
		return _error_result("empty_request", "相談内容を入力してください。")

	var executable: Dictionary = _resolve_codex_executable()
	if String(executable.get("status", "")) != "ok":
		return executable

	var schema_path := ProjectSettings.globalize_path(RULE_PROPOSAL_SCHEMA_PATH)
	if not FileAccess.file_exists(schema_path):
		return _error_result("schema_missing", "PoC4 proposal schema が見つかりません。", {"schema_path": schema_path})

	var runtime_dir_status: Dictionary = _ensure_runtime_directory()
	if String(runtime_dir_status.get("status", "")) != "ok":
		return runtime_dir_status

	var available_packages: Array = _repository.list_available_rule_packages()
	var clone_candidates: Array = _repository.resolve_clone_candidates(trimmed_request, 3)
	var resolution_seed: Dictionary = _build_resolution_seed(trimmed_request, clone_candidates)
	var prompt: String = _build_codex_prompt(trimmed_request, available_packages, clone_candidates, resolution_seed)
	var workdir := ProjectSettings.globalize_path("res://")
	var output_path := _runtime_file_path(CODEX_OUTPUT_FILE_NAME)
	var prompt_path := _runtime_file_path(CODEX_PROMPT_FILE_NAME)
	_cleanup_output_file(output_path)
	_cleanup_output_file(prompt_path)
	var prompt_write_error := _write_text_file(prompt_path, prompt)
	if prompt_write_error != OK:
		return _error_result("prompt_write_failed", "Codex prompt file を書き込めませんでした。", {"path": prompt_path, "error": prompt_write_error})

	var process_output: Array = []
	var command := "cat %s | %s exec --skip-git-repo-check%s --cd %s --output-schema %s -o %s -" % [
		_shell_escape(prompt_path),
		_shell_escape(String(executable.get("path", "codex"))),
		_build_codex_safety_flags(),
		_shell_escape(workdir),
		_shell_escape(schema_path),
		_shell_escape(output_path)
	]
	var exit_code := OS.execute("/bin/bash", ["-lc", command], process_output, true)
	var cli_output := _join_output(process_output)
	var codex_details := _build_codex_details(executable, workdir, cli_output, exit_code)
	_cleanup_output_file(prompt_path)

	if exit_code != 0:
		var error_code: String = "codex_execution_failed"
		if cli_output.to_lower().find("auth") != -1:
			error_code = "codex_auth_required"
		return _error_result(error_code, "Codex proposal generation failed.", {
			"exit_code": exit_code,
			"cli_output": cli_output
		}, codex_details)

	if not FileAccess.file_exists(output_path):
		return _error_result("codex_output_missing", "Codex proposal output file was not created.", {"cli_output": cli_output}, codex_details)

	var raw_output := FileAccess.get_file_as_string(output_path)
	_cleanup_output_file(output_path)
	var parsed_output: Variant = JSON.parse_string(raw_output)
	if typeof(parsed_output) != TYPE_DICTIONARY:
		return _error_result("codex_invalid_json", "Codex did not return a JSON object proposal.", {
			"cli_output": cli_output,
			"raw_output": raw_output
		}, codex_details)

	var validation: Dictionary = _validate_proposal_contract(parsed_output)
	if String(validation.get("status", "")) != "valid":
		return _error_result("schema_invalid", "Codex proposal failed backend schema validation.", {
			"findings": validation.get("findings", []),
			"raw_output": parsed_output
		}, codex_details)

	var normalized_proposal: Dictionary = _normalize_proposal(parsed_output, trimmed_request, resolution_seed)
	var summary: Dictionary = _build_backend_summary(normalized_proposal)
	var issue_preview: Dictionary = _build_issue_preview(normalized_proposal, summary)

	return {
		"status": "proposal_ready",
		"player_request": trimmed_request,
		"proposal": normalized_proposal,
		"summary": summary,
		"issue_preview": issue_preview,
		"consent_required": true,
		"consent_granted": false,
		"message": "PoC4 backend prepared a proposal and runtime apply preview.",
		"codex": codex_details
	}

func _ensure_dependencies() -> void:
	if _repository == null:
		_repository = RulePackageRepositoryScript.new()


func _build_resolution_seed(player_request: String, clone_candidates: Array) -> Dictionary:
	var best_candidate: Dictionary = clone_candidates[0] if not clone_candidates.is_empty() and clone_candidates[0] is Dictionary else {}
	return {
		"request_text": player_request,
		"resolution": "clone_candidate" if not best_candidate.is_empty() else "draft_custom_rule_patch",
		"candidate": best_candidate.duplicate(true),
		"review_status": "needs_design_review",
		"suggested_pr_target": best_candidate.get("suggested_pr_target", null) if not best_candidate.is_empty() else null
	}


func _build_codex_prompt(player_request: String, available_packages: Array, clone_candidates: Array, resolution_seed: Dictionary) -> String:
	var prompt_sections: Array[String] = [
		"You are generating a PoC4 backend rule proposal for a Godot 4 simulation project.",
		"Return only JSON that satisfies the provided output schema.",
		"",
		"Player request:",
		player_request,
		"",
		"Known rule packages:",
		JSON.stringify(available_packages, "  "),
		"",
		"Closest package candidates:",
		JSON.stringify(clone_candidates, "  "),
		"",
		"Existing compiler recommendation:",
		JSON.stringify(resolution_seed, "  "),
		"",
		"Proposal requirements:",
		"- Keep package_schema_version = rule_package_v1 and schema_version = codex_rule_proposal_v1.",
		"- Only use declarative patch.operations with op in [upsert_stat, upsert_rule, add_event_binding, add_relation].",
		"- touched_surfaces must enumerate every stat_id, rule_id, binding_id, or relation touched by the patch.",
		"- review_status must be needs_design_review unless repair_required or rejected is clearly justified.",
		"- suggested_pr_target should follow the closest existing package when appropriate.",
		"- issue.title and issue.body_sections should summarize the proposal clearly for reviewer context.",
		"- Mention validation findings when the design needs human review or safety review.",
		"- Never include scripts, arbitrary code execution, or non-schema keys."
	]
	return "\n".join(prompt_sections)


func _validate_proposal_contract(proposal: Dictionary) -> Dictionary:
	var findings: Array = []
	_require_string_value(proposal, "schema_version", "codex_rule_proposal_v1", findings)
	_require_non_empty_string(proposal, "proposal_title", findings)
	_require_non_empty_string(proposal, "player_request_summary", findings)
	_require_non_empty_string(proposal, "package_id", findings)
	if proposal.has("package_id") and not _is_valid_package_id(String(proposal.get("package_id", ""))):
		findings.append(_finding("schema", "error", "package_id must match ^[a-z0-9._-]+$."))
	_require_string_value(proposal, "package_schema_version", "rule_package_v1", findings)

	var suggested_pr_target = proposal.get("suggested_pr_target", null)
	if suggested_pr_target != null:
		if typeof(suggested_pr_target) != TYPE_DICTIONARY:
			findings.append(_finding("schema", "error", "suggested_pr_target must be an object or null."))
		else:
			for key in ["repo", "base_ref", "package_id"]:
				if String(suggested_pr_target.get(key, "")).strip_edges().is_empty():
					findings.append(_finding("schema", "error", "suggested_pr_target.%s must be a non-empty string." % key))

	var patch = proposal.get("patch", null)
	if typeof(patch) != TYPE_DICTIONARY:
		findings.append(_finding("schema", "error", "patch must be an object."))
	else:
		if String(patch.get("format", "")) != "rule_patch_v1":
			findings.append(_finding("schema", "error", "patch.format must be rule_patch_v1."))
		var operations = patch.get("operations", [])
		if not (operations is Array) or operations.is_empty():
			findings.append(_finding("schema", "error", "patch.operations must be a non-empty array."))
		else:
			for operation in operations:
				if typeof(operation) != TYPE_DICTIONARY:
					findings.append(_finding("schema", "error", "Each patch operation must be an object."))
					continue
				var op := String(operation.get("op", ""))
				if not ALLOWED_OPERATION_TYPES.has(op):
					findings.append(_finding("schema", "error", "Unsupported patch operation: %s" % op))

	var touched_surfaces = proposal.get("touched_surfaces", null)
	if typeof(touched_surfaces) != TYPE_DICTIONARY:
		findings.append(_finding("schema", "error", "touched_surfaces must be an object."))
	else:
		for key in ["stats", "rules", "event_bindings", "relations"]:
			_require_string_array(touched_surfaces, key, findings)

	_require_string_array(proposal, "risk_notes", findings)

	var validation = proposal.get("validation", null)
	if typeof(validation) != TYPE_DICTIONARY:
		findings.append(_finding("schema", "error", "validation must be an object."))
	else:
		var validation_status := String(validation.get("status", ""))
		if not VALIDATION_STATUSES.has(validation_status):
			findings.append(_finding("schema", "error", "validation.status is invalid."))
		var validation_findings = validation.get("findings", [])
		if not (validation_findings is Array):
			findings.append(_finding("schema", "error", "validation.findings must be an array."))
		else:
			for finding in validation_findings:
				if typeof(finding) != TYPE_DICTIONARY:
					findings.append(_finding("schema", "error", "validation.findings entries must be objects."))
					continue
				if not ["schema", "semantic", "safety"].has(String(finding.get("category", ""))):
					findings.append(_finding("schema", "error", "validation.findings.category is invalid."))
				if not ["info", "warning", "error"].has(String(finding.get("severity", ""))):
					findings.append(_finding("schema", "error", "validation.findings.severity is invalid."))
				if String(finding.get("message", "")).strip_edges().is_empty():
					findings.append(_finding("schema", "error", "validation.findings.message must be non-empty."))

	var review_status := String(proposal.get("review_status", ""))
	if not REVIEW_STATUSES.has(review_status):
		findings.append(_finding("schema", "error", "review_status is invalid."))

	var issue = proposal.get("issue", null)
	if typeof(issue) != TYPE_DICTIONARY:
		findings.append(_finding("schema", "error", "issue must be an object."))
	else:
		_require_non_empty_string(issue, "title", findings)
		var body_sections = issue.get("body_sections", null)
		if typeof(body_sections) != TYPE_DICTIONARY:
			findings.append(_finding("schema", "error", "issue.body_sections must be an object."))
		else:
			for key in ["summary", "proposal", "validation", "review"]:
				_require_string(body_sections, key, findings)

	for finding in findings:
		if String(finding.get("severity", "")) == "error":
			return {
				"status": "invalid",
				"findings": findings
			}

	return {
		"status": "valid",
		"findings": findings
	}


func _normalize_proposal(proposal: Dictionary, player_request: String, resolution_seed: Dictionary) -> Dictionary:
	var normalized := proposal.duplicate(true)
	normalized["proposal_title"] = String(normalized.get("proposal_title", "")).strip_edges()
	normalized["player_request_summary"] = String(normalized.get("player_request_summary", player_request)).strip_edges()
	normalized["package_id"] = String(normalized.get("package_id", "")).strip_edges().to_lower()
	normalized["schema_version"] = "codex_rule_proposal_v1"
	normalized["package_schema_version"] = "rule_package_v1"
	normalized["review_status"] = String(normalized.get("review_status", "needs_design_review"))
	normalized["risk_notes"] = _normalize_string_array(normalized.get("risk_notes", []))

	var patch: Dictionary = normalized.get("patch", {}).duplicate(true)
	patch["format"] = "rule_patch_v1"
	patch["operations"] = _normalize_operations(patch.get("operations", []))
	normalized["patch"] = patch

	var derived_surfaces := _derive_touched_surfaces(patch.get("operations", []))
	var touched_surfaces: Dictionary = normalized.get("touched_surfaces", {}).duplicate(true)
	for key in ["stats", "rules", "event_bindings", "relations"]:
		touched_surfaces[key] = _merge_string_arrays(touched_surfaces.get(key, []), derived_surfaces.get(key, []))
	normalized["touched_surfaces"] = touched_surfaces

	if normalized.get("suggested_pr_target", null) == null:
		if resolution_seed.has("suggested_pr_target"):
			normalized["suggested_pr_target"] = resolution_seed.get("suggested_pr_target")
		else:
			var candidate: Dictionary = resolution_seed.get("candidate", {})
			if not candidate.is_empty():
				normalized["suggested_pr_target"] = candidate.get("suggested_pr_target", null)

	var validation: Dictionary = normalized.get("validation", {}).duplicate(true)
	validation["status"] = String(validation.get("status", "needs_human_review"))
	validation["findings"] = _normalize_validation_findings(validation.get("findings", []))
	normalized["validation"] = validation

	var issue: Dictionary = normalized.get("issue", {}).duplicate(true)
	issue["title"] = String(issue.get("title", "PoC4 proposal: %s" % normalized.get("proposal_title", "Rule Proposal"))).strip_edges()
	var body_sections: Dictionary = issue.get("body_sections", {}).duplicate(true)
	for key in ["summary", "proposal", "validation", "review"]:
		body_sections[key] = String(body_sections.get(key, "")).strip_edges()
	issue["body_sections"] = body_sections
	normalized["issue"] = issue
	return normalized


func _build_backend_summary(proposal: Dictionary) -> Dictionary:
	var operations: Array = proposal.get("patch", {}).get("operations", [])
	var operation_types: Array = []
	for operation in operations:
		var op := String(operation.get("op", ""))
		if not op.is_empty() and not operation_types.has(op):
			operation_types.append(op)

	var touched_surfaces: Dictionary = proposal.get("touched_surfaces", {})
	return {
		"title": proposal.get("proposal_title", ""),
		"package_id": proposal.get("package_id", ""),
		"player_request_summary": proposal.get("player_request_summary", ""),
		"operation_count": operations.size(),
		"operation_types": operation_types,
		"has_stat_changes": not Array(touched_surfaces.get("stats", [])).is_empty(),
		"has_rule_changes": not Array(touched_surfaces.get("rules", [])).is_empty(),
		"has_event_binding_changes": not Array(touched_surfaces.get("event_bindings", [])).is_empty(),
		"has_relation_changes": not Array(touched_surfaces.get("relations", [])).is_empty(),
		"review_status": proposal.get("review_status", "needs_design_review"),
		"validation_status": proposal.get("validation", {}).get("status", "needs_human_review"),
		"suggested_pr_target": proposal.get("suggested_pr_target", null)
	}


func _build_issue_preview(proposal: Dictionary, summary: Dictionary) -> Dictionary:
	var issue: Dictionary = proposal.get("issue", {})
	var body_sections: Dictionary = issue.get("body_sections", {})
	var preview_lines: Array[String] = [
		"## Summary",
		String(body_sections.get("summary", "")),
		"",
		"- Proposal title: %s" % String(summary.get("title", "")),
		"- Package ID: %s" % String(summary.get("package_id", "")),
		"- Player request: %s" % String(summary.get("player_request_summary", "")),
		"",
		"## Proposal",
		String(body_sections.get("proposal", "")),
		"",
		"- Operations (%d): %s" % [int(summary.get("operation_count", 0)), ", ".join(_normalize_string_array(summary.get("operation_types", [])))],
		"- Stat changes: %s" % _bool_label(bool(summary.get("has_stat_changes", false))),
		"- Rule changes: %s" % _bool_label(bool(summary.get("has_rule_changes", false))),
		"- Event bindings: %s" % _bool_label(bool(summary.get("has_event_binding_changes", false))),
		"- Relations: %s" % _bool_label(bool(summary.get("has_relation_changes", false))),
		"",
		"## Validation",
		String(body_sections.get("validation", "")),
		"",
		"- Validation status: %s" % String(summary.get("validation_status", "needs_human_review")),
		"",
		"## Review",
		String(body_sections.get("review", "")),
		"",
		"- Review status: %s" % String(summary.get("review_status", "needs_design_review")),
		"- Suggested PR target: %s" % _format_pr_target(summary.get("suggested_pr_target", null))
	]
	return {
		"title": String(issue.get("title", "PoC4 proposal")),
		"body": "\n".join(preview_lines).strip_edges(),
		"sections": body_sections.duplicate(true),
		"summary": summary.duplicate(true)
	}


func _derive_touched_surfaces(operations: Array) -> Dictionary:
	var touched_surfaces := {
		"stats": [],
		"rules": [],
		"event_bindings": [],
		"relations": []
	}
	for operation_variant in operations:
		if typeof(operation_variant) != TYPE_DICTIONARY:
			continue
		var operation: Dictionary = operation_variant
		match String(operation.get("op", "")):
			"upsert_stat":
				_push_unique_string(touched_surfaces["stats"], str(operation.get("stat_id", "")))
			"upsert_rule":
				_push_unique_string(touched_surfaces["rules"], str(operation.get("rule_id", "")))
				var touched_stat: Variant = operation.get("target_stat", operation.get("watch_stat", ""))
				if touched_stat is String or touched_stat is StringName:
					_push_unique_string(touched_surfaces["stats"], str(touched_stat))
			"add_event_binding":
				_push_unique_string(touched_surfaces["event_bindings"], str(operation.get("binding_id", "")))
				_push_unique_string(touched_surfaces["rules"], str(operation.get("target_rule", "")))
			"add_relation":
				_push_unique_string(touched_surfaces["relations"], str(operation.get("relation_id", "%s:%s" % [operation.get("source", ""), operation.get("target", "")])).strip_edges())
	return touched_surfaces


func _normalize_operations(operations: Array) -> Array:
	var normalized: Array = []
	for operation_variant in operations:
		if typeof(operation_variant) != TYPE_DICTIONARY:
			continue
		var operation: Dictionary = operation_variant.duplicate(true)
		operation["op"] = String(operation.get("op", "")).strip_edges()
		normalized.append(operation)
	return normalized


func _normalize_validation_findings(findings: Array) -> Array:
	var normalized: Array = []
	for finding_variant in findings:
		if typeof(finding_variant) != TYPE_DICTIONARY:
			continue
		var finding: Dictionary = finding_variant.duplicate(true)
		finding["category"] = String(finding.get("category", "semantic")).strip_edges()
		finding["severity"] = String(finding.get("severity", "warning")).strip_edges()
		finding["message"] = String(finding.get("message", "")).strip_edges()
		normalized.append(finding)
	return normalized


func _normalize_string_array(values: Array) -> Array:
	var normalized: Array = []
	for value_variant in values:
		var value := String(value_variant).strip_edges()
		if value.is_empty() or normalized.has(value):
			continue
		normalized.append(value)
	return normalized


func _merge_string_arrays(primary: Array, secondary: Array) -> Array:
	var merged := _normalize_string_array(primary)
	for value in _normalize_string_array(secondary):
		if not merged.has(value):
			merged.append(value)
	return merged


func _require_non_empty_string(container: Dictionary, key: String, findings: Array) -> void:
	if String(container.get(key, "")).strip_edges().is_empty():
		findings.append(_finding("schema", "error", "%s must be a non-empty string." % key))


func _require_string(container: Dictionary, key: String, findings: Array) -> void:
	if not container.has(key) or typeof(container.get(key)) != TYPE_STRING:
		findings.append(_finding("schema", "error", "%s must be a string." % key))


func _require_string_value(container: Dictionary, key: String, expected: String, findings: Array) -> void:
	if String(container.get(key, "")) != expected:
		findings.append(_finding("schema", "error", "%s must equal %s." % [key, expected]))


func _require_string_array(container: Dictionary, key: String, findings: Array) -> void:
	var values = container.get(key, null)
	if not (values is Array):
		findings.append(_finding("schema", "error", "%s must be an array of strings." % key))
		return
	for value in values:
		if typeof(value) != TYPE_STRING:
			findings.append(_finding("schema", "error", "%s must contain only strings." % key))
			return


func _finding(category: String, severity: String, message: String) -> Dictionary:
	return {
		"category": category,
		"severity": severity,
		"message": message
	}


func _resolve_codex_executable() -> Dictionary:
	if OS.has_environment("POC4_CODEX_PATH"):
		var configured_path := OS.get_environment("POC4_CODEX_PATH").strip_edges()
		if not configured_path.is_empty() and FileAccess.file_exists(configured_path):
			return {"status": "ok", "path": configured_path}

	var output: Array = []
	var exit_code := OS.execute("which", ["codex"], output, true)
	if exit_code == 0:
		var resolved := _join_output(output).strip_edges()
		if not resolved.is_empty():
			return {"status": "ok", "path": resolved}

	return _error_result("codex_unavailable", "codex CLI が見つかりません。")


func _ensure_runtime_directory() -> Dictionary:
	var absolute_path := ProjectSettings.globalize_path(WORKSPACE_RUNTIME_DIR)
	if DirAccess.dir_exists_absolute(absolute_path):
		return {"status": "ok", "path": absolute_path}
	var make_result := DirAccess.make_dir_recursive_absolute(absolute_path)
	if make_result != OK:
		return _error_result("runtime_directory_error", "PoC4 runtime directory を作成できませんでした。", {"path": absolute_path, "error": make_result})
	return {"status": "ok", "path": absolute_path}


func _runtime_file_path(file_name: String) -> String:
	return ProjectSettings.globalize_path("%s/%s" % [WORKSPACE_RUNTIME_DIR, file_name])


func _allow_unsafe_codex_flags() -> bool:
	if not OS.is_debug_build():
		return false
	if OS.has_environment("POC4_ALLOW_UNSAFE_CODEX"):
		return OS.get_environment("POC4_ALLOW_UNSAFE_CODEX").strip_edges() == "1"
	return false


func _build_codex_safety_flags() -> String:
	return " --dangerously-bypass-approvals-and-sandbox" if _allow_unsafe_codex_flags() else ""


func _write_text_file(path: String, content: String) -> int:
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return FileAccess.get_open_error()
	file.store_string(content)
	return OK


func _shell_escape(value: String) -> String:
	return "'" + value.replace("'", "'\\''") + "'"


func _cleanup_output_file(output_path: String) -> void:
	if FileAccess.file_exists(output_path):
		DirAccess.remove_absolute(output_path)


func _join_output(lines: Array) -> String:
	var parts: Array[String] = []
	for line in lines:
		parts.append(String(line))
	return "\n".join(parts).strip_edges()


func _build_codex_details(executable: Dictionary, workdir: String, cli_output: String = "", exit_code: int = 0) -> Dictionary:
	var parsed := _parse_codex_cli_output(cli_output)
	var unsafe_enabled := _allow_unsafe_codex_flags()
	return {
		"status": "ok" if exit_code == 0 else "error",
		"path": executable.get("path", "codex"),
		"session_id": String(parsed.get("session_id", "")),
		"model": String(parsed.get("model", "")),
		"workdir": String(parsed.get("workdir", workdir)).strip_edges(),
		"approval": String(parsed.get("approval", "dangerously-bypass-approvals" if unsafe_enabled else "default")).strip_edges(),
		"sandbox": String(parsed.get("sandbox", "dangerously-bypass-sandbox" if unsafe_enabled else "default")).strip_edges(),
		"exit_code": exit_code,
		"cli_output_excerpt": _summarize_codex_cli_output(cli_output),
		"cli_output_line_count": _count_non_empty_output_lines(cli_output)
	}


func _parse_codex_cli_output(cli_output: String) -> Dictionary:
	var parsed := {}
	if cli_output.strip_edges().is_empty():
		return parsed

	for raw_line in cli_output.split("\n"):
		var line := String(raw_line).strip_edges()
		if line.is_empty():
			continue

		if not parsed.has("session_id"):
			var session_id := _extract_labeled_codex_value(line, ["session id", "session_id", "session"])
			if not session_id.is_empty():
				parsed["session_id"] = session_id

		if not parsed.has("model"):
			var model := _extract_labeled_codex_value(line, ["model"])
			if not model.is_empty():
				parsed["model"] = model

		if not parsed.has("workdir"):
			var extracted_workdir := _extract_labeled_codex_value(line, ["workdir", "working directory", "cwd"])
			if not extracted_workdir.is_empty():
				parsed["workdir"] = extracted_workdir

		if not parsed.has("approval"):
			var approval := _extract_labeled_codex_value(line, ["approval", "approval policy"])
			if not approval.is_empty():
				parsed["approval"] = approval

		if not parsed.has("sandbox"):
			var sandbox := _extract_labeled_codex_value(line, ["sandbox", "sandbox policy"])
			if not sandbox.is_empty():
				parsed["sandbox"] = sandbox

	return parsed


func _extract_labeled_codex_value(line: String, labels: Array) -> String:
	var candidate := line.strip_edges()
	for prefix in ["- ", "* ", "• "]:
		if candidate.begins_with(prefix):
			candidate = candidate.substr(prefix.length()).strip_edges()
			break

	var normalized := candidate.to_lower()
	for raw_label in labels:
		var label := String(raw_label).to_lower()
		for separator in [":", "=", " - ", " -> "]:
			var prefix := "%s%s" % [label, separator]
			if normalized.begins_with(prefix):
				return candidate.substr(prefix.length()).strip_edges()
	return ""


func _summarize_codex_cli_output(cli_output: String) -> String:
	if cli_output.strip_edges().is_empty():
		return ""

	var excerpt_lines: Array[String] = []
	for raw_line in cli_output.split("\n"):
		var line := String(raw_line).strip_edges()
		if line.is_empty():
			continue
		excerpt_lines.append(line)
		if excerpt_lines.size() >= 4:
			break

	var excerpt := "\n".join(excerpt_lines)
	if _count_non_empty_output_lines(cli_output) > excerpt_lines.size():
		excerpt += "\n…"
	if excerpt.length() > 600:
		excerpt = excerpt.substr(0, 600).strip_edges() + "…"
	return excerpt


func _count_non_empty_output_lines(cli_output: String) -> int:
	var count := 0
	for raw_line in cli_output.split("\n"):
		if not String(raw_line).strip_edges().is_empty():
			count += 1
	return count


func _error_result(error_code: String, message: String, details: Dictionary = {}, codex: Dictionary = {}) -> Dictionary:
	var result := {
		"status": "error",
		"error_code": error_code,
		"message": message,
		"details": details.duplicate(true)
	}
	if not codex.is_empty():
		result["codex"] = codex.duplicate(true)
	return result


func _is_valid_package_id(package_id: String) -> bool:
	if package_id.is_empty():
		return false
	for character in package_id:
		var code := character.unicode_at(0)
		var is_lower := code >= 97 and code <= 122
		var is_digit := code >= 48 and code <= 57
		if is_lower or is_digit or character in [".", "_", "-"]:
			continue
		return false
	return true


func _push_unique_string(values: Array, candidate: String) -> void:
	var normalized := candidate.strip_edges()
	if normalized.is_empty() or values.has(normalized):
		return
	values.append(normalized)


func _bool_label(value: bool) -> String:
	return "yes" if value else "no"


func _format_pr_target(target) -> String:
	if typeof(target) != TYPE_DICTIONARY:
		return "(none)"
	return "%s @ %s (%s)" % [
		String(target.get("repo", "")),
		String(target.get("base_ref", "")),
		String(target.get("package_id", ""))
	]
