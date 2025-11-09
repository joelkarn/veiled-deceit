extends Node

## Server-authoritative inventory manager for multiplayer
## Manages inventories for all connected players

signal inventory_updated(peer_id: int)
signal item_added(peer_id: int, item_id: String, quantity: int)
signal item_removed(peer_id: int, item_id: String, quantity: int)

const TOOLBAR_SLOTS = 9  ## Number of slots in the toolbar

## Dictionary of all inventories: { peer_id: [slot_data_array] }
## slot_data = { "item_id": String, "quantity": int }
var player_inventories: Dictionary = {}

## Item database - loaded at runtime
var item_database: Dictionary = {}

func _ready() -> void:
	# Load all item resources
	_load_item_database()
	
	# Connect to multiplayer signals if available
	if multiplayer:
		multiplayer.peer_disconnected.connect(_on_peer_disconnected)

## Load all item resources from the items folder
func _load_item_database() -> void:
	# For now, we'll register items manually
	# In the future, you could scan a directory for .tres files
	print("InventoryManager: Item database loaded")

## Initialize inventory for a new player
func initialize_player_inventory(peer_id: int) -> void:
	if player_inventories.has(peer_id):
		print("InventoryManager: Player ", peer_id, " inventory already exists")
		return
	
	# Create empty inventory with TOOLBAR_SLOTS slots
	var inventory = []
	for i in range(TOOLBAR_SLOTS):
		inventory.append({"item_id": "", "quantity": 0})
	
	player_inventories[peer_id] = inventory
	print("InventoryManager: Initialized inventory for player ", peer_id)
	
	# If we're the server, sync to the new client
	if multiplayer.is_server():
		rpc_id(peer_id, "sync_full_inventory", peer_id, inventory)

## Get a player's inventory
func get_inventory(peer_id: int) -> Array:
	if not player_inventories.has(peer_id):
		initialize_player_inventory(peer_id)
	return player_inventories[peer_id]

## Try to add an item to a player's inventory
## Returns true if successful, false if inventory is full
func add_item(peer_id: int, item_id: String, quantity: int = 1) -> bool:
	if not multiplayer.is_server():
		# Client requests server to add item
		rpc_id(1, "request_add_item", peer_id, item_id, quantity)
		return false  # Will be confirmed by server
	
	return _add_item_internal(peer_id, item_id, quantity)

## Internal method to add item (server only)
func _add_item_internal(peer_id: int, item_id: String, quantity: int) -> bool:
	var inventory = get_inventory(peer_id)
	var item_data = get_item_data(item_id)
	
	if not item_data:
		push_error("InventoryManager: Item not found: " + item_id)
		return false
	
	var max_stack = item_data.max_stack
	var remaining = quantity
	
	# First, try to stack with existing items
	if max_stack > 1:
		for i in range(inventory.size()):
			var slot = inventory[i]
			if slot["item_id"] == item_id and slot["quantity"] < max_stack:
				var space = max_stack - slot["quantity"]
				var to_add = min(space, remaining)
				slot["quantity"] += to_add
				remaining -= to_add
				
				if remaining <= 0:
					break
	
	# Then, try to add to empty slots
	while remaining > 0:
		var empty_slot_index = _find_empty_slot(inventory)
		if empty_slot_index == -1:
			print("InventoryManager: Inventory full for player ", peer_id)
			# Sync partial add
			rpc("sync_full_inventory", peer_id, inventory)
			inventory_updated.emit(peer_id)
			return false
		
		var to_add = min(remaining, max_stack)
		inventory[empty_slot_index] = {"item_id": item_id, "quantity": to_add}
		remaining -= to_add
	
	# Sync to all clients
	rpc("sync_full_inventory", peer_id, inventory)
	item_added.emit(peer_id, item_id, quantity)
	inventory_updated.emit(peer_id)
	
	return true

## Remove an item from inventory
func remove_item(peer_id: int, item_id: String, quantity: int = 1) -> bool:
	if not multiplayer.is_server():
		rpc_id(1, "request_remove_item", peer_id, item_id, quantity)
		return false
	
	return _remove_item_internal(peer_id, item_id, quantity)

