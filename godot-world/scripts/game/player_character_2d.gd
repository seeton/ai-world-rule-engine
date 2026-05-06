extends CharacterBody2D

const SPEED: float = 240.0

@onready var visual: ColorRect = $Visual
@onready var collision_shape: CollisionShape2D = $CollisionShape2D


func _physics_process(_delta: float) -> void:
	var direction := Input.get_vector("ui_left", "ui_right", "ui_up", "ui_down")
	velocity = direction.normalized() * SPEED if direction.length_squared() > 0.0001 else Vector2.ZERO
	move_and_slide()


func apply_visual_style(size: Vector2, color: Color) -> void:
	visual.position = -(size * 0.5)
	visual.size = size
	visual.color = color
	if collision_shape.shape is RectangleShape2D:
		(collision_shape.shape as RectangleShape2D).size = size
