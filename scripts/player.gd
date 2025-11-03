extends CharacterBody3D

# Network properties
@export var player_id: int = 0
var is_local_player: bool = false
var is_host: bool = false

@onready var camera_mount: Node3D = $camera_mount
@onready var animation_player: AnimationPlayer = $visuals/mixamo_base/AnimationPlayer
@onready var visuals: Node3D = $visuals
@onready var camera: Camera3D = $camera_mount/Camera3D

@export var pitch_min_deg := -80.0
@export var pitch_max_deg := 20.0
var _pitch := 0.0

@export var max_health: float = 100.0
@export var health: float = 100.0

@export var health_bar_offset_y = 2

# Input buffer for network
var input_buffer = {
	"movement": Vector2.ZERO,
	"jump": false,
	"attack": false,
	"camera_rotation": Vector2.ZERO,  # Only set when mouse moves
	"speed_multiplier": 1.0
}

# Network state sync
var sync_timer: float = 0.0
const SYNC_INTERVAL: float = 0.05  # ~20 Hz - Lower frequency for non-competitive games, reduces network load

# Client-to-server position update timer (for local players)
var position_update_timer: float = 0.0
const POSITION_UPDATE_INTERVAL: float = 0.05  # ~20 Hz - Send position updates to server

# Server reconciliation for local player (disabled - client is fully authoritative for movement)
var last_server_position: Vector3 = Vector3.ZERO
var position_error_threshold: float = 10.0  # Only reconcile for very large errors (teleporting/desync)
var smooth_correction_speed: float = 3.0  # How fast to correct position (units per second) - very gentle

# Server-side position validation
var last_validated_position: Vector3 = Vector3.ZERO
var last_validated_rotation: float = 0.0
var last_validation_time: float = 0.0  # Time in seconds since game start

# Remote player interpolation (for non-local players on clients)
var target_position: Vector3 = Vector3.ZERO
var target_rotation_y: float = 0.0
var target_camera_pitch: float = 0.0
var target_velocity: Vector3 = Vector3.ZERO
var has_target_state: bool = false  # Whether we've received a state update
var remote_interpolation_speed: float = 15.0  # units per second

const SPEED := 7.0
const GRAVITY := -45.0
const JUMP_VELOCITY := 13.0

@export var sens_horizontal := 0.1
@export var sens_vertical := 0.1
@export var fov: float = 50.0  # fish eye

var init_jump_input := Vector2.ZERO
var init_jump_dir := Vector2.ZERO

var is_jumping := false

const AUTO_ATTACK_COOLDOWN := 0.5
const AUTO_ATTACK_WINDOW_SECONDS := 0.1
const AUTO_ATTACK_DAMAGE := 10
# Local offset of the hitbox relative to the player (in front, chest height)
const MELEE_OFFSET := Vector3(0.0, 1.0, -1.5)
# Size of the hitbox (BoxShape3D): width (X), height (Y), depth (Z forward)
const MELEE_BOX_SIZE := Vector3(1.8, 1.2, 1.6)

var auto_attack_on_cooldown := false
var melee_area: Area3D
var melee_shape: CollisionShape3D
var auto_attack_active := false
var already_hit := {} # Dictionary used as a set to prevent multi-hits per swing

# --------------------------
# Debugging (hitbox visual)
# --------------------------
@export var show_melee_debug := true
var melee_debug_mesh: MeshInstance3D
var melee_debug_mat_idle: StandardMaterial3D
var melee_debug_mat_active: StandardMaterial3D

var ui_manager: Node

