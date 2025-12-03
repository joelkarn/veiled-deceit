extends CharacterBody3D

# Network properties
@export var player_id: int = 0
@export var player_name: String = ""  # Character name (Witch/Hunter/Knight)
var is_local_player: bool = false
var is_host: bool = false

@onready var camera_mount: Node3D = $camera_mount
@onready var animation_player: AnimationPlayer = $visuals/mixamo_base/AnimationPlayer
@onready var visuals: Node3D = $visuals
@onready var camera: Camera3D = $camera_mount/Camera3D

@export var pitch_min_deg := -89.0  # Look down
@export var pitch_max_deg := 89.0  # Look up
var _pitch := 0.0

@export var key_yaw_speed_deg := 180.0

@export var max_health: float = 100.0
@export var health: float = 100.0

@export var health_bar_offset_y = 2

# Interaction system
@export var interact_distance: float = 3.0
var current_interactable: Node = null
var is_interacting: bool = false
var interact_start_time: float = 0.0

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
const SYNC_INTERVAL: float = 0.01

# Client-to-server position update timer
var position_update_timer: float = 0.0
const POSITION_UPDATE_INTERVAL: float = 0.01  # Match host sync rate for smooth movement

# Server reconciliation (only for very large errors - client is authoritative)
var last_server_position: Vector3 = Vector3.ZERO
var position_error_threshold: float = 10.0

# Server-side position validation (unused but kept for potential future use)
var last_validated_position: Vector3 = Vector3.ZERO
var last_validated_rotation: float = 0.0
var last_validation_time: float = 0.0

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

# Soft collision constants (for entity-to-entity collision)
const SOFT_COLLISION_RADIUS := 0.2  # Horizontal collision radius (cylinder radius)
const SOFT_COLLISION_PUSH_SPEED := 0.5  # Constant speed to push away from other entities

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

# Raycast constants for ranged weapons (bow)
const BOW_RAYCAST_RANGE := 20.0
const BOW_DAMAGE := 12.0

# Arrow scene for visual projectiles
var arrow_scene: PackedScene = preload("res://scenes/arrow.tscn")
# Fireball scene for staff attacks
var fireball_scene: PackedScene = preload("res://scenes/fireball.tscn")

# Debug line for bow attacks
var debug_line: MeshInstance3D = null
var debug_line_mesh: ImmediateMesh = null
@export var show_bow_debug_line: bool = true

var auto_attack_on_cooldown := false
var melee_area: Area3D
var melee_shape: CollisionShape3D
var auto_attack_active := false
var already_hit := {} # Dictionary used as a set to prevent multi-hits per swing

# Current equipped weapon/item
var equipped_weapon_data: WeaponData = null
var equipped_item_data: ItemData = null  # For non-weapon items like books
var crosshair_ui: Control = null
var book_ui: Control = null
var is_reading_book: bool = false

# --------------------------
# Debugging (hitbox visual)
# --------------------------
@export var show_melee_debug := true
var melee_debug_mesh: MeshInstance3D
var melee_debug_mat_idle: StandardMaterial3D
var melee_debug_mat_active: StandardMaterial3D



var ui_manager: Node
var aoe_indicator: Node3D = null
var aoe_indicator_scene: PackedScene = preload("res://scenes/ui/aoe_indicator.tscn")
var staff_equipped: bool = false

# Constellation system
var constellation_manager: Node = null
var constellation_ui: Control = null
var current_constellation_index: int = -1
const CONSTELLATION_CHECK_INTERVAL: float = 0.1
var constellation_check_timer: float = 0.0
var astrolabe_equipped: bool = false

# Camera collision
var default_camera_position: Vector3 = Vector3.ZERO

func _ready() -> void:
	health = max_health
	velocity = Vector3.ZERO
	last_server_position = position
	target_position = position
	has_target_state = false

	# Initialize validation state
	last_validated_position = position
	last_validated_rotation = rotation.y
	last_validation_time = Time.get_ticks_msec() / 1000.0

	# Set collision layers:
	# Layer 1 = Environment (ground, walls, obstacles)
	# Layer 2 = Players (entities)
	# Players should collide with environment (layer 1) but not with each other (layer 2)
	collision_layer = 2  # Player is on layer 2
	collision_mask = 1    # Player only collides with layer 1 (environment)

	# Add to players group so enemies can find players
	add_to_group("players")

	# Set multiplayer authority
	call_deferred("_set_multiplayer_authority")

	if camera_mount:
		_pitch = camera_mount.rotation.x

	ui_manager = get_node_or_null("../UIManager")
	crosshair_ui = get_tree().current_scene.get_node_or_null("UILayers/CrosshairLayer/Crosshair")
	book_ui = get_tree().current_scene.get_node_or_null("UILayers/BookUILayer/BookUI")
	constellation_manager = get_tree().current_scene.get_node_or_null("ConstellationManager")
	constellation_ui = get_tree().current_scene.get_node_or_null("UILayers/ConstellationUILayer/ConstellationUI")

	_create_melee_area()
	_create_melee_debug_mesh()
	_update_melee_debug_visual(false)
	_create_debug_line()

	# Give astrolabe to witch players
	if player_name == "Witch":
		call_deferred("_give_starting_astrolabe")

	# Setup camera after everything is ready
	call_deferred("_setup_camera")

