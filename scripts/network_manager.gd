extends Node

# Network Manager - Handles multiplayer connection and player spawning

const PORT = 7777
const MAX_PLAYERS = 5

# Flag to track if we're shutting down (prevents crashes during cleanup)
var is_shutting_down: bool = false

# Multiplayer scene ready handshake
var peers_ready: Dictionary = {} # {peer_id: true}
var expected_peers: Array = []
var peers_spawned: Dictionary = {} # {peer_id: true} - tracks who has spawned their players

# Character selection state
var player_characters: Dictionary = {}  # {peer_id: character_name}
var available_characters: Array[String] = ["Witch", "Hunter", "Knight"]
var game_started: bool = false

# Spawn points for players (5 locations)
var spawn_points = [
	Vector3(0, 0, 0),
	Vector3(10, 0, 0),
	Vector3(-10, 0, 0),
	Vector3(0, 0, 10),
	Vector3(0, 0, -10)
]

@onready var player_scene = load("res://scenes/player.tscn")

signal character_selected(peer_id: int, character_name: String)
signal player_list_updated
signal host_started
signal handshake_complete

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

	# Emit host_started signal so lobby can react
	host_started.emit()

	# Don't spawn players yet - wait for character selection and game start

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

# ----------------------------
# Character Selection
# ----------------------------

## Request to select a character (called by client)
func request_character_selection(character_name: String) -> void:
	var peer_id = multiplayer.get_unique_id()

	if multiplayer.is_server():
		_validate_and_assign_character(peer_id, character_name)
	else:
		rpc_id(1, "_request_select_character", character_name)

@rpc("any_peer", "call_remote", "reliable")
func _request_select_character(character_name: String) -> void:
	if not multiplayer.is_server():
		return

	var peer_id = multiplayer.get_remote_sender_id()
	_validate_and_assign_character(peer_id, character_name)

func _validate_and_assign_character(peer_id: int, character_name: String) -> void:
	# Check if character is available
	var is_available = character_name in available_characters

	# Check if character is already taken by another player
	for existing_peer_id in player_characters.keys():
		if player_characters[existing_peer_id] == character_name and existing_peer_id != peer_id:
			is_available = false
			break

	if is_available:
		player_characters[peer_id] = character_name
		print("Player ", peer_id, " selected ", character_name)

		# Sync to all clients
		rpc("_sync_character_selection", peer_id, character_name)
		character_selected.emit(peer_id, character_name)
		# Emit player_list_updated locally on host so host UI updates
		if multiplayer.is_server():
			player_list_updated.emit()

@rpc("authority", "call_remote", "reliable")
func _sync_character_selection(peer_id: int, character_name: String) -> void:
	player_characters[peer_id] = character_name
	character_selected.emit(peer_id, character_name)
	player_list_updated.emit()

## Get available characters (not yet selected by anyone)
func get_available_characters() -> Array[String]:
	var available: Array[String] = []
	for character in available_characters:
		var is_taken = false
		for selected_character in player_characters.values():
			if selected_character == character:
				is_taken = true
				break
		if not is_taken:
			available.append(character)
	return available

## Check if all connected players have selected characters
func all_players_ready() -> bool:
	if game_started:
		return false

	# Get all connected peer IDs
	var connected_peers = [1]  # Host is always peer 1
	connected_peers.append_array(multiplayer.get_peers())

	# Check if each peer has selected a character
	for peer_id in connected_peers:
		if not player_characters.has(peer_id):
			return false

	return connected_peers.size() > 0

## Host starts the game (loads main scene and spawns players)
func start_game() -> void:
	if not multiplayer.is_server():
		return

	if not all_players_ready():
		print("Cannot start game - not all players are ready!")
		return

	game_started = true
	print("[Handshake] start_game called. Players: ", player_characters)

	# Setup handshake tracking
	peers_ready.clear()
	peers_spawned.clear()
	expected_peers = [1]
	expected_peers.append_array(multiplayer.get_peers())
	print("[Handshake] Expected peers: ", expected_peers)

	# Tell all clients to load the game scene
	rpc("_load_game_scene")

