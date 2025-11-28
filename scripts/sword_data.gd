extends WeaponData

## Sword weapon
class_name SwordData

func _init() -> void:
	item_id = "sword"
	item_name = "Sword"
	item_type = ItemType.WEAPON
	description = "A sword."
	max_stack = 1

	damage = 20.0
	attack_speed = 1
	attack_range = 2.5