func _give_starting_astrolabe() -> void:
	# Give astrolabe to witch at game start (only on server to avoid duplicates)
	if not multiplayer.is_server():
		return

	if InventoryManager:
		InventoryManager.add_item(player_id, "astrolabe", 1)
		print("Gave astrolabe to Witch player ", player_id)

func _setup_camera() -> void:
	if camera:
		camera.fov = fov
		camera.current = is_local_player
		# Store the default camera position for collision recovery
		default_camera_position = camera.position
	if camera_mount:
		_pitch = camera_mount.rotation.x

func _set_multiplayer_authority() -> void:
	if not is_inside_tree() or multiplayer.multiplayer_peer == null:
		return

	set_multiplayer_authority(1)  # Host has authority

func _input(event: InputEvent) -> void:
	# Only local player processes input
	if not is_local_player:
		return

	# Don't process input if multiplayer is disconnected
	if multiplayer.multiplayer_peer == null:
		return

	# Don't process input if network manager is shutting down
	var network_manager = NetworkManager
	if network_manager and network_manager.is_shutting_down:
		return

	# Don't process input if menu is open
	if ui_manager and ui_manager.is_menu_active():
		return

	if event is InputEventMouseMotion:
		handle_mouse_motion(event)
		input_buffer["camera_rotation"] = event.relative


	if event.is_action_pressed("attack"):
		input_buffer["attack"] = true
		# Check if book is equipped - show book UI instead of attacking
		_update_equipped_item()
		if equipped_item_data and equipped_item_data is BookData:
			_start_reading_book()

	if event.is_action_released("attack"):
		input_buffer["attack"] = false
		# Stop reading book when left click is released
		if is_reading_book:
			_stop_reading_book()

	if event.is_action_pressed("interact"):
		start_interaction()

	if event.is_action_released("interact"):
		stop_interaction()

func _physics_process(delta: float) -> void:
	# Don't process if multiplayer is disconnected (prevents crashes during shutdown)
	if multiplayer.multiplayer_peer == null:
		return

	# Don't process if network manager is shutting down
	var network_manager = NetworkManager
	if network_manager and network_manager.is_shutting_down:
		return

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

			if _yaw_key_active:
				var yaw_axis := Input.get_axis("rotate_right", "rotate_left")
				rotate_y(deg_to_rad(key_yaw_speed_deg) * yaw_axis * delta)

			# Handle continuous attack when holding button
			if Input.is_action_pressed("attack") and not is_reading_book:
				auto_attack()

			# Process movement immediately (client-side authority - includes jump)
			process_movement(delta)
			input_buffer["jump"] = false

			# Send position updates to server periodically (includes jump state)
			position_update_timer += delta
			if position_update_timer >= POSITION_UPDATE_INTERVAL:
				position_update_timer = 0.0
				send_position_update_to_server()


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

	# Check for nearby interactables (local player only)
	if is_local_player and not menu_active:
		_check_for_interactables()
		_update_interaction(delta)

	# Update weapon-specific UI (only for local player)
	if is_local_player:
		_update_equipped_weapon()  # Check what weapon is equipped
		_update_melee_debug_visual(false)
		_update_crosshair_visibility()
		_update_staff_equipped()
		_update_aoe_indicator_visibility()
		_update_astrolabe_equipped()

		# Prevent camera from going through ground
		_adjust_camera_collision()

		# Check for constellations (only when astrolabe equipped)
		if astrolabe_equipped:
			constellation_check_timer += delta
			if constellation_check_timer >= CONSTELLATION_CHECK_INTERVAL:
				constellation_check_timer = 0.0
				_check_constellation_look()
		else:
			# Clear constellation highlight when astrolabe not equipped
			if current_constellation_index != -1:
				if constellation_manager:
					constellation_manager.highlight_constellation(current_constellation_index, 0.0)
				if constellation_ui:
					constellation_ui.hide_constellation()
				current_constellation_index = -1


func _update_staff_equipped() -> void:
	staff_equipped = equipped_weapon_data != null and equipped_weapon_data is StaffData

func _update_astrolabe_equipped() -> void:
	# Check if astrolabe is equipped in toolbar
	var toolbar = get_tree().current_scene.get_node_or_null("UILayers/ToolbarLayer/Toolbar")
	if not toolbar:
		astrolabe_equipped = false
		return

	var selected_slot = toolbar.selected_slot
	var inventory = InventoryManager.get_inventory(player_id)

	if selected_slot >= 0 and selected_slot < inventory.size():
		var slot_data = inventory[selected_slot]
		var item_id = slot_data.get("item_id", "")

		if item_id == "astrolabe":
			astrolabe_equipped = true
			return

	astrolabe_equipped = false

func _update_aoe_indicator_visibility() -> void:
	if not is_local_player:
		return
	if staff_equipped:
		if aoe_indicator == null:
			aoe_indicator = aoe_indicator_scene.instantiate()
			get_tree().current_scene.add_child(aoe_indicator)
		# Raycast from camera to ground to position indicator
		if camera:
			var space_state = get_world_3d().direct_space_state
			var from = camera.global_position
			var to = from + (-camera.global_transform.basis.z * 100)
			var query = PhysicsRayQueryParameters3D.create(from, to)
			query.collide_with_areas = false
			query.collision_mask = 1 # Only ground/environment
			query.exclude = [self]
			var result = space_state.intersect_ray(query)
			if result and result.has("position"):
				# Smoothly interpolate to target position to avoid jitter
				var target_pos = result["position"]
				aoe_indicator.global_position = aoe_indicator.global_position.lerp(target_pos, 0.3)
	else:
		if aoe_indicator:
			aoe_indicator.queue_free()
			aoe_indicator = null