func _ready() -> void:
	print("=== PLAYER _ready() ===")
	print("  Player ID: ", player_id)
	print("  Is local: ", is_local_player)
	print("  Is host: ", is_host)
	
	health = max_health
	velocity = Vector3.ZERO  # Initialize velocity to zero
	last_server_position = position  # Initialize last server position
	target_position = position  # Initialize target position for remote players
	has_target_state = false  # Reset state flag
	
	# Initialize validation state
	last_validated_position = position
	last_validated_rotation = rotation.y
	last_validation_time = Time.get_ticks_msec() / 1000.0  # Convert to seconds
	
	# Set multiplayer authority - host has authority over all player instances
	# Use call_deferred to ensure multiplayer is initialized first
	call_deferred("_set_multiplayer_authority")
	
	# Debug: Log initial position
	print("  Initial position set to: ", position)
	
	if camera_mount:
		_pitch = camera_mount.rotation.x
	
	ui_manager = get_node_or_null("../UIManager")
	
	print("  Creating melee area...")
	_create_melee_area()
	_create_melee_debug_mesh()
	_update_melee_debug_visual(false)
	print("  Player _ready() complete!")
	
	# Setup camera after everything is ready (for local player)
	# Use call_deferred to ensure @onready variables are initialized
	call_deferred("_setup_camera")

func _setup_camera() -> void:
	# Setup camera after all @onready variables are initialized
	if camera:
		camera.fov = fov
		# Only local player should see their camera
		if is_local_player:
			camera.current = true
			print("  Camera enabled for local player (Player ID: ", player_id, ")")
		else:
			camera.current = false
			print("  Disabled camera for remote player (Player ID: ", player_id, ")")
	else:
		print("  WARNING: Camera not found! (Player ID: ", player_id, ")")
	
	# Also ensure camera_mount pitch is set
	if camera_mount:
		_pitch = camera_mount.rotation.x

func _set_multiplayer_authority() -> void:
	# Set multiplayer authority - only if multiplayer is active and we're in the tree
	if not is_inside_tree():
		print("  WARNING: Node not in tree yet, skipping authority setup")
		return
		
	if multiplayer.multiplayer_peer != null:
		set_multiplayer_authority(1)  # Host has authority
		print("  Set multiplayer authority to host (1)")
	else:
		print("  WARNING: Multiplayer not initialized, skipping authority setup")

func _input(event: InputEvent) -> void:
	# Only local player processes input
	if not is_local_player:
		return
	
	# Don't process input if menu is open
	if ui_manager and ui_manager.is_menu_active():
		return
	
	if event is InputEventMouseMotion:
		handle_mouse_motion(event)
		input_buffer["camera_rotation"] = event.relative
		

	if event.is_action_pressed("attack"):
		input_buffer["attack"] = true
		auto_attack()

func _physics_process(delta: float) -> void:
	# Stop movement if menu
	var menu_active = ui_manager and ui_manager.is_menu_active()
	if menu_active and is_local_player:
		stop_movement(delta)
	
	# CLIENT-AUTHORITATIVE MOVEMENT: Local players process movement immediately
	if is_local_player:
		if not menu_active:
			# Collect input for local player
			input_buffer["movement"] = Input.get_vector("left", "right", "forward", "backward")
			input_buffer["jump"] = Input.is_action_just_pressed("jump")
			input_buffer["speed_multiplier"] = 0.5 if Input.is_action_pressed("backward") else 1.0
			
			# Process movement immediately (client-side authority - includes jump)
			process_movement(delta)
			input_buffer["jump"] = false
			
			# Send position updates to server periodically (includes jump state)
			position_update_timer += delta
			if position_update_timer >= POSITION_UPDATE_INTERVAL:
				position_update_timer = 0.0
				send_position_update_to_server()
			
			# Send camera rotation for server display (no movement processing)
			if input_buffer["camera_rotation"] != Vector2.ZERO:
				send_camera_rotation_to_server()
			
			# Reset camera rotation after sending (prevents drift)
			input_buffer["camera_rotation"] = Vector2.ZERO
		else:
			# Menu is open, still send position updates (but not movement)
			position_update_timer += delta
			if position_update_timer >= POSITION_UPDATE_INTERVAL:
				position_update_timer = 0.0
				send_position_update_to_server()
		
		# Apply gentle server reconciliation for local player (only if client)
		if not multiplayer.is_server():
			_apply_server_reconciliation(delta)
	
	# SERVER: Update visuals and animation for remote players (movement is client-authoritative)
	elif multiplayer.is_server():
		# Server doesn't process movement - it only accepts position updates from clients
		# Position updates are handled via validate_client_position_state()
		# But we need to update visuals rotation and animation for remote players on host
		if not is_local_player:
			_update_remote_player_visuals_and_animation(delta)
	
	# REMOTE PLAYERS ON CLIENTS: Interpolate toward target position
	else:
		if has_target_state:
			_interpolate_remote_player(delta)
		else:
			# If we haven't received state yet, just apply basic gravity to prevent falling
			if not is_on_floor():
				velocity.y += GRAVITY * delta
				move_and_slide()
	
	# Sync state periodically (host only) - ALWAYS do this, even when menu is open
	# This ensures all players see movement updates even when host is in menu
	if multiplayer.is_server():
		sync_timer += delta
		if sync_timer >= SYNC_INTERVAL:
			sync_timer = 0.0
			sync_player_state()

