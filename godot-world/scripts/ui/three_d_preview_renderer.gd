extends VBoxContainer

const DEFAULT_CAMERA_POSITION := Vector3(7.5, 6.0, 8.5)
const DEFAULT_CAMERA_TARGET := Vector3(0.0, 1.0, 0.0)
const DEFAULT_LIGHT_DIRECTION := Vector3(-0.6, -1.0, -0.35)

var _status_label: Label
var _placeholder_label: Label
var _viewport_container: SubViewportContainer
var _viewport: SubViewport
var _scene_root: Node3D
var _renderables_root: Node3D
var _camera: Camera3D
var _light: DirectionalLight3D
var _floor: MeshInstance3D
var _environment: Environment


func _ready() -> void:
    size_flags_horizontal = Control.SIZE_EXPAND_FILL
    size_flags_vertical = Control.SIZE_EXPAND_FILL
    add_theme_constant_override("separation", 8)
    _build_ui()
    _show_placeholder(
        "GM用の3D俯瞰メモを準備中です。\nWorldState の snapshot[\"three_d_preview\"] があれば、会話中に簡易俯瞰をここで確認できます。"
    )


func update_from_snapshot(snapshot: Dictionary) -> void:
    var preview_value = snapshot.get("three_d_preview", null)
    if not (preview_value is Dictionary):
        _show_placeholder(
            "この会話には3D化後の確認データがありません。\n本編を3Dへ切り替えると、GM確認用の snapshot[\"three_d_preview\"] がここへ表示されます。"
        )
        return

    var preview_data: Dictionary = preview_value
    if not _variant_to_bool(preview_data.get("enabled", false)):
        _show_placeholder(
            "俯瞰データはありますが現在は無効です。\nsnapshot[\"three_d_preview\"][\"enabled\"] を true にすると、GM用の簡易俯瞰が表示されます。"
        )
        return

    _placeholder_label.visible = false
    _viewport_container.visible = true
    _render_preview(preview_data)


func _build_ui() -> void:
    _status_label = Label.new()
    _status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
    add_child(_status_label)

    _placeholder_label = Label.new()
    _placeholder_label.custom_minimum_size = Vector2(0, 240)
    _placeholder_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    _placeholder_label.size_flags_vertical = Control.SIZE_EXPAND_FILL
    _placeholder_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
    _placeholder_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
    _placeholder_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
    add_child(_placeholder_label)

    _viewport_container = SubViewportContainer.new()
    _viewport_container.visible = false
    _viewport_container.custom_minimum_size = Vector2(0, 240)
    _viewport_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    _viewport_container.size_flags_vertical = Control.SIZE_EXPAND_FILL
    _viewport_container.stretch = true
    _viewport_container.mouse_filter = Control.MOUSE_FILTER_IGNORE
    add_child(_viewport_container)

    _viewport = SubViewport.new()
    _viewport.disable_3d = false
    _viewport.size = Vector2i(1280, 720)
    _viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
    _viewport.render_target_clear_mode = SubViewport.CLEAR_MODE_ALWAYS
    _viewport.transparent_bg = false
    _viewport_container.add_child(_viewport)

    _scene_root = Node3D.new()
    _viewport.add_child(_scene_root)

    var environment_node := WorldEnvironment.new()
    _environment = Environment.new()
    _environment.background_mode = Environment.BG_COLOR
    _environment.background_color = Color(0.08, 0.1, 0.14)
    _environment.ambient_light_color = Color(0.72, 0.76, 0.84)
    _environment.ambient_light_energy = 0.4
    environment_node.environment = _environment
    _scene_root.add_child(environment_node)

    _renderables_root = Node3D.new()
    _scene_root.add_child(_renderables_root)

    _floor = MeshInstance3D.new()
    _floor.mesh = BoxMesh.new()
    _floor.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
    var floor_material := StandardMaterial3D.new()
    floor_material.albedo_color = Color(0.3, 0.33, 0.38)
    floor_material.roughness = 0.95
    _floor.material_override = floor_material
    _scene_root.add_child(_floor)

    _light = DirectionalLight3D.new()
    _light.light_energy = 1.5
    _light.light_color = Color(1.0, 0.97, 0.92)
    _light.visible = false
    _scene_root.add_child(_light)
    _orient_light(DEFAULT_LIGHT_DIRECTION)

    _camera = Camera3D.new()
    _camera.current = true
    _camera.near = 0.1
    _camera.far = 200.0
    _camera.fov = 65.0
    _scene_root.add_child(_camera)
    _camera.position = DEFAULT_CAMERA_POSITION
    _camera.look_at(DEFAULT_CAMERA_TARGET, Vector3.UP)


