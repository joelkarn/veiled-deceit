extends Node3D

## Fireball projectile that travels in an arc and deals AoE damage
class_name Fireball

@onready var mesh_instance: MeshInstance3D = $MeshInstance3D

var start_position: Vector3 = Vector3.ZERO
var target_position: Vector3 = Vector3.ZERO
var travel_time: float = 1.5  # Time to reach target in seconds
var current_time: float = 0.0
var aoe_radius: float = 2.0
var damage: float = 20.0
var attacker_id: int = -1
var has_exploded: bool = false

# Arc height control
var arc_height: float = 5.0  # Height of the arc

func set_target_data(from: Vector3, to: Vector3, arc_duration: float = 1.5) -> void:
	start_position = from
	target_position = to
	travel_time = arc_duration
	global_position = start_position

func set_damage_data(dmg: float, shooter_id: int) -> void:
	damage = dmg
	attacker_id = shooter_id

func _ready() -> void:
	set_physics_process(true)
	# Safety cleanup after a bit longer than travel time
	var cleanup_timer = Timer.new()
	cleanup_timer.wait_time = travel_time + 0.5
	cleanup_timer.one_shot = true
	cleanup_timer.timeout.connect(_on_cleanup_timeout)
	add_child(cleanup_timer)
	cleanup_timer.start()

func _on_cleanup_timeout() -> void:
	if not has_exploded:
		_explode()

func _physics_process(delta: float) -> void:
	if has_exploded:
		return
	
	current_time += delta
	var t = current_time / travel_time
	
	if t >= 1.0:
		# Reached target - explode
		global_position = target_position
		_explode()
		return
	
	# Calculate position along arc using quadratic bezier curve
	# Start -> Peak -> End
	var horizontal_pos = start_position.lerp(target_position, t)
	
	# Add vertical arc (parabola)
	# Use sin for smooth arc that peaks in the middle
	var arc_offset = sin(t * PI) * arc_height
	
	global_position = horizontal_pos + Vector3(0, arc_offset, 0)
	
	# Rotate fireball to face direction of travel
	var direction = (target_position - start_position).normalized()
	if direction.length() > 0.01:
		look_at(global_position + direction, Vector3.UP)

func _explode() -> void:
	if has_exploded:
		return
	
	has_exploded = true
	set_physics_process(false)
	
	# Hide the fireball mesh immediately
	if mesh_instance:
		mesh_instance.visible = false
	
	# Create explosion particles
	_create_explosion_particles()
	
	# Deal damage to all entities in radius
	var space_state = get_world_3d().direct_space_state
	var query = PhysicsShapeQueryParameters3D.new()
	var sphere = SphereShape3D.new()
	sphere.radius = aoe_radius
	query.shape = sphere
	query.transform = global_transform
	query.collision_mask = 2  # Layer 2 = players and enemies
	query.collide_with_areas = false
	query.collide_with_bodies = true
	
	var results = space_state.intersect_shape(query)
	
	# Process damage on server or send to server
	if multiplayer.is_server():
		for result in results:
			var body = result.collider
			if body.has_method("take_damage"):
				body.take_damage(damage, attacker_id)
				print("[Fireball] Dealt ", damage, " damage to ", body.name)
	else:
		# Client - send damage requests to server
		var network_manager = NetworkManager
		if network_manager:
			for result in results:
				var body = result.collider
				if body.has_method("take_damage"):
					var body_name = ""
					var body_peer_id = 0
					
					if body.get("player_id") != null:
						body_peer_id = body.player_id
						body_name = "Player_" + str(body_peer_id)
					else:
						body_name = body.name
					
					network_manager.rpc_id(1, "process_damage_request", attacker_id, body_name, body_peer_id, damage)
	
	# Wait for particles to finish before cleanup
	await get_tree().create_timer(1.0).timeout
	queue_free()

func _create_explosion_particles() -> void:
	# Create GPU particles for performance
	var particles = GPUParticles3D.new()
	add_child(particles)
	
	# Particle settings
	particles.emitting = true
	particles.one_shot = true
	particles.amount = 50
	particles.lifetime = 0.8
	particles.explosiveness = 1.0  # All particles spawn at once
	
	# Create particle material
	var particle_material = ParticleProcessMaterial.new()
	
	# Emission shape - sphere burst
	particle_material.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	particle_material.emission_sphere_radius = 0.2
	
	# Direction - radial explosion
	particle_material.direction = Vector3(0, 1, 0)
	particle_material.spread = 180.0
	particle_material.initial_velocity_min = 3.0
	particle_material.initial_velocity_max = 6.0
	
	# Gravity
	particle_material.gravity = Vector3(0, -9.8, 0)
	
	# Size
	particle_material.scale_min = 0.2
	particle_material.scale_max = 0.5
	
	# Color - orange to red to black (fade out)
	var gradient = Gradient.new()
	gradient.add_point(0.0, Color(1.0, 0.8, 0.2, 1.0))  # Bright yellow-orange
	gradient.add_point(0.3, Color(1.0, 0.4, 0.0, 1.0))  # Orange
	gradient.add_point(0.6, Color(0.8, 0.1, 0.0, 0.8))  # Dark red
	gradient.add_point(1.0, Color(0.2, 0.0, 0.0, 0.0))  # Fade to transparent
	
	var gradient_texture = GradientTexture1D.new()
	gradient_texture.gradient = gradient
	particle_material.color_ramp = gradient_texture
	
	# Damping (particles slow down)
	particle_material.damping_min = 2.0
	particle_material.damping_max = 4.0
	
	particles.process_material = particle_material
	
	# Create mesh for particles (small spheres)
	var particle_mesh = SphereMesh.new()
	particle_mesh.radial_segments = 8
	particle_mesh.rings = 4
	particle_mesh.radius = 0.15
	particle_mesh.height = 0.3
	
	# Create glowing material for particles
	var particle_draw_material = StandardMaterial3D.new()
	particle_draw_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	particle_draw_material.vertex_color_use_as_albedo = true
	particle_draw_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	particle_draw_material.emission_enabled = true
	particle_draw_material.emission_energy_multiplier = 2.0
	
	particle_mesh.material = particle_draw_material
	particles.draw_pass_1 = particle_mesh