func process_movement(delta: float) -> void:
	var speed_multiplier = input_buffer.get("speed_multiplier", 1.0)
	
	# For local player or remote players on host, use input buffer
	# Remote players on host get their input via RPC which populates input_buffer
	var input_dir: Vector2 = input_buffer.get("movement", Vector2.ZERO)
	
	# Calculate movement direction using the rotation from input buffer
	# For remote players, this uses the rotation they sent (from their client)
	# For local players, this uses current rotation
	var player_rotation_y = input_buffer.get("player_rotation_y", rotation.y)
	var rotation_basis = Basis.from_euler(Vector3(0, player_rotation_y, 0))
	var direction: Vector3 = (rotation_basis * Vector3(input_dir.x, 0.0, input_dir.y))
	
	# Debug: Log movement for remote players on host
	#if multiplayer.is_server() and not is_local_player:
		#if input_dir != Vector2.ZERO:
			#print("  [HOST] Processing movement for Player ", player_id, ": input_dir=", input_dir, " rotation_y=", player_rotation_y, " direction=", direction)


	# In air (fall or jump)
	if not is_on_floor():
		# Apply gravity only when in air
		velocity.y += GRAVITY * delta

		if is_jumping:
			handle_jumping(init_jump_input, direction, input_dir, speed_multiplier)
		else:
			handle_falling(direction, speed_multiplier)
		
		move_and_slide()
		return

	# If on the floor, allow horizontal movement
	is_jumping = false
	# Animate and set velocity
	if direction != Vector3.ZERO:
		if animation_player and animation_player.current_animation != "running":
			animation_player.play("running")
		# Rotate visuals to face movement direction
		visuals.look_at(position + direction)
		
		velocity.x = direction.x * SPEED * speed_multiplier
		velocity.z = direction.z * SPEED * speed_multiplier
	else:
		if animation_player and animation_player.current_animation != "idle":
			animation_player.play("idle")
		# Stop moving horizontally
		velocity.x = 0.0
		velocity.z = 0.0

	if input_buffer.get("jump", false):
		is_jumping = true
		velocity.y = JUMP_VELOCITY
		init_jump_input = input_dir
		init_jump_dir.x = direction.x
		init_jump_dir.y = direction.z
		input_buffer["jump"] = false

	move_and_slide()

func handle_jumping(initial_input: Vector2, direction: Vector3, input_dir: Vector2, speed_multiplier: float) -> void:
	# Jump with no initial horizontal velocity
	if initial_input == Vector2.ZERO:
		# If input in any direction, go slow
		if direction != Vector3.ZERO:
			velocity.x = direction.x * SPEED * 0.25 * speed_multiplier
			velocity.z = direction.z * SPEED * 0.25 * speed_multiplier
		else:
			# If no input, go straight up and down
			velocity.x = 0.0
			velocity.z = 0.0
		return

	# Jump with initial horizontal velocity
	# If input direction key is pressed, continue with SPEED
	if input_dir == initial_input:
		velocity.x = init_jump_dir.x * SPEED * speed_multiplier
		velocity.z = init_jump_dir.y * SPEED * speed_multiplier
		return

	# If opposite of input direction key is pressed, go slow
	if input_dir + initial_input == Vector2.ZERO:
		velocity.x = init_jump_dir.x * SPEED * 0.25 * speed_multiplier
		velocity.z = init_jump_dir.y * SPEED * 0.25 * speed_multiplier
		return

	# If no key related to input direction is pressed, go medium slow
	velocity.x = init_jump_dir.x * SPEED * 0.5 * speed_multiplier
	velocity.z = init_jump_dir.y * SPEED * 0.5 * speed_multiplier

