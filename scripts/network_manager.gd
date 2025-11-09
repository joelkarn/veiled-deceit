extends Node

# Network Manager - Handles multiplayer connection and player spawning

const PORT = 7777
const MAX_PLAYERS = 5

# Flag to track if we're shutting down (prevents crashes during cleanup)
var is_shutting_down: bool = false

# Spawn points for players (5 locations)
var spawn_points = [
	Vector3(0, 0, 0),
	Vector3(10, 0, 0),
	Vector3(-10, 0, 0),
	Vector3(0, 0, 10),
	Vector3(0, 0, -10)
]

@onready var player_scene = load("res://scenes/player.tscn")

func _ready() -> void:
	# Connect multiplayer signals
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	multiplayer.connected_to_server.connect(_on_connected_to_server)
	multiplayer.connection_failed.connect(_on_connection_failed)
	multiplayer.server_disconnected.connect(_on_server_disconnected)
	
	print("NetworkManager ready! Use lobby UI to host or join.")

# Host: Start server
func host_game() -> void:
	print("Starting host on port ", PORT)
	var peer = ENetMultiplayerPeer.new()
	var error = peer.create_server(PORT, MAX_PLAYERS)
	
	if error != OK:
		print("Failed to create server: ", error)
		if error == 20:  # ENet error - address already in use
			print("ERROR: Port ", PORT, " is already in use! Another instance might be hosting.")
		return
	
	multiplayer.multiplayer_peer = peer
	print("Host started! Waiting for players...")
	
	# Notify lobby that host started
	var lobby = get_tree().current_scene.get_node_or_null("UILayers/LobbyLayer/Lobby")
	if lobby:
		lobby._on_host_started()
	
	# Spawn host's own player
	await get_tree().process_frame
	await get_tree().process_frame
	spawn_player(1)  # Host is always peer ID 1

# Client: Join server
func join_game(ip: String) -> void:
	print("Connecting to server at ", ip, ":", PORT)
	var peer = ENetMultiplayerPeer.new()
	var error = peer.create_client(ip, PORT)
	
	if error != OK:
		print("Failed to create client: ", error)
		return
	
	multiplayer.multiplayer_peer = peer
	print("Connecting...")

# Called when a peer connects (host receives this)
func _on_peer_connected(peer_id: int) -> void:
	print("Peer ", peer_id, " connected!")
	
	# Don't process the host's own connection
	if peer_id == 1:
		return
	
	# Spawn the new player for all clients
	if multiplayer.is_server():
		call_deferred("_handle_new_client", peer_id)

# Handle new client connection
func _handle_new_client(peer_id: int) -> void:
	# Send all existing players to the new client
	var scene = get_tree().current_scene
	if scene:
		for child in scene.get_children():
			if child.name.begins_with("Player_"):
				var existing_peer_id = int(child.name.substr(7))  # Remove "Player_" prefix
				
				# Don't send the new client's own player
				if existing_peer_id != peer_id:
					rpc_id(peer_id, "sync_player_spawn", existing_peer_id, child.position)
	
	# Wait a frame then spawn the new player
	await get_tree().process_frame
	spawn_player(peer_id)

# Called when a peer disconnects
func _on_peer_disconnected(peer_id: int) -> void:
	print("Peer ", peer_id, " disconnected")
	
	# Remove player from scene (players are children of scene root, not NetworkManager)
	var scene = get_tree().current_scene
	if scene:
		var player_node = scene.get_node_or_null("Player_" + str(peer_id))
		if player_node:
			player_node.queue_free()

# Client: Called when successfully connected to server
func _on_connected_to_server() -> void:
	print("Successfully connected to server!")
	var peer_id = multiplayer.get_unique_id()
	
	# Server will spawn us and send existing players via sync_player_spawn
	# Just wait for spawn messages

# Client: Called when connection fails
func _on_connection_failed() -> void:
	print("Failed to connect to server!")
	multiplayer.multiplayer_peer = null

# Client: Called when server disconnects
func _on_server_disconnected() -> void:
	print("Server disconnected - shutting down client...")
	
	# Set shutdown flag immediately to prevent any further processing
	is_shutting_down = true
	
	# Clean up all player nodes
	var scene = get_tree().current_scene
	if scene:
		for child in scene.get_children():
			if child and child.name.begins_with("Player_"):
				child.call_deferred("queue_free")
	
	# Clean up multiplayer after cleaning up nodes (prevents RPC errors)
	multiplayer.multiplayer_peer = null
	
	# Shutdown game
	call_deferred("_shutdown_game_immediate")

