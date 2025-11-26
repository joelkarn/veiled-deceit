extends Control

## Sign UI - Shows text content when reading a sign

@onready var sign_panel: Panel = $SignContainer/SignPanel
@onready var sign_title: Label = $SignContainer/SignPanel/MarginContainer/VBoxContainer/SignTitle
@onready var sign_text: Label = $SignContainer/SignPanel/MarginContainer/VBoxContainer/SignText

var current_sign_data: SignData = null

func _ready() -> void:
	hide()
	mouse_filter = Control.MOUSE_FILTER_IGNORE

func show_sign(sign_data: SignData) -> void:
	if not sign_data:
		return

	current_sign_data = sign_data

	# Set the text content
	if sign_title:
		sign_title.text = sign_data.sign_title
	if sign_text:
		sign_text.text = sign_data.sign_text

	# Show the sign UI
	show()
	mouse_filter = Control.MOUSE_FILTER_STOP

func hide_sign() -> void:
	hide()
	current_sign_data = null
	mouse_filter = Control.MOUSE_FILTER_IGNORE