func handle_falling(direction: Vector3, speed_multiplier: float) -> void:
	# Placeholder for falling behavior
	velocity.x = direction.x * SPEED * 0.5 * speed_multiplier
	velocity.z = direction.z * SPEED * 0.5 * speed_multiplier

# ----------------------------
# Melee hitbox: Area3D setup
# ----------------------------
func _create_melee_area() -> void:
	melee_area = Area3D.new()
	melee_shape = CollisionShape3D.new()

	var box := BoxShape3D.new()
	box.size = MELEE_BOX_SIZE
	melee_shape.shape = box

	add_child(melee_area)
	melee_area.add_child(melee_shape)

	# Place it in front of the player; since it's a child, it follows rotation
	melee_area.transform = Transform3D(Basis(), MELEE_OFFSET)

	# Detect bodies only, keep off by default
	melee_area.monitoring = false
	melee_area.monitorable = false

	# Optional: restrict to an "enemies" layer if you use layers
	# melee_area.collision_mask = 1 << 3  # example: only layer 3

	# Connect signal once
	melee_area.body_entered.connect(_on_melee_area_body_entered)

# Toggle the melee window
func _enable_melee_area(enable: bool) -> void:
	if enable:
		melee_area.monitoring = true
		melee_area.monitorable = true
	else:
		melee_area.monitoring = false
		melee_area.monitorable = false
	_update_melee_debug_visual(enable)

# ----------------------------
# Melee attack flow
# ----------------------------
func auto_attack() -> void:
	if auto_attack_active:
		return

	if auto_attack_on_cooldown:
		return

	auto_attack_active = true
	auto_attack_on_cooldown = true
	already_hit.clear()

	if animation_player and animation_player.has_animation("attack"):
		animation_player.play("attack")

	# Enable hitbox for the short active window
	_enable_melee_area(true)
	await get_tree().create_timer(AUTO_ATTACK_WINDOW_SECONDS).timeout
	_enable_melee_area(false)

	auto_attack_active = false

	# Cooldown timer before next attack allowed
	await get_tree().create_timer(AUTO_ATTACK_COOLDOWN).timeout
	auto_attack_on_cooldown = false

# Called when a body enters the hitbox during the active window
func _on_melee_area_body_entered(body: Node) -> void:
	if not auto_attack_active:
		return

	if already_hit.has(body):
		return

	already_hit[body] = true

	if body.has_method("take_damage"):
		if multiplayer.is_server():
			# Host processes damage directly
			body.take_damage(AUTO_ATTACK_DAMAGE, player_id)
		else:
			# Client sends damage request to host
			var network_manager = get_tree().current_scene.get_node_or_null("NetworkManager")
			if network_manager:
				# Send body information for validation
				# Try to identify the body - check if it's a player or enemy
				var body_name = ""
				var body_peer_id = 0
				
				# Check if it's a player (has player_id property)
				if body.get("player_id") != null:
					body_peer_id = body.player_id
					body_name = "Player_" + str(body_peer_id)
				else:
					# It's an enemy or other object - use its name
					body_name = body.name
				
				network_manager.rpc_id(1, "process_damage_request", player_id, body_name, body_peer_id, AUTO_ATTACK_DAMAGE)

