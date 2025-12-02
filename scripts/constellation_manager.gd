extends Node

## Manages constellations in the sky - spawns them at random positions and handles highlighting

@export var constellations: Array[ConstellationData] = []
@export var sky_material: ShaderMaterial = null

# Randomized constellation positions (set once at game start)
var constellation_positions: Array[Vector3] = []
var constellation_highlights: Array[float] = []  # 0.0 to 1.0 for glow intensity

# Lines between stars (MeshInstance3D for drawing constellation lines)
var constellation_lines: MeshInstance3D = null
var line_material: StandardMaterial3D = null

# Stars mesh for drawing constellation stars permanently
var constellation_stars: MeshInstance3D = null
var star_material: StandardMaterial3D = null

# Random background stars
var background_stars: MeshInstance3D = null
var background_star_material: StandardMaterial3D = null
@export var num_background_stars: int = 200
var background_star_directions: Array[Vector3] = []

func _ready() -> void:
	# Create line rendering setup
	_setup_line_renderer()
	_setup_star_renderer()
	_setup_background_stars()

	# Randomize constellation positions
	randomize_constellations()

	# Generate random background stars
	_generate_background_stars()

	# Update shader with constellation data
	update_shader_uniforms()

	# Draw all constellation stars
	_draw_all_constellation_stars()
	_draw_background_stars()

func _setup_line_renderer() -> void:
	constellation_lines = MeshInstance3D.new()
	add_child(constellation_lines)

	# Material for constellation lines
	line_material = StandardMaterial3D.new()
	line_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	line_material.vertex_color_use_as_albedo = true
	line_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	line_material.albedo_color = Color(1.0, 0.9, 0.5, 0.8)  # Golden color

	constellation_lines.material_override = line_material
	constellation_lines.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

func randomize_constellations() -> void:
	constellation_positions.clear()
	constellation_highlights.clear()

	var min_separation = 0.8  # Minimum distance between constellation centers (on unit sphere)
	var max_attempts = 100  # Max attempts per constellation to find valid position

	for constellation in constellations:
		var valid_position = false
		var attempts = 0
		var random_dir = Vector3.ZERO

		while not valid_position and attempts < max_attempts:
			# Generate random direction in sky
			random_dir = Vector3(
				randf_range(-1.0, 1.0),
				randf_range(0.2, 1.0),  # Keep above horizon
				randf_range(-1.0, 1.0)
			).normalized()

			# Check if far enough from existing constellations
			valid_position = true
			for existing_pos in constellation_positions:
				var distance = random_dir.distance_to(existing_pos)
				if distance < min_separation:
					valid_position = false
					break

			attempts += 1

		# If couldn't find valid position after max attempts, use last attempt anyway
		constellation_positions.append(random_dir)
		constellation_highlights.append(0.0)  # Start unhighlighted

func update_shader_uniforms() -> void:
	if not sky_material:
		return

	sky_material.set_shader_parameter("num_constellations", constellations.size())

	# Pass constellation centers
	for i in range(constellations.size()):
		sky_material.set_shader_parameter("constellation_centers[%d]" % i, constellation_positions[i])
		sky_material.set_shader_parameter("constellation_radii[%d]" % i, constellations[i].radius)
		sky_material.set_shader_parameter("constellation_glow[%d]" % i, constellation_highlights[i])

func highlight_constellation(index: int, intensity: float = 1.0) -> void:
	if index < 0 or index >= constellation_highlights.size():
		return

	constellation_highlights[index] = clamp(intensity, 0.0, 1.0)

	# Update shader
	if sky_material:
		sky_material.set_shader_parameter("constellation_glow[%d]" % index, constellation_highlights[index])

	# Debug output
	if constellation_highlights[index] > 0.0:
		print("[ConstellationManager] Highlighting constellation ", index, " with intensity ", constellation_highlights[index])

	# Draw constellation lines
	if constellation_highlights[index] > 0.0:
		_draw_constellation_lines(index)
	else:
		_clear_constellation_lines()

func unhighlight_all() -> void:
	for i in range(constellation_highlights.size()):
		constellation_highlights[i] = 0.0
		if sky_material:
			sky_material.set_shader_parameter("constellation_glow[%d]" % i, 0.0)

	_clear_constellation_lines()

func check_ray_intersection(ray_direction: Vector3) -> int:
	"""Check if a ray from camera intersects any constellation. Returns constellation index or -1."""
	ray_direction = ray_direction.normalized()

	for i in range(constellation_positions.size()):
		var constellation_center = constellation_positions[i].normalized()
		var distance = ray_direction.distance_to(constellation_center)

		if distance < constellations[i].radius:
			return i

	return -1

