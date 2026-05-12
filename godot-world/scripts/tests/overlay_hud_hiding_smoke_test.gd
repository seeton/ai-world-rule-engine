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
	await process_frame

	var active_world: Node = main._active_world
	if active_world == null:
		exit_code = 1
		failure_message = "Active world was not instantiated."

	if exit_code == 0 and not active_world.has_method("set_overlay_active"):
		exit_code = 1
		failure_message = "Active world does not expose set_overlay_active hook."

	if exit_code == 0 and active_world._overlay_active:
		exit_code = 1
		failure_message = "Active world should not start with an overlay flag set."

	var hud_layer: CanvasLayer = active_world._hud_layer
	if exit_code == 0 and hud_layer == null:
		exit_code = 1
		failure_message = "HUD layer was not built."
	if exit_code == 0 and not hud_layer.visible:
		exit_code = 1
		failure_message = "HUD layer should be visible before any overlay opens."

	# 1. Rule tree overlay hides HUD generically (no per-overlay glue needed).
	if exit_code == 0:
		main._on_rule_tree_toggle_requested()
		await process_frame
		await process_frame
		if not active_world._overlay_active:
			exit_code = 1
			failure_message = "World overlay-active flag did not flip on rule tree open."
		elif hud_layer.visible:
			exit_code = 1
			failure_message = "HUD layer should be hidden while rule tree overlay is open."

	if exit_code == 0:
		main._close_rule_tree_overlay()
		await create_timer(0.3).timeout
		await process_frame
		if active_world._overlay_active:
			exit_code = 1
			failure_message = "World overlay-active flag did not clear after rule tree closed."
		elif not hud_layer.visible:
			exit_code = 1
			failure_message = "HUD layer should return to visible after rule tree closed."

	# 2. CLI inspect overlay (different overlay type, same generic behavior).
	if exit_code == 0:
		main._on_cli_overlay_toggle_requested()
		await process_frame
		await process_frame
		if hud_layer.visible:
			exit_code = 1
			failure_message = "HUD layer should be hidden while CLI inspect overlay is open."

	if exit_code == 0:
		main._close_cli_inspect_overlay()
		await create_timer(0.3).timeout
		await process_frame
		if not hud_layer.visible:
			exit_code = 1
			failure_message = "HUD layer should return to visible after CLI overlay closed."

	# 3. GM screen overlay — same path.
	if exit_code == 0:
		main._on_gm_interaction_requested()
		await process_frame
		await process_frame
		if hud_layer.visible:
			exit_code = 1
			failure_message = "HUD layer should be hidden while GM screen is open."

	# 4. An ad-hoc overlay added directly to overlay_layer must also trigger the
	#    generic hide path (this is the "future overlays just work" guarantee).
	if exit_code == 0:
		var ad_hoc_overlay := Control.new()
		ad_hoc_overlay.name = "AdHocFutureOverlay"
		main.overlay_layer.add_child(ad_hoc_overlay)
		await process_frame
		await process_frame
		if hud_layer.visible:
			exit_code = 1
			failure_message = "HUD layer should stay hidden while any overlay child is present."
		ad_hoc_overlay.queue_free()
		await process_frame

	if is_instance_valid(main):
		main.queue_free()
	if is_instance_valid(world):
		world.queue_free()

	if exit_code != 0:
		push_error(failure_message)
	else:
		print("overlay_hud_hiding_smoke: ok")
	quit(exit_code)
