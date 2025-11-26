extends InteractableBase

## Shared chest - all players can deposit and withdraw items

@export var chest_size: int = 9  # Number of slots in the chest

# Chest inventory - shared among all players
# This is server-authoritative
var chest_inventory: Array = []

func _ready() -> void:
	super._ready()
	interact_prompt = "Press E to open chest"
	
	# Initialize empty chest inventory (server only)
	if multiplayer.is_server():
		for i in range(chest_size):
			chest_inventory.append({"item_id": "", "quantity": 0})

# Send current state to a specific client (for late joiners)
func sync_state_to_client(peer_id: int) -> void:
	if multiplayer.is_server():
		rpc_id(peer_id, "sync_chest_inventory", chest_inventory)

func interact(player: Node) -> void:
	# Only process on server
	if not multiplayer.is_server():
		return
	
	var player_id = player.get("player_id")
	if player_id == null:
		print("Chest: Player has no peer_id")
		return
	
	print("Chest: Player ", player_id, " opened chest")
	
	# Send chest inventory to the player who opened it
	if player_id == 1:  # Host (server)
		# Call locally for host
		open_chest_ui(chest_inventory)
	else:
		# Send to remote client
		rpc_id(player_id, "open_chest_ui", chest_inventory)

# Server: Add item to chest
func add_item_to_chest(item_id: String, quantity: int) -> bool:
	if not multiplayer.is_server():
		return false
	
	var item_data = InventoryManager.get_item_data(item_id)
	if not item_data:
		return false
	
	var max_stack = item_data.max_stack
	var remaining = quantity
	
	# Try to stack with existing items
	if max_stack > 1:
		for i in range(chest_inventory.size()):
			var slot = chest_inventory[i]
			if slot["item_id"] == item_id and slot["quantity"] < max_stack:
				var space = max_stack - slot["quantity"]
				var to_add = min(space, remaining)
				slot["quantity"] += to_add
				remaining -= to_add
				
				if remaining <= 0:
					break
	
	# Add to empty slots
	while remaining > 0:
		var empty_slot = _find_empty_slot()
		if empty_slot == -1:
			print("Chest: Chest is full")
			# Sync partial add
			rpc("sync_chest_inventory", chest_inventory)
			return false
		
		var to_add = min(remaining, max_stack)
		chest_inventory[empty_slot] = {"item_id": item_id, "quantity": to_add}
		remaining -= to_add
	
	# Sync to all clients
	rpc("sync_chest_inventory", chest_inventory)
	return true

# Server: Remove item from chest
func remove_item_from_chest(item_id: String, quantity: int) -> bool:
	if not multiplayer.is_server():
		return false
	
	var remaining = quantity
	
	# Remove from slots
	for i in range(chest_inventory.size()):
		var slot = chest_inventory[i]
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
		print("Chest: Not enough ", item_id, " in chest")
		return false
	
	# Sync to all clients
	rpc("sync_chest_inventory", chest_inventory)
	return true

func _find_empty_slot() -> int:
	for i in range(chest_inventory.size()):
		if chest_inventory[i]["item_id"] == "" or chest_inventory[i]["quantity"] <= 0:
			return i
	return -1

# RPC: Sync chest inventory to clients
@rpc("authority", "call_local", "reliable")
func sync_chest_inventory(inventory: Array) -> void:
	chest_inventory = inventory
	# Update UI if it's open
	var ui_manager = get_tree().current_scene.get_node_or_null("UIManager")
	if ui_manager and ui_manager.has_method("update_chest_ui"):
		ui_manager.update_chest_ui(inventory)

# RPC: Tell client to open chest UI
@rpc("authority", "call_remote", "reliable")
func open_chest_ui(inventory: Array) -> void:
	chest_inventory = inventory
	
	# Tell UI manager to show chest UI
	var ui_manager = get_tree().current_scene.get_node_or_null("UIManager")
	if ui_manager and ui_manager.has_method("show_chest_ui"):
		ui_manager.show_chest_ui(self, inventory)

# Called from client: Request to deposit item
@rpc("any_peer", "call_remote", "reliable")
func request_deposit_item(player_id: int, item_id: String, quantity: int) -> void:
	if not multiplayer.is_server():
		return
	
	# Check if player has the item
	var player_inventory = InventoryManager.get_inventory(player_id)
	var player_has = _count_item_in_inventory(player_inventory, item_id)
	
	if player_has < quantity:
		print("Chest: Player ", player_id, " doesn't have enough ", item_id)
		return
	
	# Remove from player inventory
	if InventoryManager.remove_item(player_id, item_id, quantity):
		# Add to chest
		if not add_item_to_chest(item_id, quantity):
			# Failed to add to chest, give back to player
			InventoryManager.add_item(player_id, item_id, quantity)
			print("Chest: Failed to add to chest, returned to player")
		else:
			print("Chest: Player ", player_id, " deposited ", quantity, "x ", item_id)

# Called from client: Request to withdraw item
@rpc("any_peer", "call_remote", "reliable")
func request_withdraw_item(player_id: int, item_id: String, quantity: int) -> void:
	if not multiplayer.is_server():
		return
	
	# Check if chest has the item
	var chest_has = _count_item_in_inventory(chest_inventory, item_id)
	
	if chest_has < quantity:
		print("Chest: Not enough ", item_id, " in chest")
		return
	
	# Remove from chest
	if remove_item_from_chest(item_id, quantity):
		# Add to player inventory
		if not InventoryManager.add_item(player_id, item_id, quantity):
			# Failed to add to player, put back in chest
			add_item_to_chest(item_id, quantity)
			print("Chest: Player inventory full, returned to chest")
		else:
			print("Chest: Player ", player_id, " withdrew ", quantity, "x ", item_id)

func _count_item_in_inventory(inventory: Array, item_id: String) -> int:
	var count = 0
	for slot in inventory:
		if slot["item_id"] == item_id:
			count += slot["quantity"]
	return count

func can_interact() -> bool:
	return true
