extends Node
class_name CollapseWatcher

signal collapse_signals_appeared(new_signals: PackedStringArray)

const WorldOpDispatcherScript = preload("res://scripts/world_ops/dispatcher.gd")

const DEFAULT_POLL_INTERVAL: float = 0.5

@export var poll_interval: float = DEFAULT_POLL_INTERVAL

var _world_state: Node = null
var _previous_signals: Dictionary = {}
var _baseline_taken: bool = false
var _poll_timer: float = 0.0


func _ready() -> void:
	_world_state = get_node_or_null("/root/WorldState")
	poll_once()


func _process(delta: float) -> void:
	_poll_timer += delta
	if _poll_timer < poll_interval:
		return
	_poll_timer = 0.0
	poll_once()


func poll_once() -> void:
	if _world_state == null:
		return
	var inspect_result: Dictionary = WorldOpDispatcherScript.dispatch(_world_state, "InspectWorld", {}, {})
	var payload: Dictionary = inspect_result.get("payload", {})
	var status: Dictionary = payload.get("world_status", {})
	var current_signals: Array = status.get("collapse_signals", [])

	if not _baseline_taken:
		_previous_signals = _to_signal_set(current_signals)
		_baseline_taken = true
		return

	var current_set: Dictionary = _to_signal_set(current_signals)
	var added: PackedStringArray = PackedStringArray()
	for signal_name in current_set.keys():
		if not _previous_signals.has(signal_name):
			added.append(String(signal_name))
	_previous_signals = current_set

	if added.size() > 0:
		collapse_signals_appeared.emit(added)


func reset_baseline() -> void:
	_baseline_taken = false
	_previous_signals = {}


func set_world_state(world_state: Node) -> void:
	_world_state = world_state
	reset_baseline()


func _to_signal_set(signals: Array) -> Dictionary:
	var result: Dictionary = {}
	for raw in signals:
		var name := String(raw)
		if name.is_empty():
			continue
		result[name] = true
	return result
