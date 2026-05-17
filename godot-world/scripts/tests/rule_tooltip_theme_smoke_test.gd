extends SceneTree

const RuleTooltipThemeScript = preload("res://scripts/ui/rule_tooltip_theme.gd")
const RuleTooltipPopupScript = preload("res://scripts/ui/rule_tooltip_popup.gd")


func _initialize() -> void:
	var exit_code := 0
	var failure_message := ""

	var popup := RuleTooltipPopupScript.new()
	root.add_child(popup)
	if not popup.has_method("show_tooltip"):
		exit_code = 1
		failure_message = "popup helper missing show_tooltip"
	else:
		popup.call("show_tooltip", "tooltip text", Vector2(32.0, 32.0), Vector2(800.0, 600.0))
		var tooltip_panel := RuleTooltipThemeScript.build_stylebox()
		if not (tooltip_panel is StyleBoxFlat):
			exit_code = 1
			failure_message = "tooltip panel stylebox was not a StyleBoxFlat"
		else:
			var style := tooltip_panel as StyleBoxFlat
			if style.bg_color.a < 0.999:
				exit_code = 1
				failure_message = "tooltip background was not opaque enough"
			elif style.border_width_left <= 0 or style.border_width_top <= 0:
				exit_code = 1
				failure_message = "tooltip border widths were not configured"
	if exit_code == 0:
		var theme := RuleTooltipThemeScript.build_theme()
		var fallback_panel := theme.get_stylebox("panel", "TooltipPanel")
		if not (fallback_panel is StyleBoxFlat):
			exit_code = 1
			failure_message = "fallback tooltip theme panel stylebox was not a StyleBoxFlat"
		elif (fallback_panel as StyleBoxFlat).bg_color.a < 0.999:
			exit_code = 1
			failure_message = "fallback tooltip theme alpha was not opaque enough"

	if exit_code != 0:
		push_error(failure_message)
	else:
		print("[smoke] rule_tooltip_theme smoke test passed")
	quit(exit_code)
