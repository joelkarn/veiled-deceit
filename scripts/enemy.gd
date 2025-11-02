extends CharacterBody3D

@export var max_health: float = 100.0
@export var health: float = 100.0

@onready var mesh_instance: MeshInstance3D = $MeshInstance3D

var original_material: StandardMaterial3D
var is_flashing := false

func _ready():
	health = max_health
	# Create a unique material for this enemy
	original_material = StandardMaterial3D.new()
	original_material.albedo_color = Color.WHITE
	mesh_instance.material_override = original_material

func take_damage(amount: float, attacker_id: int = 0) -> void:
	# Only host processes damage
	if not multiplayer.is_server():
		return
	
	health -= amount
	health = max(0, health)  # Clamp to 0
	print("Enemy took ", amount, " damage. Health: ", health)
	
	# Sync health to all clients
	sync_health()
	
	# Visual feedback - flash red
	if mesh_instance:
		flash_damage()
	
	if health <= 0:
		die()

func sync_health() -> void:
	if not multiplayer.is_server():
		return
	
	# Sync health to all clients
	rpc("update_health", health)

@rpc("authority", "call_remote", "reliable")
func update_health(new_health: float) -> void:
	health = new_health
	
	# Visual feedback on clients
	if mesh_instance:
		flash_damage()
	
	if health <= 0:
		die()

func flash_damage() -> void:
	# Prevent overlapping flashes
	if is_flashing:
		return
	
	is_flashing = true
	# Flash red
	original_material.albedo_color = Color.RED
	await get_tree().create_timer(0.15).timeout
	# Flash back to white
	original_material.albedo_color = Color.WHITE
	is_flashing = false

func die() -> void:
	if not multiplayer.is_server():
		return
	
	print("Enemy died!")
	
	# Broadcast death to all clients
	rpc("sync_enemy_death")
	queue_free()

@rpc("authority", "call_remote", "reliable")
func sync_enemy_death() -> void:
	queue_free()
