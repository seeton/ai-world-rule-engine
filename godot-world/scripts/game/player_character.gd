extends CharacterBody3D

const SPEED: float = 5.6
const ACCELERATION: float = 18.0
const GRAVITY: float = 24.0
const TURN_SPEED: float = 10.0

@onready var collision_shape: CollisionShape3D = $CollisionShape3D
@onready var visual: MeshInstance3D = $Visual

var _reference_camera: Camera3D = null
var _visual_material: StandardMaterial3D = null


func _ready() -> void:
    _visual_material = _ensure_material(Color(0.33, 0.55, 0.97, 1.0))


func set_reference_camera(reference_camera: Camera3D) -> void:
    _reference_camera = reference_camera


func apply_visual_style(size: Vector3, color: Color) -> void:
    if visual.mesh is BoxMesh:
        (visual.mesh as BoxMesh).size = size
    if collision_shape.shape is BoxShape3D:
        (collision_shape.shape as BoxShape3D).size = Vector3(max(size.x, 0.6), max(size.y, 1.4), max(size.z, 0.6))
    if _visual_material == null:
        _visual_material = _ensure_material(color)
    _visual_material.albedo_color = color


func _physics_process(delta: float) -> void:
    var input_vector := Input.get_vector("ui_left", "ui_right", "ui_up", "ui_down")
    var movement_direction := _camera_relative_direction(input_vector)
    var horizontal_velocity := Vector3(velocity.x, 0.0, velocity.z)
    var target_velocity := movement_direction * SPEED

    horizontal_velocity = horizontal_velocity.move_toward(target_velocity, ACCELERATION * delta)
    velocity.x = horizontal_velocity.x
    velocity.z = horizontal_velocity.z

    if not is_on_floor():
        velocity.y -= GRAVITY * delta
    elif velocity.y < 0.0:
        velocity.y = 0.0

    move_and_slide()

    if movement_direction.length_squared() > 0.0001:
        var target_basis := Basis.looking_at(movement_direction, Vector3.UP)
        basis = basis.slerp(target_basis, clamp(delta * TURN_SPEED, 0.0, 1.0))


func _camera_relative_direction(input_vector: Vector2) -> Vector3:
    if input_vector.length_squared() <= 0.0001:
        return Vector3.ZERO

    var camera_basis := _reference_camera.global_transform.basis if _reference_camera != null else global_transform.basis
    var forward := -camera_basis.z
    forward.y = 0.0
    forward = forward.normalized()
    var right := camera_basis.x
    right.y = 0.0
    right = right.normalized()

    var movement_direction := (right * input_vector.x) + (forward * -input_vector.y)
    movement_direction.y = 0.0
    return movement_direction.normalized()


func _ensure_material(default_color: Color) -> StandardMaterial3D:
    var source_material := visual.material_override
    var material := source_material.duplicate() if source_material is StandardMaterial3D else StandardMaterial3D.new()
    material.albedo_color = default_color
    material.roughness = 0.72
    visual.material_override = material
    return material
