extends CharacterBody3D

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
const MELEE_OFFSET := Vector3(0.0, 1.0, -1.2)
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
@export var show_melee_debug := false
var melee_debug_mesh: MeshInstance3D
var melee_debug_mat_idle: StandardMaterial3D
var melee_debug_mat_active: StandardMaterial3D

var ui_manager: Node

func _ready() -> void:
	health = max_health
	# Mouse mode is handled by UI manager
	_pitch = camera_mount.rotation.x
	
	# Set camera FOV to reduce fish-eye effect
	if camera:
		camera.fov = fov
	
	# Get UI manager reference
	ui_manager = get_node_or_null("/root/Node3D/UIManager")
	if ui_manager == null:
		ui_manager = get_node_or_null("../UIManager")
	
	_create_melee_area()
	_create_melee_debug_mesh()
	_update_melee_debug_visual(false)

func _input(event: InputEvent) -> void:
	# Don't process input if menu is open
	if ui_manager and ui_manager.is_menu_active():
		return
	
	if event is InputEventMouseMotion:
		# Rotate player (horizontal)
		rotate_y(deg_to_rad(-event.relative.x * sens_horizontal))
		
		var delta_pitch_deg: float = -event.relative.y * sens_vertical
		_pitch += deg_to_rad(delta_pitch_deg)
		_pitch = clamp(_pitch, deg_to_rad(pitch_min_deg), deg_to_rad(pitch_max_deg))
		camera_mount.rotation.x = _pitch
		
		
		#camera_mount.rotate_x(deg_to_rad(-event.relative.y * sens_vertical))
		# TODO: decide what to do here, it's more obvious where player is looking
		# without the visuals.rotate...
		# Rotate only visuals so player model doesn't rotate when standing still
		#visuals.rotate_y(deg_to_rad(event.relative.x * sens_horizontal))
		# Rotate camera (vertical)
		
	
	if event.is_action_pressed("attack"):
		auto_attack()

func _physics_process(delta: float) -> void:
	# Don't process movement if menu is open
	if ui_manager and ui_manager.is_menu_active():
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
		return
	
	# no input: (0, 0), right: (0, 1), forward: (0, -1), left back: (-0.707107, 0.707107)
	var input_dir: Vector2 = Input.get_vector("left", "right", "forward", "backward")
	# relative to world so input is transformed to the world's basis
	var direction: Vector3 = (transform.basis * Vector3(input_dir.x, 0.0, input_dir.y))

	# In air, either falling or jumping
	if not is_on_floor():
		# Apply gravity only when in air
		velocity.y += CUSTOM_GRAVITY * delta

		if is_jumping:
			handle_jumping(init_jump_input, direction, input_dir)
		else:
			handle_falling(direction)
		
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
		
		velocity.x = direction.x * SPEED
		velocity.z = direction.z * SPEED
	else:
		if animation_player and animation_player.current_animation != "idle":
			animation_player.play("idle")
		# Stop moving horizontally
		velocity.x = 0.0
		velocity.z = 0.0

	# Handle jump with initial conditions
	if Input.is_action_just_pressed("ui_accept"):
		is_jumping = true
		velocity.y = JUMP_VELOCITY
		init_jump_input = input_dir
		init_jump_dir.x = direction.x
		init_jump_dir.y = direction.z

	move_and_slide()

func handle_jumping(initial_input: Vector2, direction: Vector3, input_dir: Vector2) -> void:
	# Jump with no initial horizontal velocity
	if initial_input == Vector2.ZERO:
		# If input in any direction, go slow
		if direction != Vector3.ZERO:
			velocity.x = direction.x * SPEED * 0.25
			velocity.z = direction.z * SPEED * 0.25
		else:
			# If no input, go straight up and down
			velocity.x = 0.0
			velocity.z = 0.0
	else:
		# Jump with initial horizontal velocity
		# If input direction key is pressed, continue with SPEED
		if input_dir == initial_input:
			velocity.x = init_jump_dir.x * SPEED
			velocity.z = init_jump_dir.y * SPEED
		else:
			# If opposite of input direction key is pressed, go slow
			if input_dir + initial_input == Vector2.ZERO:
				velocity.x = init_jump_dir.x * SPEED * 0.25
				velocity.z = init_jump_dir.y * SPEED * 0.25
			else:
				# If no key related to input direction is pressed, go medium slow
				velocity.x = init_jump_dir.x * SPEED * 0.5
				velocity.z = init_jump_dir.y * SPEED * 0.5

func handle_falling(direction) -> void:
	# Placeholder for falling behavior
	velocity.x = direction.x * SPEED * 0.5
	velocity.z = direction.z * SPEED * 0.5

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
