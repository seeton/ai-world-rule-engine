extends SceneTree

const WorldStateScript = preload("res://scripts/core/WorldState.gd")
const MainScene = preload("res://scenes/Main.tscn")


func _initialize() -> void:
	var exit_code := 0
	var failure_message := ""

	var world := WorldStateScript.new()
	world.name = "WorldState"
	root.add_child(world)
	await process_frame

	var status: Dictionary = world.get_codex_preflight_status(true)
	if String(status.get("overall_status", "")).strip_edges().is_empty():
		exit_code = 1
		failure_message = "Codex preflight status did not expose overall_status."
	elif not status.has("cli_available") or not status.has("login_ok") or not status.has("schema_ready"):
		exit_code = 1
		failure_message = "Codex preflight status was missing readiness fields."
	elif not (status.get("recent", null) is Dictionary):
		exit_code = 1
		failure_message = "Codex preflight status was missing the recent status dictionary."

	var main = null
	if exit_code == 0:
		main = MainScene.instantiate()
		root.add_child(main)
		await process_frame
		await process_frame
		if main._codex_preflight_indicator == null:
			exit_code = 1
			failure_message = "Main scene did not create the Codex preflight indicator."
		elif not main._codex_preflight_indicator.visible:
			exit_code = 1
			failure_message = "Codex preflight indicator should start visible."
		else:
			var status_label := main._codex_preflight_indicator.get_node_or_null("Content/StatusLabel") as Label
			if status_label == null or String(status_label.text).strip_edges().find("Codex") == -1:
				exit_code = 1
				failure_message = "Codex preflight indicator did not render status text."

	if exit_code == 0:
		var active_world: Node = main._active_world
		var hud_layer: CanvasLayer = active_world._hud_layer
		main._on_gm_interaction_requested()
		await process_frame
		await process_frame
		if hud_layer.visible:
			exit_code = 1
			failure_message = "World HUD should still hide while the GM overlay is open."
		elif not main._codex_preflight_indicator.visible:
			exit_code = 1
			failure_message = "Codex preflight indicator should remain visible while overlays are open."

	if is_instance_valid(main):
		main.queue_free()
	if is_instance_valid(world):
		world.queue_free()

	if exit_code != 0:
		push_error(failure_message)
	else:
		print("codex_preflight_indicator_smoke: ok")
	quit(exit_code)