func _yaw_key_active() -> bool:
	return Input.is_action_pressed("rotate_left") or Input.is_action_pressed("rotate_right")

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

	# In air (fall or jump)
	if not is_on_floor():
		# Apply gravity only when in air
		velocity.y += GRAVITY * delta

		if is_jumping:
			handle_jumping(init_jump_input, direction, input_dir, speed_multiplier)
		else:
			handle_falling(direction, speed_multiplier)

		# Apply soft collision push-away (only for local players, horizontal only)
		if is_local_player:
			_apply_soft_collision(delta)

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

	# Apply soft collision push-away (only for local players, horizontal only)
	if is_local_player:
		_apply_soft_collision(delta)

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
# Soft Collision (Entity-to-Entity)
# ----------------------------
func _apply_soft_collision(_delta: float) -> void:
	# Only apply to local players
	if not is_local_player:
		return

	# Get horizontal position (XZ plane only)
	var my_pos_horizontal = Vector2(position.x, position.z)

	# Find all other players and enemies in the scene
	var scene = get_tree().current_scene
	if not scene:
		return

	var push_away_velocity = Vector2.ZERO

	# Check all children of the scene root
	for child in scene.get_children():
		# Skip self
		if child == self:
			continue

		# Check if it's a player
		var is_player = child.name.begins_with("Player_")
		# Check if it's an enemy (enemies have the Enemy script)
		var is_enemy = child.has_method("take_damage") and not is_player

		# Only process players and enemies
		if not (is_player or is_enemy):
			continue

		# Skip if it's not a CharacterBody3D (shouldn't happen, but safety check)
		if not child is CharacterBody3D:
			continue

		# Get horizontal position of other entity
		var other_pos_horizontal = Vector2(child.position.x, child.position.z)

		# Calculate horizontal distance
		var horizontal_distance = my_pos_horizontal.distance_to(other_pos_horizontal)

		# Check if circles overlap (2 * radius is the combined radius)
		var combined_radius = SOFT_COLLISION_RADIUS * 2.0
		if horizontal_distance < combined_radius and horizontal_distance > 0.0:
			# Calculate direction away from other entity (horizontal only)
			var direction_away = (my_pos_horizontal - other_pos_horizontal).normalized()

			# Handle edge case where positions are exactly the same (extremely rare)
			if direction_away == Vector2.ZERO:
				# Use a random direction to avoid division by zero
				direction_away = Vector2(1.0, 0.0)

			# Apply constant push-away velocity
			push_away_velocity += direction_away * SOFT_COLLISION_PUSH_SPEED

	# Apply push-away velocity to horizontal movement only (XZ plane)
	if push_away_velocity != Vector2.ZERO:
		velocity.x += push_away_velocity.x
		velocity.z += push_away_velocity.y

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

	# Set collision mask to detect layer 2 (players/entities)
	# Layer 1 = Environment, Layer 2 = Players/Entities
	# We want to hit players and enemies, which are on layer 2
	melee_area.collision_mask = 2  # Detect layer 2 (players and enemies)

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

	# Update equipped weapon from toolbar
	_update_equipped_weapon()

	# Staff AoE attack
	if equipped_weapon_data and equipped_weapon_data is StaffData:
		_perform_staff_aoe_attack()
		return

	# Check if we're using a bow (ranged weapon)
	if equipped_weapon_data and equipped_weapon_data is BowData:
		_perform_bow_attack()
	else:
		# Default melee attack
		_perform_melee_attack()

func _perform_staff_aoe_attack() -> void:
	auto_attack_active = true
	auto_attack_on_cooldown = true

	if animation_player and animation_player.has_animation("attack"):
		animation_player.play("attack")

	# Get target position from aoe_indicator
	var target_pos = Vector3.ZERO
	if aoe_indicator:
		target_pos = aoe_indicator.global_position
	else:
		# Fallback: position in front of player
		target_pos = global_position + (-global_transform.basis.z * 5.0)

	# Spawn fireball from player position (chest height) to target
	var fireball_start = global_position + Vector3(0, 1.5, 0)
	_spawn_fireball(fireball_start, target_pos)

	# Sync fireball spawn to other clients
	if multiplayer.multiplayer_peer != null:
		rpc("_sync_fireball_spawn", fireball_start, target_pos)

	await get_tree().create_timer(AUTO_ATTACK_COOLDOWN).timeout
	auto_attack_active = false
	auto_attack_on_cooldown = false

