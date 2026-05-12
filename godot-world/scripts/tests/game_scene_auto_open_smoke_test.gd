extends SceneTree

const WorldStateScript = preload("res://scripts/core/WorldState.gd")
const MainScene = preload("res://scenes/Main.tscn")


func _initialize() -> void:
	var exit_code := 0
	var failure_message := ""

	var world := WorldStateScript.new()
	world.name = "WorldState"
	root.add_child(world)

	var main := MainScene.instantiate()
	root.add_child(main)
	await process_frame

	main._on_rule_tree_toggle_requested()
	await process_frame
	if main._rule_tree_overlay == null:
		exit_code = 1
		failure_message = "Rule tree overlay did not open."

	if exit_code == 0:
		main._on_collapse_signals_appeared(PackedStringArray(["disabled_rules_present"]))
		await process_frame
		if main._rule_tree_overlay == null:
			exit_code = 1
			failure_message = "Rule tree overlay was closed by collapse auto-open."
		elif main._cli_inspect_overlay != null:
			exit_code = 1
			failure_message = "CLI overlay auto-opened while rule tree overlay was visible."
		elif not main._pending_auto_open_signals.has("disabled_rules_present"):
			exit_code = 1
			failure_message = "Collapse signal was not queued while rule tree overlay was visible."

	if exit_code == 0:
		main._close_rule_tree_overlay()
		await create_timer(0.3).timeout
		if main._rule_tree_overlay != null:
			exit_code = 1
			failure_message = "Rule tree overlay did not finish closing."
		elif main._cli_inspect_overlay == null:
			exit_code = 1
			failure_message = "Queued collapse signal did not open the CLI overlay after rule tree close."

	if is_instance_valid(main):
		main.queue_free()
	if is_instance_valid(world):
		world.queue_free()

	if exit_code != 0:
		push_error(failure_message)
	quit(exit_code)
