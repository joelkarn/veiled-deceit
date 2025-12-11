extends CharacterBody3D

enum EnemyType {
	REGULAR,
	SPIDER
}

@export var enemy_type: EnemyType = EnemyType.REGULAR
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

# Spider-specific attack variables
var is_jumping: bool = false
var jump_velocity: Vector3 = Vector3.ZERO
var last_special_attack_time: float = 0.0
var special_attack_cooldown: float = 5.0  # Cooldown for jump and poison spray
var next_spider_attack: int = 0  # 0 = jump, 1 = poison spray
var is_charging_attack: bool = false
var charge_start_time: float = 0.0
var charge_duration: float = 1.5  # Seconds to charge before attack
var charge_indicator: Node3D = null
var original_scale: Vector3 = Vector3.ONE

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
	# Set color based on enemy type
	if enemy_type == EnemyType.SPIDER:
		# Spider uses its own texture from the model, no override needed
		pass
	else:
		original_material.albedo_color = Color.WHITE  # White for regular
		mesh_instance.material_override = original_material

	# Store original scale
	original_scale = mesh_instance.scale

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

	# Handle charge animation
	if is_charging_attack:
		var charge_time = (Time.get_ticks_msec() / 1000.0) - charge_start_time
		var charge_progress = charge_time / charge_duration

		if charge_progress >= 1.0:
			# Charge complete, execute attack
			is_charging_attack = false
			_execute_charged_attack()
		else:
			# Update charge visual
			_update_charge_visual(charge_progress)

		# Stop movement during charge
		velocity.x = 0.0
		velocity.z = 0.0
		if not is_on_floor():
			velocity.y += GRAVITY * delta
		else:
			velocity.y = 0.0
	# Handle jump attack physics
	elif is_jumping:
		velocity = jump_velocity
		jump_velocity.y += GRAVITY * delta

		# Check if landed
		if is_on_floor():
			is_jumping = false
			jump_velocity = Vector3.ZERO
			# Deal impact damage to nearby players
			_check_jump_impact_damage()
			# Reset scale
			if mesh_instance:
				mesh_instance.scale = original_scale
	else:
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
			elif enemy_type == EnemyType.SPIDER and distance_to_player <= 15.0:
				# Spider can use special attacks from farther away
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
	if is_charging_attack:
		return  # Already charging

	var current_time = Time.get_ticks_msec() / 1000.0

	# Spider uses special attacks
	if enemy_type == EnemyType.SPIDER:
		# Try special attack first (if cooldown is ready)
		if current_time - last_special_attack_time >= special_attack_cooldown:
			if not target_player or not is_instance_valid(target_player):
				return

			var distance = global_position.distance_to(target_player.global_position)

			# Determine which attack to use based on distance
			if next_spider_attack == 0:  # Jump attack
				# Can jump from any reasonable distance
				last_special_attack_time = current_time
				start_charge_attack(0)  # 0 = jump
				next_spider_attack = 1
			elif distance <= 12.0:  # Poison spray - larger range now
				last_special_attack_time = current_time
				start_charge_attack(1)  # 1 = poison spray
				next_spider_attack = 0
		# Fallback to melee if special is on cooldown and in melee range
		elif current_time - last_attack_time >= attack_cooldown:
			if target_player and is_instance_valid(target_player):
				var distance = global_position.distance_to(target_player.global_position)
				if distance <= attack_range:
					last_attack_time = current_time
					perform_attack()
	else:
		# Regular enemy melee attack
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

func start_charge_attack(attack_type: int) -> void:
	"""Start charging an attack (0 = jump, 1 = poison spray)"""
	is_charging_attack = true
	charge_start_time = Time.get_ticks_msec() / 1000.0
	next_spider_attack = attack_type

	# Create charge indicator
	_create_charge_indicator(attack_type)

	# Sync to clients
	if multiplayer.multiplayer_peer != null:
		rpc("sync_start_charge", attack_type)

