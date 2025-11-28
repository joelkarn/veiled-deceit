extends InteractableBase

## Item pickup - collectible item that adds to inventory

@export var item_id: String = "hammer"
@export var quantity: int = 1

var is_picked_up: bool = false

@onready var mesh_instance: Node3D = $ItemModel

func _ready() -> void:
	super._ready()
	_update_prompt()
	update_visibility()

func _update_prompt() -> void:
	# Load item data to get the proper name
	var item_data = InventoryManager.get_item_data(item_id)
	if item_data:
		interact_prompt = "Press E to pick up " + item_data.item_name
	else:
		interact_prompt = "Press E to pick up"

func interact(player: Node) -> void:
	# Only process on server
	if not multiplayer.is_server():
		return

	if is_picked_up:
		print("ItemPickup: Already picked up")
		return

	# Get player's peer ID
	var player_id = player.get("player_id")
	if player_id == null:
		print("ItemPickup: Player has no peer_id")
		return

	# Add item to player's inventory
	var success = InventoryManager.add_item(player_id, item_id, quantity)

	if success:
		print("ItemPickup: Player ", player_id, " picked up ", item_id)
		is_picked_up = true
		update_visibility()
		rpc("sync_pickup_state", true)
	else:
		print("ItemPickup: Failed to add item to inventory (full?)")

func update_visibility() -> void:
	if mesh_instance:
		mesh_instance.visible = not is_picked_up

@rpc("authority", "call_remote", "reliable")
func sync_pickup_state(picked_up: bool) -> void:
	is_picked_up = picked_up
	update_visibility()

# Send current state to a specific client (for late joiners)
func sync_state_to_client(peer_id: int) -> void:
	if multiplayer.is_server():
		rpc_id(peer_id, "sync_pickup_state", is_picked_up)

func can_interact() -> bool:
	return not is_picked_up

func has_been_interacted() -> bool:
	return is_picked_up
