extends CharacterBody3D

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


func apply_runtime_motion(horizontal_velocity: Vector3) -> void:
    var movement_direction := Vector3(horizontal_velocity.x, 0.0, horizontal_velocity.z)
    if movement_direction.length_squared() <= 0.0001:
        return
    basis = Basis.looking_at(movement_direction.normalized(), Vector3.UP)


func set_render_enabled(enabled: bool) -> void:
    visible = enabled
    visual.visible = enabled
    collision_shape.disabled = not enabled


func is_render_enabled() -> bool:
    return visible and visual.visible


func _ensure_material(default_color: Color) -> StandardMaterial3D:
    var source_material := visual.material_override
    var material := source_material.duplicate() if source_material is StandardMaterial3D else StandardMaterial3D.new()
    material.albedo_color = default_color
    material.roughness = 0.72
    visual.material_override = material
    return material
