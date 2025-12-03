extends Node3D

## AoE indicator that projects onto surfaces like a decal
class_name AoEIndicator

@onready var decal: Decal = $Decal
@onready var area: Area3D = $Area3D

func _ready() -> void:
	# Ensure decal projects downward
	if decal:
		# The decal will project along its -Y axis (down)
		# Size controls the projection box: X width, Y depth projection, Z height
		decal.size = Vector3(4.0, 10.0, 4.0)  # 4x4 circle, projects 10 units down
