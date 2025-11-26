extends Control

## Toolbar UI - displays player's inventory slots at bottom of screen

@onready var slots_container: HBoxContainer = $Panel/MarginContainer/HBoxContainer

var slot_scenes: Array[Node] = []
var player_id: int = 0
var is_initialized: bool = false
var selected_slot: int = 0  # Currently selected slot (0-8)

func _ready() -> void:
	# Initialize slots immediately
	_create_slots()

	# Connect to inventory updates
	if InventoryManager:
		InventoryManager.inventory_updated.connect(_on_inventory_updated)
		print("Toolbar: Connected to InventoryManager inventory_updated signal")
	else:
		push_error("Toolbar: InventoryManager not found!")

	# Connect to multiplayer signals to detect when we get our peer ID
	if multiplayer:
		multiplayer.connected_to_server.connect(_on_connected_to_server)

	# Try to initialize immediately if we're already connected
	_try_initialize()

func _try_initialize() -> void:
	# Wait for multiplayer to be ready
	await get_tree().process_frame

	# Get local player's peer ID
	if multiplayer and multiplayer.multiplayer_peer:
		var new_player_id = multiplayer.get_unique_id()
		if new_player_id > 0 and new_player_id != player_id:
			# Player ID changed (client connected to server)
			var old_player_id = player_id
			player_id = new_player_id
			is_initialized = true
			print("Toolbar: Player ID updated from ", old_player_id, " to ", player_id)

			# Request initial sync with correct player ID
			if InventoryManager:
				InventoryManager.initialize_player_inventory(player_id)
				_refresh_display()
		elif new_player_id > 0 and not is_initialized:
			# First initialization (host)
			player_id = new_player_id
			is_initialized = true
			print("Toolbar: Initialized for player_id ", player_id)

			# Request initial sync
			if InventoryManager:
				InventoryManager.initialize_player_inventory(player_id)
				_refresh_display()

func _on_connected_to_server() -> void:
	# Client just connected, get the real peer ID
	print("Toolbar: Connected to server, updating player_id")
	_try_initialize()

func _create_slots() -> void:
	if not slots_container:
		push_error("Toolbar: slots_container not found!")
		return

	# Clear existing slots
	for child in slots_container.get_children():
		child.queue_free()
	slot_scenes.clear()

	# Create slots
	var slot_scene = preload("res://scenes/ui/inventory_slot.tscn")
	for i in range(InventoryManager.TOOLBAR_SLOTS):
		var slot = slot_scene.instantiate()
		slot.slot_index = i
		slot.slot_clicked.connect(_on_slot_clicked)
		slot.slot_right_clicked.connect(_on_slot_right_clicked)
		slots_container.add_child(slot)
		slot_scenes.append(slot)

	# Highlight first slot by default
	_update_slot_highlight()

func _on_inventory_updated(peer_id: int) -> void:
	# If we don't have a player_id yet, try to initialize
	if player_id == 0 and not is_initialized:
		_try_initialize()

	# Only update if it's our inventory
	if peer_id == player_id:
		_refresh_display()

func _refresh_display() -> void:
	var inventory = InventoryManager.get_inventory(player_id)

	for i in range(min(inventory.size(), slot_scenes.size())):
		var slot_data = inventory[i]
		var slot_ui = slot_scenes[i]

		if slot_ui and slot_ui.has_method("set_item"):
			slot_ui.set_item(slot_data.get("item_id", ""), slot_data.get("quantity", 0))

	# Update highlight after refreshing
	_update_slot_highlight()

func _on_slot_clicked(slot_index: int) -> void:
	# Select this slot
	select_slot(slot_index)

func _on_slot_right_clicked(slot_index: int) -> void:
	# Use/consume item in clicked slot
	InventoryManager.use_item(player_id, slot_index)

func select_slot(slot_index: int) -> void:
	if slot_index < 0 or slot_index >= slot_scenes.size():
		return

	selected_slot = slot_index
	_update_slot_highlight()

func _update_slot_highlight() -> void:
	# Update visual highlight on selected slot
	for i in range(slot_scenes.size()):
		var slot = slot_scenes[i]
		if slot and slot.has_method("set_selected"):
			slot.set_selected(i == selected_slot)
		elif slot:
			# Fallback: Use modulate for highlighting
			if i == selected_slot:
				slot.modulate = Color(1.2, 1.2, 1.2, 1.0)  # Brighter
			else:
				slot.modulate = Color(1.0, 1.0, 1.0, 1.0)  # Normal

func use_selected_slot() -> void:
	# Use the currently selected slot
	InventoryManager.use_item(player_id, selected_slot)

## Handle keyboard and mouse input for slot selection
func _input(event: InputEvent) -> void:
	if not visible:
		return

	# Don't process if menu is open
	var ui_manager = get_tree().current_scene.get_node_or_null("UIManager")
	if ui_manager and ui_manager.is_menu_active():
		return

	# Mouse wheel to scroll through slots
	if event is InputEventMouseButton:
		if event.pressed:
			if event.button_index == MOUSE_BUTTON_WHEEL_UP:
				# Scroll left (previous slot)
				select_slot((selected_slot - 1 + slot_scenes.size()) % slot_scenes.size())
				accept_event()
			elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
				# Scroll right (next slot)
				select_slot((selected_slot + 1) % slot_scenes.size())
				accept_event()
			elif event.button_index == MOUSE_BUTTON_RIGHT:
				# Right-click anywhere to use selected slot
				use_selected_slot()
				accept_event()

	# Number keys 1-9 to select specific slots
	if event is InputEventKey and event.pressed:
		var key_code = event.keycode
		if key_code >= KEY_1 and key_code <= KEY_9:
			var slot_index = key_code - KEY_1
			if slot_index < slot_scenes.size():
				select_slot(slot_index)
				accept_event()
