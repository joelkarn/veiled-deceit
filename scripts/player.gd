extends CharacterBody3D

@onready var camera_mount: Node3D = $camera_mount
@onready var animation_player: AnimationPlayer = $visuals/mixamo_base/AnimationPlayer
@onready var visuals: Node3D = $visuals

const SPEED = 6.5
const CUSTOM_GRAVITY = -30.0
const JUMP_VELOCITY = 10.0

@export var sens_horizontal = 0.1
@export var sens_vertical = 0.1

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
	# Add gravity when not on floor
	if not is_on_floor():
		velocity.y += CUSTOM_GRAVITY * delta

	# If on the floor, allow horizontal movement
	if is_on_floor():
		var input_dir = Input.get_vector("left", "right", "forward", "backward")
		var direction = (transform.basis * Vector3(input_dir.x, 0, input_dir.y)).normalized()

		# Animate and set velocity
		if direction != Vector3.ZERO:
			if animation_player.current_animation != "running":
				animation_player.play("running")
			# Rotate visuals to face movement direction
			visuals.look_at(position + direction)
			
			velocity.x = direction.x * SPEED
			velocity.z = direction.z * SPEED
		else:
			if animation_player.current_animation != "idle":
				animation_player.play("idle")
			# Gradually stop moving horizontally
			velocity.x = move_toward(velocity.x, 0, SPEED)
			velocity.z = move_toward(velocity.z, 0, SPEED)

		# Handle jump only when on the floor
		if Input.is_action_just_pressed("ui_accept"):
			velocity.y = JUMP_VELOCITY

	# If not on the floor, don't modify velocity.x or velocity.z (no air control)
	# velocity.y is already being handled by gravity above

	move_and_slide()
