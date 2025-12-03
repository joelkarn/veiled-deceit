extends CharacterBody3D

@export var max_health: float = 100.0
@export var health: float = 100.0
@export var move_speed: float = 3.0
@export var attack_range: float = 2.0
@export var attack_damage: float = 10.0
@export var attack_cooldown: float = 1.0

@onready var mesh_instance: MeshInstance3D = $MeshInstance3D
@onready var nav_agent: NavigationAgent3D = $NavigationAgent3D

var original_material: StandardMaterial3D
var is_flashing := false
var last_attacker_id: int = 0  # Track who killed this enemy
var target_player: CharacterBody3D = null
var last_attack_time: float = 0.0
var is_aggroed: bool = false  # Only aggro when hit
var aggroed_player: CharacterBody3D = null  # Track which player we're aggroed to
const GRAVITY: float = -45.0

# Debug timer for periodic logging
var debug_timer: float = 0.0
const DEBUG_INTERVAL: float = 5.0

func _ready():
	health = max_health

	# Set collision layers (same as players):
	# Layer 1 = Environment (ground, walls, obstacles)
	# Layer 2 = Players/Entities
	# Enemies should collide with environment (layer 1) but not with players/other entities (layer 2)
	collision_layer = 2  # Enemy is on layer 2 (same as players)
	collision_mask = 1    # Enemy only collides with layer 1 (environment)

	# Create a unique material for this enemy
	original_material = StandardMaterial3D.new()
	original_material.albedo_color = Color.WHITE
	mesh_instance.material_override = original_material

	# Wait for navigation to be ready
	call_deferred("setup_navigation")

	# If we're the server, listen for new clients and send them our state
	if multiplayer.multiplayer_peer != null and multiplayer.is_server():
		multiplayer.peer_connected.connect(_on_new_peer_connected)
		# Also broadcast to any existing clients
		await get_tree().create_timer(0.1).timeout
		broadcast_state_to_all_clients()

func setup_navigation():
	# Wait for navigation map to be ready
	await get_tree().physics_frame
	await get_tree().physics_frame

	# Configure navigation agent
	if nav_agent:
		nav_agent.path_desired_distance = 0.5
		nav_agent.target_desired_distance = 0.5
		nav_agent.path_max_distance = 3.0
		nav_agent.avoidance_enabled = true
		nav_agent.radius = 0.5

	print("Enemy navigation ready at ", global_position)

func _physics_process(delta: float) -> void:
	# Only the host controls enemy movement and attacks
	# In single-player (no multiplayer peer), act as server
	if multiplayer.multiplayer_peer != null and not multiplayer.is_server():
		return

	# Apply gravity
	if not is_on_floor():
		velocity.y += GRAVITY * delta
	else:
		velocity.y = 0.0

	# Only pursue player if aggroed
	if is_aggroed:
		# Check if aggroed player is still valid
		if aggroed_player and is_instance_valid(aggroed_player):
			target_player = aggroed_player
		else:
			# Aggroed player is gone, de-aggro
			is_aggroed = false
			aggroed_player = null
			target_player = null

	if target_player and is_instance_valid(target_player):
		var distance_to_player = global_position.distance_to(target_player.global_position)

		# Always update navigation target to player
		if nav_agent:
			nav_agent.target_position = target_player.global_position

		# Check if in attack range
		if distance_to_player <= attack_range:
			# Stop moving and attack
			velocity.x = 0.0
			velocity.z = 0.0
			attempt_attack()
		else:
			# Move towards player using navigation
			if nav_agent.is_navigation_finished():
				velocity.x = 0.0
				velocity.z = 0.0
			else:
				var next_position = nav_agent.get_next_path_position()
				var direction = (next_position - global_position).normalized()
				direction.y = 0.0  # Keep movement horizontal

				velocity.x = direction.x * move_speed
				velocity.z = direction.z * move_speed

				# Face the direction of movement
				if direction.length() > 0.01:
					look_at(global_position + direction, Vector3.UP)
	else:
		# No target, slow down
		velocity.x = 0.0
		velocity.z = 0.0

	move_and_slide()

	# Logging removed for production. Movement and aggro logic simplified.

	# Sync position to clients if in multiplayer
	if multiplayer.multiplayer_peer != null and multiplayer.is_server():
		rpc("sync_position", global_position, rotation)

func aggro_to_player(attacker_id: int) -> void:
	is_aggroed = true
	# Find the player who hit us
	var players = get_tree().get_nodes_in_group("players")
	for player in players:
		if player and is_instance_valid(player):
			# Use player_id property which matches peer_id/multiplayer_authority
			var player_pid = player.get("player_id")

			if player_pid == attacker_id:
				aggroed_player = player
				# Immediately update navigation target to player position
				if nav_agent and aggroed_player:
					nav_agent.target_position = aggroed_player.global_position
				# Sync aggro to all clients
				if multiplayer.multiplayer_peer != null:
					rpc("sync_aggro", attacker_id)
				break

@rpc("authority", "call_remote", "reliable")
func sync_aggro(attacker_id: int) -> void:
	is_aggroed = true
	# Find the player on this client
	var players = get_tree().get_nodes_in_group("players")
	for player in players:
		if player and is_instance_valid(player):
			# Use player_id property which matches peer_id/multiplayer_authority
			var player_pid = player.get("player_id")
			if player_pid == attacker_id:
				aggroed_player = player
				break

func _on_new_peer_connected(peer_id: int) -> void:
	# When a new client connects, send them our current state
	if multiplayer.is_server():
		var aggro_id = 0
		if is_aggroed and aggroed_player and is_instance_valid(aggroed_player):
			if aggroed_player.get("player_id") != null:
				aggro_id = aggroed_player.player_id

		print("Server sending state to new peer ", peer_id, " - Health: ", health, ", Aggroed: ", is_aggroed, ", Aggro ID: ", aggro_id)
		rpc_id(peer_id, "receive_initial_state", health, is_aggroed, aggro_id)