# ----------------------------
# Debug mesh for the hitbox
# ----------------------------
func _create_melee_debug_mesh() -> void:
	# Materials
	melee_debug_mat_idle = StandardMaterial3D.new()
	melee_debug_mat_idle.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	melee_debug_mat_idle.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	melee_debug_mat_idle.albedo_color = Color(1.0, 0.0, 0.0, 0.25) # red, semi-transparent
	melee_debug_mat_idle.emission_enabled = true
	melee_debug_mat_idle.emission = Color(1.0, 0.0, 0.0, 0.25)

	melee_debug_mat_active = StandardMaterial3D.new()
	melee_debug_mat_active.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	melee_debug_mat_active.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	melee_debug_mat_active.albedo_color = Color(0.0, 1.0, 0.0, 0.35) # green, semi-transparent
	melee_debug_mat_active.emission_enabled = true
	melee_debug_mat_active.emission = Color(0.0, 1.0, 0.0, 0.35)

	# Mesh that matches the BoxShape3D
	melee_debug_mesh = MeshInstance3D.new()
	var box_mesh := BoxMesh.new()
	box_mesh.size = MELEE_BOX_SIZE
	melee_debug_mesh.mesh = box_mesh
	melee_debug_mesh.material_override = melee_debug_mat_idle

	# Parent it to the melee area so it uses the same transform/offset
	melee_area.add_child(melee_debug_mesh)

	# Draw both sides to reduce clipping visibility issues
	melee_debug_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	melee_debug_mesh.visible = show_melee_debug

func _update_melee_debug_visual(active: bool) -> void:
	if melee_debug_mesh == null:
		return

	# Always base visibility purely on this one flag
	melee_debug_mesh.visible = show_melee_debug

	if not show_melee_debug:
		return

	if active:
		melee_debug_mesh.material_override = melee_debug_mat_active
	else:
		melee_debug_mesh.material_override = melee_debug_mat_idle
		
func stop_movement(delta):
	# Stop animation and movement when menu is open
	if animation_player and animation_player.current_animation != "idle":
		animation_player.play("idle")
	# Just apply gravity and stop horizontal movement
	if not is_on_floor():
		velocity.y += GRAVITY * delta
	else:
		velocity.y = 0.0
	velocity.x = 0.0
	velocity.z = 0.0
	move_and_slide()
	
func handle_mouse_motion(event):
	# Rotate player (horizontal)
	rotate_y(deg_to_rad(-event.relative.x * sens_horizontal))
	
	# Rotate camera (look up and down)
	var delta_pitch_deg: float = -event.relative.y * sens_vertical
	_pitch += deg_to_rad(delta_pitch_deg)
	_pitch = clamp(_pitch, deg_to_rad(pitch_min_deg), deg_to_rad(pitch_max_deg))
	camera_mount.rotation.x = _pitch

func take_damage(amount: float, attacker_id: int = 0) -> void:
	# Only host processes damage
	if not multiplayer.is_server():
		return
	
	health -= amount
	health = max(0, health)  # Clamp to 0
	print("Player ", player_id, " took ", amount, " damage. Health: ", health)
	
	# Sync health to all clients
	sync_health()
	
	if health <= 0:
		die()

func die() -> void:
	if not multiplayer.is_server():
		return
	
	print("Player ", player_id, " died!")
	
	# Reset health
	health = max_health
	
	# Get spawn position for this player
	var network_manager = get_tree().current_scene.get_node_or_null("NetworkManager")
	var spawn_pos = position
	if network_manager and network_manager.spawn_points.size() > 0:
		var spawn_index = (player_id - 1) % network_manager.spawn_points.size()
		spawn_pos = network_manager.spawn_points[spawn_index]
	
	# Reset position to spawn
	position = spawn_pos
	velocity = Vector3.ZERO
	
	# Sync death and respawn to all clients
	rpc("sync_death_and_respawn", spawn_pos, health)

@rpc("authority", "call_remote", "reliable")
func sync_death_and_respawn(spawn_pos: Vector3, new_health: float) -> void:
	print("Player ", player_id, " died and respawned at ", spawn_pos)
	health = new_health
	position = spawn_pos
	velocity = Vector3.ZERO

func sync_health() -> void:
	if not multiplayer.is_server():
		return
	
	# Sync health to all clients
	rpc("update_health", health)

@rpc("authority", "call_remote", "reliable")
func update_health(new_health: float) -> void:
	health = new_health
	print("Player ", player_id, " health updated to ", health)

# ----------------------------
# Network Methods
# ----------------------------