@rpc("authority", "call_local", "reliable")
func _load_game_scene() -> void:
	game_started = true
	print("[Handshake] _load_game_scene called on peer ", multiplayer.get_unique_id())
	# Load the main game scene
	get_tree().change_scene_to_file("res://scenes/main.tscn")

	# Wait for scene to load
	await get_tree().process_frame
	await get_tree().process_frame

	print("[Handshake] Scene loaded on peer ", multiplayer.get_unique_id())
	# Notify host/server that this peer is ready
	if not multiplayer.is_server():
		print("[Handshake] Client sending scene_ready to host.")
		rpc_id(1, "scene_ready", multiplayer.get_unique_id())
	else:
		print("[Handshake] Host sending scene_ready for itself.")
		scene_ready(multiplayer.get_unique_id())
# Scene ready handshake RPC (clients call this on host)
@rpc("any_peer", "call_remote", "reliable")
func scene_ready(peer_id: int) -> void:
	peers_ready[peer_id] = true
	print("[Handshake] scene_ready called by peer ", peer_id)
	print("[Handshake] Current ready peers: ", peers_ready)
	# Check if all expected peers are ready
	var all_ready = true
	for id in expected_peers:
		if not peers_ready.has(id):
			all_ready = false
			print("[Handshake] Peer ", id, " not ready yet.")
			break
	if all_ready:
		print("[Handshake] All peers ready! Sending spawn commands...")
		# Send spawn commands to all peers (including self)
		for id in expected_peers:
			if player_characters.has(id):
				print("[Handshake] Sending spawn command for peer ", id)
				_send_spawn_command_to_all(id)

		# Wait for all peers to confirm they've spawned players
		# This happens in _confirm_player_spawned RPC

# Send spawn command to all peers (including self)
func _send_spawn_command_to_all(peer_id: int) -> void:
	if not player_characters.has(peer_id):
		return

	var spawn_index = (peer_id - 1) % spawn_points.size()
	var spawn_position = spawn_points[spawn_index]
	var character_name = player_characters[peer_id]

	# Send to all peers (including self via call_local)
	rpc("_spawn_player_on_client", peer_id, spawn_position, character_name)

# RPC: Spawn a player on this client
@rpc("authority", "call_local", "reliable")
func _spawn_player_on_client(peer_id: int, spawn_position: Vector3, character_name: String) -> void:
	print("[Handshake] Spawning player ", peer_id, " on peer ", multiplayer.get_unique_id())

	# Spawn the player locally
	_do_immediate_spawn(peer_id, spawn_position, character_name)

	# Notify server that we've spawned this player
	if multiplayer.is_server():
		# Host confirms immediately
		_confirm_player_spawned(multiplayer.get_unique_id(), peer_id)
	else:
		# Client sends confirmation to host
		rpc_id(1, "_confirm_player_spawned", multiplayer.get_unique_id(), peer_id)

# Confirm that a peer has spawned a player
@rpc("any_peer", "call_remote", "reliable")
func _confirm_player_spawned(confirming_peer_id: int, spawned_player_id: int) -> void:
	if not multiplayer.is_server():
		return

	print("[Handshake] Peer ", confirming_peer_id, " confirmed spawn of player ", spawned_player_id)

	# Track which peers have confirmed spawning all players
	if not peers_spawned.has(confirming_peer_id):
		peers_spawned[confirming_peer_id] = []

	peers_spawned[confirming_peer_id].append(spawned_player_id)

	# Check if all peers have spawned all players
	var all_spawned = true
	for peer_id in expected_peers:
		if not peers_spawned.has(peer_id):
			all_spawned = false
			print("[Handshake] Waiting for peer ", peer_id, " to spawn players")
			break

		# Check if this peer has spawned all expected players
		var spawned_list = peers_spawned[peer_id]
		for player_id in expected_peers:
			if not player_id in spawned_list:
				all_spawned = false
				print("[Handshake] Peer ", peer_id, " hasn't spawned player ", player_id, " yet")
				break

		if not all_spawned:
			break

	if all_spawned:
		print("[Handshake] All players spawned on all peers! Initializing quests...")
		# Initialize quests for all players now that everyone is spawned
		_initialize_all_player_quests()
		handshake_complete.emit()
		rpc("_handshake_done")

