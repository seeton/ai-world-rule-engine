extends SceneTree

const MainScene = preload("res://scenes/Main.tscn")


func _initialize() -> void:
	var exit_code := 0
	var failure_message := ""

	var main := MainScene.instantiate()
	root.add_child(main)
	await process_frame
	await process_frame

	if main._cli_inspect_overlay != null:
		exit_code = 1
		failure_message = "CLI overlay should start closed."

	if exit_code == 0:
		main._on_cli_overlay_toggle_requested()
		await process_frame
		await process_frame
		if main._cli_inspect_overlay == null:
			exit_code = 1
			failure_message = "CLI overlay did not open from the main scene."

	var overlay = main._cli_inspect_overlay
	if exit_code == 0:
		overlay._set_input_text("rule enable")
		overlay._handle_tab_completion()
		await process_frame
		if overlay._completion_panel == null or not overlay._completion_panel.visible:
			exit_code = 1
			failure_message = "Completion panel did not open for 'rule enable' in main scene."
		elif overlay._completion_candidates.is_empty():
			exit_code = 1
			failure_message = "Completion candidates were empty for 'rule enable' in main scene."
		elif String(overlay._completion_candidates[0].get("summary", "")).find("現在は無効な rule がない") == -1:
			exit_code = 1
			failure_message = "Unexpected enable completion summary: %s" % JSON.stringify(overlay._completion_candidates)

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
			failure_message = "Expected package install completion candidate missing in main scene: %s" % JSON.stringify(overlay._completion_candidates)

	if exit_code == 0:
		overlay._hide_completion_candidates()
		overlay._set_input_text("rule disable")
		overlay._handle_tab_completion()
		await process_frame
		if overlay._completion_panel == null or not overlay._completion_panel.visible:
			exit_code = 1
			failure_message = "Completion panel did not open for 'rule disable' in main scene."
		elif overlay._completion_candidates.is_empty():
			exit_code = 1
			failure_message = "Completion candidates were empty for 'rule disable' in main scene."
		else:
			var found_default_disable_candidate := false
			for candidate in overlay._completion_candidates:
				if candidate is Dictionary and String(candidate.get("value", "")).begins_with("rule disable default_package."):
					found_default_disable_candidate = true
					break
			if not found_default_disable_candidate:
				exit_code = 1
				failure_message = "Expected bootstrap disable candidates in main scene: %s" % JSON.stringify(overlay._completion_candidates)
			elif String(overlay._completion_candidates[0].get("summary", "")).find("導入済み rule がない") != -1:
				exit_code = 1
				failure_message = "Unexpected empty-world disable summary: %s" % JSON.stringify(overlay._completion_candidates)

	if is_instance_valid(main):
		main.queue_free()

	if exit_code != 0:
		push_error(failure_message)
	else:
		print("main_scene_cli_overlay_completion_smoke: ok")
	quit(exit_code)
