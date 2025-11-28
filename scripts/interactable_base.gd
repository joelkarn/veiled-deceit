extends Area3D
class_name InteractableBase

## Base class for all interactable objects (bushes, chests, NPCs, etc.)

signal interacted(player: Node)

@export var interact_prompt: String = "Press E to interact"
@export var interact_distance: float = 3.0
@export var can_interact_multiple_times: bool = true

var is_player_nearby: bool = false
var nearby_player: Node = null

func _ready() -> void:
	# Set up collision - don't override collision_layer (set in scene)
	# collision_layer should be 4 (interactable layer)
	collision_mask = 0  # Don't collide with anything
	monitoring = false  # We don't need to monitor (player will detect us)
	monitorable = true  # Player can detect us

	# Connect signals (though we won't use them with the sphere cast approach)
	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)

func _on_body_entered(body: Node) -> void:
	# Check if it's a player
	if body.has_method("interact_with"):
		is_player_nearby = true
		nearby_player = body
		show_prompt()

func _on_body_exited(body: Node) -> void:
	if body == nearby_player:
		is_player_nearby = false
		nearby_player = null
		hide_prompt()

func show_prompt() -> void:
	# Future: Show UI prompt above object
	pass

func hide_prompt() -> void:
	# Future: Hide UI prompt
	pass

## Called when player presses interact key
## Override this in subclasses
func interact(player: Node) -> void:
	print("InteractableBase: interact() called by ", player.name)
	interacted.emit(player)

## Check if this object can be interacted with
func can_interact() -> bool:
	return can_interact_multiple_times or not has_been_interacted()

## Override in subclasses to track interaction state
func has_been_interacted() -> bool:
	return false
