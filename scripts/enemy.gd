extends CharacterBody3D

@export var max_health: float = 100.0
@export var health: float = 100.0

@onready var mesh_instance: MeshInstance3D = $MeshInstance3D

func _ready():
	health = max_health

func take_damage(amount: float) -> void:
	health -= amount
	print("Enemy took ", amount, " damage. Health: ", health)
	
	# Visual feedback - flash red
	if mesh_instance:
		flash_damage()
	
	if health <= 0:
		die()

func flash_damage() -> void:
	# Create a brief red flash effect
	var material = mesh_instance.get_active_material(0)
	if material:
		var original_color = material.albedo_color
		material.albedo_color = Color.RED
		await get_tree().create_timer(0.1).timeout
		material.albedo_color = original_color

func die() -> void:
	print("Enemy died!")
	queue_free()