func _show_placeholder(message: String) -> void:
    _viewport_container.visible = false
    _placeholder_label.visible = true
    _placeholder_label.text = message
    _status_label.text = "GM用俯瞰メモは未接続です"


func _render_preview(preview_data: Dictionary) -> void:
    var gravity_data := _coerce_dictionary(preview_data.get("gravity", {}))
    var lighting_data := _coerce_dictionary(preview_data.get("lighting", {}))
    var camera_data := _coerce_dictionary(preview_data.get("camera", {}))
    var floor_y := float(gravity_data.get("floor_y", 0.0))
    var normalized_renderables := _normalize_renderables(preview_data.get("renderables", []), floor_y)

    _apply_floor(floor_y, normalized_renderables)
    _apply_lighting(lighting_data)
    _rebuild_renderables(normalized_renderables)
    _update_camera(camera_data, normalized_renderables, floor_y)

    var lighting_enabled := _variant_to_bool(lighting_data.get("enabled", false))
    var shadows_enabled := lighting_enabled and _variant_to_bool(lighting_data.get("shadows_enabled", false))
    var gravity_enabled := _variant_to_bool(gravity_data.get("enabled", false))
    _status_label.text = "GM用俯瞰メモ | 描画対象 %d 件 | 光 %s | 影 %s | 重力 %s" % [
        normalized_renderables.size(),
        "有効" if lighting_enabled else "無効",
        "有効" if shadows_enabled else "無効",
        "有効" if gravity_enabled else "無効"
    ]


func _normalize_renderables(renderables_value: Variant, floor_y: float) -> Array:
    var normalized: Array = []
    if not (renderables_value is Array):
        return normalized

    var renderables: Array = renderables_value
    var layout_index := 0
    for renderable_value in renderables:
        if not (renderable_value is Dictionary):
            continue

        var renderable: Dictionary = renderable_value
        var visual_kind := _resolve_visual_kind(renderable)
        var size := _resolve_size(renderable, visual_kind)
        var default_position := _default_position(layout_index, size, floor_y)
        var position := _vector3_from_variant(
            renderable.get("position", renderable.get("translation", null)),
            default_position
        )
        var color := _resolve_color(renderable, visual_kind)
        normalized.append({
            "id": str(renderable.get("id", "renderable_%d" % layout_index)),
            "kind": visual_kind,
            "name": str(renderable.get("name", renderable.get("id", visual_kind.capitalize()))),
            "position": position,
            "size": size,
            "color": color
        })
        layout_index += 1

    return normalized


func _resolve_visual_kind(renderable: Dictionary) -> String:
    var kind := str(renderable.get("kind", renderable.get("type", renderable.get("name", "object")))).to_lower()
    var flags := _variant_to_string_array(renderable.get("flags", []))
    var flag_map: Dictionary = {}
    for flag in flags:
        flag_map[str(flag).to_lower()] = true

    if kind.find("gm") != -1 or kind.find("game_master") != -1 or flag_map.has("gm"):
        return "gm"
    if kind.find("character") != -1 or kind.find("agent") != -1 or kind.find("npc") != -1 or flag_map.has("character"):
        return "character"
    return "object"