## Get currently equipped weapon from toolbar
func _update_equipped_weapon() -> void:
	# Get the toolbar to find selected slot
	var toolbar = get_tree().current_scene.get_node_or_null("UILayers/ToolbarLayer/Toolbar")
	if not toolbar:
		equipped_weapon_data = null
		return

	var selected_slot = toolbar.selected_slot
	var inventory = InventoryManager.get_inventory(player_id)

	if selected_slot >= 0 and selected_slot < inventory.size():
		var slot_data = inventory[selected_slot]
		var item_id = slot_data.get("item_id", "")

		if item_id != "":
			var item_data = InventoryManager.get_item_data(item_id)
			if item_data and item_data is WeaponData:
				equipped_weapon_data = item_data
				return

	equipped_weapon_data = null

## Get currently equipped item (weapon or other) from toolbar
func _update_equipped_item() -> void:
	# Get the toolbar to find selected slot
	var toolbar = get_tree().current_scene.get_node_or_null("UILayers/ToolbarLayer/Toolbar")
	if not toolbar:
		equipped_item_data = null
		return

	var selected_slot = toolbar.selected_slot
	var inventory = InventoryManager.get_inventory(player_id)

	if selected_slot >= 0 and selected_slot < inventory.size():
		var slot_data = inventory[selected_slot]
		var item_id = slot_data.get("item_id", "")

		if item_id != "":
			var item_data = InventoryManager.get_item_data(item_id)
			if item_data:
				equipped_item_data = item_data
				return

	equipped_item_data = null

## Perform a melee attack (sword, hammer, etc.)
func _perform_melee_attack() -> void:
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

## Perform a ranged attack with the bow
func _perform_bow_attack() -> void:
	auto_attack_active = true
	auto_attack_on_cooldown = true

	if animation_player and animation_player.has_animation("attack"):
		animation_player.play("attack")

	# Single raycast from camera center in aim direction
	if camera:
		var space_state = get_world_3d().direct_space_state
		var camera_from = camera.global_position
		var camera_to = camera_from + (-camera.global_transform.basis.z * BOW_RAYCAST_RANGE)

		var camera_query = PhysicsRayQueryParameters3D.create(camera_from, camera_to)
		camera_query.collision_mask = 3  # Layer 1 (environment) + Layer 2 (entities)
		camera_query.exclude = [self]  # Don't hit ourselves

		var camera_result = space_state.intersect_ray(camera_query)

		var hit_position = camera_to
		if camera_result and camera_result.has("collider"):
			hit_position = camera_result["position"]

		var arrow_start = global_position + Vector3(0, 1.5, 0) # chest height
		var arrow_direction = (hit_position - arrow_start).normalized()
		var arrow_end = arrow_start + arrow_direction * BOW_RAYCAST_RANGE

		# Second raycast from arrow start to hit position to determine actual hit
		var arrow_query = PhysicsRayQueryParameters3D.create(arrow_start, arrow_end)
		arrow_query.collision_mask = 3  # Layer 1 (environment) + Layer 2 (entities)
		arrow_query.exclude = [self]  # Don't hit ourselves

		var arrow_result = space_state.intersect_ray(arrow_query)
		var hit_success = false
		if arrow_result and arrow_result.has("collider"):
			hit_position = arrow_result["position"]
			hit_success = true

		var hit_body = null
		if arrow_result and arrow_result.has("collider"):
			hit_body = arrow_result["collider"]
		# Draw debug line (local only)
		if is_local_player:
			_draw_debug_line(arrow_start, hit_position, hit_success)
		_spawn_arrow(arrow_start, arrow_direction, hit_position, hit_body, hit_success)
		if multiplayer.multiplayer_peer != null:
			var body_path = null
			if hit_body:
				body_path = hit_body.get_path()
			rpc("_sync_arrow_spawn", arrow_start, arrow_direction, hit_position, body_path, hit_success)

	auto_attack_active = false
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
			var damage = AUTO_ATTACK_DAMAGE
			if equipped_weapon_data:
				damage = equipped_weapon_data.damage
			body.take_damage(damage, player_id)
		else:
			# Client sends damage request to host
			var network_manager = NetworkManager
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
					# It's an enemy or other object - use its node name directly
					body_name = body.name

				var damage = AUTO_ATTACK_DAMAGE
				if equipped_weapon_data:
					damage = equipped_weapon_data.damage
				network_manager.rpc_id(1, "process_damage_request", player_id, body_name, body_peer_id, damage)

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

	# Check if melee weapon is equipped (not bow, not staff)
	var melee_equipped = equipped_weapon_data != null and not (equipped_weapon_data is BowData) and not (equipped_weapon_data is StaffData)

	# Show only if melee weapon equipped, debug enabled, and local player
	melee_debug_mesh.visible = melee_equipped and show_melee_debug and is_local_player

	if not melee_debug_mesh.visible:
		return

	if active:
		melee_debug_mesh.material_override = melee_debug_mat_active
	else:
		melee_debug_mesh.material_override = melee_debug_mat_idle

# Update crosshair visibility based on equipped weapon
func _update_crosshair_visibility() -> void:
	if not crosshair_ui or not is_local_player:
		return

	# Show crosshair only when bow is equipped
	var bow_equipped = equipped_weapon_data != null and equipped_weapon_data is BowData

	if bow_equipped:
		crosshair_ui.show_crosshair()
	else:
		crosshair_ui.hide_crosshair()

# ----------------------------
# Bow attack helpers
# ----------------------------

