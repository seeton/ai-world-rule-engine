class_name RuleTooltipTheme
extends RefCounted


static func build_theme() -> Theme:
	var theme := Theme.new()
	theme.set_stylebox("panel", "TooltipPanel", build_stylebox())
	theme.set_color("font_color", "TooltipLabel", Color(0.96, 0.97, 1.0, 1.0))
	theme.set_color("font_shadow_color", "TooltipLabel", Color(0.0, 0.0, 0.0, 0.0))
	theme.set_constant("shadow_outline_size", "TooltipLabel", 0)
	theme.set_font_size("font_size", "TooltipLabel", 13)

	return theme


static func build_stylebox() -> StyleBoxFlat:
	var tooltip_panel := StyleBoxFlat.new()
	tooltip_panel.draw_center = true
	tooltip_panel.bg_color = Color(0.03, 0.05, 0.09, 1.0)
	tooltip_panel.border_width_left = 2
	tooltip_panel.border_width_top = 2
	tooltip_panel.border_width_right = 2
	tooltip_panel.border_width_bottom = 2
	tooltip_panel.border_color = Color(0.96, 0.84, 0.48, 1.0)
	tooltip_panel.corner_radius_top_left = 10
	tooltip_panel.corner_radius_top_right = 10
	tooltip_panel.corner_radius_bottom_left = 10
	tooltip_panel.corner_radius_bottom_right = 10
	tooltip_panel.content_margin_left = 12
	tooltip_panel.content_margin_top = 10
	tooltip_panel.content_margin_right = 12
	tooltip_panel.content_margin_bottom = 10
	return tooltip_panel