# Initialize quests for all players after handshake (server only)
func _initialize_all_player_quests() -> void:
	if not multiplayer.is_server():
		return

	if not QuestManager:
		print("[Handshake] WARNING: QuestManager not found!")
		return

	print("[Handshake] Initializing quests for all players...")
	for peer_id in expected_peers:
		if player_characters.has(peer_id):
			print("[Handshake] Initializing quests for player ", peer_id)
			QuestManager.initialize_player(peer_id)

	print("[Handshake] Quest initialization complete!")

# RPC to notify all peers handshake is done
@rpc("authority", "call_remote", "reliable")
func _handshake_done() -> void:
	print("[Handshake] handshake_done RPC received, hiding loading screen.")
	handshake_complete.emit()

# Called when a peer connects (host receives this)
func _on_peer_connected(peer_id: int) -> void:
	print("Peer ", peer_id, " connected!")

	# Don't process the host's own connection
	if peer_id == 1:
		return

	# Spawn the new player for all clients
	if multiplayer.is_server():
		call_deferred("_handle_new_client", peer_id)

	# Emit player_list_updated so host lobby updates immediately
	player_list_updated.emit()

# Handle new client connection
func _handle_new_client(peer_id: int) -> void:
	# Sync character selection state to new client
	rpc_id(peer_id, "_sync_all_character_selections", player_characters)

	# Send all existing players to the new client
	var scene = get_tree().current_scene
	if scene:
		for child in scene.get_children():
			if child.name.begins_with("Player_"):
				var existing_peer_id = int(child.name.substr(7))  # Remove "Player_" prefix

				# Don't send the new client's own player
				if existing_peer_id != peer_id:
					var character_name = player_characters.get(existing_peer_id, "Unknown")
					rpc_id(peer_id, "sync_player_spawn", existing_peer_id, child.position, character_name)

	# Sync all interactable objects' states to the new client
	_sync_world_state_to_client(peer_id)

	# Wait a frame then spawn the new player (only if game has started)
	await get_tree().process_frame
	if game_started:
		spawn_player(peer_id)

@rpc("authority", "call_remote", "reliable")
func _sync_all_character_selections(characters: Dictionary) -> void:
	player_characters = characters
	player_list_updated.emit()

# Sync all world object states to a newly connected client
func _sync_world_state_to_client(peer_id: int) -> void:
	var scene = get_tree().current_scene
	if not scene:
		return

	# Recursively find all nodes with sync_state_to_client method
	_sync_node_state_recursive(scene, peer_id)

# Helper to recursively sync node states
func _sync_node_state_recursive(node: Node, peer_id: int) -> void:
	# If node has sync method, call it
	if node.has_method("sync_state_to_client"):
		node.sync_state_to_client(peer_id)

	# Recurse through children
	for child in node.get_children():
		_sync_node_state_recursive(child, peer_id)

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
	# Server will send character selections and we'll wait for game start

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

# Immediate spawn without network handshaking (used during initial game start)
func _do_immediate_spawn(peer_id: int, spawn_position: Vector3, character_name: String) -> void:
	# Don't spawn if we're shutting down
	if is_shutting_down:
		return

	# Verify multiplayer is initialized
	if multiplayer.multiplayer_peer == null:
		print("ERROR: Cannot spawn player - multiplayer not initialized!")
		return

	# Check if player has selected a character
	if not player_characters.has(peer_id):
		print("ERROR: Cannot spawn player ", peer_id, " - no character selected!")
		return

	# Only spawn if we don't already have this player
	var existing_player = get_tree().current_scene.get_node_or_null("Player_" + str(peer_id))
	if existing_player:
		print("[Handshake] Player ", peer_id, " already exists on peer ", multiplayer.get_unique_id())
		return

	var my_peer_id = multiplayer.get_unique_id()
	var is_local = (peer_id == my_peer_id)
	var is_server = multiplayer.is_server()

	# Instantiate player
	var player = player_scene.instantiate()
	if not player:
		print("ERROR: Failed to instantiate player scene!")
		return

	player.name = "Player_" + str(peer_id)
	player.position = spawn_position

	# Set network properties
	player.player_id = peer_id
	player.is_local_player = is_local
	player.is_host = is_server
	player.player_name = character_name

	# Add to scene
	var parent = get_tree().current_scene
	if not parent:
		print("ERROR: Could not find scene root to add player!")
		player.queue_free()
		return

	parent.add_child(player, true)

	# Initialize inventory for this player
	if InventoryManager:
		InventoryManager.initialize_player_inventory(peer_id)

		# Give starting items (server only)
		if is_server:
			await get_tree().process_frame
			InventoryManager.add_item(peer_id, "sword", 1)

	# NOTE: Quests are initialized later in _initialize_all_player_quests() after handshake
	# This prevents duplicate quest initialization

	print("[Handshake] Spawned player ", peer_id, " on peer ", multiplayer.get_unique_id())

