extends Node
class_name CollapseWatcher

# Watches WorldState for transitions into a collapsed state and emits a
# signal when *new* collapse_signals appear. Used by game_scene.gd to
# auto-open the in-game CLI overlay so the player has an immediate entry
# point into the recovery flow when the world quietly degrades.
#
# Design rules:
# - Initial-state signals are NOT emitted (the very first poll establishes
#   a baseline; only later additions trigger). Otherwise the default empty
#   world (no_installed_rules) would fire on every game start.
# - Already-known signals don't re-fire. The watcher only emits on the
#   set-difference (new minus previous).
# - The watcher does no UI work itself; cooldown / exclusivity logic lives
#   in the consumer (game_scene.gd) so the watcher stays trivially testable.

signal collapse_signals_appeared(new_signals: PackedStringArray)

const InspectReportScript = preload("res://scripts/cli/inspect_report.gd")

const DEFAULT_POLL_INTERVAL: float = 0.5

@export var poll_interval: float = DEFAULT_POLL_INTERVAL

var _world_state: Node = null
var _previous_signals: Dictionary = {}
var _baseline_taken: bool = false
var _poll_timer: float = 0.0


func _ready() -> void:
	_world_state = get_node_or_null("/root/WorldState")
	# poll_once() with _baseline_taken == false establishes the baseline
	# without emitting, so the next poll only fires on transitions.
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
	var report: Dictionary = InspectReportScript.build(_world_state, "")
	var status: Dictionary = report.get("world_status", {})
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
