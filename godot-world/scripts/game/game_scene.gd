extends Node2D

signal gm_interaction_requested

@onready var player: CharacterBody2D = $Player
@onready var gm: Node2D = $GameMaster
@onready var interaction_hint: Label = $InteractionHint

const INTERACTION_DISTANCE: float = 80.0

func _ready() -> void:
	interaction_hint.visible = false
	if gm.has_signal("interaction_triggered"):
		gm.interaction_triggered.connect(_on_gm_interaction)

func _process(_delta: float) -> void:
	_update_interaction_hint()

func _update_interaction_hint() -> void:
	if not player or not gm:
		return
	
	var distance: float = player.global_position.distance_to(gm.global_position)
	var in_range: bool = distance < INTERACTION_DISTANCE
	
	interaction_hint.visible = in_range
	
	if in_range:
		interaction_hint.global_position = gm.global_position + Vector2(-40, -60)

func _on_gm_interaction() -> void:
	gm_interaction_requested.emit()
