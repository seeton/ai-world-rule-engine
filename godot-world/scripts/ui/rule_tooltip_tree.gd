extends Tree

const RuleTooltipPopupScript = preload("res://scripts/ui/rule_tooltip_popup.gd")

var _tooltip_popup: PopupPanel = null
var _hovered_item: TreeItem = null


func _ready() -> void:
	mouse_exited.connect(_on_mouse_exited)
	_tooltip_popup = RuleTooltipPopupScript.new()
	add_child(_tooltip_popup)


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		var motion := event as InputEventMouseMotion
		_update_tooltip_for_position(motion.position)
	elif event is InputEventMouseButton:
		var button_event := event as InputEventMouseButton
		if button_event.pressed:
			_hide_tooltip()


func _update_tooltip_for_position(local_position: Vector2) -> void:
	if _tooltip_popup == null:
		return
	var item := get_item_at_position(local_position)
	if item == null:
		_hide_tooltip()
		return
	var tooltip_text := String(item.get_metadata(1) if item.get_metadata(1) != null else "")
	if tooltip_text.is_empty():
		_hide_tooltip()
		return
	_hovered_item = item
	_tooltip_popup.show_tooltip(
		tooltip_text,
		get_viewport().get_mouse_position(),
		get_viewport_rect().size
	)


func _on_mouse_exited() -> void:
	_hide_tooltip()


func _hide_tooltip() -> void:
	_hovered_item = null
	if _tooltip_popup != null:
		(_tooltip_popup as Object).call("hide_tooltip")