## Internal method to remove item (server only)
func _remove_item_internal(peer_id: int, item_id: String, quantity: int) -> bool:
	var inventory = get_inventory(peer_id)
	var remaining = quantity
	
	# Remove from slots with this item
	for i in range(inventory.size()):
		var slot = inventory[i]
		if slot["item_id"] == item_id and slot["quantity"] > 0:
			var to_remove = min(slot["quantity"], remaining)
			slot["quantity"] -= to_remove
			remaining -= to_remove
			
			# Clear slot if empty
			if slot["quantity"] <= 0:
				slot["item_id"] = ""
				slot["quantity"] = 0
			
			if remaining <= 0:
				break
	
	if remaining > 0:
		print("InventoryManager: Not enough ", item_id, " to remove")
		return false
	
	# Sync to all clients
	rpc("sync_full_inventory", peer_id, inventory)
	item_removed.emit(peer_id, item_id, quantity)
	inventory_updated.emit(peer_id)
	
	return true

## Find first empty slot index, or -1 if full
func _find_empty_slot(inventory: Array) -> int:
	for i in range(inventory.size()):
		if inventory[i]["item_id"] == "" or inventory[i]["quantity"] <= 0:
			return i
	return -1

## Get item data from database
func get_item_data(item_id: String) -> ItemData:
	if item_database.has(item_id):
		return item_database[item_id]
	
	# Try to load from resources folder
	var path = "res://resources/items/" + item_id + ".tres"
	if ResourceLoader.exists(path):
		var item = ResourceLoader.load(path)
		item_database[item_id] = item
		return item
	
	return null

## Register an item in the database (for manual registration)
func register_item(item_data: ItemData) -> void:
	if item_data and item_data.item_id != "":
		item_database[item_data.item_id] = item_data
		print("InventoryManager: Registered item: ", item_data.item_id)

## Client requests to add item
@rpc("any_peer", "call_remote", "reliable")
func request_add_item(peer_id: int, item_id: String, quantity: int) -> void:
	if not multiplayer.is_server():
		return
	_add_item_internal(peer_id, item_id, quantity)

## Client requests to remove item
@rpc("any_peer", "call_remote", "reliable")
func request_remove_item(peer_id: int, item_id: String, quantity: int) -> void:
	if not multiplayer.is_server():
		return
	_remove_item_internal(peer_id, item_id, quantity)

## Sync full inventory to clients
@rpc("authority", "call_local", "reliable")
func sync_full_inventory(peer_id: int, inventory: Array) -> void:
	player_inventories[peer_id] = inventory
	inventory_updated.emit(peer_id)

## Clean up inventory when player disconnects
func _on_peer_disconnected(peer_id: int) -> void:
	# Keep inventory in memory for potential reconnection
	# In a real game, you'd save this to a database
	print("InventoryManager: Player ", peer_id, " disconnected (inventory preserved)")
	
	# Optional: Remove inventory after a timeout
	# await get_tree().create_timer(300.0).timeout  # 5 minutes
	# player_inventories.erase(peer_id)

## Use an item from inventory
func use_item(peer_id: int, slot_index: int) -> bool:
	if not multiplayer.is_server():
		rpc_id(1, "request_use_item", peer_id, slot_index)
		return false
	
	return _use_item_internal(peer_id, slot_index)

## Internal method to use item (server only)
func _use_item_internal(peer_id: int, slot_index: int) -> bool:
	var inventory = get_inventory(peer_id)
	if slot_index < 0 or slot_index >= inventory.size():
		return false
	
	var slot = inventory[slot_index]
	if slot["item_id"] == "" or slot["quantity"] <= 0:
		return false
	
	var item_data = get_item_data(slot["item_id"])
	if not item_data:
		return false
	
	# Get player node
	var player = get_tree().current_scene.get_node_or_null("Player_" + str(peer_id))
	if not player:
		return false
	
	# Use the item
	var success = item_data.use_item(player)
	
	if success:
		# Remove one from inventory
		_remove_item_internal(peer_id, slot["item_id"], 1)
		print("InventoryManager: Player ", peer_id, " used ", item_data.item_name)
	
	return success

## Client requests to use item
@rpc("any_peer", "call_remote", "reliable")
func request_use_item(peer_id: int, slot_index: int) -> void:
	if not multiplayer.is_server():
		return
	_use_item_internal(peer_id, slot_index)