func _draw_constellation_lines(constellation_index: int) -> void:
	if constellation_index < 0 or constellation_index >= constellations.size():
		return

	var constellation = constellations[constellation_index]
	var center = constellation_positions[constellation_index]

	# Create mesh for lines
	var immediate_mesh = ImmediateMesh.new()
	immediate_mesh.surface_begin(Mesh.PRIMITIVE_LINES)

	# Get camera to position lines in world space
	var camera = get_viewport().get_camera_3d()
	if not camera:
		return

	var cam_pos = camera.global_position
	var distance_from_camera = 100.0  # Far enough to look like skybox, follows camera

	# Create local coordinate system at constellation center to preserve shape
	var center_dir = center.normalized()
	var tangent = center_dir.cross(Vector3.UP)
	if tangent.length_squared() < 0.001:
		tangent = center_dir.cross(Vector3.RIGHT)
	tangent = tangent.normalized()
	var bitangent = center_dir.cross(tangent).normalized()

	# Draw lines between connected stars
	for connection in constellation.connections:
		var star1_idx = connection.x
		var star2_idx = connection.y

		if star1_idx >= constellation.star_positions.size() or star2_idx >= constellation.star_positions.size():
			continue

		# Project star positions onto the tangent plane to preserve constellation shape
		var star1_offset = constellation.star_positions[star1_idx]
		var star2_offset = constellation.star_positions[star2_idx]

		var star1_dir = (center_dir + tangent * star1_offset.x + bitangent * star1_offset.y).normalized()
		var star2_dir = (center_dir + tangent * star2_offset.x + bitangent * star2_offset.y).normalized()

		var star1_pos = cam_pos + star1_dir * distance_from_camera
		var star2_pos = cam_pos + star2_dir * distance_from_camera

		# Add line vertices with color
		var alpha = constellation_highlights[constellation_index]
		var line_color = Color(1.0, 0.9, 0.5, alpha * 0.8)

		immediate_mesh.surface_set_color(line_color)
		immediate_mesh.surface_add_vertex(star1_pos)
		immediate_mesh.surface_set_color(line_color)
		immediate_mesh.surface_add_vertex(star2_pos)

	immediate_mesh.surface_end()
	constellation_lines.mesh = immediate_mesh

func _clear_constellation_lines() -> void:
	if constellation_lines:
		constellation_lines.mesh = null

func get_constellation_name(index: int) -> String:
	if index >= 0 and index < constellations.size():
		return constellations[index].constellation_name
	return ""

func get_constellation_description(index: int) -> String:
	if index >= 0 and index < constellations.size():
		return constellations[index].description
	return ""

func _setup_star_renderer() -> void:
	constellation_stars = MeshInstance3D.new()
	add_child(constellation_stars)

	# Material for constellation stars
	star_material = StandardMaterial3D.new()
	star_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	star_material.vertex_color_use_as_albedo = true
	star_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	star_material.albedo_color = Color(1.0, 1.0, 1.0, 1.0)
	star_material.blend_mode = BaseMaterial3D.BLEND_MODE_ADD  # Additive blending for glow effect

	constellation_stars.material_override = star_material
	constellation_stars.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

var last_highlight_state: Array[float] = []  # Track when to redraw

func _draw_all_constellation_stars() -> void:
	# Create mesh for all constellation stars (as billboarded quads)
	var immediate_mesh = ImmediateMesh.new()
	immediate_mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLES)

	# Get camera to position stars relative to view (skybox effect)
	var camera = get_viewport().get_camera_3d()
	if not camera:
		return

	var cam_pos = camera.global_position
	var distance_from_camera = 100.0  # Far enough to look like skybox, follows camera
	var star_size = 0.15  # Base size of star quads

	# Draw stars for each constellation
	for i in range(constellations.size()):
		var constellation = constellations[i]
		var center = constellation_positions[i]

		# Check if this constellation is highlighted
		var is_highlighted = constellation_highlights[i] > 0.0

		# Create local coordinate system at constellation center to preserve shape
		var center_dir = center.normalized()
		var tangent = center_dir.cross(Vector3.UP)
		if tangent.length_squared() < 0.001:
			tangent = center_dir.cross(Vector3.RIGHT)
		tangent = tangent.normalized()
		var bitangent = center_dir.cross(tangent).normalized()

		# Draw each star in the constellation
		for star_pos_relative in constellation.star_positions:
			# Project star position onto the tangent plane to preserve constellation shape
			var star_dir = (center_dir + tangent * star_pos_relative.x + bitangent * star_pos_relative.y).normalized()
			var star_pos = cam_pos + star_dir * distance_from_camera

			# Calculate billboard orientation (always face camera)
			var to_camera = (cam_pos - star_pos).normalized()

			# Make highlighted stars bigger
			var actual_star_size = star_size
			if is_highlighted:
				actual_star_size = star_size * 2.0  # Double size when highlighted
			var right = to_camera.cross(Vector3.UP).normalized()
			var up = right.cross(to_camera).normalized()

			# Star color - much brighter when highlighted
			var star_color = Color(1.2, 1.2, 1.0, 1.0)  # Slightly bright normally
			if is_highlighted:
				star_color = Color(5.0, 4.5, 3.0, 1.0)  # Extremely bright golden glow when highlighted

			# Create quad (two triangles) for the star
			var v1 = star_pos - right * actual_star_size - up * actual_star_size
			var v2 = star_pos + right * actual_star_size - up * actual_star_size
			var v3 = star_pos + right * actual_star_size + up * actual_star_size
			var v4 = star_pos - right * actual_star_size + up * actual_star_size

			# First triangle
			immediate_mesh.surface_set_color(star_color)
			immediate_mesh.surface_add_vertex(v1)
			immediate_mesh.surface_set_color(star_color)
			immediate_mesh.surface_add_vertex(v2)
			immediate_mesh.surface_set_color(star_color)
			immediate_mesh.surface_add_vertex(v3)

			# Second triangle
			immediate_mesh.surface_set_color(star_color)
			immediate_mesh.surface_add_vertex(v1)
			immediate_mesh.surface_set_color(star_color)
			immediate_mesh.surface_add_vertex(v3)
			immediate_mesh.surface_set_color(star_color)
			immediate_mesh.surface_add_vertex(v4)

	immediate_mesh.surface_end()
	constellation_stars.mesh = immediate_mesh