# Send input to host (for attacks and camera rotation only - movement is via position updates)
func send_player_input_keep_jump() -> void:
	if not is_local_player:
		return
	
	# Only send attacks and camera rotation - movement is fully client-authoritative
	# Camera rotation is handled separately via send_camera_rotation_to_server()
	# But we can still send attacks here if needed
	if input_buffer.get("attack", false):
		var input_copy = {
			"attack": true,
			"player_rotation_y": rotation.y  # Send rotation for display
		}
		
		if multiplayer.is_server():
			# We are the host, process directly
			process_player_input(input_copy)
		else:
			# Send to host's NetworkManager
			var network_manager = get_tree().current_scene.get_node_or_null("NetworkManager")
			if network_manager:
				network_manager.rpc_id(1, "receive_player_input", player_id, input_copy)
		
		input_buffer["attack"] = false

# Send input to host (for network sync - resets all one-time inputs)
func send_player_input() -> void:
	if not is_local_player:
		return
	
	var input_copy = input_buffer.duplicate()
	# Reset one-time inputs
	input_copy.attack = false
	input_copy.jump = false
	
	if multiplayer.is_server():
		# We are the host, process directly
		process_player_input(input_copy)
	else:
		# Send to host's NetworkManager
		var network_manager = get_tree().current_scene.get_node_or_null("NetworkManager")
		if network_manager:
			network_manager.rpc_id(1, "receive_player_input", player_id, input_copy)
	
	# Reset one-time inputs
	input_buffer["attack"] = false
	input_buffer["jump"] = false

# Host processes input from clients (for attacks only - movement is handled via position updates)
# This is called by NetworkManager for remote players, or directly for local host player
func process_player_input(input_data: Dictionary) -> void:
	# Only process attacks - movement is fully client-authoritative via position updates
	input_buffer["attack"] = input_data.get("attack", false)
	
	# Process camera rotation if provided (for display)
	if input_data.has("camera_rotation"):
		var rotation_delta = input_data["camera_rotation"]
		rotate_y(deg_to_rad(-rotation_delta.x * sens_horizontal))
		var delta_pitch = -rotation_delta.y * sens_vertical
		_pitch += deg_to_rad(delta_pitch)
		_pitch = clamp(_pitch, deg_to_rad(pitch_min_deg), deg_to_rad(pitch_max_deg))
		camera_mount.rotation.x = _pitch
	
	# Update rotation if provided (for display)
	if input_data.has("player_rotation_y"):
		rotation.y = input_data["player_rotation_y"]

# Host syncs player state to all clients
# Optimized for non-competitive games: lower frequency, smaller corrections
func sync_player_state() -> void:
	if not multiplayer.is_server():
		return
	
	# Only sync if we're actually in the scene tree (spawned)
	if not is_inside_tree():
		return
	
	var state = {
		"position": position,
		"rotation_y": rotation.y,
		"camera_pitch": camera_mount.rotation.x,
		"health": health,
		"velocity": velocity,
		"is_jumping": is_jumping,
		"animation": animation_player.current_animation if animation_player else "idle"
	}
	
	# Use unreliable for frequent position updates (drops packets gracefully)
	# Lower frequency (20Hz) reduces network load and potential crash issues
	rpc("update_player_state", state)

