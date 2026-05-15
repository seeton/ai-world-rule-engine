extends Node2D

var _life_ratio: float = 0.0
var _primary_color: Color = Color(1.0, 0.48, 0.27, 1.0)
var _accent_color: Color = Color(1.0, 0.89, 0.51, 1.0)


func apply_effect(effect: Dictionary, screen_position: Vector2) -> void:
	position = screen_position
	_life_ratio = clamp(float(effect.get("life_ratio", 0.0)), 0.0, 1.0)
	_primary_color = _color_from_variant(effect.get("color", "#ff7a45"), Color(1.0, 0.48, 0.27, 1.0))
	_accent_color = _color_from_variant(effect.get("accent_color", "#ffe082"), Color(1.0, 0.89, 0.51, 1.0))
	modulate.a = clamp(1.0 - _life_ratio, 0.0, 1.0)
	queue_redraw()


func _draw() -> void:
	var outer_radius := lerpf(18.0, 62.0, _life_ratio)
	var inner_radius := lerpf(4.0, 14.0, _life_ratio)
	var tip_radius := lerpf(3.0, 6.0, 1.0 - _life_ratio)
	for index in range(8):
		var angle := (TAU * float(index) / 8.0) + (_life_ratio * 0.45)
		var direction := Vector2.RIGHT.rotated(angle)
		draw_line(direction * inner_radius, direction * outer_radius, _primary_color, 3.0, true)
		draw_circle(direction * outer_radius, tip_radius, _accent_color)
	draw_circle(Vector2.ZERO, lerpf(7.0, 2.0, _life_ratio), _accent_color)


func _color_from_variant(value: Variant, default_value: Color) -> Color:
	if value is Color:
		return value
	if value is String:
		return Color.from_string(String(value), default_value)
	return default_value