## Create debug line mesh for visualizing bow shots
func _create_debug_line() -> void:
	debug_line_mesh = ImmediateMesh.new()
	debug_line = MeshInstance3D.new()
	debug_line.mesh = debug_line_mesh
	debug_line.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# Add to scene root, not to player, so it uses global coordinates
	get_tree().current_scene.call_deferred("add_child", debug_line)

## Draw a debug line from start to end position
func _draw_debug_line(start: Vector3, end: Vector3, hit_success: bool) -> void:
	if not show_bow_debug_line or not is_local_player or not debug_line_mesh:
		return

	# Clear previous line
	debug_line_mesh.clear_surfaces()

	# Create material
	var material = StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.vertex_color_use_as_albedo = false
	material.disable_receive_shadows = true

	# Green if hit, red if blocked
	if hit_success:
		material.albedo_color = Color(0.0, 1.0, 0.0, 0.8)
	else:
		material.albedo_color = Color(1.0, 0.0, 0.0, 0.8)

	# Draw line in global space
	debug_line_mesh.surface_begin(Mesh.PRIMITIVE_LINES, material)
	debug_line_mesh.surface_add_vertex(start)
	debug_line_mesh.surface_add_vertex(end)
	debug_line_mesh.surface_end()

	# Make sure debug_line is at origin for global coordinates
	if debug_line:
		debug_line.global_position = Vector3.ZERO

	# Clear line after a short delay
	await get_tree().create_timer(0.5).timeout
	if debug_line_mesh:
		debug_line_mesh.clear_surfaces()

## Spawn an arrow at the hit position and attach it to the hit object
func _spawn_arrow(arrow_start: Vector3, direction: Vector3, arrow_target_position: Vector3, target_body: Node3D, hit_success: bool) -> void:
	if not arrow_scene:
		return

	var arrow = arrow_scene.instantiate()
	get_tree().current_scene.add_child(arrow)

	arrow.global_position = arrow_start
	arrow.hit_success = hit_success
	var arrow_basis = Basis.looking_at(direction, Vector3.UP)
	arrow.global_transform.basis = arrow_basis

	if arrow.has_method("set_target_position"):
		arrow.set_target_position(arrow_target_position, target_body)
	if arrow.has_method("set_arrow_shooter"):
		arrow.set_arrow_shooter(self)

## RPC to sync arrow spawns across all clients
@rpc("any_peer", "call_remote", "reliable")
func _sync_arrow_spawn(arrow_start: Vector3, direction: Vector3, arrow_target_position: Vector3, body_path: NodePath, hit_success: bool) -> void:
	var target_body = null
	if body_path != null:
		target_body = get_node_or_null(body_path)
	_spawn_arrow(arrow_start, direction, arrow_target_position, target_body, hit_success)

# ----------------------------
# Fireball attack helpers
# ----------------------------

## Spawn a fireball that travels in an arc to the target position
func _spawn_fireball(from: Vector3, to: Vector3) -> void:
	if not fireball_scene:
		return

	var fireball = fireball_scene.instantiate()
	get_tree().current_scene.add_child(fireball)

	# Set fireball trajectory
	if fireball.has_method("set_target_data"):
		fireball.set_target_data(from, to, 1.5)  # 1.5 second travel time

	# Set damage data
	var damage = 20.0
	if equipped_weapon_data:
		damage = equipped_weapon_data.damage

	if fireball.has_method("set_damage_data"):
		fireball.set_damage_data(damage, player_id)

## RPC to sync fireball spawns across all clients
@rpc("any_peer", "call_remote", "reliable")
func _sync_fireball_spawn(from: Vector3, to: Vector3) -> void:
	_spawn_fireball(from, to)

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

func handle_mouse_motion(event) -> void:
	# Rotate player (yaw)
	if not _yaw_key_active():
		rotate_y(deg_to_rad(-event.relative.x * sens_horizontal))

	# Rotate camera (look up and down)
	var delta_pitch_deg: float = -event.relative.y * sens_vertical
	_pitch += deg_to_rad(delta_pitch_deg)
	_pitch = clamp(_pitch, deg_to_rad(pitch_min_deg), deg_to_rad(pitch_max_deg))
	camera_mount.rotation.x = _pitch

func take_damage(amount: float, _attacker_id: int = 0) -> void:
	if not multiplayer.is_server():
		return

	health -= amount
	health = max(0, health)
	sync_health()

	if health <= 0:
		die()

func die() -> void:
	if not multiplayer.is_server():
		return

	health = max_health

	# Get spawn position for this player
	var network_manager = NetworkManager
	var spawn_pos = position
	if network_manager and network_manager.spawn_points.size() > 0:
		var spawn_index = (player_id - 1) % network_manager.spawn_points.size()
		spawn_pos = network_manager.spawn_points[spawn_index]

	position = spawn_pos
	velocity = Vector3.ZERO

	rpc("sync_death_and_respawn", spawn_pos, health)

@rpc("authority", "call_remote", "reliable")
func sync_death_and_respawn(spawn_pos: Vector3, new_health: float) -> void:
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

# ----------------------------
# Network Methods
# ----------------------------

