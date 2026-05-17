extends PopupPanel

const RuleTooltipThemeScript = preload("res://scripts/ui/rule_tooltip_theme.gd")
const OFFSET := Vector2(18.0, 20.0)

var _label: Label = null


func _ready() -> void:
	add_theme_stylebox_override("panel", RuleTooltipThemeScript.build_stylebox())
	_label = Label.new()
	_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_label.custom_minimum_size = Vector2(320.0, 0.0)
	_label.add_theme_color_override("font_color", Color(0.96, 0.97, 1.0, 1.0))
	_label.add_theme_color_override("font_shadow_color", Color(0.0, 0.0, 0.0, 0.0))
	_label.add_theme_font_size_override("font_size", 13)
	_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_label)
	hide()


func show_tooltip(text: String, mouse_position: Vector2, viewport_size: Vector2) -> void:
	if _label == null or text.is_empty():
		hide()
		return

	_label.text = text
	reset_size()
	var tooltip_size := size
	var target_position := mouse_position + OFFSET
	if tooltip_size.x > 0.0 and target_position.x + tooltip_size.x > viewport_size.x - 8.0:
		target_position.x = maxf(8.0, mouse_position.x - tooltip_size.x - 12.0)
	if tooltip_size.y > 0.0 and target_position.y + tooltip_size.y > viewport_size.y - 8.0:
		target_position.y = maxf(8.0, mouse_position.y - tooltip_size.y - 12.0)
	position = Vector2i(round(target_position.x), round(target_position.y))
	popup()


func hide_tooltip() -> void:
	hide()
