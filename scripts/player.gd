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
const SYNC_INTERVAL: float = 0.033  # ~30 Hz

const SPEED := 7.0
const CUSTOM_GRAVITY := -45.0
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
	health = max_health
	_pitch = camera_mount.rotation.x
	
	if camera:
		camera.fov = fov
		# Only local player should see their camera
		if not is_local_player:
			camera.current = false
	
	ui_manager = get_node_or_null("../UIManager")
	
	_create_melee_area()
	_create_melee_debug_mesh()
	_update_melee_debug_visual(false)

func _input(event: InputEvent) -> void:
	# Only local player processes input
	if not is_local_player:
		return
	
	# Don't process input if menu is open
	if ui_manager and ui_manager.is_menu_active():
		return
	
	if event is InputEventMouseMotion:
		handle_mouse_motion(event)
		input_buffer.camera_rotation = event.relative
		

	if event.is_action_pressed("attack"):
		input_buffer.attack = true
		auto_attack()

func _physics_process(delta: float) -> void:
	if ui_manager and ui_manager.is_menu_active():
		stop_movement(delta)
		return
	
	# Collect input for local player
	if is_local_player:
		input_buffer.movement = Input.get_vector("left", "right", "forward", "backward")
		input_buffer.jump = Input.is_action_just_pressed("jump")
		input_buffer.speed_multiplier = 0.5 if Input.is_action_pressed("backward") else 1.0
		
		# Send input to host (but don't reset jump yet - we need it for local processing)
		send_player_input_keep_jump()
		
		# Reset camera rotation after sending (prevents drift)
		# It will be set in _input() if mouse moves
		input_buffer.camera_rotation = Vector2.ZERO
	
	# Host processes movement for all players
	# Local player also processes (client-side prediction)
	if multiplayer.is_server() or is_local_player:
		process_movement(delta)
		
		# Reset jump after processing (local player)
		if is_local_player:
			input_buffer.jump = false
	else:
		# Remote players on clients - they get state updates, but we still need to apply gravity
		if not is_on_floor():
			velocity.y += CUSTOM_GRAVITY * delta
		move_and_slide()
	
	# Sync state periodically (host only)
	if multiplayer.is_server():
		sync_timer += delta
		if sync_timer >= SYNC_INTERVAL:
			sync_timer = 0.0
			sync_player_state()

func process_movement(delta: float) -> void:
	var speed_multiplier = input_buffer.speed_multiplier if is_local_player else 1.0
	
	# For local player, use input buffer
	# For remote players on host, we'll get their input via RPC
	# For now, let local player use their own input
	var input_dir: Vector2 = input_buffer.movement if is_local_player else Vector2.ZERO
	var direction: Vector3 = (transform.basis * Vector3(input_dir.x, 0.0, input_dir.y))


	# In air (fall or jump)
	if not is_on_floor():
		# Apply gravity only when in air
		velocity.y += CUSTOM_GRAVITY * delta

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

	if input_buffer.jump:
		is_jumping = true
		velocity.y = JUMP_VELOCITY
		init_jump_input = input_dir
		init_jump_dir.x = direction.x
		init_jump_dir.y = direction.z
		input_buffer.jump = false

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
		body.take_damage(AUTO_ATTACK_DAMAGE)

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
		velocity.y += CUSTOM_GRAVITY * delta
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

func take_damage(amount: float) -> void:
	health -= amount
	print("Player took ", amount, " damage. Health: ", health)
	
	if health <= 0:
		die()

func die() -> void:
	print("Player died!")
	# You might want to add game over logic here
	# For now, just reset health
	health = max_health

# ----------------------------
# Network Methods
# ----------------------------

# Send input to host (keeps jump for local processing)
func send_player_input_keep_jump() -> void:
	if not is_local_player:
		return
	
	var input_copy = input_buffer.duplicate()
	# Reset one-time inputs except jump (we'll reset it after processing)
	input_copy.attack = false
	
	# Only send camera rotation if it's non-zero (prevents unnecessary updates)
	if input_copy.camera_rotation == Vector2.ZERO:
		input_copy.erase("camera_rotation")  # Remove from dict if zero
	
	if multiplayer.is_server():
		# We are the host, process directly
		process_player_input(input_copy)
	else:
		# Send to host's NetworkManager
		var network_manager = get_tree().current_scene.get_node_or_null("NetworkManager")
		if network_manager:
			network_manager.rpc_id(1, "receive_player_input", player_id, input_copy)
	
	# Reset one-time inputs except jump
	input_buffer.attack = false

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
	input_buffer.attack = false
	input_buffer.jump = false

# Host processes input from clients (or locally)
# This is called by NetworkManager for remote players, or directly for local host player
func process_player_input(input_data: Dictionary) -> void:
	# Store input for this player
	input_buffer.movement = input_data.get("movement", Vector2.ZERO)
	input_buffer.jump = input_data.get("jump", false)
	input_buffer.attack = input_data.get("attack", false)
	input_buffer.speed_multiplier = input_data.get("speed_multiplier", 1.0)
	
	# Process camera rotation if provided
	if input_data.has("camera_rotation"):
		var rotation_delta = input_data["camera_rotation"]
		rotate_y(deg_to_rad(-rotation_delta.x * sens_horizontal))
		var delta_pitch = -rotation_delta.y * sens_vertical
		_pitch += deg_to_rad(delta_pitch)
		_pitch = clamp(_pitch, deg_to_rad(pitch_min_deg), deg_to_rad(pitch_max_deg))
		camera_mount.rotation.x = _pitch

# Host syncs player state to all clients
func sync_player_state() -> void:
	if not multiplayer.is_server():
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
	
	rpc("update_player_state", state)

# Clients receive state from host
@rpc("authority", "call_remote", "unreliable")
func update_player_state(state: Dictionary) -> void:
	if is_local_player:
		# Don't overwrite local player with server state (client-side prediction)
		# We'll use this for correction if needed later
		return
	
	# Interpolate position smoothly for remote players
	position = position.lerp(state.get("position", position), 0.3)
	rotation.y = state.get("rotation_y", rotation.y)
	camera_mount.rotation.x = state.get("camera_pitch", camera_mount.rotation.x)
	health = state.get("health", health)
	velocity = state.get("velocity", velocity)
	is_jumping = state.get("is_jumping", false)
	
	# Update animation
	var anim = state.get("animation", "idle")
	if animation_player and anim != "" and animation_player.current_animation != anim:
		if animation_player.has_animation(anim):
			animation_player.play(anim)
