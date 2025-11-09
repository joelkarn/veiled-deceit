extends ItemData
class_name ConsumableData

## Consumable item data - items that can be consumed for effects

enum EffectType {
	HEAL,
	MANA,
	BUFF,
	DEBUFF
}

@export var effect_type: EffectType = EffectType.HEAL
@export var effect_value: float = 10.0  ## Amount of health/mana/etc restored
@export var duration: float = 0.0  ## Duration for buffs (0 = instant)

func _init() -> void:
	item_type = ItemType.CONSUMABLE
	is_equippable = false
	max_stack = 99  ## Consumables stack

func use_item(player: Node) -> bool:
	# Apply effect based on type
	match effect_type:
		EffectType.HEAL:
			if player.has_method("heal"):
				player.heal(effect_value)
				print(player.name, " consumed ", item_name, " and healed ", effect_value, " HP")
				return true
		EffectType.MANA:
			# Future: Add mana system
			print(player.name, " consumed ", item_name, " (mana not implemented)")
			return true
		_:
			print("Effect type not implemented: ", effect_type)
	
	return false
