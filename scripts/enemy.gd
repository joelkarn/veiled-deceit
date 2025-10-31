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

func take_damage(amount: float) -> void:
	health -= amount
	print("Enemy took ", amount, " damage. Health: ", health)
	
	# Visual feedback - flash red
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
	print("Enemy died!")
	queue_free()