# Clients receive state from host
@rpc("authority", "call_remote", "unreliable")
func update_player_state(state: Dictionary) -> void:
	# Check if we're in the scene tree - if not, we shouldn't update yet
	if not is_inside_tree():
		return
	
	var server_pos = state.get("position", position)
	
	if is_local_player:
		# Store server position for reconciliation (client-side prediction with correction)
		last_server_position = server_pos
		# Don't immediately overwrite - let reconciliation handle it smoothly
		# Camera rotation is 100% client-side for local players - don't overwrite from server
		# This prevents the dizzy camera re-adjusting issue
		# MOVEMENT is 100% client-authoritative - don't overwrite velocity or is_jumping from server
		# This prevents server from interfering with jumps and movement
		# Only update non-movement state
		health = state.get("health", health)
		# DO NOT overwrite velocity or is_jumping - client is authoritative for movement!
		# velocity = state.get("velocity", velocity)  # REMOVED - client authoritative
		# is_jumping = state.get("is_jumping", false)  # REMOVED - client authoritative
		
		# Don't log position differences - reduces console spam and potential crash issues
		# Position reconciliation will handle any differences smoothly
	else:
		# Remote players: store target state for interpolation in _physics_process
		var new_target_position = state.get("position", position)
		var distance = position.distance_to(new_target_position)
		
		target_position = new_target_position
		target_rotation_y = state.get("rotation_y", rotation.y)
		target_camera_pitch = state.get("camera_pitch", camera_mount.rotation.x)
		target_velocity = state.get("velocity", Vector3.ZERO)  # Always get velocity, default to zero
		
		# On first state update or large position difference, snap to position immediately
		# This prevents players from flying off into space on spawn
		var was_first_update = not has_target_state
		has_target_state = true
		
		if was_first_update or distance > 2.0:
			position = target_position
			rotation.y = target_rotation_y
			camera_mount.rotation.x = target_camera_pitch
			velocity = Vector3.ZERO  # Reset velocity when snapping
		
		# Update health and jump state immediately (these don't need interpolation)
		health = state.get("health", health)
		is_jumping = state.get("is_jumping", false)
		
		# Don't update animation from server state - animation is determined by velocity
		# Animation will be updated in _interpolate_remote_player() based on actual movement

# Send position update to server (client-side authority)
func send_position_update_to_server() -> void:
	if not is_local_player:
		return
	
	var state = {
		"position": position,
		"rotation_y": rotation.y,
		"camera_pitch": camera_mount.rotation.x,
		"velocity": velocity,
		"is_jumping": is_jumping
	}
	
	if multiplayer.is_server():
		# We are the host, validate our own position
		validate_client_position_state(state)
	else:
		# Send to server for validation
		var network_manager = get_tree().current_scene.get_node_or_null("NetworkManager")
		if network_manager:
			network_manager.rpc_id(1, "receive_client_position_update", player_id, state)

# Server receives position update from client
@rpc("any_peer", "call_local", "unreliable")
func receive_client_position_update(peer_id: int, state: Dictionary) -> void:
	if not multiplayer.is_server():
		return  # Only server processes
	
	# Find the player instance
	var player = get_tree().current_scene.get_node_or_null("Player_" + str(peer_id))
	if player and player.has_method("validate_client_position_state"):
		player.validate_client_position_state(state)

# Server accepts client position update (client is fully authoritative - no validation)
func validate_client_position_state(state: Dictionary) -> void:
	if not multiplayer.is_server():
		return
	
	# Only accept updates for remote players (not local host player)
	if is_local_player:
		return
	
	# Client is fully authoritative - just accept their position, rotation, and state
	# No validation or prediction - just for display purposes
	var client_pos = state.get("position", position)
	var client_rot = state.get("rotation_y", rotation.y)
	var client_velocity = state.get("velocity", velocity)
	
	# Accept client state directly (client is authoritative)
	position = client_pos
	rotation.y = client_rot
	camera_mount.rotation.x = state.get("camera_pitch", camera_mount.rotation.x)
	velocity = client_velocity
	is_jumping = state.get("is_jumping", is_jumping)
	
	# Update tracking state (for potential future use, but not for validation)
	last_validated_position = position
	last_validated_rotation = rotation.y
	last_validation_time = Time.get_ticks_msec() / 1000.0

# Send camera rotation to server (for display only, no movement processing)
func send_camera_rotation_to_server() -> void:
	if not is_local_player:
		return
	
	var rotation_data = {
		"camera_rotation": input_buffer["camera_rotation"]
	}
	
	if multiplayer.is_server():
		# We are the host, apply camera rotation directly
		var rotation_delta = rotation_data["camera_rotation"]
		rotate_y(deg_to_rad(-rotation_delta.x * sens_horizontal))
		var delta_pitch = -rotation_delta.y * sens_vertical
		_pitch += deg_to_rad(delta_pitch)
		_pitch = clamp(_pitch, deg_to_rad(pitch_min_deg), deg_to_rad(pitch_max_deg))
		camera_mount.rotation.x = _pitch
	else:
		# Send to server for display
		var network_manager = get_tree().current_scene.get_node_or_null("NetworkManager")
		if network_manager:
			network_manager.rpc_id(1, "receive_camera_rotation", player_id, rotation_data)