# Spawn a player for a given peer_id
func spawn_player(peer_id: int) -> void:
	# Don't spawn if we're shutting down
	if is_shutting_down:
		return
	
	# Verify multiplayer is initialized
	if multiplayer.multiplayer_peer == null:
		print("ERROR: Cannot spawn player - multiplayer not initialized!")
		return
	
	var is_server = multiplayer.is_server()
	var my_peer_id = multiplayer.get_unique_id()
	var is_local = (peer_id == my_peer_id)
	
	# Determine spawn position
	var spawn_index = (peer_id - 1) % spawn_points.size()
	var spawn_position = spawn_points[spawn_index]
	
	# Instantiate player
	var player = player_scene.instantiate()
	if not player:
		print("ERROR: Failed to instantiate player scene!")
		return
		
	player.name = "Player_" + str(peer_id)
	player.position = spawn_position
	
	# Set network properties (they're exported, so they exist)
	player.player_id = peer_id
	player.is_local_player = is_local
	player.is_host = is_server
	
	# Add to scene (parent is the main scene root)
	var parent = get_tree().current_scene
	if not parent:
		print("ERROR: Could not find scene root to add player!")
		player.queue_free()
		return
		
	parent.add_child(player, true)  # force_readable_name = true for networking
	
	# Initialize inventory for this player
	if InventoryManager:
		InventoryManager.initialize_player_inventory(peer_id)
		
		# Give starting items (server only)
		if is_server:
			# Give a sword to start
			await get_tree().process_frame
			InventoryManager.add_item(peer_id, "sword", 1)
	
	# If we're the server, tell all clients to spawn this player
	if is_server:
		call_deferred("_send_spawn_to_clients", peer_id, spawn_position)

# Send spawn to all clients
func _send_spawn_to_clients(peer_id: int, position: Vector3) -> void:
	rpc("sync_player_spawn", peer_id, position)

# Clients send their input to host
@rpc("any_peer", "call_local", "reliable")
func receive_player_input(peer_id: int, input_data: Dictionary) -> void:
	if not multiplayer.is_server():
		return  # Only host processes
	
	# Don't process if shutting down
	if is_shutting_down:
		return
	
	# Find the player instance for this peer_id
	var player = get_tree().current_scene.get_node_or_null("Player_" + str(peer_id))
	if player and player.has_method("process_player_input"):
		player.process_player_input(input_data)

# Clients send position updates to host (client-authoritative movement)
@rpc("any_peer", "call_local", "unreliable")
func receive_client_position_update(peer_id: int, state: Dictionary) -> void:
	if not multiplayer.is_server():
		return  # Only host processes
	
	# Don't process if shutting down
	if is_shutting_down:
		return
	
	# Find the player instance for this peer_id
	var player = get_tree().current_scene.get_node_or_null("Player_" + str(peer_id))
	if player and player.has_method("validate_client_position_state"):
		player.validate_client_position_state(state)

# Clients send camera rotation to host (for display only)
@rpc("any_peer", "call_local", "unreliable")
func receive_camera_rotation(peer_id: int, rotation_data: Dictionary) -> void:
	if not multiplayer.is_server():
		return  # Only host processes
	
	# Don't process if shutting down
	if is_shutting_down:
		return
	
	# Find the player instance for this peer_id
	var player = get_tree().current_scene.get_node_or_null("Player_" + str(peer_id))
	if player and player.has_method("process_player_input"):
		# Use process_player_input to handle camera rotation
		var input_data = {
			"camera_rotation": rotation_data.get("camera_rotation", Vector2.ZERO)
		}
		player.process_player_input(input_data)

# Clients send damage requests to host for validation
@rpc("any_peer", "call_local", "reliable")
func process_damage_request(attacker_id: int, body_name: String, body_peer_id: int, damage: float) -> void:
	if not multiplayer.is_server():
		return  # Only host processes
	
	# Don't process if shutting down
	if is_shutting_down:
		return
	
	# Find the body to damage
	var body = null
	
	# If body_peer_id is set, it's a player
	if body_peer_id > 0:
		body = get_tree().current_scene.get_node_or_null("Player_" + str(body_peer_id))
	else:
		# It's an enemy or other object - find by name
		body = get_tree().current_scene.get_node_or_null(body_name)
	
	if body and body.has_method("take_damage"):
		body.take_damage(damage, attacker_id)
		print("Host: Processed damage from Player ", attacker_id, " to ", body_name, " (", damage, " damage)")
	else:
		print("Host: Could not find target for damage: ", body_name, " (peer_id: ", body_peer_id, ")")

# Clients send interaction requests to host for validation
@rpc("any_peer", "call_local", "reliable")
func request_interact(player_id: int, interactable_path: NodePath) -> void:
	if not multiplayer.is_server():
		return  # Only host processes
	
	# Don't process if shutting down
	if is_shutting_down:
		return
	
	# Find the interactable object
	var interactable = get_tree().current_scene.get_node_or_null(interactable_path)
	if not interactable:
		print("Host: Could not find interactable: ", interactable_path)
		return
	
	# Find the player
	var player = get_tree().current_scene.get_node_or_null("Player_" + str(player_id))
	if not player:
		print("Host: Could not find player: ", player_id)
		return
	
	# Validate distance (prevent cheating)
	var distance = player.global_position.distance_to(interactable.global_position)
	if distance > 5.0:  # Max interaction distance
		print("Host: Player ", player_id, " too far from interactable (", distance, "m)")
		return
	
	# Process interaction
	if interactable.has_method("interact"):
		interactable.interact(player)
		print("Host: Player ", player_id, " interacted with ", interactable.name)

