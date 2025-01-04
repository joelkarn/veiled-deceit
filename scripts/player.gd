extends CharacterBody3D

@onready var camera_mount: Node3D = $camera_mount
@onready var animation_player: AnimationPlayer = $visuals/mixamo_base/AnimationPlayer
@onready var visuals: Node3D = $visuals

const SPEED = 6.5
const CUSTOM_GRAVITY = -30.0
const JUMP_VELOCITY = 10.0

@export var sens_horizontal = 0.1
@export var sens_vertical = 0.1

var facing_dir = Vector2.ZERO
var init_jump_input = Vector2.ZERO
var init_jump_dir = Vector2.ZERO

var is_jumping = false

func _ready():
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

func _input(event):
	if event is InputEventMouseMotion:
		# Rotate player (horizontal)
		rotate_y(deg_to_rad(-event.relative.x * sens_horizontal))
		# Rotate only visuals so player model doesn't rotate when standing still
		visuals.rotate_y(deg_to_rad(event.relative.x * sens_horizontal))
		# Rotate camera (vertical)
		camera_mount.rotate_x(deg_to_rad(-event.relative.y * sens_vertical))

func _physics_process(delta: float) -> void:
	var input_dir = Input.get_vector("left", "right", "forward", "backward")
	var direction = (transform.basis * Vector3(input_dir.x, 0, input_dir.y)).normalized()
	
	# In air, either falling or jumping
	if not is_on_floor():
		# Add gravity when not on floor
		velocity.y += CUSTOM_GRAVITY * delta
		
		# No fall logic right now, but if you walk off edge without jumping
		# you would "fall" without the following code
		if is_jumping:
			# Jump with no initial horizontal velocity
			if init_jump_input == Vector2.ZERO:
				# If input in any direction, go slow
				if direction != Vector3.ZERO:
					velocity.x = direction.x * SPEED * 0.25
					velocity.z = direction.z * SPEED * 0.25
				
				# If no input, go straight up and down
				else:
					velocity.x = 0
					velocity.z = 0
				
			else:
				# If input direction key is pressed, continue with SPEED
				if input_dir == init_jump_input:
					velocity.x = init_jump_dir.x * SPEED
					velocity.z = init_jump_dir.y * SPEED
				
				# If opposite of input direction key is pressed, go slow
				elif input_dir + init_jump_input == Vector2.ZERO:
					velocity.x = init_jump_dir.x * SPEED * 0.25
					velocity.z = init_jump_dir.y * SPEED * 0.25
				
				# If no key related to input direction is pressed, go medium slow
				else:
					velocity.x = init_jump_dir.x * SPEED * 0.5
					velocity.z = init_jump_dir.y * SPEED * 0.5

	# If on the floor, allow horizontal movement
	if is_on_floor():
		is_jumping = false
		# Animate and set velocity
		if direction != Vector3.ZERO:
			#facing_dir = direction
			if animation_player.current_animation != "running":
				animation_player.play("running")
			# Rotate visuals to face movement direction
			visuals.look_at(position + direction)
			
			velocity.x = direction.x * SPEED
			velocity.z = direction.z * SPEED
		else:
			if animation_player.current_animation != "idle":
				animation_player.play("idle")
			# Stop moving horizontally
			velocity.x = 0
			velocity.z = 0

		# Handle jump with initial conditions
		if Input.is_action_just_pressed("ui_accept"):
			is_jumping = true
			velocity.y = JUMP_VELOCITY
			init_jump_input = input_dir
			init_jump_dir.x = direction.x
			init_jump_dir.y = direction.z
			


	move_and_slide()
