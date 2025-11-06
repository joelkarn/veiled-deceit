extends Node3D

# Enemy Spawner - Spawns enemies at a location and respawns them after death

@export var enemy_scene: PackedScene = preload("res://scenes/enemy.tscn")
@export var respawn_time: float = 30.0  # Time in seconds before respawning after death
@export var spawn_on_ready: bool = true  # Spawn immediately when ready

var current_enemy: Node = null
var spawn_timer: Timer = null
var is_spawning: bool = false
var monitoring_task: bool = false

func _ready() -> void:
	# Wait for multiplayer to be ready (both host and clients need this)
	if multiplayer.multiplayer_peer == null:
		# Wait for multiplayer to initialize
		await _wait_for_multiplayer()
	
	# Double-check we're still in a valid state
	if multiplayer.multiplayer_peer == null:
		return
	
	# Only host manages spawning - clients should NEVER spawn enemies
	if not multiplayer.is_server():
		# Clients should connect to peer_connected signal to receive existing enemies
		# But only if we're actually a client (not during initialization)
		if multiplayer.multiplayer_peer != null:
			multiplayer.peer_connected.connect(_on_peer_connected)
		return
	
	# Create spawn timer (host only)
	spawn_timer = Timer.new()
	spawn_timer.wait_time = respawn_time
	spawn_timer.one_shot = true
	spawn_timer.timeout.connect(_on_spawn_timer_timeout)
	add_child(spawn_timer)
	
	# Connect to peer_connected to sync existing enemies to new clients
	multiplayer.peer_connected.connect(_on_peer_connected)
	
	# Spawn initial enemy if enabled
	if spawn_on_ready:
		await get_tree().process_frame
		# Double-check we're still the server before spawning
		if multiplayer.is_server():
			spawn_enemy()

func _on_peer_connected(peer_id: int) -> void:
	# Only host sends existing enemies to new clients
	if not multiplayer.is_server():
		return
	
	# Don't process the host's own connection
	if peer_id == 1:
		return
	
	# Wait a frame to ensure the new client is fully connected
	await get_tree().process_frame
	
	# Send existing enemy to the new client with exact name and position
	if current_enemy != null and is_instance_valid(current_enemy) and current_enemy.is_inside_tree():
		print("Host: Sending existing enemy ", current_enemy.name, " at ", current_enemy.position, " to new client ", peer_id)
		rpc_id(peer_id, "sync_enemy_spawn", current_enemy.name, current_enemy.position)

func _wait_for_multiplayer() -> void:
	# Wait for multiplayer to be initialized
	while multiplayer.multiplayer_peer == null:
		await get_tree().process_frame

func _is_shutting_down() -> bool:
	# Check if network manager is shutting down
	var network_manager = get_tree().current_scene.get_node_or_null("NetworkManager")
	if network_manager and network_manager.get("is_shutting_down"):
		return network_manager.is_shutting_down
	return false

func spawn_enemy() -> void:
	# Only host spawns enemies
	if not multiplayer.is_server():
		return
	
	# Don't spawn if shutting down
	if _is_shutting_down():
		return
	
	# Don't spawn if already spawning or enemy exists
	if is_spawning or (current_enemy != null and is_instance_valid(current_enemy) and current_enemy.is_inside_tree()):
		return
	
	is_spawning = true
	
	# Instantiate enemy
	var enemy = enemy_scene.instantiate()
	if not enemy:
		print("ERROR: Failed to instantiate enemy scene!")
		is_spawning = false
		return
	
	# Set enemy position to spawner position
	enemy.position = global_position
	
	# Add to scene (parent is the main scene root)
	var parent = get_tree().current_scene
	if not parent:
		print("ERROR: Could not find scene root to add enemy!")
		enemy.queue_free()
		is_spawning = false
		return
	
	# Generate unique name for the enemy
	var enemy_name = "Enemy_" + str(get_instance_id()) + "_" + str(Time.get_ticks_msec())
	enemy.name = enemy_name
	
	parent.add_child(enemy, true)  # force_readable_name = true for networking
	
	current_enemy = enemy
	
	# Connect to enemy's tree_exiting signal to detect death (emitted before removal)
	# Use call_deferred to ensure the enemy is in the tree first
	call_deferred("_connect_enemy_death_signal", enemy)
	
	# Sync spawn to all clients
	rpc("sync_enemy_spawn", enemy_name, global_position)
	
	is_spawning = false
	print("Enemy spawned at ", global_position, " with name ", enemy_name)