func _resolve_size(renderable: Dictionary, visual_kind: String) -> Vector3:
    var default_size := Vector3(0.9, 0.9, 0.9)
    match visual_kind:
        "gm":
            default_size = Vector3(1.3, 2.1, 1.3)
        "character":
            default_size = Vector3(0.9, 1.8, 0.9)
        _:
            default_size = Vector3(0.9, 0.9, 0.9)
    return _vector3_from_variant(renderable.get("size", null), default_size)


func _resolve_color(renderable: Dictionary, visual_kind: String) -> Color:
    var default_color := Color(0.74, 0.78, 0.84)
    match visual_kind:
        "gm":
            default_color = Color(0.52, 0.38, 0.9)
        "character":
            default_color = Color(0.34, 0.68, 0.92)
        _:
            default_color = Color(0.84, 0.72, 0.55)
    return _color_from_variant(renderable.get("color", default_color), default_color)


func _default_position(index: int, size: Vector3, floor_y: float) -> Vector3:
    var column := index % 4
    var row := int(index / 4)
    return Vector3(float(column) * 2.4 - 3.6, floor_y + size.y * 0.5, float(row) * 2.6 - 1.3)


func _rebuild_renderables(normalized_renderables: Array) -> void:
    for child in _renderables_root.get_children():
        child.queue_free()

    for renderable_value in normalized_renderables:
        var renderable: Dictionary = renderable_value
        var mesh_instance := MeshInstance3D.new()
        var box_mesh := BoxMesh.new()
        box_mesh.size = renderable.get("size", Vector3.ONE)
        mesh_instance.mesh = box_mesh
        mesh_instance.position = renderable.get("position", Vector3.ZERO)
        mesh_instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON

        var material := StandardMaterial3D.new()
        material.albedo_color = renderable.get("color", Color.WHITE)
        material.roughness = 0.7
        mesh_instance.material_override = material
        _renderables_root.add_child(mesh_instance)


func _apply_floor(floor_y: float, normalized_renderables: Array) -> void:
    var extent := 10.0
    if not normalized_renderables.is_empty():
        var scene_metrics := _compute_scene_metrics(normalized_renderables)
        extent = max(10.0, float(scene_metrics.get("radius", 4.0)) * 3.2)

    var floor_mesh := _floor.mesh as BoxMesh
    if floor_mesh != null:
        floor_mesh.size = Vector3(extent, 0.2, extent)
    _floor.position = Vector3(0.0, floor_y - 0.1, 0.0)


func _apply_lighting(lighting_data: Dictionary) -> void:
    var enabled := _variant_to_bool(lighting_data.get("enabled", false))
    _light.visible = enabled
    _light.shadow_enabled = enabled and _variant_to_bool(lighting_data.get("shadows_enabled", false))
    _light.light_energy = float(lighting_data.get("intensity", lighting_data.get("energy", 1.5)))
    _light.light_color = _color_from_variant(lighting_data.get("color", Color(1.0, 0.97, 0.92)), Color(1.0, 0.97, 0.92))

    if lighting_data.has("light_rotation_degrees") or lighting_data.has("rotation_degrees"):
        _light.rotation_degrees = _vector3_from_variant(
            lighting_data.get("light_rotation_degrees", lighting_data.get("rotation_degrees")),
            Vector3(-50.0, -35.0, 0.0)
        )
        return

    var direction := _vector3_from_variant(
        lighting_data.get("direction", lighting_data.get("light_direction", DEFAULT_LIGHT_DIRECTION)),
        DEFAULT_LIGHT_DIRECTION
    )
    _orient_light(direction)