# Clients send harvest start requests to host
@rpc("any_peer", "call_local", "reliable")
func request_start_harvest(player_id: int, interactable_path: NodePath) -> void:
	if not multiplayer.is_server():
		return
	
	if is_shutting_down:
		return
	
	var interactable = get_tree().current_scene.get_node_or_null(interactable_path)
	if not interactable:
		return
	
	var player = get_tree().current_scene.get_node_or_null("Player_" + str(player_id))
	if not player:
		return
	
	# Validate distance
	var distance = player.global_position.distance_to(interactable.global_position)
	if distance > 5.0:
		return
	
	# Start harvest
	if interactable.has_method("start_harvest"):
		interactable.start_harvest(player)

# Clients send harvest cancel requests to host
@rpc("any_peer", "call_local", "reliable")
func request_cancel_harvest(player_id: int) -> void:
	if not multiplayer.is_server():
		return
	
	if is_shutting_down:
		return
	
	# Find all berry bushes being harvested by this player
	var scene = get_tree().current_scene
	var found = false
	
	# Search recursively through all nodes
	for child in scene.get_children():
		if _cancel_harvest_in_node(child, player_id):
			found = true
			break
		# Check children recursively
		for grandchild in child.get_children():
			if _cancel_harvest_in_node(grandchild, player_id):
				found = true
				break
		if found:
			break

func _cancel_harvest_in_node(node: Node, player_id: int) -> bool:
	"""Helper to check if a node is being harvested by the player and cancel it"""
	if node.has_method("cancel_harvest") and node.has_method("is_harvesting"):
		if node.is_harvesting():
			var harvesting_player = node.get("harvesting_player")
			if harvesting_player and harvesting_player.get("player_id") == player_id:
				node.cancel_harvest()
				return true
	return false

# Shutdown game when server disconnects
func _shutdown_game_immediate() -> void:
	if not is_shutting_down:
		return
	
	# Quit after a delay to ensure all input events finish processing
	call_deferred("_do_quit")

# Actually quit the game (called deferred to avoid crashes)
func _do_quit() -> void:
	if not is_shutting_down:
		return
	
	# Wait a bit longer to ensure all input events are processed
	await get_tree().create_timer(0.15).timeout
	get_tree().quit()

# Shutdown client (called when client exits)
func shutdown_client() -> void:
	if multiplayer.is_server():
		return  # Not a client
	
	print("Client shutting down...")
	is_shutting_down = true
	
	# Clean up all player nodes
	var scene = get_tree().current_scene
	if scene:
		for child in scene.get_children():
			if child and child.name.begins_with("Player_"):
				child.call_deferred("queue_free")
	
	# Disconnect from server gracefully
	if multiplayer.multiplayer_peer != null:
		multiplayer.multiplayer_peer.close()
		multiplayer.multiplayer_peer = null
	
	# Quit after a delay to ensure all input events finish
	await get_tree().create_timer(0.15).timeout
	get_tree().quit()

# Shutdown host server (called when host exits)
func shutdown_host() -> void:
	if not multiplayer.is_server():
		return
	
	print("Host shutting down...")
	is_shutting_down = true
	
	# Clean up all player nodes
	var scene = get_tree().current_scene
	if scene:
		for child in scene.get_children():
			if child and child.name.begins_with("Player_"):
				child.call_deferred("queue_free")
	
	# Close server connection (triggers server_disconnected on all clients)
	if multiplayer.multiplayer_peer != null:
		multiplayer.multiplayer_peer.close()
		multiplayer.multiplayer_peer = null
	
	# Quit after a delay to ensure all input events finish
	await get_tree().create_timer(0.15).timeout
	get_tree().quit()

# Remote call: Sync player spawn to all clients
@rpc("authority", "call_remote", "reliable")
func sync_player_spawn(peer_id: int, position: Vector3) -> void:
	if is_shutting_down:
		return
	
	# Only spawn if we don't already have this player
	var existing_player = get_tree().current_scene.get_node_or_null("Player_" + str(peer_id))
	if existing_player:
		return
	
	var my_peer_id = multiplayer.get_unique_id()
	var is_local = (peer_id == my_peer_id)
	var is_server = multiplayer.is_server()
	
	# Use call_deferred to avoid issues with spawning during network callbacks
	call_deferred("_do_spawn_player", peer_id, position, is_local, is_server)

# Spawn the player (deferred)
func _do_spawn_player(peer_id: int, position: Vector3, is_local: bool, is_server: bool) -> void:
	var player = player_scene.instantiate()
	player.name = "Player_" + str(peer_id)
	player.position = position
	player.player_id = peer_id
	player.is_local_player = is_local
	player.is_host = is_server
	
	var parent = get_tree().current_scene
	if parent:
		parent.add_child(player, true)
		await get_tree().process_frame