func _execute_charged_attack() -> void:
	"""Execute the attack after charging is complete"""
	_remove_charge_indicator()

	if next_spider_attack == 0:
		perform_jump_attack()
	else:
		perform_poison_spray()

func perform_jump_attack() -> void:
	if not target_player or not is_instance_valid(target_player):
		return

	print("[Spider] Performing jump attack!")
	is_jumping = true

	# Calculate jump direction and force
	var direction = (target_player.global_position - global_position).normalized()
	direction.y = 0  # Keep horizontal

	# Adjust horizontal speed based on distance to land closer
	var distance = global_position.distance_to(target_player.global_position)
	var horizontal_speed = min(distance * 0.6, 10.0)  # Scale with distance, max 10

	jump_velocity = direction * horizontal_speed
	jump_velocity.y = 8.0  # Reduced upward force for shorter arc

	# Sync jump to all clients
	if multiplayer.multiplayer_peer != null:
		rpc("sync_jump_attack", global_position, jump_velocity)

@rpc("authority", "call_local", "reliable")
func sync_start_charge(attack_type: int) -> void:
	is_charging_attack = true
	charge_start_time = Time.get_ticks_msec() / 1000.0
	next_spider_attack = attack_type
	_create_charge_indicator(attack_type)

@rpc("authority", "call_local", "reliable")
func sync_jump_attack(start_pos: Vector3, jump_vel: Vector3) -> void:
	global_position = start_pos
	is_jumping = true
	jump_velocity = jump_vel

func perform_poison_spray() -> void:
	if not target_player or not is_instance_valid(target_player):
		return

	print("[Spider] Performing poison spray attack!")

	# Create AOE cone in front of spider
	var forward = -global_transform.basis.z.normalized()
	forward.y = 0

	# Find all players in cone
	var players = get_tree().get_nodes_in_group("players")
	for player in players:
		if player and is_instance_valid(player):
			var to_player = (player.global_position - global_position).normalized()
			to_player.y = 0

			var distance = global_position.distance_to(player.global_position)
			var angle = forward.dot(to_player)

			# Cone: 12m range, 90 degree angle (cos(45°) = 0.707)
			if distance <= 12.0 and angle >= 0.3:
				if player.has_method("take_damage"):
					player.take_damage(attack_damage * 1.5)  # 1.5x damage for spray
					print("[Spider] Hit ", player.name, " with poison spray!")

	# Sync visual effect to all clients
	if multiplayer.multiplayer_peer != null:
		rpc("sync_poison_spray", global_position, forward)

@rpc("authority", "call_local", "reliable")
func sync_poison_spray(spray_pos: Vector3, spray_direction: Vector3) -> void:
	# Create visual effect for poison spray
	_create_poison_spray_effect(spray_pos, spray_direction)

func _create_poison_spray_effect(spray_pos: Vector3, spray_direction: Vector3) -> void:
	# Create a temporary visual for the poison spray
	var spray_visual = CSGBox3D.new()
	spray_visual.size = Vector3(8, 1.5, 12)  # Much larger: 8m wide, 12m deep

	var material = StandardMaterial3D.new()
	material.albedo_color = Color(0.5, 0, 0.5, 0.4)  # Purple with transparency
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	spray_visual.material = material

	get_parent().add_child(spray_visual)
	spray_visual.global_position = spray_pos + spray_direction * 6  # Position at center of cone
	spray_visual.look_at(spray_pos + spray_direction * 20, Vector3.UP)

	# Remove after a short duration
	await get_tree().create_timer(0.5).timeout
	if is_instance_valid(spray_visual):
		spray_visual.queue_free()

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

	print("Enemy died! Type: ", enemy_type, ", Killed by player: ", last_attacker_id)

	# Track quest progress for the player who killed it
	if last_attacker_id > 0 and QuestManager:
		# Track different quest types based on enemy type
		if enemy_type == EnemyType.SPIDER:
			# Spiders count towards spider quest
			QuestManager.add_progress_by_type(QuestData.QuestType.KILL_ENEMIES, 1, last_attacker_id)
			# Also give poison to hunters who have the quest
			_try_give_poison_to_hunter(last_attacker_id)
		else:
			# Regular enemies count towards generic kill quest
			QuestManager.add_progress_by_type(QuestData.QuestType.KILL_ENEMIES, 1, last_attacker_id)

	# Broadcast death to all clients with the attacker ID
	rpc("sync_enemy_death", last_attacker_id)
	queue_free()