# Send input to host (for attacks only - movement is via position updates)
func send_player_input_keep_jump() -> void:
	if not is_local_player or not input_buffer.get("attack", false):
		return

	var input_copy = {
		"attack": true,
		"player_rotation_y": rotation.y
	}

	if multiplayer.is_server():
		process_player_input(input_copy)
	else:
		var network_manager = NetworkManager
		if network_manager:
			network_manager.rpc_id(1, "receive_player_input", player_id, input_copy)

	input_buffer["attack"] = false

# Host processes input from clients (for attacks and camera rotation only)
func process_player_input(input_data: Dictionary) -> void:
	input_buffer["attack"] = input_data.get("attack", false)

	if input_data.has("camera_rotation"):
		var rotation_delta = input_data["camera_rotation"]
		# TODO: figure out whether I need to add something for _yaw_key_active here
		rotate_y(deg_to_rad(-rotation_delta.x * sens_horizontal))
		var delta_pitch = -rotation_delta.y * sens_vertical
		_pitch += deg_to_rad(delta_pitch)
		_pitch = clamp(_pitch, deg_to_rad(pitch_min_deg), deg_to_rad(pitch_max_deg))
		camera_mount.rotation.x = _pitch

	if input_data.has("player_rotation_y"):
		rotation.y = input_data["player_rotation_y"]

# Host syncs player state to all clients
func sync_player_state() -> void:
	if not multiplayer.is_server() or not is_inside_tree():
		return

	var network_manager = NetworkManager
	if network_manager and network_manager.is_shutting_down:
		return

	var animation_to_play = "idle"
	if animation_player:
		animation_to_play = animation_player.current_animation

	var state = {
		"position": position,
		"rotation_y": rotation.y,
		"camera_pitch": camera_mount.rotation.x,
		"health": health,
		"velocity": velocity,
		"is_jumping": is_jumping,
		"animation": animation_to_play
	}

	rpc("update_player_state", state)

# Clients receive state from host
@rpc("authority", "call_remote", "unreliable")
func update_player_state(state: Dictionary) -> void:
	# Check if we're in the scene tree - if not, we shouldn't update yet
	if not is_inside_tree():
		return

	# Don't process if shutting down
	var network_manager = NetworkManager
	if network_manager and network_manager.is_shutting_down:
		return

	var server_pos = state.get("position", position)

	if is_local_player:
		# Store server position for reconciliation (client is authoritative for movement)
		last_server_position = server_pos
		health = state.get("health", health)
	else:
		# Remote players: store target state for interpolation
		var new_target_position = state.get("position", position)
		var distance = position.distance_to(new_target_position)

		target_position = new_target_position
		target_rotation_y = state.get("rotation_y", rotation.y)
		target_camera_pitch = state.get("camera_pitch", camera_mount.rotation.x)
		target_velocity = state.get("velocity", Vector3.ZERO)

		# Snap to position on first update or large difference
		var was_first_update = not has_target_state
		has_target_state = true

		if was_first_update or distance > 2.0:
			position = target_position
			rotation.y = target_rotation_y
			camera_mount.rotation.x = target_camera_pitch
			velocity = Vector3.ZERO

		health = state.get("health", health)
		is_jumping = state.get("is_jumping", false)

# Send position update to server (client-side authority)
func send_position_update_to_server() -> void:
	if not is_local_player or multiplayer.multiplayer_peer == null:
		return

	var state = {
		"position": position,
		"rotation_y": rotation.y,
		"camera_pitch": camera_mount.rotation.x,
		"velocity": velocity,
		"is_jumping": is_jumping
	}

	if multiplayer.is_server():
		validate_client_position_state(state)
	else:
		var network_manager = NetworkManager
		if network_manager:
			network_manager.rpc_id(1, "receive_client_position_update", player_id, state)

# Server receives position update from client
@rpc("any_peer", "call_local", "unreliable")
func receive_client_position_update(peer_id: int, state: Dictionary) -> void:
	if not multiplayer.is_server():
		return

	# Don't process if shutting down
	var network_manager = NetworkManager
	if network_manager and network_manager.is_shutting_down:
		return

	# Find the player instance
	var player = get_tree().current_scene.get_node_or_null("Player_" + str(peer_id))
	if player and player.has_method("validate_client_position_state"):
		player.validate_client_position_state(state)

# Server accepts client position update
func validate_client_position_state(state: Dictionary) -> void:
	if not multiplayer.is_server() or is_local_player:
		return

	# Accept client state directly (client is authoritative)
	position = state.get("position", position)
	rotation.y = state.get("rotation_y", rotation.y)
	camera_mount.rotation.x = state.get("camera_pitch", camera_mount.rotation.x)
	velocity = state.get("velocity", velocity)
	is_jumping = state.get("is_jumping", is_jumping)

	# Update tracking state
	last_validated_position = position
	last_validated_rotation = rotation.y
	last_validation_time = Time.get_ticks_msec() / 1000.0

# Snaps player back to server position if distance is too large
func _apply_server_reconciliation(_delta: float) -> void:
	if last_server_position == Vector3.ZERO:
		return

	var position_error = position.distance_to(last_server_position)

	# Don't care about small distances
	if position_error < position_error_threshold:
		return

	# Snap to server position for very large errors
	if position_error > position_error_threshold:
		position = last_server_position