# Spawn a player for a given peer_id (legacy function, kept for late joiners)
func spawn_player(peer_id: int) -> void:
	# Don't spawn if we're shutting down
	if is_shutting_down:
		return

	# Verify multiplayer is initialized
	if multiplayer.multiplayer_peer == null:
		print("ERROR: Cannot spawn player - multiplayer not initialized!")
		return

	# Check if player has selected a character
	if not player_characters.has(peer_id):
		print("ERROR: Cannot spawn player ", peer_id, " - no character selected!")
		return

	var is_server = multiplayer.is_server()
	var my_peer_id = multiplayer.get_unique_id()
	var is_local = (peer_id == my_peer_id)

	# Determine spawn position
	var spawn_index = (peer_id - 1) % spawn_points.size()
	var spawn_position = spawn_points[spawn_index]

	# Get character name
	var character_name = player_characters[peer_id]

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
	player.player_name = character_name  # Set character name

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

	# Initialize quests for this player (server only)
	# This is ONLY for late joiners - initial players get quests after handshake
	if is_server and QuestManager and game_started:
		QuestManager.initialize_player(peer_id)
		print("[LateJoin] Initialized quests for late joiner: ", peer_id)

	# If we're the server, tell all clients to spawn this player (for late joiners)
	if is_server:
		# Use the old sync method for late joiners (after game has started)
		rpc("sync_player_spawn", peer_id, spawn_position, character_name)

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
		# It's an enemy - search in enemies group by name
		var enemies = get_tree().get_nodes_in_group("enemies")
		for enemy in enemies:
			if enemy.name == body_name:
				body = enemy
				break

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

# Clients send quest addition requests to host
@rpc("any_peer", "call_local", "reliable")
func request_add_quest(quest_id: String, player_id: int) -> void:
	if not multiplayer.is_server():
		return

	if is_shutting_down:
		return

	print("[NetworkManager] Server received quest addition request: ", quest_id, " for player ", player_id)

	# Add quest on server for specific player
	if QuestManager and QuestManager.has_method("add_quest_by_id"):
		QuestManager.add_quest_by_id(quest_id, player_id)
	else:
		print("[NetworkManager] ERROR: Could not find QuestManager")

# Clients send book read events to host for quest tracking
@rpc("any_peer", "call_remote", "reliable")
func process_book_read(player_id: int) -> void:
	if not multiplayer.is_server():
		return

	if is_shutting_down:
		return

	print("[NetworkManager] Server received book read from player ", player_id)

	# Track quest progress on server
	if QuestManager:
		QuestManager.add_progress_by_type(QuestData.QuestType.READ_BOOK, 1, player_id)
	else:
		print("[NetworkManager] ERROR: Could not find QuestManager")

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
func sync_player_spawn(peer_id: int, position: Vector3, character_name: String) -> void:
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
	call_deferred("_do_spawn_player", peer_id, position, character_name, is_local, is_server)

# Spawn the player (deferred)
func _do_spawn_player(peer_id: int, position: Vector3, character_name: String, is_local: bool, is_server: bool) -> void:
	var player = player_scene.instantiate()
	player.name = "Player_" + str(peer_id)
	player.position = position
	player.player_id = peer_id
	player.is_local_player = is_local
	player.is_host = is_server
	player.player_name = character_name  # Set character name

	var parent = get_tree().current_scene
	if parent:
		parent.add_child(player, true)
		await get_tree().process_frame