func _process(_delta: float) -> void:
	# Redraw stars every frame to follow camera (skybox effect)
	# This is necessary because stars are positioned relative to camera
	_draw_all_constellation_stars()
	_draw_background_stars()

	# Also redraw lines if any constellation is highlighted
	for i in range(constellation_highlights.size()):
		if constellation_highlights[i] > 0.0:
			_draw_constellation_lines(i)
			break

# ----------------------------
# Background Stars
# ----------------------------

func _setup_background_stars() -> void:
	background_stars = MeshInstance3D.new()
	add_child(background_stars)

	# Material for background stars
	background_star_material = StandardMaterial3D.new()
	background_star_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	background_star_material.vertex_color_use_as_albedo = true
	background_star_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	background_star_material.albedo_color = Color(1.0, 1.0, 1.0, 1.0)
	background_star_material.blend_mode = BaseMaterial3D.BLEND_MODE_ADD  # Additive blending for glow

	background_stars.material_override = background_star_material
	background_stars.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

func _generate_background_stars() -> void:
	background_star_directions.clear()

	for i in range(num_background_stars):
		# Generate random direction in sky
		var random_dir = Vector3(
			randf_range(-1.0, 1.0),
			randf_range(-0.3, 1.0),  # Allow some below horizon for fuller sky
			randf_range(-1.0, 1.0)
		).normalized()

		background_star_directions.append(random_dir)

func _draw_background_stars() -> void:
	# Create mesh for background stars
	var immediate_mesh = ImmediateMesh.new()
	immediate_mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLES)

	# Get camera to position stars
	var camera = get_viewport().get_camera_3d()
	if not camera:
		return

	var cam_pos = camera.global_position
	var distance_from_camera = 95.0  # Slightly closer than constellations
	var star_size = 0.08  # Smaller than constellation stars

	# Draw each background star
	for star_dir in background_star_directions:
		var star_pos = cam_pos + star_dir * distance_from_camera

		# Calculate billboard orientation
		var to_camera = (cam_pos - star_pos).normalized()
		var right = to_camera.cross(Vector3.UP).normalized()
		var up = right.cross(to_camera).normalized()

		# Random brightness and slight color variation
		var brightness = randf_range(0.6, 1.0)
		var star_color = Color(brightness, brightness, brightness * 0.95, 1.0)

		# Create quad
		var v1 = star_pos - right * star_size - up * star_size
		var v2 = star_pos + right * star_size - up * star_size
		var v3 = star_pos + right * star_size + up * star_size
		var v4 = star_pos - right * star_size + up * star_size

		# First triangle
		immediate_mesh.surface_set_color(star_color)
		immediate_mesh.surface_add_vertex(v1)
		immediate_mesh.surface_set_color(star_color)
		immediate_mesh.surface_add_vertex(v2)
		immediate_mesh.surface_set_color(star_color)
		immediate_mesh.surface_add_vertex(v3)

		# Second triangle
		immediate_mesh.surface_set_color(star_color)
		immediate_mesh.surface_add_vertex(v1)
		immediate_mesh.surface_set_color(star_color)
		immediate_mesh.surface_add_vertex(v3)
		immediate_mesh.surface_set_color(star_color)
		immediate_mesh.surface_add_vertex(v4)

	immediate_mesh.surface_end()
	background_stars.mesh = immediate_mesh
