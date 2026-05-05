extends Node2D

signal gm_interaction_requested

@onready var player: CharacterBody2D = $Player
@onready var gm: Node2D = $GameMaster
@onready var interaction_hint: Label = $InteractionHint

const INTERACTION_DISTANCE: float = 80.0
const ACTIVE_LANGUAGE := "ja"
const UI_TEXT := {
	"ja": {
		"hint": "クリックして話す",
		"clock_prefix": "時計 ",
		"player_label": "プレイヤー",
		"gm_label": "ゲームマスター"
	},
	"en": {
		"hint": "Click to talk",
		"clock_prefix": "Clock ",
		"player_label": "Player",
		"gm_label": "Game Master"
	}
}

var _world_state: Node = null
var _clock_layer: CanvasLayer
var _clock_label: Label
var _gm_dialog: Control = null

func _ready() -> void:
	_world_state = get_node_or_null("/root/WorldState")
	interaction_hint.visible = false
	interaction_hint.text = _text("hint")
	if gm.has_signal("interaction_triggered"):
		gm.interaction_triggered.connect(_on_gm_interaction)
	_setup_clock_ui()
	_update_nameplates()

func _process(delta: float) -> void:
	if _world_state != null and _world_state.has_method("advance_tick"):
		_world_state.call("advance_tick", delta)
	_update_interaction_hint()
	_update_clock()

func _update_interaction_hint() -> void:
	if not player or not gm:
		return

	var in_range := _is_player_in_range()
	interaction_hint.visible = in_range and _gm_dialog == null

	if in_range:
		interaction_hint.global_position = gm.global_position + Vector2(-40, -60)

func _on_gm_interaction() -> void:
	if not _is_player_in_range() or _gm_dialog != null:
		return

	gm_interaction_requested.emit()
	player.set_physics_process(false)
	_gm_dialog = Control.new()
	_gm_dialog.set_script(load("res://scripts/ui/gm_dialog.gd"))
	_gm_dialog.closed.connect(_on_gm_dialog_closed)
	get_tree().root.add_child(_gm_dialog)


func _on_gm_dialog_closed() -> void:
	player.set_physics_process(true)
	_gm_dialog = null
	_update_clock()


func _is_player_in_range() -> bool:
	return player.global_position.distance_to(gm.global_position) < INTERACTION_DISTANCE


func _setup_clock_ui() -> void:
	_clock_layer = CanvasLayer.new()
	add_child(_clock_layer)

	_clock_label = Label.new()
	_clock_label.position = Vector2(980, 16)
	_clock_label.size = Vector2(280, 28)
	_clock_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_clock_label.add_theme_font_size_override("font_size", 22)
	_clock_label.add_theme_color_override("font_color", Color.BLACK)
	_clock_label.visible = false
	_clock_layer.add_child(_clock_label)


func _update_clock() -> void:
	if _clock_label == null or _gm_dialog != null:
		_clock_label.visible = false
		return
	if _world_state == null or not _world_state.has_method("get_world_snapshot"):
		_clock_label.visible = false
		return

	var snapshot = _world_state.call("get_world_snapshot")
	if not (snapshot is Dictionary):
		_clock_label.visible = false
		return

	var clock: Dictionary = snapshot.get("clock", {})
	var visible := bool(clock.get("visible", false))
	_clock_label.visible = visible
	if visible:
		_clock_label.text = "%s%s" % [_text("clock_prefix"), str(clock.get("formatted", ""))]


func _update_nameplates() -> void:
	var player_label := $Player/Label as Label
	var gm_label := $GameMaster/Label as Label
	player_label.text = _text("player_label")
	gm_label.text = _text("gm_label")


func _text(key: String) -> String:
	var table: Dictionary = UI_TEXT.get(ACTIVE_LANGUAGE, UI_TEXT["ja"])
	return String(table.get(key, key))
