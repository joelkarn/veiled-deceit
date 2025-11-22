extends Node3D

## Arrow projectile that sticks to objects
class_name Arrow

@onready var mesh_instance: MeshInstance3D = $MeshInstance3D

var lifetime: float = 10.0  # Seconds before arrow disappears
var timer: float = 0.0

func _ready() -> void:
	# Auto-remove after lifetime
	pass

func _process(delta: float) -> void:
	timer += delta
	if timer >= lifetime:
		queue_free()
