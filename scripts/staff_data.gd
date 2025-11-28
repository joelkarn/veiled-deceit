extends WeaponData

## Staff weapon - slower but more powerful than sword
class_name StaffData

func _init() -> void:
	item_id = "staff"
	item_name = "Staff"
	item_type = ItemType.WEAPON
	description = "A sorcerers staff."
	max_stack = 1

	damage = 20.0
	attack_speed = 0.67  # Slower than sword (1.5s per attack = 0.67 attacks/sec)
	attack_range = 2.5
