extends Node

const WORLD_2D_SCENE := preload("res://scenes/World2D.tscn")
const WORLD_3D_SCENE := preload("res://scenes/World3D.tscn")
const GM_SCREEN_OVERLAY_SCRIPT := preload("res://scripts/game/gm_screen_overlay.gd")
const RULE_TREE_OVERLAY_SCRIPT := preload("res://scripts/game/rule_tree_overlay.gd")
const CLI_INSPECT_OVERLAY_SCRIPT := preload("res://scripts/game/cli_inspect_overlay.gd")
const COLLAPSE_WATCHER_SCRIPT := preload("res://scripts/game/collapse_watcher.gd")
const AUTO_OPEN_COOLDOWN_SECONDS: float = 8.0

@onready var world_host: Node = $WorldHost
@onready var overlay_layer: CanvasLayer = $OverlayLayer

var _world_state: Node = null
var _active_world: Node = null
var _active_mode: String = ""
var _gm_screen: Control = null
var _rule_tree_overlay: Control = null
var _cli_inspect_overlay: Control = null
var _collapse_watcher: Node = null
var _signal_cooldowns: Dictionary = {}
var _pending_auto_open_signals: PackedStringArray = PackedStringArray()


func _ready() -> void:
	_world_state = get_node_or_null("/root/WorldState")
	_collapse_watcher = COLLAPSE_WATCHER_SCRIPT.new()
	_collapse_watcher.collapse_signals_appeared.connect(_on_collapse_signals_appeared)
	add_child(_collapse_watcher)
	_switch_world(_desired_world_mode())


func _process(delta: float) -> void:
	var desired_mode := _desired_world_mode()
	if desired_mode != _active_mode:
		_switch_world(desired_mode)
	_tick_signal_cooldowns(delta)


func _desired_world_mode() -> String:
	if _world_state != null and _world_state.has_method("get_world_snapshot"):
		var snapshot_variant = _world_state.call("get_world_snapshot")
		if snapshot_variant is Dictionary:
			return String(snapshot_variant.get("world_mode", "two_d"))
	return "two_d"


func _switch_world(world_mode: String) -> void:
	if _active_world != null:
		_active_world.queue_free()
		_active_world = null

	var packed_scene := WORLD_3D_SCENE if world_mode == "three_d" else WORLD_2D_SCENE
	_active_world = packed_scene.instantiate()
	if _active_world.has_signal("gm_interaction_requested"):
		_active_world.gm_interaction_requested.connect(_on_gm_interaction_requested)
	if _active_world.has_signal("rule_tree_toggle_requested"):
		_active_world.rule_tree_toggle_requested.connect(_on_rule_tree_toggle_requested)
	if _active_world.has_signal("cli_overlay_toggle_requested"):
		_active_world.cli_overlay_toggle_requested.connect(_on_cli_overlay_toggle_requested)
	world_host.add_child(_active_world)
	_active_mode = world_mode
	_refresh_active_world_interaction_pause()


func _on_gm_interaction_requested() -> void:
	if _gm_screen != null:
		return

	_close_rule_tree_overlay()
	_close_cli_inspect_overlay()

	_gm_screen = GM_SCREEN_OVERLAY_SCRIPT.new()
	_gm_screen.closed.connect(_on_gm_screen_closed)
	overlay_layer.add_child(_gm_screen)
	_refresh_active_world_interaction_pause()


func _on_gm_screen_closed() -> void:
	_gm_screen = null

	var desired_mode := _desired_world_mode()
	if desired_mode != _active_mode:
		_switch_world(desired_mode)
	else:
		_refresh_active_world_interaction_pause()
	_drain_pending_auto_open()


func _on_rule_tree_toggle_requested() -> void:
	if _gm_screen != null:
		return

	if _rule_tree_overlay != null:
		_close_rule_tree_overlay()
		return

	_close_cli_inspect_overlay()
	_rule_tree_overlay = RULE_TREE_OVERLAY_SCRIPT.new()
	_rule_tree_overlay.closed.connect(_on_rule_tree_overlay_closed)
	overlay_layer.add_child(_rule_tree_overlay)
	_refresh_active_world_interaction_pause()