# Update visuals and animation for remote players on host
func _update_remote_player_visuals_and_animation(_delta: float) -> void:
	var horizontal_velocity = Vector3(velocity.x, 0, velocity.z)
	var movement_magnitude = horizontal_velocity.length()

	if movement_magnitude > 0.1:
		visuals.look_at(position + horizontal_velocity.normalized())

	if animation_player:
		if movement_magnitude > 0.1:
			if animation_player.current_animation != "running" and animation_player.has_animation("running"):
				animation_player.play("running")
		else:
			if animation_player.current_animation != "idle" and animation_player.has_animation("idle"):
				animation_player.play("idle")

# Interpolate remote player toward target state
func _interpolate_remote_player(delta: float) -> void:
	if not has_target_state:
		return

	# Interpolate position
	var distance = position.distance_to(target_position)
	if distance > 0.01:
		var max_correction = remote_interpolation_speed * delta
		position = position.move_toward(target_position, min(distance, max_correction))
	else:
		position = target_position

	# Interpolate rotation
	rotation.y = lerp_angle(rotation.y, target_rotation_y, 0.2)
	camera_mount.rotation.x = lerp(camera_mount.rotation.x, target_camera_pitch, 0.2)

	# Update visuals and animation based on movement direction
	var horizontal_velocity = Vector3(target_velocity.x, 0, target_velocity.z)
	var movement_magnitude = horizontal_velocity.length()

	if movement_magnitude > 0.1:
		visuals.look_at(position + horizontal_velocity.normalized())

	if animation_player:
		if movement_magnitude > 0.1:
			if animation_player.current_animation != "running" and animation_player.has_animation("running"):
				animation_player.play("running")
		else:
			if animation_player.current_animation != "idle" and animation_player.has_animation("idle"):
				animation_player.play("idle")

	velocity = Vector3.ZERO

# ----------------------------
# Interaction system
# ----------------------------

## Check for interactable objects using raycast
func _check_for_interactables() -> void:
	if not camera:
		return

	# Use a sphere cast instead of raycast for easier interaction
	var space_state = get_world_3d().direct_space_state

	# Check in a sphere around the player
	var query = PhysicsShapeQueryParameters3D.new()
	var sphere = SphereShape3D.new()
	sphere.radius = interact_distance
	query.shape = sphere
	query.transform = global_transform
	query.collision_mask = 4  # Interactable layer
	query.collide_with_areas = true
	query.collide_with_bodies = false

	var results = space_state.intersect_shape(query)

	var old_interactable = current_interactable
	var closest_interactable = null
	var closest_distance = interact_distance + 1.0  # Start with max distance

	if results.size() > 0:
		# Find the closest interactable object
		for result in results:
			var collider = result.collider
			if collider.has_method("can_interact") and collider.can_interact():
				var distance = global_position.distance_to(collider.global_position)
				if distance < closest_distance:
					closest_distance = distance
					closest_interactable = collider

		# Set the closest one as current
		if closest_interactable:
			current_interactable = closest_interactable
			_update_interaction_prompt()
			return

	# Don't clear current_interactable if we're actively interacting with it
	# This prevents losing the reference during harvest/interaction
	if not is_interacting:
		current_interactable = null

		# Hide prompt if we lost the interactable
		if old_interactable != null and current_interactable == null:
			_update_interaction_prompt()

func _update_interaction_prompt() -> void:
	"""Update the interaction prompt UI based on current interactable"""
	var prompt_ui = get_tree().current_scene.get_node_or_null("UILayers/InteractionPromptLayer/InteractionPrompt")
	if not prompt_ui:
		return

	if current_interactable and current_interactable.has_method("get"):
		var prompt_text = current_interactable.get("interact_prompt")
		if prompt_text:
			prompt_ui.show_prompt(prompt_text)
		else:
			prompt_ui.show_prompt("E to interact")
	else:
		prompt_ui.hide_prompt()

## Called when player presses interact key (E)
func start_interaction() -> void:
	if not is_local_player:
		return

	if not current_interactable:
		return

	is_interacting = true
	interact_start_time = Time.get_ticks_msec() / 1000.0

	# Hide interaction prompt while interacting
	var prompt_ui = get_tree().current_scene.get_node_or_null("UILayers/InteractionPromptLayer/InteractionPrompt")
	if prompt_ui:
		prompt_ui.hide_prompt()

	# Check if this requires harvesting (hold E) or instant interaction (press E)
	if current_interactable.has_method("start_harvest"):
		# Harvesting interaction (hold E)
		# For clients, show UI immediately for responsive feedback
		# For host, the berry bush will show it after validation in start_harvest()
		if not multiplayer.is_server():
			if current_interactable.has_method("get_harvest_duration"):
				var duration = current_interactable.get_harvest_duration()
				var harvest_ui = get_node_or_null("/root/HarvestUIManager")
				if harvest_ui:
					harvest_ui.start_harvest_ui(current_interactable, duration)

		# Tell server to start harvest
		if multiplayer.is_server():
			current_interactable.start_harvest(self)
		else:
			var network_manager = NetworkManager
			if network_manager:
				network_manager.rpc_id(1, "request_start_harvest", player_id, current_interactable.get_path())
	elif current_interactable.has_method("stop_interact"):
		# Hold interaction (like reading a sign) - call interact to show UI
		current_interactable.interact(self)
		# is_interacting stays true so we can detect when to stop
	else:
		# Instant interaction (press E once)
		is_interacting = false  # Don't hold for instant pickups
		if multiplayer.is_server():
			current_interactable.interact(self)
		else:
			var network_manager = NetworkManager
			if network_manager:
				network_manager.rpc_id(1, "request_interact", player_id, current_interactable.get_path())