func _connect_enemy_death_signal(enemy_node: Node) -> void:
	# Connect to enemy's tree_exiting signal to detect death
	if enemy_node != null and is_instance_valid(enemy_node):
		if enemy_node.tree_exiting.connect(_on_enemy_died) != OK:
			# Fallback to monitoring if signal connection fails
			_monitor_enemy_death()

func _on_enemy_died() -> void:
	# Enemy has been removed from tree (died)
	if current_enemy != null:
		print("Enemy died, respawning in ", respawn_time, " seconds...")
		current_enemy = null
		monitoring_task = false
		
		# Don't start timer if shutting down
		if _is_shutting_down():
			return
		
		# Start respawn timer
		if spawn_timer:
			spawn_timer.start()

func _monitor_enemy_death() -> void:
	# Fallback monitoring method if signal connection fails
	if monitoring_task:
		return  # Already monitoring
	
	monitoring_task = true
	
	# Monitor the enemy to detect when it dies
	if current_enemy == null or not is_instance_valid(current_enemy):
		monitoring_task = false
		return
	
	# Wait for enemy to be removed from tree
	while current_enemy != null and is_instance_valid(current_enemy) and current_enemy.is_inside_tree():
		await get_tree().process_frame
	
	# Enemy has been removed (died)
	_on_enemy_died()

func _on_spawn_timer_timeout() -> void:
	# Timer finished, spawn new enemy
	spawn_enemy()

# Sync enemy spawn to all clients
@rpc("authority", "call_remote", "reliable")
func sync_enemy_spawn(enemy_name: String, spawn_position: Vector3) -> void:
	# Only clients need to handle this (host already spawned)
	if multiplayer.is_server():
		return
	
	print("Client: Received enemy spawn notification: ", enemy_name, " at ", spawn_position)
	
	# Check if enemy already exists with the correct name
	var existing_enemy = get_tree().current_scene.get_node_or_null(enemy_name)
	if existing_enemy:
		print("Client: Enemy ", enemy_name, " already exists with correct name, skipping spawn")
		return
	
	# IMPORTANT: Remove any existing enemies at this spawn position that have a different name
	# This prevents ghost enemies with wrong names
	var scene = get_tree().current_scene
	if scene:
		var enemies_to_remove = []
		for child in scene.get_children():
			if child.name.begins_with("Enemy_") and child.position.distance_to(spawn_position) < 0.1:
				# Found an enemy at this position with a different name - remove it
				if child.name != enemy_name:
					print("Client: Removing ghost enemy ", child.name, " at position ", spawn_position, " (replacing with ", enemy_name, ")")
					enemies_to_remove.append(child)
		
		# Remove ghost enemies
		for enemy in enemies_to_remove:
			if is_instance_valid(enemy):
				enemy.queue_free()
	
	# Wait a frame to ensure cleanup is done
	await get_tree().process_frame
	
	# Double-check the enemy doesn't exist now
	existing_enemy = get_tree().current_scene.get_node_or_null(enemy_name)
	if existing_enemy:
		print("Client: Enemy ", enemy_name, " already exists after cleanup, skipping spawn")
		return
	
	# Instantiate enemy for client with the EXACT name from host
	var enemy = enemy_scene.instantiate()
	if not enemy:
		print("ERROR: Failed to instantiate enemy scene on client!")
		return
	
	# Use the EXACT name sent by the host - this is critical for damage system
	enemy.name = enemy_name
	enemy.position = spawn_position
	
	var parent = get_tree().current_scene
	if parent:
		parent.add_child(enemy, true)
		print("Client: Enemy spawned at ", spawn_position, " with name ", enemy_name, " (matches host)")

