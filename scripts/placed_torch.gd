extends InteractableBase

## Placed torch - can be picked up by interacting with it

var is_picked_up: bool = false

@onready var torch_light: OmniLight3D = $TorchLight
@onready var torch_model: Node3D = $TorchModel

func _ready() -> void:
	super._ready()
	interact_prompt = "Press E to pick up torch"
	can_interact_multiple_times = false

func interact(player: Node) -> void:
	# Only process on server
	if not multiplayer.is_server():
		return

	if is_picked_up:
		return

	# Get player's peer ID
	var player_id = player.get("player_id")
	if player_id == null:
		return

	# Add torch back to player's inventory
	var success = InventoryManager.add_item(player_id, "torch", 1)

	if success:
		print("PlacedTorch: Player ", player_id, " picked up torch")
		is_picked_up = true
		# Remove the placed torch from the scene
		rpc("remove_placed_torch")
		queue_free()
	else:
		print("PlacedTorch: Failed to add torch to inventory (full?)")

@rpc("authority", "call_remote", "reliable")
func remove_placed_torch() -> void:
	queue_free()

func can_interact() -> bool:
	return not is_picked_up

func has_been_interacted() -> bool:
	return is_picked_up
