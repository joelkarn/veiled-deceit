extends CharacterBody3D

@onready var camera_mount: Node3D = $camera_mount
@onready var animation_player: AnimationPlayer = $visuals/mixamo_base/AnimationPlayer
@onready var visuals: Node3D = $visuals

const SPEED = 6.5
const CUSTOM_GRAVITY = -25.0
const JUMP_VELOCITY = 10.0

@export var sens_horizontal = 0.1
@export var sens_vertical = 0.1

# Stores info about the "locked" direction and speed once in the air
var jump_dir_string = "none"    # String form of direction input (e.g., "W", "W+D", "none")
var jump_direction = Vector3.ZERO  # Actual direction vector (normalized)
var jump_speed = 0.0            # Magnitude of horizontal speed when jump started

# Dictionary to help us determine opposites
var OPPOSITES = {
	"W": "S", "A": "D", "S": "W", "D": "A",
	"W+A": "S+D", "A+W": "S+D",
	"W+D": "S+A", "D+W": "S+A",
	"S+A": "W+D", "A+S": "W+D",
	"S+D": "W+A", "D+S": "W+A"
}

func join_strings(array: Array, delimiter: String = ",") -> String:
	var result := ""
	for i in range(array.size()):
		if i > 0:
			result += delimiter
		result += str(array[i])
	return result

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
	# Always apply gravity if not on the floor
	if not is_on_floor():
		velocity.y += CUSTOM_GRAVITY * delta

	if is_on_floor():
		# ---------------------------------------
		#       NORMAL MOVEMENT ON FLOOR
		# ---------------------------------------
		var input_dir = Input.get_vector("left", "right", "forward", "backward", 0.01)
		var direction = (transform.basis * Vector3(input_dir.x, 0, input_dir.y)).normalized()

		# Animate and set velocity
		if direction != Vector3.ZERO:
			if animation_player.current_animation != "running":
				animation_player.play("running")
			visuals.look_at(position + direction)
			velocity.x = direction.x * SPEED
			velocity.z = direction.z * SPEED
		else:
			if animation_player.current_animation != "idle":
				animation_player.play("idle")
			velocity.x = move_toward(velocity.x, 0, SPEED)
			velocity.z = move_toward(velocity.z, 0, SPEED)

		# Handle jump
		if Input.is_action_just_pressed("ui_accept"):
			# Lock in horizontal direction and speed if not zero
			var dir_string = _get_direction_string()
			if direction.length() > 0.001:
				jump_dir_string = dir_string
				jump_direction = direction
				jump_speed = SPEED
			else:
				# No initial direction => locked direction = none
				jump_dir_string = "none"
				jump_direction = Vector3.ZERO
				jump_speed = 0.0

			velocity.y = JUMP_VELOCITY

	else:
		# ---------------------------------------
		#            IN THE AIR
		# ---------------------------------------
		# We do NOT recalculate direction or rotate visuals based on new input.
		# Instead, we modify the speed factor depending on pressed keys.
		_apply_midair_velocity_logic()

	move_and_slide()


func _apply_midair_velocity_logic() -> void:
	var dir_string = _get_direction_string()
	var new_factor = 1.0

	# CASE 1: If we jumped with no direction locked
	if jump_dir_string == "none":
		if dir_string == "none":
			# Still no direction => no horizontal movement
			velocity.x = 0
			velocity.z = 0
			return
		else:
			# If the player presses ANY direction in midair for the first time,
			# we "lock" that direction at 50% speed.
			var new_dir = _get_direction_vector(dir_string).normalized()
			jump_direction = new_dir
			jump_dir_string = dir_string
			jump_speed = SPEED  # store normal speed internally
			new_factor = 0.5    # but only move at 50%
			velocity.x = jump_direction.x * jump_speed * new_factor
			velocity.z = jump_direction.z * jump_speed * new_factor
			return
	else:
		# CASE 2: We jumped with a locked direction
		# Decide if the current pressed direction is the same, opposite, or unrelated
		if dir_string == jump_dir_string:
			# Same direction => 100%
			new_factor = 1.0
		elif OPPOSITES.get(jump_dir_string, "") == dir_string:
			# Opposite direction => 25%
			new_factor = 0.25
		elif dir_string == "none":
			# Released keys => 50%
			new_factor = 0.5
		else:
			# Some unrelated direction => also 50%
			# For example, jumped forward (W) but pressed D => "unrelated"
			new_factor = 0.5

		# Apply the locked direction with the chosen factor
		velocity.x = jump_direction.x * jump_speed * new_factor
		velocity.z = jump_direction.z * jump_speed * new_factor


#
# Helpers to track direction as string vs. vector
#
func _get_direction_string() -> String:
	var pressed = []
	if Input.is_action_pressed("forward"):
		pressed.append("W")
	if Input.is_action_pressed("backward"):
		pressed.append("S")
	if Input.is_action_pressed("left"):
		pressed.append("A")
	if Input.is_action_pressed("right"):
		pressed.append("D")

	if pressed.size() == 0:
		return "none"

	# Sort so "W+D" == "D+W"
	pressed.sort_custom(func(a, b):
		if a < b:
			return -1
		elif a > b:
			return 1
		else:
			return 0
)
	return join_strings(pressed, "+")


func _get_direction_vector(dir_string: String) -> Vector3:
	# Convert a direction string (e.g., "W+D") into a local direction vector
	var result = Vector3.ZERO
	if dir_string == "none":
		return result

	# Because we rely on the transform basis for correct orientation in 3D,
	# we find forward/backward from transform.basis.z, left/right from transform.basis.x
	if dir_string.find("W") != -1:
		result += -transform.basis.z  # forward
	if dir_string.find("S") != -1:
		result += transform.basis.z   # backward
	if dir_string.find("A") != -1:
		result += -transform.basis.x  # left
	if dir_string.find("D") != -1:
		result += transform.basis.x   # right

	return result  # normalization done by caller
