extends Node

# Network Manager - Handles multiplayer connection and player spawning
# For now: Basic host/client setup for testing

const PORT = 7777
const MAX_PLAYERS = 5

# Spawn points for players (5 locations)
var spawn_points = [
	Vector3(-0.179691, 0, 4.3177),  # Current player position
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
	
	# Spawn host's own player
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
	
	# Spawn the new player for all clients
	if multiplayer.is_server():
		await get_tree().process_frame  # Wait a frame for network to stabilize
		spawn_player(peer_id)

# Called when a peer disconnects
func _on_peer_disconnected(peer_id: int) -> void:
	print("Peer ", peer_id, " disconnected!")
	
	# Remove player from scene
	var player_node = get_node_or_null("../Player_" + str(peer_id))
	if player_node:
		player_node.queue_free()

# Client: Called when successfully connected to server
func _on_connected_to_server() -> void:
	print("Successfully connected to server!")
	var peer_id = multiplayer.get_unique_id()
	
	# Server will spawn us, so we just wait

# Client: Called when connection fails
func _on_connection_failed() -> void:
	print("Failed to connect to server!")
	multiplayer.multiplayer_peer = null

# Client: Called when server disconnects
func _on_server_disconnected() -> void:
	print("Server disconnected!")
	multiplayer.multiplayer_peer = null

# Spawn a player for a given peer_id
func spawn_player(peer_id: int) -> void:
	var is_server = multiplayer.is_server()
	var is_local = (peer_id == multiplayer.get_unique_id())
	
	print("Spawning player for peer ", peer_id, " (local: ", is_local, ", server: ", is_server, ")")
	
	# Determine spawn position
	var spawn_index = (peer_id - 1) % spawn_points.size()
	var spawn_position = spawn_points[spawn_index]
	
	# Instantiate player
	var player = player_scene.instantiate()
	player.name = "Player_" + str(peer_id)
	player.position = spawn_position
	
	# Set network properties (they're exported, so they exist)
	player.player_id = peer_id
	player.is_local_player = is_local
	player.is_host = is_server
	
	# Add to scene (parent is the main scene root)
	var parent = get_tree().current_scene
	if parent:
		parent.add_child(player, true)  # force_readable_name = true for networking
		
		print("Player spawned at position: ", spawn_position)
		
		# If we're the server, tell all clients to spawn this player
		if is_server:
			rpc("sync_player_spawn", peer_id, spawn_position)

# Clients send their input to host
@rpc("any_peer", "call_local", "reliable")
func receive_player_input(peer_id: int, input_data: Dictionary) -> void:
	if not multiplayer.is_server():
		return  # Only host processes
	
	# Find the player instance for this peer_id
	var player = get_tree().current_scene.get_node_or_null("Player_" + str(peer_id))
	if player and player.has_method("process_player_input"):
		player.process_player_input(input_data)

# Remote call: Sync player spawn to all clients
@rpc("authority", "call_remote", "reliable")
func sync_player_spawn(peer_id: int, position: Vector3) -> void:
	# Only spawn if we don't already have this player
	var existing_player = get_tree().current_scene.get_node_or_null("Player_" + str(peer_id))
	if existing_player:
		return
	
	# Don't spawn ourselves (we're already spawned)
	if peer_id == multiplayer.get_unique_id():
		return
	
	var is_local = (peer_id == multiplayer.get_unique_id())
	var is_server = multiplayer.is_server()
	
	var player = player_scene.instantiate()
	player.name = "Player_" + str(peer_id)
	player.position = position
	
	# Set network properties (they're exported, so they exist)
	player.player_id = peer_id
	player.is_local_player = is_local
	player.is_host = is_server
	
	var parent = get_tree().current_scene
	if parent:
		parent.add_child(player, true)
		print("Synced player ", peer_id, " spawn at ", position)