func _try_give_poison_to_hunter(player_id: int) -> void:
	# Find the player who killed this spider
	var players = get_tree().get_nodes_in_group("players")
	for player in players:
		if player and is_instance_valid(player) and player.get("player_id") == player_id:
			# Check if player is a hunter with the kill_spiders quest
			if player.get("player_name") == "Hunter":
				# Check if hunter has the quest
				if QuestManager and QuestManager.has_method("has_quest"):
					if QuestManager.has_quest("kill_spiders", player_id):
						# Give poison (or update poison count)
						print("[Enemy] Hunter ", player_id, " collected poison from spider!")
						# The poison is tracked via the quest progress
			break

func _create_charge_indicator(attack_type: int) -> void:
	"""Create visual indicator for charging attack"""
	if charge_indicator:
		charge_indicator.queue_free()

	charge_indicator = Node3D.new()
	get_parent().add_child(charge_indicator)
	charge_indicator.global_position = global_position + Vector3(0, 2, 0)

	# Create a glowing sphere indicator
	var sphere = CSGSphere3D.new()
	sphere.radius = 0.5
	var material = StandardMaterial3D.new()

	if attack_type == 0:  # Jump attack
		material.albedo_color = Color.ORANGE
		material.emission_enabled = true
		material.emission = Color.ORANGE
		material.emission_energy_multiplier = 2.0
	else:  # Poison spray
		material.albedo_color = Color.GREEN_YELLOW
		material.emission_enabled = true
		material.emission = Color.GREEN_YELLOW
		material.emission_energy_multiplier = 2.0

	sphere.material = material
	charge_indicator.add_child(sphere)

func _update_charge_visual(progress: float) -> void:
	"""Update visual during charge - squat animation for jump"""
	if next_spider_attack == 0 and mesh_instance:  # Jump attack - squat down
		# Squat: scale down Y, scale up slightly X and Z
		var squat_amount = 0.7 + (0.3 * progress)  # From 0.7 to 1.0
		mesh_instance.scale.y = original_scale.y * squat_amount
		mesh_instance.scale.x = original_scale.x * (1.0 + (1.0 - squat_amount) * 0.3)
		mesh_instance.scale.z = original_scale.z * (1.0 + (1.0 - squat_amount) * 0.3)

	# Update indicator position
	if charge_indicator:
		charge_indicator.global_position = global_position + Vector3(0, 2, 0)
		# Pulse the indicator
		if charge_indicator.get_child_count() > 0:
			var sphere = charge_indicator.get_child(0)
			var pulse = 0.5 + sin(progress * PI * 4) * 0.2  # Pulse effect
			sphere.scale = Vector3.ONE * (1.0 + progress) * pulse

func _remove_charge_indicator() -> void:
	"""Remove charge indicator and reset scale"""
	if charge_indicator:
		charge_indicator.queue_free()
		charge_indicator = null

	if mesh_instance:
		mesh_instance.scale = original_scale

func _check_jump_impact_damage() -> void:
	# Deal damage to all players within impact radius
	var players = get_tree().get_nodes_in_group("players")
	for player in players:
		if player and is_instance_valid(player):
			var distance = global_position.distance_to(player.global_position)
			if distance <= 3.0:  # 3m impact radius
				if player.has_method("take_damage"):
					player.take_damage(attack_damage * 2.0)  # 2x damage for jump attack
					print("[Spider] Jump attack hit ", player.name, "!")

@rpc("authority", "call_remote", "reliable")
func sync_enemy_death(_attacker_id: int) -> void:
	# Quest progress is already tracked on server and synced via QuestManager RPC
	# No need to track here on client - just handle death
	queue_free()
