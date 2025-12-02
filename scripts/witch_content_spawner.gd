extends Node

## Spawns witch-specific content (quest sign and obelisk) when a witch player joins the game

@export var witch_sign_scene: PackedScene = preload("res://scenes/sign.tscn")
@export var witch_sign_data: SignData = preload("res://resources/witch_quest_sign.tres")
@export var obelisk_scene: PackedScene = preload("res://scenes/obelisk.tscn")

@export var sign_spawn_position: Vector3 = Vector3(0, 0, 5)
@export var obelisk_spawn_position: Vector3 = Vector3(10, 0, 10)

var has_spawned: bool = false
var spawned_sign: Node = null
var spawned_obelisk: Node = null

func _ready() -> void:
	print("[WitchContentSpawner] Initializing...")
	# Wait for handshake to complete before checking for witch players
	NetworkManager.handshake_complete.connect(_on_handshake_complete)

func _on_handshake_complete() -> void:
	if has_spawned:
		return

	print("[WitchContentSpawner] Handshake complete, checking for witch players...")

	# Now check if any player is a witch
	var players = get_tree().get_nodes_in_group("players")
	print("[WitchContentSpawner] Found ", players.size(), " players")

	for player in players:
		if "player_name" in player:
			print("[WitchContentSpawner] Player: ", player.player_name)
			if player.player_name == "Witch":
				print("[WitchContentSpawner] Found witch! Spawning content...")
				_spawn_witch_content()
				break

func _spawn_witch_content() -> void:
	if has_spawned:
		print("[WitchContentSpawner] Already spawned, skipping...")
		return

	print("[WitchContentSpawner] Starting spawn process...")
	has_spawned = true

	# Get the map node (parent is the world node, map is a child of it)
	var map_node = get_parent().get_node_or_null("map")
	if not map_node:
		print("[WitchContentSpawner] ERROR: Could not find map node!")
		return

	print("[WitchContentSpawner] Found map node: ", map_node.name)

	# Spawn the quest sign
	if witch_sign_scene:
		spawned_sign = witch_sign_scene.instantiate()
		if spawned_sign and witch_sign_data:
			# Set the sign data
			spawned_sign.sign_data = witch_sign_data

			# Add to scene first, then set position
			map_node.add_child(spawned_sign)
			spawned_sign.global_position = sign_spawn_position
			print("[WitchContentSpawner] Spawned witch quest sign at ", sign_spawn_position)
		else:
			print("[WitchContentSpawner] ERROR: Failed to instantiate sign or load sign data")
	else:
		print("[WitchContentSpawner] ERROR: witch_sign_scene is null")

	# Spawn the obelisk
	if obelisk_scene:
		spawned_obelisk = obelisk_scene.instantiate()
		if spawned_obelisk:
			# Add to scene first, then set position
			map_node.add_child(spawned_obelisk)
			spawned_obelisk.global_position = obelisk_spawn_position
			print("[WitchContentSpawner] Spawned obelisk at ", obelisk_spawn_position)
		else:
			print("[WitchContentSpawner] ERROR: Failed to instantiate obelisk")
	else:
		print("[WitchContentSpawner] ERROR: obelisk_scene is null")

func despawn_witch_content() -> void:
	"""Optional: Remove witch content if needed"""
	if spawned_sign:
		spawned_sign.queue_free()
		spawned_sign = null

	if spawned_obelisk:
		spawned_obelisk.queue_free()
		spawned_obelisk = null

	has_spawned = false
