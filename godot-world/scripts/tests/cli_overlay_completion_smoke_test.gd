extends SceneTree

const WorldStateScript = preload("res://scripts/core/WorldState.gd")
const CliInspectOverlayScript = preload("res://scripts/game/cli_inspect_overlay.gd")


func _initialize() -> void:
	var exit_code := 0
	var failure_message := ""
	var nodes_to_release: Array = []
	var installed_package_rule_id := ""

	await process_frame
	await process_frame

	var world = root.get_node_or_null("/root/WorldState")
	if world == null:
		exit_code = 1
		failure_message = "Autoload WorldState was not available."

	var overlay = null
	if exit_code == 0:
		overlay = CliInspectOverlayScript.new()
		root.add_child(overlay)
		nodes_to_release.append(overlay)
		await process_frame
		await process_frame

	if exit_code == 0:
		overlay._set_input_text("inspect")
		overlay._request_input_focus()
		await process_frame
		await process_frame
		var enter_press := InputEventKey.new()
		enter_press.pressed = true
		enter_press.keycode = KEY_ENTER
		Input.parse_input_event(enter_press)
		var enter_release := InputEventKey.new()
		enter_release.pressed = false
		enter_release.keycode = KEY_ENTER
		Input.parse_input_event(enter_release)
		await process_frame
		await process_frame
		var focus_owner: Control = overlay.get_viewport().gui_get_focus_owner()
		if not overlay._input.has_focus() and focus_owner != overlay._input:
			exit_code = 1
			failure_message = "CLI input did not regain focus after Enter submission."

	if exit_code == 0:
		var type_press := InputEventKey.new()
		type_press.pressed = true
		type_press.keycode = KEY_A
		type_press.unicode = "a".unicode_at(0)
		Input.parse_input_event(type_press)
		var type_release := InputEventKey.new()
		type_release.pressed = false
		type_release.keycode = KEY_A
		Input.parse_input_event(type_release)
		await process_frame
		await process_frame
		if overlay._input.text != "a":
			exit_code = 1
			failure_message = "CLI input did not accept immediate typing after Enter submission: '%s'" % overlay._input.text

	if exit_code == 0:
		overlay._hide_completion_candidates()
		overlay._set_input_text("p")
		overlay._handle_tab_completion()
		await process_frame
		var saw_package_prefix := false
		var saw_help := false
		for candidate in overlay._completion_candidates:
			if not (candidate is Dictionary):
				continue
			var candidate_value := String(candidate.get("value", ""))
			if candidate_value.begins_with("package "):
				saw_package_prefix = true
			if candidate_value == "help":
				saw_help = true
		if not saw_package_prefix:
			exit_code = 1
			failure_message = "Expected package-prefixed candidates for 'p': %s" % JSON.stringify(overlay._completion_candidates)
		elif saw_help:
			exit_code = 1
			failure_message = "Single-letter prefix 'p' should not suggest help: %s" % JSON.stringify(overlay._completion_candidates)

	if exit_code == 0:
		overlay._hide_completion_candidates()
		overlay._set_input_text("rule enable")
		overlay._handle_tab_completion()
		await process_frame
		if overlay._completion_panel == null or not overlay._completion_panel.visible:
			exit_code = 1
			failure_message = "Completion panel did not open for 'rule enable'."
		elif overlay._completion_candidates.is_empty():
			exit_code = 1
			failure_message = "Completion candidates were empty for 'rule enable'."
		elif String(overlay._completion_candidates[0].get("summary", "")).find("現在は無効な rule がない") == -1:
			exit_code = 1
			failure_message = "Expected no-disabled-rule fallback summary for 'rule enable': %s" % JSON.stringify(overlay._completion_candidates)

	if exit_code == 0:
		overlay._hide_completion_candidates()
		overlay._set_input_text("package install")
		overlay._handle_tab_completion()
		await process_frame
		var found_package_candidate := false
		for candidate in overlay._completion_candidates:
			if candidate is Dictionary and String(candidate.get("value", "")) == "package install builtin.time":
				found_package_candidate = true
				break
		if not found_package_candidate:
			exit_code = 1
			failure_message = "Expected package install candidate missing: %s" % JSON.stringify(overlay._completion_candidates)
		elif overlay._completion_list == null or overlay._completion_list.item_count == 0:
			exit_code = 1
			failure_message = "Package completion list did not render rows."
		else:
			var rendered_text: String = overlay._completion_list.get_item_text(0)
			if rendered_text.find(" — ") != rendered_text.rfind(" — "):
				exit_code = 1
				failure_message = "Package completion row rendered duplicate separators: %s" % rendered_text

	if exit_code == 0:
		overlay._on_input_submitted("package install builtin.time")
		await process_frame
		var package_snapshot: Dictionary = world.get_world_snapshot()
		var installed_rules_variant: Variant = package_snapshot.get("installed_rules", [])
		if not (installed_rules_variant is Array) or (installed_rules_variant as Array).is_empty():
			exit_code = 1
			failure_message = "package install did not add an installed rule: %s" % JSON.stringify(package_snapshot)
		else:
			for entry in installed_rules_variant:
				if not (entry is Dictionary):
					continue
				var installed_rule: Dictionary = entry
				var metadata: Dictionary = installed_rule.get("metadata", {})
				if String(metadata.get("package_id", "")) == "builtin.time":
					installed_package_rule_id = String(installed_rule.get("id", ""))
					break
			if installed_package_rule_id.is_empty():
				exit_code = 1
				failure_message = "package install did not expose a rule id for builtin.time: %s" % JSON.stringify(package_snapshot)

	if exit_code == 0:
		var install_result: Dictionary = world.create_rule_from_patch({
			"template_id": "hunger",
			"id": "overlay_tab_rule",
			"metadata": {"package_id": "overlay.tab.smoke"}
		})
		if String(install_result.get("status", "")) != "installed":
			exit_code = 1
			failure_message = "Failed to seed overlay smoke rule: %s" % JSON.stringify(install_result)
		else:
			var snapshot: Dictionary = world.get_world_snapshot()
			var installed_rules_variant: Variant = snapshot.get("installed_rules", [])
			if not (installed_rules_variant is Array) or (installed_rules_variant as Array).is_empty():
				exit_code = 1
				failure_message = "Seeded world snapshot still had no installed rules: %s" % JSON.stringify(snapshot)

	if exit_code == 0:
		overlay._hide_completion_candidates()
		if overlay._world_state == null:
			exit_code = 1
			failure_message = "Overlay could not resolve /root/WorldState."

	if exit_code == 0:
		var overlay_rules: Array = overlay._extract_installed_rules()
		if overlay_rules.is_empty():
			exit_code = 1
			failure_message = "Overlay did not see installed rules after seed: %s" % JSON.stringify(world.get_world_snapshot())

	if exit_code == 0:
		overlay._set_input_text("rule disable")
		overlay._handle_tab_completion()
		await process_frame
		var found_default_disable_candidate := false
		var found_time_disable_candidate := false
		var found_disable_candidate := false
		for candidate in overlay._completion_candidates:
			if candidate is Dictionary and String(candidate.get("value", "")).begins_with("rule disable default_package."):
				found_default_disable_candidate = true
			if candidate is Dictionary and String(candidate.get("value", "")) == "rule disable %s" % installed_package_rule_id:
				found_time_disable_candidate = true
			if candidate is Dictionary and String(candidate.get("value", "")) == "rule disable overlay_tab_rule":
				found_disable_candidate = true
		if not found_default_disable_candidate:
			exit_code = 1
			failure_message = "Expected disable candidate missing for bootstrap default package rules: %s" % JSON.stringify(overlay._completion_candidates)
		elif not found_time_disable_candidate:
			exit_code = 1
			failure_message = "Expected disable candidate missing for installed package rule: %s" % JSON.stringify(overlay._completion_candidates)
		elif not found_disable_candidate:
			exit_code = 1
			failure_message = "Expected disable candidate missing for enabled rule: %s" % JSON.stringify(overlay._completion_candidates)

	if exit_code == 0:
		var disable_result: Dictionary = world.set_rule_enabled("overlay_tab_rule", false)
		if String(disable_result.get("status", "")) != "disabled":
			exit_code = 1
			failure_message = "Failed to disable seeded smoke rule: %s" % JSON.stringify(disable_result)

	if exit_code == 0:
		overlay._hide_completion_candidates()
		overlay._set_input_text("rule enable")
		overlay._handle_tab_completion()
		await process_frame
		var found_rule_candidate := false
		for candidate in overlay._completion_candidates:
			if candidate is Dictionary and String(candidate.get("value", "")) == "rule enable overlay_tab_rule":
				found_rule_candidate = true
				break
		if not found_rule_candidate:
			exit_code = 1
			failure_message = "Expected rule candidate missing after install: %s" % JSON.stringify(overlay._completion_candidates)

	if exit_code == 0:
		overlay._hide_completion_candidates()
		overlay._set_input_text("rule enable ")
		overlay._handle_tab_completion()
		await process_frame
		if overlay._completion_candidates.is_empty():
			exit_code = 1
			failure_message = "Completion candidates were empty for 'rule enable '."

	if exit_code == 0:
		overlay._apply_completion_candidate(0)
		if not overlay._input.text.begins_with("rule enable "):
			exit_code = 1
			failure_message = "Applying completion did not keep the rule enable prefix: %s" % overlay._input.text

	for node in nodes_to_release:
		if is_instance_valid(node):
			node.queue_free()

	if exit_code != 0:
		push_error(failure_message)
	else:
		print("cli_overlay_completion_smoke: ok")
	quit(exit_code)
