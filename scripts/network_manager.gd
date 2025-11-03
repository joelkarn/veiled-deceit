extends Node

# Network Manager - Handles multiplayer connection and player spawning

const PORT = 7777
const MAX_PLAYERS = 5

# Spawn points for players (5 locations)
var spawn_points = [
	Vector3(-0, 0, 0),  # Current player position
	Vector3(5, 0, 4.3177),
	Vector3(-5, 0, 4.3177),
	Vector3(0, 0, 10),
	Vector3(0, 0, -2)
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
	
	# Spawn host's own player (wait a bit longer to ensure multiplayer is ready)
	await get_tree().process_frame
	await get_tree().process_frame  # Extra frame to ensure everything is initialized
	print("About to spawn host player...")
	spawn_player(1)  # Host is always peer ID 1
	print("Host player spawn complete!")

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
	
	# Don't process the host's own connection (peer_id 1)
	if peer_id == 1:
		print("Ignoring host's own peer_connected signal")
		return
	
	# Spawn the new player for all clients (use call_deferred to avoid blocking)
	if multiplayer.is_server():
		# Use call_deferred to handle spawn asynchronously
		call_deferred("_handle_new_client", peer_id)

# Handle new client connection (deferred)
func _handle_new_client(peer_id: int) -> void:
	print("=== HANDLING NEW CLIENT ===")
	print("  New client peer ID: ", peer_id)
	print("  My peer ID: ", multiplayer.get_unique_id())
	print("  Is server: ", multiplayer.is_server())
	
	# First, send all existing players to the new client
	# Check all Player_ nodes in the scene to find existing players
	var scene = get_tree().current_scene
	if scene:
		for child in scene.get_children():
			if child.name.begins_with("Player_"):
				var existing_peer_id_str = child.name.substr(7)  # Remove "Player_" prefix
				var existing_peer_id = int(existing_peer_id_str)
				
				# Don't send the new client's own player (they'll spawn themselves)
				if existing_peer_id != peer_id:
					print("  Sending existing player ", existing_peer_id, " to new client ", peer_id, " at position ", child.position)
					rpc_id(peer_id, "sync_player_spawn", existing_peer_id, child.position)
	
	# Small delay to ensure spawn messages are sent
	await get_tree().process_frame
	print("  Frame processed, now spawning new player")
	
	# Now spawn the new player
	spawn_player(peer_id)
	print("  Finished handling new client")

# Called when a peer disconnects
func _on_peer_disconnected(peer_id: int) -> void:
	print("=== PEER DISCONNECTED ===")
	print("  Peer ID: ", peer_id)
	print("  My peer ID: ", multiplayer.get_unique_id())
	print("  Is server: ", multiplayer.is_server())
	print("  Multiplayer peer: ", multiplayer.multiplayer_peer != null)
	
	# Remove player from scene
	var player_node = get_node_or_null("../Player_" + str(peer_id))
	if player_node:
		print("  Removing player node from scene")
		player_node.queue_free()
	else:
		print("  Player node not found for peer ", peer_id)

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
	print("=== SERVER DISCONNECTED (CLIENT SIDE) ===")
	print("  My peer ID: ", multiplayer.get_unique_id())
	print("  Multiplayer peer was: ", multiplayer.multiplayer_peer != null)
	multiplayer.multiplayer_peer = null

# Spawn a player for a given peer_id
func spawn_player(peer_id: int) -> void:
	# Verify multiplayer is initialized
	if multiplayer.multiplayer_peer == null:
		print("ERROR: Cannot spawn player - multiplayer not initialized!")
		return
	
	var is_server = multiplayer.is_server()
	var my_peer_id = multiplayer.get_unique_id()
	var is_local = (peer_id == my_peer_id)
	
	print("Spawning player for peer ", peer_id, " (my peer_id: ", my_peer_id, ", local: ", is_local, ", server: ", is_server, ")")
	
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
	print("Player spawned at position: ", spawn_position)
	
	# If we're the server, tell all clients to spawn this player
	# Use call_deferred to ensure it happens after the player is fully added
	if is_server:
		print("  Server: Scheduling spawn broadcast for all clients")
		call_deferred("_send_spawn_to_clients", peer_id, spawn_position)

# Helper function to send spawn to clients (deferred)
func _send_spawn_to_clients(peer_id: int, position: Vector3) -> void:
	print("=== SENDING SPAWN TO CLIENTS ===")
	print("  Peer ID: ", peer_id)
	print("  Position: ", position)
	print("  Is server: ", multiplayer.is_server())
	rpc("sync_player_spawn", peer_id, position)
	print("  RPC sent!")

# Clients send their input to host
@rpc("any_peer", "call_local", "reliable")
func receive_player_input(peer_id: int, input_data: Dictionary) -> void:
	if not multiplayer.is_server():
		return  # Only host processes
	
	# Find the player instance for this peer_id
	var player = get_tree().current_scene.get_node_or_null("Player_" + str(peer_id))
	if player and player.has_method("process_player_input"):
		player.process_player_input(input_data)

# Clients send position updates to host (client-authoritative movement)
@rpc("any_peer", "call_local", "unreliable")
func receive_client_position_update(peer_id: int, state: Dictionary) -> void:
	if not multiplayer.is_server():
		return  # Only host processes
	
	# Find the player instance for this peer_id
	var player = get_tree().current_scene.get_node_or_null("Player_" + str(peer_id))
	if player and player.has_method("validate_client_position_state"):
		player.validate_client_position_state(state)

# Clients send camera rotation to host (for display only)
@rpc("any_peer", "call_local", "unreliable")
func receive_camera_rotation(peer_id: int, rotation_data: Dictionary) -> void:
	if not multiplayer.is_server():
		return  # Only host processes
	
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

# Remote call: Sync player spawn to all clients
@rpc("authority", "call_remote", "reliable")
func sync_player_spawn(peer_id: int, position: Vector3) -> void:
	# Only spawn if we don't already have this player
	var existing_player = get_tree().current_scene.get_node_or_null("Player_" + str(peer_id))
	if existing_player:
		print("Player ", peer_id, " already exists, skipping spawn")
		return
	
	var my_peer_id = multiplayer.get_unique_id()
	var is_local = (peer_id == my_peer_id)
	var is_server = multiplayer.is_server()
	
	print("Client: Syncing spawn for player ", peer_id, " (my peer_id: ", my_peer_id, ", local: ", is_local, ")")
	
	# Use call_deferred to avoid issues with spawning during network callbacks
	call_deferred("_do_spawn_player", peer_id, position, is_local, is_server)

# Actually spawn the player (deferred)
func _do_spawn_player(peer_id: int, position: Vector3, is_local: bool, is_server: bool) -> void:
	print("=== DOING SPAWN PLAYER (DEFERRED) ===")
	print("  Peer ID: ", peer_id)
	print("  Position: ", position)
	print("  Is local: ", is_local)
	print("  Is server: ", is_server)
	print("  My peer ID: ", multiplayer.get_unique_id())
	
	var player = player_scene.instantiate()
	player.name = "Player_" + str(peer_id)
	player.position = position
	
	# Set network properties (they're exported, so they exist)
	player.player_id = peer_id
	player.is_local_player = is_local
	player.is_host = is_server
	
	print("  Player instantiated, properties set")
	
	var parent = get_tree().current_scene
	if parent:
		print("  Adding player to scene tree...")
		parent.add_child(player, true)
		print("  Player added to scene!")
		# Wait one frame for player to be fully initialized
		await get_tree().process_frame
		print("  Player initialized!")
		print("Client: Successfully synced player ", peer_id, " spawn at ", position)
	else:
		print("ERROR: Could not find scene root to add player!")