# Apply server reconciliation for local player on clients
# DISABLED for normal movement - client is fully authoritative
# Only reconciles for very large errors (teleporting/desync) to prevent cheating
func _apply_server_reconciliation(delta: float) -> void:
	if last_server_position == Vector3.ZERO:
		return  # Haven't received server position yet
	
	var position_error = position.distance_to(last_server_position)
	
	# Only reconcile for very large errors (teleporting/desync) - client is authoritative for normal movement
	# This prevents cheating but doesn't interfere with normal movement
	if position_error < position_error_threshold:
		# Normal movement range - client is authoritative, no correction needed
		return
	
	# Only correct for very large errors (likely cheating or desync)
	if position_error > position_error_threshold:
		# Error is too large (teleporting/desync) - snap immediately
		position = last_server_position
		# DO NOT reset velocity - client is authoritative for movement
		# velocity = Vector3.ZERO  # REMOVED - client authoritative

# Update visuals and animation for remote players on host
# Remote players on host have their position/velocity updated via validate_client_position_state()
# This function updates visuals rotation and animation based on velocity
func _update_remote_player_visuals_and_animation(delta: float) -> void:
	# Calculate movement direction from velocity for visuals rotation and animation
	var horizontal_velocity = Vector3(velocity.x, 0, velocity.z)
	var movement_magnitude = horizontal_velocity.length()
	
	# Rotate visuals to face movement direction (if moving)
	if movement_magnitude > 0.1:
		var movement_direction = horizontal_velocity.normalized()
		# Rotate visuals to face movement direction (same as local player)
		visuals.look_at(position + movement_direction)
	
	# Update animation based on movement (idle vs running)
	# This ensures animation matches actual movement direction
	if animation_player:
		if movement_magnitude > 0.1:
			# Player is moving - play running animation
			if animation_player.current_animation != "running":
				if animation_player.has_animation("running"):
					animation_player.play("running")
		else:
			# Player is not moving - play idle animation
			if animation_player.current_animation != "idle":
				if animation_player.has_animation("idle"):
					animation_player.play("idle")

# Interpolate remote player toward target state (called in _physics_process with delta)
func _interpolate_remote_player(delta: float) -> void:
	if not has_target_state:
		return
	
	# Interpolate position smoothly (direct position update, no physics)
	# For remote players, we directly set position based on server state
	var distance = position.distance_to(target_position)
	if distance > 0.01:
		var max_correction = remote_interpolation_speed * delta
		if distance > max_correction:
			position = position.move_toward(target_position, max_correction)
		else:
			position = target_position
	else:
		position = target_position
	
	# Interpolate rotation smoothly
	rotation.y = lerp_angle(rotation.y, target_rotation_y, 0.2)
	camera_mount.rotation.x = lerp(camera_mount.rotation.x, target_camera_pitch, 0.2)
	
	# Calculate movement direction from velocity for visuals rotation and animation
	# Use target_velocity (from server) to determine movement direction
	var horizontal_velocity = Vector3(target_velocity.x, 0, target_velocity.z)
	var movement_magnitude = horizontal_velocity.length()
	
	# Rotate visuals to face movement direction (if moving)
	if movement_magnitude > 0.1:
		var movement_direction = horizontal_velocity.normalized()
		# Rotate visuals to face movement direction (same as local player)
		visuals.look_at(position + movement_direction)
	
	# Update animation based on movement (idle vs running)
	# This ensures animation matches actual movement direction
	if animation_player:
		if movement_magnitude > 0.1:
			# Player is moving - play running animation
			if animation_player.current_animation != "running":
				if animation_player.has_animation("running"):
					animation_player.play("running")
		else:
			# Player is not moving - play idle animation
			if animation_player.current_animation != "idle":
				if animation_player.has_animation("idle"):
					animation_player.play("idle")
	
	# Reset velocity to zero since we're directly controlling position
	# This prevents any physics from interfering with our position interpolation
	velocity = Vector3.ZERO
