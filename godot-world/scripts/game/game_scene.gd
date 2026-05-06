extends Node2D

signal gm_interaction_requested

@onready var player: CharacterBody2D = $Player
@onready var gm: Node2D = $GameMaster
@onready var interaction_hint: Label = $InteractionHint

const INTERACTION_DISTANCE: float = 80.0

var _is_hovering_gm: bool = false

func _ready() -> void:
	interaction_hint.visible = false
	interaction_hint.modulate.a = 0.0
	if gm.has_signal("interaction_triggered"):
		gm.interaction_triggered.connect(_on_gm_interaction)
	if gm.has_signal("hover_changed"):
		gm.hover_changed.connect(_on_gm_hover_changed)

func _process(delta: float) -> void:
	_update_interaction_hint(delta)

func _update_interaction_hint(delta: float) -> void:
	if not player or not gm:
		return
	
	var distance: float = player.global_position.distance_to(gm.global_position)
	var in_range: bool = distance < INTERACTION_DISTANCE
	var should_show: bool = in_range or _is_hovering_gm
	
	interaction_hint.visible = should_show
	
	if should_show:
		interaction_hint.global_position = gm.global_position + Vector2(-50, -60)
		interaction_hint.modulate.a = move_toward(interaction_hint.modulate.a, 1.0, delta * 5.0)
	else:
		interaction_hint.modulate.a = move_toward(interaction_hint.modulate.a, 0.0, delta * 8.0)

func _on_gm_interaction() -> void:
	gm_interaction_requested.emit()

func _on_gm_hover_changed(is_hovering: bool) -> void:
	_is_hovering_gm = is_hovering
