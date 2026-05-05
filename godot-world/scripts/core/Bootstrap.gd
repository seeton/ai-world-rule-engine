extends Node


func _process(delta: float) -> void:
	WorldState.advance_tick(delta)
