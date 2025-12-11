extends MeshInstance3D

## Holy symbol that glows when light is nearby

@export var detection_range: float = 15.0  ## Distance to detect light sources
@export var max_brightness: float = 3.0  ## Maximum emission strength
@export var fade_speed: float = 2.0  ## How fast the symbol fades in/out

var current_brightness: float = 0.0
var symbol_material: ShaderMaterial
var update_timer: float = 0.0
var update_interval: float = 0.1  # Update 10 times per second for performance

const SYMBOL_FOLDER = "res://assets/textures/holy_symbols_folder/"

func _ready() -> void:
	# Get list of all PNG files in the holy symbols folder
	var symbol_textures = _get_symbol_textures()

	# Pick a random texture
	var random_texture: Texture2D = null
	if symbol_textures.size() > 0:
		randomize()
		var random_index = randi() % symbol_textures.size()
		random_texture = load(SYMBOL_FOLDER + symbol_textures[random_index])

	# Create shader material for the symbol
	var shader = load("res://assets/shaders/holy_symbol.gdshader")
	symbol_material = ShaderMaterial.new()
	symbol_material.shader = shader

	# Set the texture and initial emission
	if random_texture:
		symbol_material.set_shader_parameter("symbol_texture", random_texture)
	symbol_material.set_shader_parameter("glow_color", Vector3(1.0, 0.95, 0.7))
	symbol_material.set_shader_parameter("emission_strength", 0.0)  # Start invisible	# Create a quad mesh for the symbol
	var quad = QuadMesh.new()
	quad.size = Vector2(2.0, 2.0)
	mesh = quad
	material_override = symbol_material

	# Set render priority to draw on top of walls
	transparency = 0.99  # Make slightly transparent to enable alpha blending
	sorting_offset = 0.1  # Draw on top of geometry at same position

func _get_symbol_textures() -> Array:
	var textures = []
	var dir = DirAccess.open(SYMBOL_FOLDER)

	if dir:
		dir.list_dir_begin()
		var file_name = dir.get_next()

		while file_name != "":
			# Only get PNG files (not .import files)
			if file_name.ends_with(".png") and not file_name.ends_with(".import"):
				textures.append(file_name)
			file_name = dir.get_next()

		dir.list_dir_end()

	return textures

func _process(delta: float) -> void:
	# Update less frequently for performance
	update_timer += delta
	if update_timer < update_interval:
		# Still smoothly transition even when not checking lights
		current_brightness = lerp(current_brightness, current_brightness, fade_speed * delta)
		_update_material()
		return

	update_timer = 0.0

	var target_brightness = 0.0
	var nearest_light_distance = _find_nearest_light_distance()

	if nearest_light_distance <= detection_range:
		# Fade in based on distance (closer = brighter)
		var distance_factor = 1.0 - (nearest_light_distance / detection_range)
		# Use a power curve for more dramatic reveal
		distance_factor = pow(distance_factor, 0.7)
		target_brightness = max_brightness * distance_factor

	# Smoothly transition to target brightness
	current_brightness = lerp(current_brightness, target_brightness, fade_speed * delta * 10.0)
	_update_material()

func _update_material() -> void:
	if symbol_material:
		# Update shader emission strength parameter
		symbol_material.set_shader_parameter("emission_strength", current_brightness)

func _find_nearest_light_distance() -> float:
	var nearest = detection_range + 1.0

	# Recursively check all nodes for OmniLight3D
	nearest = _find_lights_recursive(get_tree().root, nearest)

	return nearest

func _find_lights_recursive(node: Node, current_nearest: float) -> float:
	if node is OmniLight3D and node.visible and node.light_energy > 0.5:
		var distance = global_position.distance_to(node.global_position)
		if distance < current_nearest:
			current_nearest = distance

	for child in node.get_children():
		var child_nearest = _find_lights_recursive(child, current_nearest)
		if child_nearest < current_nearest:
			current_nearest = child_nearest

	return current_nearest
