extends AcceptDialog
class_name TempleNameInput

## UI for entering the temple name at the sentinel

signal name_submitted(temple_name: String)

@onready var message_label: Label = $VBoxContainer/MessageLabel
@onready var hint_label: Label = $VBoxContainer/HintLabel
@onready var name_input: LineEdit = $VBoxContainer/NameInput
@onready var submit_button: Button = $VBoxContainer/SubmitButton

var player_node: Node = null

func _ready() -> void:
	# Make sure dialog is hidden initially
	hide()

	# Connect the LineEdit's text_submitted signal (when Enter is pressed)
	if name_input:
		name_input.text_submitted.connect(_on_text_submitted)

func _on_text_submitted(_text: String) -> void:
	"""Called when Enter is pressed in the input field"""
	# Trigger the same action as clicking OK
	_on_confirmed()

func _on_submit_button_pressed() -> void:
	"""Called when the Submit button is clicked"""
	_on_confirmed()

func show_input(player: Node, locked_msg: String, hint_msg: String) -> void:
	"""Show the dialog with custom messages"""
	player_node = player

	# Set custom messages
	if message_label:
		message_label.text = locked_msg
	if hint_label:
		hint_label.text = hint_msg

	# Clear previous input
	if name_input:
		name_input.text = ""

	# Disable player input
	if player_node and "menu_active" in player_node:
		player_node.menu_active = true

	# Release mouse for UI interaction
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

	# Show dialog and focus input
	popup_centered()
	if name_input:
		name_input.grab_focus()

func _on_confirmed() -> void:
	"""Called when OK button is pressed"""
	if name_input:
		var entered_name = name_input.text.strip_edges()
		name_submitted.emit(entered_name)

	_close_dialog()

func _on_canceled() -> void:
	"""Called when Cancel/X button is pressed"""
	_close_dialog()

func _close_dialog() -> void:
	"""Clean up and close the dialog"""
	# Re-enable player input
	if player_node and "menu_active" in player_node:
		player_node.menu_active = false

	player_node = null
	hide()

	# Re-capture mouse
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
