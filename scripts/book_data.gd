extends ItemData
class_name BookData

## Book item data - items that can be read to show text content

@export_multiline var left_page_text: String = "This is the left page of the book.\n\nYou can write any text here."
@export_multiline var right_page_text: String = "This is the right page of the book.\n\nAdd more content as needed."

func _init() -> void:
	item_type = ItemType.QUEST_ITEM
	is_equippable = true
	max_stack = 1  ## Books don't stack

func use_item(player: Node) -> bool:
	# Equipping the book - doesn't consume it
	print("Book equipped: ", item_name)
	return false  # Don't consume the item
