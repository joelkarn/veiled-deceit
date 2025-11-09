extends ItemData
class_name WeaponData

## Weapon item data - extends ItemData with weapon-specific properties

@export var damage: float = 10.0  ## Base damage
@export var attack_speed: float = 1.0  ## Attacks per second
@export var range: float = 2.0  ## Attack range in meters
@export var weapon_model: PackedScene = null  ## 3D model to display when equipped

func _init() -> void:
	item_type = ItemType.WEAPON
	is_equippable = true
	max_stack = 1  ## Weapons don't stack

func use_item(player: Node) -> bool:
	# Equip weapon logic will be handled by player/weapon manager
	print("Equipped weapon: ", item_name)
	return true
