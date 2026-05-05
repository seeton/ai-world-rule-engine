extends Node2D

var _gm_button: Button
var _clock_label: Label
var _world_state: Node = null
var _gm_ui_scene := preload("res://scripts/ui/gm_dialog.gd")


func _ready() -> void:
	_world_state = get_node("/root/WorldState")
	_build_ui()


func _process(delta: float) -> void:
	if _world_state != null:
		_world_state.advance_tick(delta)
		_update_clock_display()


func _build_ui() -> void:
	var canvas_layer := CanvasLayer.new()
	add_child(canvas_layer)

	_clock_label = Label.new()
	_clock_label.position = Vector2(1280, 20)
	_clock_label.add_theme_font_size_override("font_size", 20)
	_clock_label.add_theme_color_override("font_color", Color.WHITE)
	_clock_label.add_theme_color_override("font_outline_color", Color.BLACK)
	_clock_label.add_theme_constant_override("outline_size", 2)
	_clock_label.visible = false
	canvas_layer.add_child(_clock_label)

	_gm_button = Button.new()
	_gm_button.text = "GMと話す"
	_gm_button.position = Vector2(20, 20)
	_gm_button.custom_minimum_size = Vector2(120, 40)
	_gm_button.pressed.connect(_on_gm_button_pressed)
	canvas_layer.add_child(_gm_button)

	var bg := ColorRect.new()
	bg.color = Color(0.2, 0.3, 0.2, 1.0)
	bg.size = Vector2(1440, 900)
	add_child(bg)

	var center_label := Label.new()
	center_label.text = "2D世界シーン\n\n左上の「GMと話す」ボタンを押してください"
	center_label.position = Vector2(600, 400)
	center_label.add_theme_font_size_override("font_size", 24)
	center_label.add_theme_color_override("font_color", Color.WHITE)
	center_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_child(center_label)


func _update_clock_display() -> void:
	if _world_state == null:
		return

	var snapshot: Dictionary = _world_state.get_world_snapshot()
	var world_clock: Dictionary = snapshot.get("world_clock", {})

	if world_clock.is_empty():
		_clock_label.visible = false
		return

	var elapsed := float(world_clock.get("elapsed_seconds", 0.0))
	var ticks := int(world_clock.get("total_ticks", 0))

	_clock_label.text = "時刻: %.1f秒 (Tick: %d)" % [elapsed, ticks]
	_clock_label.visible = true


func _on_gm_button_pressed() -> void:
	var gm_ui := Control.new()
	gm_ui.set_script(_gm_ui_scene)
	gm_ui.closed.connect(_on_gm_ui_closed.bind(gm_ui))
	get_tree().root.add_child(gm_ui)
	_gm_button.visible = false


func _on_gm_ui_closed(gm_ui: Control) -> void:
	_gm_button.visible = true
