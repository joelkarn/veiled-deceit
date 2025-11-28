extends Resource
class_name ItemData

## Base class for all items in the game
## Items can be weapons, consumables, quest items, etc.

enum ItemType {
	WEAPON,
	CONSUMABLE,
	QUEST_ITEM,
	MATERIAL
}

@export var item_id: String = ""  ## Unique identifier for this item
@export var item_name: String = ""  ## Display name
@export var description: String = ""  ## Item description
@export var icon: Texture2D = null  ## Icon for UI display
@export var item_type: ItemType = ItemType.MATERIAL
@export var max_stack: int = 1  ## Maximum stack size (1 = doesn't stack)
@export var is_equippable: bool = false  ## Can this item be equipped?

## Virtual method for item use - override in subclasses
func use_item(_player: Node) -> bool:
	push_warning("use_item not implemented for " + item_name)
	return false
