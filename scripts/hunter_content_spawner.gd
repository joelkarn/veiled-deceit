extends Node

## Spawns hunter-specific content (quest sign) when a hunter player joins the game

@export var hunter_sign_scene: PackedScene = preload("res://scenes/sign.tscn")
@export var hunter_sign_data: SignData = preload("res://resources/hunter_quest_sign.tres")

@export var sign_spawn_position: Vector3 = Vector3(5, 0, 5)

var has_spawned: bool = false
var spawned_sign: Node = null

func _ready() -> void:
	print("[HunterContentSpawner] Initializing...")
	# Wait for handshake to complete before checking for hunter players
	NetworkManager.handshake_complete.connect(_on_handshake_complete)

func _on_handshake_complete() -> void:
	if has_spawned:
		return

	print("[HunterContentSpawner] Handshake complete, checking for hunter players...")

	# Now check if any player is a hunter
	var players = get_tree().get_nodes_in_group("players")
	print("[HunterContentSpawner] Found ", players.size(), " players")

	for player in players:
		if "player_name" in player:
			print("[HunterContentSpawner] Player: ", player.player_name)
			if player.player_name == "Hunter":
				print("[HunterContentSpawner] Found hunter! Spawning content...")
				_spawn_hunter_content()
				break

func _spawn_hunter_content() -> void:
	if has_spawned:
		print("[HunterContentSpawner] Already spawned, skipping...")
		return

	print("[HunterContentSpawner] Starting spawn process...")
	has_spawned = true

	# Server spawns the content and syncs to all clients
	if multiplayer.is_server():
		_spawn_content_on_server()
		# Tell all clients to spawn
		rpc("_spawn_content_on_client")

@rpc("authority", "call_remote", "reliable")
func _spawn_content_on_client() -> void:
	# Clients receive this RPC and spawn the content locally
	if has_spawned:
		return
	has_spawned = true
	print("[HunterContentSpawner] Client spawning content")
	_do_spawn()

func _spawn_content_on_server() -> void:
	# Server spawns locally
	_do_spawn()

func _do_spawn() -> void:
	# Get the map node (parent is the world node, map is a child of it)
	var map_node = get_parent().get_node_or_null("map")
	if not map_node:
		print("[HunterContentSpawner] ERROR: Could not find map node!")
		return

	print("[HunterContentSpawner] Found map node: ", map_node.name)

	# Spawn the quest sign
	if hunter_sign_scene:
		spawned_sign = hunter_sign_scene.instantiate()
		if spawned_sign and hunter_sign_data:
			# Set the sign data
			spawned_sign.sign_data = hunter_sign_data

			# Add to scene first, then set position
			map_node.add_child(spawned_sign)
			spawned_sign.global_position = sign_spawn_position
			print("[HunterContentSpawner] Spawned hunter quest sign at ", sign_spawn_position)
		else:
			print("[HunterContentSpawner] ERROR: Failed to instantiate sign or load sign data")
	else:
		print("[HunterContentSpawner] ERROR: hunter_sign_scene is null")

func despawn_hunter_content() -> void:
	"""Optional: Remove hunter content if needed"""
	if spawned_sign:
		spawned_sign.queue_free()
		spawned_sign = null

	has_spawned = false
