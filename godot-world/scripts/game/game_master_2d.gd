extends Node2D

signal interaction_triggered
signal hover_changed(is_hovering: bool)

@onready var interaction_area: Area2D = $InteractionArea
@onready var visual: ColorRect = $Visual

var _is_hovering: bool = false
var _base_color := Color(1.0, 0.8, 0.2, 1.0)
var _hover_color := Color(1.0, 0.9, 0.4, 1.0)


func _ready() -> void:
	if interaction_area != null:
		interaction_area.input_event.connect(_on_input_event)
		interaction_area.mouse_entered.connect(_on_mouse_entered)
		interaction_area.mouse_exited.connect(_on_mouse_exited)


func _process(delta: float) -> void:
	var target_color := _hover_color if _is_hovering else _base_color
	visual.color = visual.color.lerp(target_color, min(delta * 8.0, 1.0))


func apply_visual_style(size: Vector2, color: Color) -> void:
	_base_color = color
	_hover_color = color.lerp(Color.WHITE, 0.24)
	visual.position = -(size * 0.5)
	visual.size = size
	if $InteractionArea/CollisionShape2D.shape is RectangleShape2D:
		($InteractionArea/CollisionShape2D.shape as RectangleShape2D).size = size + Vector2(20.0, 20.0)
	if not _is_hovering:
		visual.color = _base_color


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
