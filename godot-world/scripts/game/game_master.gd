extends Node2D

signal interaction_triggered

@onready var interaction_area: Area2D = $InteractionArea

func _ready() -> void:
	if interaction_area:
		interaction_area.input_event.connect(_on_input_event)

func _on_input_event(_viewport: Node, event: InputEvent, _shape_idx: int) -> void:
	if event is InputEventMouseButton:
		var mouse_event := event as InputEventMouseButton
		if mouse_event.pressed and mouse_event.button_index == MOUSE_BUTTON_LEFT:
			interaction_triggered.emit()