func _close_rule_tree_overlay() -> void:
	if _rule_tree_overlay == null:
		return

	if _rule_tree_overlay.has_method("close_overlay"):
		_rule_tree_overlay.call("close_overlay")
	else:
		_rule_tree_overlay.queue_free()
		_rule_tree_overlay = null


func _on_rule_tree_overlay_closed() -> void:
	_rule_tree_overlay = null
	_refresh_active_world_interaction_pause()


func _on_cli_overlay_toggle_requested() -> void:
	if _gm_screen != null:
		return

	if _cli_inspect_overlay != null:
		_close_cli_inspect_overlay()
		return

	_open_cli_inspect_overlay(PackedStringArray())


func _open_cli_inspect_overlay(auto_open_reasons: PackedStringArray) -> void:
	_close_rule_tree_overlay()
	_cli_inspect_overlay = CLI_INSPECT_OVERLAY_SCRIPT.new()
	if _cli_inspect_overlay.has_method("set_auto_open_reasons"):
		_cli_inspect_overlay.call("set_auto_open_reasons", auto_open_reasons)
	_cli_inspect_overlay.closed.connect(_on_cli_inspect_overlay_closed.bind(auto_open_reasons))
	overlay_layer.add_child(_cli_inspect_overlay)
	_refresh_active_world_interaction_pause()


func _close_cli_inspect_overlay() -> void:
	if _cli_inspect_overlay == null:
		return

	if _cli_inspect_overlay.has_method("close_overlay"):
		_cli_inspect_overlay.call("close_overlay")
	else:
		_cli_inspect_overlay.queue_free()
		_cli_inspect_overlay = null


func _on_cli_inspect_overlay_closed(auto_open_reasons: PackedStringArray = PackedStringArray()) -> void:
	_cli_inspect_overlay = null
	for reason in auto_open_reasons:
		_signal_cooldowns[String(reason)] = AUTO_OPEN_COOLDOWN_SECONDS
	_refresh_active_world_interaction_pause()


func _refresh_active_world_interaction_pause() -> void:
	if _active_world == null or not _active_world.has_method("set_interaction_paused"):
		return

	_active_world.call("set_interaction_paused", _gm_screen != null or _rule_tree_overlay != null or _cli_inspect_overlay != null)


func _on_collapse_signals_appeared(new_signals: PackedStringArray) -> void:
	var actionable: PackedStringArray = PackedStringArray()
	for raw in new_signals:
		var name := String(raw)
		if _signal_cooldowns.get(name, 0.0) > 0.0:
			continue
		actionable.append(name)
	if actionable.is_empty():
		return

	if _gm_screen != null:
		for name in actionable:
			if not _pending_auto_open_signals.has(name):
				_pending_auto_open_signals.append(name)
		return

	if _cli_inspect_overlay != null:
		return

	_open_cli_inspect_overlay(actionable)


func _drain_pending_auto_open() -> void:
	if _pending_auto_open_signals.is_empty():
		return
	if _gm_screen != null or _cli_inspect_overlay != null:
		return
	var reasons: PackedStringArray = PackedStringArray()
	for raw in _pending_auto_open_signals:
		var name := String(raw)
		if _signal_cooldowns.get(name, 0.0) > 0.0:
			continue
		reasons.append(name)
	_pending_auto_open_signals = PackedStringArray()
	if reasons.is_empty():
		return
	_open_cli_inspect_overlay(reasons)


func _tick_signal_cooldowns(delta: float) -> void:
	if _signal_cooldowns.is_empty():
		return
	var expired: Array = []
	for key in _signal_cooldowns.keys():
		var remaining := float(_signal_cooldowns[key]) - delta
		if remaining <= 0.0:
			expired.append(key)
		else:
			_signal_cooldowns[key] = remaining
	for key in expired:
		_signal_cooldowns.erase(key)
