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
const GRAVITY: float = -45.0

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

func setup_navigation():
	await get_tree().physics_frame
	# Navigation is now ready

func _physics_process(delta: float) -> void:
	# Only the host controls enemy movement and attacks
	if not multiplayer.is_server():
		return

	# Apply gravity
	if not is_on_floor():
		velocity.y += GRAVITY * delta
	else:
		velocity.y = 0.0

	# Find nearest player
	find_nearest_player()

	if target_player and is_instance_valid(target_player):
		var distance_to_player = global_position.distance_to(target_player.global_position)

		# Check if in attack range
		if distance_to_player <= attack_range:
			# Stop moving and attack
			velocity.x = 0.0
			velocity.z = 0.0
			attempt_attack()
		else:
			# Move towards player using navigation
			nav_agent.target_position = target_player.global_position

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
	# Only host processes damage
	if not multiplayer.is_server():
		return

	health -= amount
	health = max(0, health)  # Clamp to 0
	print("Enemy took ", amount, " damage. Health: ", health)

	# Track the last attacker
	if attacker_id > 0:
		last_attacker_id = attacker_id

	# Sync health to all clients
	sync_health()

	# Visual feedback - flash red
	if mesh_instance:
		flash_damage()

	if health <= 0:
		die()

func sync_health() -> void:
	if not multiplayer.is_server():
		return

	# Sync health to all clients
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
	if not multiplayer.is_server():
		return

	print("Enemy died! Killed by player: ", last_attacker_id)

	# Track quest progress for the host (if they killed it)
	var local_player_id = multiplayer.get_unique_id()
	if last_attacker_id == local_player_id and QuestManager:
		QuestManager.add_progress_by_type(QuestData.QuestType.KILL_ENEMIES, 1)

	# Broadcast death to all clients with the attacker ID
	rpc("sync_enemy_death", last_attacker_id)
	queue_free()

@rpc("authority", "call_remote", "reliable")
func sync_enemy_death(attacker_id: int) -> void:
	# Track quest progress only for the player who killed this enemy
	var local_player_id = multiplayer.get_unique_id()
	if attacker_id == local_player_id and QuestManager:
		QuestManager.add_progress_by_type(QuestData.QuestType.KILL_ENEMIES, 1)

	queue_free()
