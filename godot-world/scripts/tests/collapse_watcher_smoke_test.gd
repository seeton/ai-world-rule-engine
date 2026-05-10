extends SceneTree

# Smoke test for CollapseWatcher's signal-edge detection.

const WorldStateScript = preload("res://scripts/core/WorldState.gd")
const CollapseWatcherScript = preload("res://scripts/game/collapse_watcher.gd")


var _emissions: Array = []


func _initialize() -> void:
	var exit_code := 0
	var failure_message := ""
	var nodes_to_release: Array = []

	var world := WorldStateScript.new()
	nodes_to_release.append(world)
	root.add_child(world)

	var watcher := CollapseWatcherScript.new()
	nodes_to_release.append(watcher)
	watcher.set_world_state(world)
	watcher.collapse_signals_appeared.connect(_on_collapse_signals_appeared)

	# Initial poll establishes baseline (no_installed_rules) — no emit.
	watcher.poll_once()
	if not _emissions.is_empty():
		exit_code = 1
		failure_message = "Baseline poll emitted: %s" % JSON.stringify(_emissions)

	if exit_code == 0:
		var install_result: Dictionary = world.create_rule_from_patch({
			"template_id": "hunger",
			"id": "watcher_smoke_rule",
			"metadata": {"package_id": "watcher.smoke"}
		})
		if String(install_result.get("status", "")) != "installed":
			exit_code = 1
			failure_message = "Failed to install rule: %s" % JSON.stringify(install_result)

	# Installing a rule REMOVES no_installed_rules and adds nothing -> no emit.
	if exit_code == 0:
		watcher.poll_once()
		if not _emissions.is_empty():
			exit_code = 1
			failure_message = "Rule install poll unexpectedly emitted: %s" % JSON.stringify(_emissions)

	if exit_code == 0:
		var disable_result: Dictionary = world.set_rule_enabled("watcher_smoke_rule", false)
		if String(disable_result.get("status", "")) != "disabled":
			exit_code = 1
			failure_message = "Failed to disable rule: %s" % JSON.stringify(disable_result)

	# Disable adds disabled_rules_present -> emit exactly once with that signal.
	if exit_code == 0:
		_emissions.clear()
		watcher.poll_once()
		if _emissions.size() != 1:
			exit_code = 1
			failure_message = "Disable did not emit exactly once: %s" % JSON.stringify(_emissions)
		else:
			var emitted: PackedStringArray = _emissions[0]
			if emitted.size() != 1 or String(emitted[0]) != "disabled_rules_present":
				exit_code = 1
				failure_message = "Disable emission mismatch: %s" % str(emitted)

	# No new signals -> no re-emit.
	if exit_code == 0:
		_emissions.clear()
		watcher.poll_once()
		if not _emissions.is_empty():
			exit_code = 1
			failure_message = "Repeat poll re-emitted: %s" % JSON.stringify(_emissions)

	# reset_baseline -> next poll silent.
	if exit_code == 0:
		_emissions.clear()
		watcher.reset_baseline()
		watcher.poll_once()
		if not _emissions.is_empty():
			exit_code = 1
			failure_message = "Post-reset poll emitted: %s" % JSON.stringify(_emissions)

	for n in nodes_to_release:
		if is_instance_valid(n):
			n.queue_free()

	if exit_code != 0:
		push_error(failure_message)
	quit(exit_code)


func _on_collapse_signals_appeared(new_signals: PackedStringArray) -> void:
	_emissions.append(new_signals.duplicate())
