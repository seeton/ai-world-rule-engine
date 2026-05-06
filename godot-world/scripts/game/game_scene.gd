extends Node

const WORLD_2D_SCENE := preload("res://scenes/World2D.tscn")
const WORLD_3D_SCENE := preload("res://scenes/World3D.tscn")
const GM_SCREEN_OVERLAY_SCRIPT := preload("res://scripts/game/gm_screen_overlay.gd")

@onready var world_host: Node = $WorldHost
@onready var overlay_layer: CanvasLayer = $OverlayLayer

var _world_state: Node = null
var _active_world: Node = null
var _active_mode: String = ""
var _gm_screen: Control = null


func _ready() -> void:
	_world_state = get_node_or_null("/root/WorldState")
	_switch_world(_desired_world_mode())


func _process(_delta: float) -> void:
	var desired_mode := _desired_world_mode()
	if desired_mode != _active_mode:
		_switch_world(desired_mode)


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
	world_host.add_child(_active_world)
	if _gm_screen != null and _active_world.has_method("set_interaction_paused"):
		_active_world.call("set_interaction_paused", true)
	_active_mode = world_mode


func _on_gm_interaction_requested() -> void:
	if _gm_screen != null:
		return

	if _active_world != null and _active_world.has_method("set_interaction_paused"):
		_active_world.call("set_interaction_paused", true)

	_gm_screen = GM_SCREEN_OVERLAY_SCRIPT.new()
	_gm_screen.closed.connect(_on_gm_screen_closed)
	overlay_layer.add_child(_gm_screen)


func _on_gm_screen_closed() -> void:
	_gm_screen = null

	var desired_mode := _desired_world_mode()
	if desired_mode != _active_mode:
		_switch_world(desired_mode)
	elif _active_world != null and _active_world.has_method("set_interaction_paused"):
		_active_world.call("set_interaction_paused", false)
