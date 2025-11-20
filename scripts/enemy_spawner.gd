extends Node3D

## Configuration
@export var enemy_scene: PackedScene  # Drag the enemy.tscn here
@export var spawn_interval: float = 5.0  # Seconds between spawns
@export var max_enemies: int = 10  # Maximum number of enemies at once
@export var spawn_radius: float = 2.0  # Random spawn radius around this node
@export var enabled: bool = true  # Enable/disable spawning
@export var auto_start: bool = true  # Start spawning automatically

## Optional settings
@export_group("Advanced")
@export var despawn_distance: float = 50.0  # Despawn enemies beyond this distance from players
@export var check_despawn: bool = false  # Enable distance-based despawning

var spawn_timer: Timer
var active_enemies: Array[Node] = []
var players_node: Node  # Reference to where players are stored
var enemy_id_counter: int = 0  # Counter for unique enemy IDs
var has_started: bool = false  # Flag to prevent multiple starts

func _ready():
	# Setup spawn timer
	spawn_timer = Timer.new()
	spawn_timer.wait_time = spawn_interval
	spawn_timer.timeout.connect(_on_spawn_timer_timeout)
	add_child(spawn_timer)

	# Try to find players node for despawn checks
	if check_despawn:
		players_node = get_tree().get_first_node_in_group("players")

	# Wait a moment for multiplayer to initialize
	await get_tree().create_timer(0.5).timeout

	# ONLY server should continue past this point
	if multiplayer.multiplayer_peer == null:
		# No multiplayer yet, wait and check again
		print("EnemySpawner: No multiplayer peer yet")
		return

	if not multiplayer.is_server():
		# We're a client, disable spawning completely
		print("EnemySpawner: Client detected - spawning disabled")
		return

	# We're the server - start spawning
	print("EnemySpawner: Server detected - initializing spawning")
	if auto_start and enabled and not has_started:
		has_started = true
		start_spawning()

func start_spawning() -> void:
	# Double check we're the server
	if multiplayer.multiplayer_peer != null and not multiplayer.is_server():
		return

	# Prevent multiple starts
	if spawn_timer and not spawn_timer.is_stopped():
		return

	if spawn_timer:
		spawn_timer.start()
		print("Enemy spawner started at ", global_position)

func stop_spawning() -> void:
	if spawn_timer:
		spawn_timer.stop()
		print("Enemy spawner stopped")

func _on_spawn_timer_timeout() -> void:
	# Only server spawns
	if multiplayer.multiplayer_peer != null and not multiplayer.is_server():
		return

	if not enabled:
		return

	# Clean up null references (dead enemies)
	active_enemies = active_enemies.filter(func(e): return is_instance_valid(e))

	# Check if we've reached max enemies
	if active_enemies.size() >= max_enemies:
		return

	spawn_enemy()

func spawn_enemy() -> void:
	# Only server can spawn
	if multiplayer.multiplayer_peer != null and not multiplayer.is_server():
		push_error("Client tried to spawn enemy - this should never happen!")
		return

	if not enemy_scene:
		push_error("Enemy scene not set in spawner!")
		return

	if not is_inside_tree():
		push_warning("Spawner not in tree yet, skipping spawn")
		return

	# Generate unique enemy ID
	enemy_id_counter += 1
	var enemy_id = enemy_id_counter

	# Random position within spawn radius
	var random_offset = Vector3(
		randf_range(-spawn_radius, spawn_radius),
		0,
		randf_range(-spawn_radius, spawn_radius)
	)
	var spawn_position = global_position + random_offset

	# Use RPC to spawn on all clients (including server with call_local)
	if multiplayer.multiplayer_peer != null:
		# In multiplayer, use RPC
		rpc("_create_enemy", enemy_id, spawn_position)
	else:
		# In single-player, spawn directly
		_create_enemy(enemy_id, spawn_position)

@rpc("authority", "call_local", "reliable")
func _create_enemy(enemy_id: int, spawn_position: Vector3) -> void:
	if not enemy_scene:
		return

	# Create enemy instance
	var enemy = enemy_scene.instantiate()
	enemy.global_position = spawn_position

	# Give it a unique, consistent name across all clients
	enemy.name = "Enemy_" + str(enemy_id)

	# Add to scene tree
	get_parent().add_child(enemy, true)  # force_readable_name for networking

	# Add enemy to group for damage tracking
	enemy.add_to_group("enemies")

	# Track this enemy (only on server)
	if multiplayer.multiplayer_peer == null or multiplayer.is_server():
		active_enemies.append(enemy)
		# Only print on server to avoid duplicate logs
		print("Spawned enemy at ", enemy.global_position, " (Total: ", active_enemies.size(), ")")

	# Connect to enemy death if possible
	if enemy.has_signal("tree_exiting"):
		enemy.tree_exiting.connect(_on_enemy_died.bind(enemy))

func _on_enemy_died(enemy: Node) -> void:
	# Remove from tracking
	active_enemies.erase(enemy)

func _process(delta: float) -> void:
	if multiplayer.multiplayer_peer != null and not multiplayer.is_server():
		return

	if not check_despawn:
		return

	# Check for enemies too far from any player
	if players_node:
		_check_despawn_distance()

func _check_despawn_distance() -> void:
	var player_positions: Array[Vector3] = []

	# Gather all player positions
	for child in players_node.get_children():
		if child is CharacterBody3D:
			player_positions.append(child.global_position)

	if player_positions.is_empty():
		return

	# Check each enemy
	for enemy in active_enemies:
		if not is_instance_valid(enemy):
			continue

		var too_far = true
		for player_pos in player_positions:
			if enemy.global_position.distance_to(player_pos) < despawn_distance:
				too_far = false
				break

		if too_far:
			enemy.queue_free()
			active_enemies.erase(enemy)

## Public methods for controlling spawner
func set_spawn_interval(interval: float) -> void:
	spawn_interval = interval
	if spawn_timer:
		spawn_timer.wait_time = interval

func get_active_enemy_count() -> int:
	# Clean up null references first
	active_enemies = active_enemies.filter(func(e): return is_instance_valid(e))
	return active_enemies.size()

func clear_all_enemies() -> void:
	if multiplayer.multiplayer_peer != null and not multiplayer.is_server():
		return

	for enemy in active_enemies:
		if is_instance_valid(enemy):
			enemy.queue_free()
	active_enemies.clear()
