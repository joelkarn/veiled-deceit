extends WeaponData

## Hammer weapon - slower but more powerful than sword
class_name HammerData

func _init() -> void:
	item_id = "hammer"
	item_name = "Hammer"
	item_type = ItemType.WEAPON
	description = "A heavy hammer. Deals high damage but swings slowly."
	max_stack = 1

	damage = 20.0
	attack_speed = 0.67  # Slower than sword (1.5s per attack = 0.67 attacks/sec)
	attack_range = 2.5
