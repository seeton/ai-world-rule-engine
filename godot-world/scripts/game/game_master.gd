extends Area3D

signal interaction_triggered
signal hover_changed(is_hovering: bool)

@onready var collision_shape: CollisionShape3D = $CollisionShape3D
@onready var visual: MeshInstance3D = $Visual

var _is_hovering: bool = false
var _base_color := Color(0.95, 0.79, 0.41, 1.0)
var _hover_color := Color(1.0, 0.9, 0.58, 1.0)
var _material: StandardMaterial3D = null


func _ready() -> void:
    input_ray_pickable = true
    mouse_entered.connect(_on_mouse_entered)
    mouse_exited.connect(_on_mouse_exited)
    input_event.connect(_on_input_event)
    _material = _ensure_material(_base_color)


func apply_renderable(size: Vector3, color: Color) -> void:
    _base_color = color
    _hover_color = color.lerp(Color.WHITE, 0.22)
    if visual.mesh is BoxMesh:
        (visual.mesh as BoxMesh).size = size
    if collision_shape.shape is BoxShape3D:
        (collision_shape.shape as BoxShape3D).size = size + Vector3(0.35, 0.35, 0.35)
    if _material == null:
        _material = _ensure_material(color)
    _material.albedo_color = _hover_color if _is_hovering else _base_color


func _process(delta: float) -> void:
    if _material == null:
        return

    var target_color := _hover_color if _is_hovering else _base_color
    _material.albedo_color = _material.albedo_color.lerp(target_color, min(delta * 8.0, 1.0))


func set_render_enabled(enabled: bool) -> void:
    visible = enabled
    visual.visible = enabled
    collision_shape.disabled = not enabled
    input_ray_pickable = enabled


func is_render_enabled() -> bool:
    return visible and visual.visible


func _exit_tree() -> void:
    Input.set_default_cursor_shape(Input.CURSOR_ARROW)


func _on_input_event(_camera: Node, event: InputEvent, _event_position: Vector3, _normal: Vector3, _shape_idx: int) -> void:
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


func _ensure_material(default_color: Color) -> StandardMaterial3D:
    var source_material := visual.material_override
    var material := source_material.duplicate() if source_material is StandardMaterial3D else StandardMaterial3D.new()
    material.albedo_color = default_color
    material.roughness = 0.72
    visual.material_override = material
    return material
