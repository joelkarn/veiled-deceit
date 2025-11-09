extends WeaponData

## Axe weapon - slower but more powerful than sword
class_name AxeData

func _init() -> void:
	item_id = "axe"
	item_name = "Axe"
	item_type = ItemType.WEAPON
	description = "A heavy woodcutting axe. Deals high damage but swings slowly."
	max_stack = 1

	damage = 20.0
	attack_speed = 0.67  # Slower than sword (1.5s per attack = 0.67 attacks/sec)
	range = 2.5
