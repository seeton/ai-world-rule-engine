extends CharacterBody2D

@onready var visual: ColorRect = $Visual
@onready var label: Label = $Label
@onready var collision_shape: CollisionShape2D = $CollisionShape2D

func apply_visual_style(size: Vector2, color: Color) -> void:
	visual.position = -(size * 0.5)
	visual.size = size
	visual.color = color
	if collision_shape.shape is RectangleShape2D:
		(collision_shape.shape as RectangleShape2D).size = size


func set_render_enabled(enabled: bool) -> void:
	visual.visible = enabled
	label.visible = enabled
	collision_shape.disabled = not enabled


func is_render_enabled() -> bool:
	return visual.visible or label.visible