## Called when player releases interact key
func stop_interaction() -> void:
	if not is_local_player:
		return

	if not is_interacting:
		return

	is_interacting = false

	# Hide harvest UI
	var harvest_ui = get_node_or_null("/root/HarvestUIManager")
	if harvest_ui:
		harvest_ui.cancel_harvest_ui()

	# Call stop_interact on the interactable (for signs, etc.)
	if current_interactable and current_interactable.has_method("stop_interact"):
		current_interactable.stop_interact(self)

	# Show interaction prompt again if still near interactable
	_update_interaction_prompt()

	# Tell server to cancel harvest
	if multiplayer.is_server():
		if current_interactable and current_interactable.has_method("cancel_harvest"):
			current_interactable.cancel_harvest()
	else:
		var network_manager = NetworkManager
		if network_manager:
			network_manager.rpc_id(1, "request_cancel_harvest", player_id)

## Update interaction state (check if moved away from object)
func _update_interaction(_delta: float) -> void:
	if not is_interacting:
		return

	# Check if E key is still being held
	if not Input.is_action_pressed("interact"):
		stop_interaction()
		return	# Check if current interactable is still available
	if not current_interactable or not current_interactable.has_method("can_interact"):
		stop_interaction()
		return

	# Check if moved too far away
	var distance = global_position.distance_to(current_interactable.global_position)
	if distance > interact_distance:
		stop_interaction()
		return

	# Progress updates come from server via RPC to berry bush
	# No need to update from client side here

## Heal the player (for consumable items)
func heal(amount: float) -> void:
	if not multiplayer.is_server():
		return

	health = min(health + amount, max_health)
	sync_health()
	print(name, " healed for ", amount, " HP. Current health: ", health)

# ----------------------------
# Book reading system
# ----------------------------

func _start_reading_book() -> void:
	if not is_local_player or not book_ui:
		return

	# Don't start reading if already reading
	if is_reading_book:
		return

	# Get the equipped book data
	if not equipped_item_data or not equipped_item_data is BookData:
		return

	is_reading_book = true

	# Show the book UI with the book data
	book_ui.show_book(equipped_item_data)

	# Track quest progress for reading the book
	if QuestManager:
		QuestManager.add_progress_by_type(QuestData.QuestType.READ_BOOK, 1, player_id)

	print("Started reading book: ", equipped_item_data.item_name)

func _stop_reading_book() -> void:
	if not is_local_player or not book_ui:
		return

	if not is_reading_book:
		return

	is_reading_book = false

	# Hide the book UI
	book_ui.hide_book()

	print("Stopped reading book")

# ----------------------------
# Constellation detection system
# ----------------------------

func _check_constellation_look() -> void:
	if not constellation_manager or not camera:
		return

	# Get camera look direction
	var camera_direction = -camera.global_transform.basis.z

	# Check if looking at any constellation
	var constellation_index = constellation_manager.check_ray_intersection(camera_direction)

	# Update highlight if changed
	if constellation_index != current_constellation_index:
		# Unhighlight previous
		if current_constellation_index != -1:
			constellation_manager.highlight_constellation(current_constellation_index, 0.0)
			if constellation_ui:
				constellation_ui.hide_constellation()

		# Highlight new
		current_constellation_index = constellation_index
		if current_constellation_index != -1:
			constellation_manager.highlight_constellation(current_constellation_index, 1.0)
			var constellation_name = constellation_manager.get_constellation_name(current_constellation_index)
			print("Looking at constellation: ", constellation_name)

			# Show constellation name in UI
			if constellation_ui:
				constellation_ui.show_constellation(constellation_name)

# ----------------------------
# Camera collision prevention
# ----------------------------

func _adjust_camera_collision() -> void:
	if not camera or not camera_mount:
		return

	# Calculate target position in world space
	var from = camera_mount.global_position
	var camera_offset_world = camera_mount.global_transform.basis * default_camera_position
	var camera_target_position = from + camera_offset_world

	# Raycast from mount to target camera position
	var space_state = get_world_3d().direct_space_state
	var query = PhysicsRayQueryParameters3D.create(from, camera_target_position)
	query.collision_mask = 1  # Only check layer 1 (environment/ground)
	query.exclude = [self]

	var result = space_state.intersect_ray(query)

	var target_local_pos = default_camera_position

	if result and result.has("position"):
		# Collision detected - calculate safe distance
		var hit_pos = result["position"]
		var safe_offset = 0.2
		var collision_distance = from.distance_to(hit_pos) - safe_offset
		var clamped_distance = max(collision_distance, 0.5)

		# Calculate clamped position in local space
		target_local_pos = default_camera_position.normalized() * clamped_distance

	# Only adjust if difference is significant (deadzone to prevent micro-jitter)
	var position_diff = camera.position.distance_to(target_local_pos)
	if position_diff > 0.01:
		# Always lerp smoothly to target (whether it's default or clamped)
		camera.position = camera.position.lerp(target_local_pos, 0.2)
