extends Label

## Interaction prompt - shows when player is near interactable objects

func _ready() -> void:
	hide()
	# Center the label
	horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vertical_alignment = VERTICAL_ALIGNMENT_CENTER

func show_prompt(text: String) -> void:
	self.text = text
	show()

func hide_prompt() -> void:
	hide()
