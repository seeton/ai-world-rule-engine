extends Node2D

signal interaction_triggered
signal hover_changed(is_hovering: bool)

@onready var interaction_area: Area2D = $InteractionArea
@onready var visual: ColorRect = $Visual
@onready var label: Label = $Label

var _is_hovering: bool = false
var _base_color: Color = Color(1.0, 0.8, 0.2, 1.0)
var _hover_color: Color = Color(1.0, 0.9, 0.4, 1.0)

func _ready() -> void:
	if interaction_area:
		interaction_area.input_event.connect(_on_input_event)
		interaction_area.mouse_entered.connect(_on_mouse_entered)
		interaction_area.mouse_exited.connect(_on_mouse_exited)

func _process(delta: float) -> void:
	if visual:
		var target_color := _hover_color if _is_hovering else _base_color
		visual.color = visual.color.lerp(target_color, delta * 8.0)

func _on_input_event(_viewport: Node, event: InputEvent, _shape_idx: int) -> void:
	if event is InputEventMouseButton:
		var mouse_event := event as InputEventMouseButton
		if mouse_event.pressed and mouse_event.button_index == MOUSE_BUTTON_LEFT:
			interaction_triggered.emit()

func _on_mouse_entered() -> void:
	_is_hovering = true
	hover_changed.emit(true)
	Input.set_default_cursor_shape(Input.CURSOR_POINTING_HAND)

func _on_mouse_exited() -> void:
	_is_hovering = false
	hover_changed.emit(false)
	Input.set_default_cursor_shape(Input.CURSOR_ARROW)