func _update_camera(camera_data: Dictionary, normalized_renderables: Array, floor_y: float) -> void:
    var scene_metrics := _compute_scene_metrics(normalized_renderables)
    var default_target: Vector3 = scene_metrics.get("center", Vector3(0.0, floor_y + 1.0, 0.0))
    var default_distance: float = max(7.5, float(scene_metrics.get("radius", 4.0)) * 2.7)

    var target := _vector3_from_variant(camera_data.get("target", camera_data.get("look_at", default_target)), default_target)
    var position := DEFAULT_CAMERA_POSITION

    if camera_data.has("position"):
        position = _vector3_from_variant(camera_data.get("position"), DEFAULT_CAMERA_POSITION)
    else:
        var yaw := deg_to_rad(float(camera_data.get("yaw_degrees", -42.0)))
        var pitch := deg_to_rad(float(camera_data.get("pitch_degrees", -25.0)))
        var distance := float(camera_data.get("distance", default_distance))
        var horizontal_distance := cos(pitch) * distance
        position = target + Vector3(
            cos(yaw) * horizontal_distance,
            sin(-pitch) * distance,
            sin(yaw) * horizontal_distance
        )

    if position.distance_to(target) < 0.25:
        position += Vector3(0.0, 1.0, 2.0)

    _camera.fov = float(camera_data.get("fov_degrees", camera_data.get("fov", 65.0)))
    _camera.position = position
    _camera.look_at(target, Vector3.UP)


func _compute_scene_metrics(normalized_renderables: Array) -> Dictionary:
    if normalized_renderables.is_empty():
        return {
            "center": DEFAULT_CAMERA_TARGET,
            "radius": 4.0
        }

    var center := Vector3.ZERO
    for renderable_value in normalized_renderables:
        center += renderable_value.get("position", Vector3.ZERO)
    center /= float(normalized_renderables.size())

    var radius := 4.0
    for renderable_value in normalized_renderables:
        var position: Vector3 = renderable_value.get("position", Vector3.ZERO)
        var size: Vector3 = renderable_value.get("size", Vector3.ONE)
        radius = max(radius, position.distance_to(center) + max(size.x, max(size.y, size.z)))

    return {
        "center": center,
        "radius": radius
    }


func _orient_light(direction: Vector3) -> void:
    var light_direction := direction
    if light_direction.length() <= 0.001:
        light_direction = DEFAULT_LIGHT_DIRECTION
    _light.position = -light_direction.normalized() * 10.0
    _light.look_at(Vector3.ZERO, Vector3.UP)


func _vector3_from_variant(value: Variant, default_value: Vector3) -> Vector3:
    if value is Vector3:
        return value
    if value is Dictionary:
        var data: Dictionary = value
        return Vector3(
            float(data.get("x", default_value.x)),
            float(data.get("y", default_value.y)),
            float(data.get("z", data.get("depth", default_value.z)))
        )
    if value is Array:
        var values: Array = value
        if values.size() >= 3:
            return Vector3(float(values[0]), float(values[1]), float(values[2]))
        if values.size() == 2:
            return Vector3(float(values[0]), default_value.y, float(values[1]))
    return default_value


func _color_from_variant(value: Variant, default_value: Color) -> Color:
    if value is Color:
        return value
    if value is String:
        return Color.from_string(String(value), default_value)
    if value is Array:
        var values: Array = value
        if values.size() >= 3:
            var alpha := float(values[3]) if values.size() >= 4 else 1.0
            return Color(float(values[0]), float(values[1]), float(values[2]), alpha)
    if value is Dictionary:
        var data: Dictionary = value
        return Color(
            float(data.get("r", default_value.r)),
            float(data.get("g", default_value.g)),
            float(data.get("b", default_value.b)),
            float(data.get("a", default_value.a))
        )
    return default_value


func _variant_to_bool(value: Variant, default_value: bool = false) -> bool:
    if value is bool:
        return value
    if value is int or value is float:
        return float(value) != 0.0
    if value is String:
        var normalized := String(value).strip_edges().to_lower()
        if normalized in ["1", "true", "yes", "on", "enabled"]:
            return true
        if normalized in ["0", "false", "no", "off", "disabled"]:
            return false
    return default_value


func _variant_to_string_array(value: Variant) -> Array:
    var values: Array = []
    if value is Array:
        for entry in value:
            var text := str(entry).strip_edges()
            if not text.is_empty():
                values.append(text)
        return values

    var text := str(value).strip_edges()
    if not text.is_empty() and text != "null":
        values.append(text)
    return values


func _coerce_dictionary(value: Variant) -> Dictionary:
    return value if value is Dictionary else {}
