extends WeaponData

## Bow weapon - ranged weapon using raycast for attacks
class_name BowData

## Maximum range for the raycast attack
@export var max_raycast_range: float = 20.0

func _init() -> void:
	item_id = "bow"
	item_name = "Hunting Bow"
	item_type = ItemType.WEAPON
	description = "A ranged weapon. Aim and shoot at distant enemies."
	max_stack = 1

	damage = 12.0
	attack_speed = 0.8  # Slower than sword (1.25s per attack = 0.8 attacks/sec)
	range = 20.0  # Used for UI display
	max_raycast_range = 20.0  # Actual raycast range
