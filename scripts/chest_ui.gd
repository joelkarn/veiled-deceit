extends Control

## Chest UI - displays chest and player inventory for item transfer

var chest_node: Node = null
var player_id: int = 0
var chest_inventory: Array = []
var player_inventory: Array = []

@onready var chest_grid: GridContainer = $Panel/VBoxContainer/ChestInventory
@onready var player_grid: GridContainer = $Panel/VBoxContainer/PlayerInventory
@onready var close_button: Button = $Panel/VBoxContainer/CloseButton

func _ready() -> void:
	visible = false
	close_button.pressed.connect(_on_close_button_pressed)

	# Listen for inventory updates
	if InventoryManager:
		InventoryManager.inventory_updated.connect(_on_inventory_updated)

func _input(event: InputEvent) -> void:
	if not visible:
		return

	if event.is_action_pressed("ui_cancel"):
		close_ui()
		get_viewport().set_input_as_handled()

func show_chest(chest: Node, chest_inv: Array) -> void:
	chest_node = chest
	chest_inventory = chest_inv
	player_id = multiplayer.get_unique_id()
	if InventoryManager:
		player_inventory = InventoryManager.get_inventory(player_id)

	visible = true

	# Release mouse for UI interaction
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

	_refresh_ui()

func close_ui() -> void:
	visible = false
	chest_node = null

	# Re-capture mouse
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

func _refresh_ui() -> void:
	_populate_grid(chest_grid, chest_inventory, true)
	_populate_grid(player_grid, player_inventory, false)

func _populate_grid(grid: GridContainer, inventory: Array, is_chest: bool) -> void:
	# Clear existing slots
	for child in grid.get_children():
		child.queue_free()

	# Create slots
	for i in range(inventory.size()):
		var slot_data = inventory[i]
		var slot_button = Button.new()
		slot_button.custom_minimum_size = Vector2(60, 60)

		# Display item info
		if slot_data["item_id"] != "" and slot_data["quantity"] > 0:
			var item_data = InventoryManager.get_item_data(slot_data["item_id"]) if InventoryManager else null
			if item_data:
				slot_button.text = item_data.item_name + "\nx" + str(slot_data["quantity"])
			else:
				slot_button.text = slot_data["item_id"] + "\nx" + str(slot_data["quantity"])

			# Connect click handler
			if is_chest:
				slot_button.pressed.connect(_on_chest_slot_clicked.bind(slot_data["item_id"], slot_data["quantity"]))
			else:
				slot_button.pressed.connect(_on_player_slot_clicked.bind(slot_data["item_id"], slot_data["quantity"]))
		else:
			slot_button.text = "Empty"
			slot_button.disabled = true

		grid.add_child(slot_button)

func _on_chest_slot_clicked(item_id: String, quantity: int) -> void:
	# Withdraw from chest (take 1 item, or all if shift-clicked)
	var amount = quantity if Input.is_key_pressed(KEY_SHIFT) else 1

	if chest_node and chest_node.has_method("request_withdraw_item"):
		if multiplayer.is_server():
			# Host: call directly
			chest_node.request_withdraw_item(player_id, item_id, amount)
		else:
			# Client: send RPC to server
			chest_node.rpc_id(1, "request_withdraw_item", player_id, item_id, amount)

func _on_player_slot_clicked(item_id: String, quantity: int) -> void:
	# Deposit to chest (deposit 1 item, or all if shift-clicked)
	var amount = quantity if Input.is_key_pressed(KEY_SHIFT) else 1

	if chest_node and chest_node.has_method("request_deposit_item"):
		if multiplayer.is_server():
			# Host: call directly
			chest_node.request_deposit_item(player_id, item_id, amount)
		else:
			# Client: send RPC to server
			chest_node.rpc_id(1, "request_deposit_item", player_id, item_id, amount)

func _on_close_button_pressed() -> void:
	close_ui()

func _on_inventory_updated(peer_id: int) -> void:
	# Refresh UI if it's our inventory or we're viewing the chest
	if visible and peer_id == player_id:
		if InventoryManager:
			player_inventory = InventoryManager.get_inventory(player_id)
			_refresh_ui()

func update_chest_inventory(inventory: Array) -> void:
	if visible:
		chest_inventory = inventory
		_refresh_ui()