func broadcast_state_to_all_clients() -> void:
	# Send current state to all connected clients
	if not multiplayer.is_server():
		return

	var aggro_id = 0
	if is_aggroed and aggroed_player and is_instance_valid(aggroed_player):
		if aggroed_player.get("player_id") != null:
			aggro_id = aggroed_player.player_id

	print("Server broadcasting state to all clients - Health: ", health, ", Aggroed: ", is_aggroed, ", Aggro ID: ", aggro_id)
	rpc("receive_initial_state", health, is_aggroed, aggro_id)

@rpc("any_peer", "call_remote", "reliable")
func request_initial_state(requesting_peer: int) -> void:
	# Only server responds
	if not multiplayer.is_server():
		return

	# Send current state to the requesting client
	var aggro_id = 0
	if is_aggroed and aggroed_player and is_instance_valid(aggroed_player):
		if aggroed_player.get("player_id") != null:
			aggro_id = aggroed_player.player_id

	print("Server sending initial state to peer ", requesting_peer, " - Health: ", health, ", Aggroed: ", is_aggroed, ", Aggro ID: ", aggro_id)
	rpc_id(requesting_peer, "receive_initial_state", health, is_aggroed, aggro_id)

@rpc("authority", "call_remote", "reliable")
func receive_initial_state(current_health: float, aggroed: bool, aggro_player_id: int) -> void:
	print("Client received initial state - Health: ", current_health, ", Aggroed: ", aggroed, ", Aggro player ID: ", aggro_player_id)
	health = current_health
	is_aggroed = aggroed

	if is_aggroed and aggro_player_id > 0:
		# Find the aggroed player
		var players = get_tree().get_nodes_in_group("players")
		for player in players:
			if player and is_instance_valid(player):
				if player.get("player_id") != null and player.player_id == aggro_player_id:
					aggroed_player = player
					break

@rpc("authority", "call_remote", "unreliable")
func sync_position(pos: Vector3, rot: Vector3) -> void:
	# Only clients update from this
	if multiplayer.multiplayer_peer != null and multiplayer.is_server():
		return

	global_position = pos
	rotation = rot

func find_nearest_player() -> void:
	var players = get_tree().get_nodes_in_group("players")
	var nearest_distance = INF
	target_player = null

	for player in players:
		if player and is_instance_valid(player):
			var distance = global_position.distance_to(player.global_position)
			if distance < nearest_distance:
				nearest_distance = distance
				target_player = player

func attempt_attack() -> void:
	var current_time = Time.get_ticks_msec() / 1000.0
	if current_time - last_attack_time >= attack_cooldown:
		last_attack_time = current_time
		perform_attack()

func perform_attack() -> void:
	if target_player and is_instance_valid(target_player):
		# Check if still in range
		var distance = global_position.distance_to(target_player.global_position)
		if distance <= attack_range:
			# Deal damage to the player
			if target_player.has_method("take_damage"):
				target_player.take_damage(attack_damage)
				print("Enemy hit player for ", attack_damage, " damage!")

func take_damage(amount: float, attacker_id: int = 0) -> void:
	print("ENEMY: take_damage called! Amount:", amount, "Attacker ID:", attacker_id, "Current health:", health)
	# Only host processes damage
	# In single-player (no multiplayer peer), act as server
	if multiplayer.multiplayer_peer != null and not multiplayer.is_server():
		print("ENEMY: Not server, ignoring damage.")
		return

	health -= amount
	print("ENEMY: Health after damage:", health)
	health = max(0, health)  # Clamp to 0

	# Track the last attacker and aggro to them
	if attacker_id > 0:
		last_attacker_id = attacker_id
		# Aggro to the attacker
		if not is_aggroed:
			aggro_to_player(attacker_id)
	# Sync health to all clients
	sync_health()

	# Visual feedback - flash red
	if mesh_instance:
		flash_damage()

	if health <= 0:
		print("ENEMY: Health <= 0, dying!")
		die()

func sync_health() -> void:
	if multiplayer.multiplayer_peer != null and not multiplayer.is_server():
		return

	# Sync health to all clients
	if multiplayer.multiplayer_peer != null:
		rpc("update_health", health)

@rpc("authority", "call_remote", "reliable")
func update_health(new_health: float) -> void:
	health = new_health

	# Visual feedback on clients
	if mesh_instance:
		flash_damage()

	if health <= 0:
		die()

func flash_damage() -> void:
	# Prevent overlapping flashes
	if is_flashing:
		return

	is_flashing = true
	# Flash red
	original_material.albedo_color = Color.RED
	await get_tree().create_timer(0.15).timeout
	# Flash back to white
	original_material.albedo_color = Color.WHITE
	is_flashing = false

func die() -> void:
	if multiplayer.multiplayer_peer != null and not multiplayer.is_server():
		return

	print("Enemy died! Killed by player: ", last_attacker_id)

	# Track quest progress for the player who killed it
	if last_attacker_id > 0 and QuestManager:
		QuestManager.add_progress_by_type(QuestData.QuestType.KILL_ENEMIES, 1, last_attacker_id)

	# Broadcast death to all clients with the attacker ID
	rpc("sync_enemy_death", last_attacker_id)
	queue_free()

@rpc("authority", "call_remote", "reliable")
func sync_enemy_death(attacker_id: int) -> void:
	# Quest progress is already tracked on server and synced via QuestManager RPC
	# No need to track here on client - just handle death
	queue_free()
