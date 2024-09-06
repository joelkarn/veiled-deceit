extends CharacterBody3D
@onready var camera_mount: Node3D = $camera_mount
@onready var animation_player: AnimationPlayer = $visuals/mixamo_base/AnimationPlayer
@onready var visuals: Node3D = $visuals


const SPEED = 5.0
const JUMP_VELOCITY = 5.0

@export var sens_horizontal = 0.1
@export var sens_vertical = 0.1

func _ready():
	# Mouse is not visible and not able to move outside of window
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	
func _input(event):
	if event is InputEventMouseMotion:
		# Rotates player on horizontal mouse movement
		rotate_y(deg_to_rad(-event.relative.x * sens_horizontal))
		# Makes it so the visuals don't rotate when standing still
		visuals.rotate_y(deg_to_rad(event.relative.x * sens_horizontal))
		# Rotates camera on vertical mouse movement
		camera_mount.rotate_x(deg_to_rad(-event.relative.y * sens_vertical))

func _physics_process(delta: float) -> void:
	# Add the gravity.
	if not is_on_floor():
		velocity += get_gravity() * delta

	# Handle jump.
	if Input.is_action_just_pressed("ui_accept") and is_on_floor():
		velocity.y = JUMP_VELOCITY

	# Get the input direction and handle the movement/deceleration.
	# As good practice, you should replace UI actions with custom gameplay actions.
	var input_dir := Input.get_vector("left", "right", "forward", "backward")
	var direction := (transform.basis * Vector3(input_dir.x, 0, input_dir.y)).normalized()
	if direction:
		if animation_player.current_animation != "running":
			animation_player.play("running")
		
		# Rotates visuals (not actual player but just the visual elements/the model)
		visuals.look_at(position + direction)
		
		velocity.x = direction.x * SPEED
		velocity.z = direction.z * SPEED
	else:
		if animation_player.current_animation != "idle":
			animation_player.play("idle")
			
		velocity.x = move_toward(velocity.x, 0, SPEED)
		velocity.z = move_toward(velocity.z, 0, SPEED)

	move_and_slide()
