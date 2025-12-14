extends InteractableBase
class_name TempleEntrance

## Temple entrance that requires players to enter the correct name (derived from cave symbols/texts)

@export var temple_name: String = "Temple of Mysteries"
@export var locked_message: String = "The temple is sealed. Speak the sacred name to enter."
@export var success_message: String = "The temple recognizes the name! The door opens."
@export var failure_message: String = "The name holds no power here. Try again."
@export var hint_message: String = "The sacred name is formed from two syllables - one from a symbol, one from a text found in the cave."

@onready var name_label_3d: Label3D = $NameLabel3D
@onready var visuals: Node3D = $Visuals

var is_unlocked: bool = false
var temple_correct_name: String = ""
var hover_time: float = 0.0
var current_player: Node = null

func _ready() -> void:
	super._ready()
	interact_prompt = "Press E to speak with the Sentinel"

	# Get the temple name from CaveMysteryManager
	if CaveMysteryManager:
		temple_correct_name = CaveMysteryManager.get_temple_name()
		print("[TempleEntrance] Temple requires name: ", temple_correct_name)

	if name_label_3d:
		name_label_3d.text = temple_name

func _process(delta: float) -> void:
	# Hovering animation for sentinel
	hover_time += delta
	if visuals:
		visuals.position.y = sin(hover_time) * 0.2

	# Make name label face the camera
	if name_label_3d:
		var camera = get_viewport().get_camera_3d()
		if camera:
			name_label_3d.look_at(camera.global_position, Vector3.UP)

func interact(player: Node) -> void:
	super.interact(player)

	if not player:
		return

	# Check if already unlocked
	if is_unlocked:
		_show_message(player, "The temple stands open. You may enter.")
		return

	# Show name input dialog
	if player.is_local_player:
		_show_name_input_dialog(player)

func _show_name_input_dialog(player: Node) -> void:
	"""Show a dialog for the player to enter the temple name"""
	# Get the temple name input UI
	var name_input_ui = get_tree().current_scene.get_node_or_null("UILayers/TempleNameInputLayer/TempleNameInput")

	if name_input_ui:
		# Connect to the signal if not already connected
		if not name_input_ui.name_submitted.is_connected(_on_name_submitted):
			name_input_ui.name_submitted.connect(_on_name_submitted)

		# Store player reference for later
		current_player = player

		# Show the UI
		name_input_ui.show_input(player, locked_message, hint_message)
	else:
		# Fallback: Create a simple input dialog
		_create_simple_input_dialog(player)

func _on_name_submitted(entered_temple_name: String) -> void:
	"""Called when player submits a name via the UI"""
	if current_player:
		_attempt_temple_entry(current_player, entered_temple_name)
		current_player = null

func _create_simple_input_dialog(player: Node) -> void:
	"""Create a simple name input dialog"""
	# Release mouse for UI interaction
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

	# Create a simple UI for name input
	var dialog = AcceptDialog.new()
	dialog.title = "Temple Sentinel"
	dialog.dialog_text = ""  # We'll use custom content instead
	dialog.exclusive = false

	# Create a VBoxContainer for proper layout
	var vbox = VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 10)

	# Add message label
	var message_label = Label.new()
	message_label.text = locked_message + "\n\n" + hint_message
	message_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	message_label.custom_minimum_size = Vector2(400, 0)
	vbox.add_child(message_label)

	# Add instruction label
	var instruction_label = Label.new()
	instruction_label.text = "\nEnter the sacred name:"
	instruction_label.add_theme_color_override("font_color", Color(0.8, 0.8, 0.8))
	vbox.add_child(instruction_label)

	# Create input field
	var input = LineEdit.new()
	input.placeholder_text = "Enter temple name..."
	input.custom_minimum_size = Vector2(400, 0)
	vbox.add_child(input)

	# Add the container to the dialog
	dialog.add_child(vbox)

	# Connect signals
	dialog.confirmed.connect(func():
		var entered_name = input.text.strip_edges()
		_attempt_temple_entry(player, entered_name)
		dialog.queue_free()
		# Re-capture mouse after dialog closes
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	)

	dialog.canceled.connect(func():
		dialog.queue_free()
		# Re-capture mouse after dialog closes
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	)

	# Add to scene and show
	get_tree().current_scene.add_child(dialog)
	dialog.popup_centered()
	input.grab_focus()

func _attempt_temple_entry(player: Node, attempted_name: String) -> void:
	"""Validate the temple name and unlock if correct"""
	if not CaveMysteryManager:
		_show_message(player, "The temple does not respond...")
		return

	if CaveMysteryManager.validate_temple_name(attempted_name):
		# Success!
		is_unlocked = true
		_show_message(player, success_message)

		# Visual feedback - change sentinel to green glow
		if visuals and visuals.has_node("Glow"):
			var glow = visuals.get_node("Glow")
			glow.light_color = Color(0.2, 1.0, 0.2)  # Green

		# Unlock on server
		if multiplayer.is_server():
			rpc("_sync_temple_unlock")
		else:
			rpc_id(1, "_server_unlock_temple")
	else:
		# Failure - show what they tried
		_show_message(player, failure_message + "\n\nYou said: '" + attempted_name + "'")

@rpc("any_peer", "call_remote", "reliable")
func _server_unlock_temple() -> void:
	if not multiplayer.is_server():
		return

	is_unlocked = true
	rpc("_sync_temple_unlock")
@rpc("authority", "call_remote", "reliable")
func _sync_temple_unlock() -> void:
	is_unlocked = true
	# Change sentinel glow to green
	if visuals and visuals.has_node("Glow"):
		var glow = visuals.get_node("Glow")
		glow.light_color = Color(0.2, 1.0, 0.2)
	print("[TempleEntrance] Temple unlocked!")

func _show_message(_player: Node, message: String) -> void:
	"""Show a message to the player"""
	print("[TempleEntrance] Message for player: ", message)

	# Try to find DialogueUI
	var dialogue_ui = get_tree().current_scene.get_node_or_null("UILayers/DialogueUILayer/DialogueUI")
	if dialogue_ui and dialogue_ui.has_method("show_dialogue"):
		dialogue_ui.show_dialogue("Temple Sentinel", message)
	else:
		# Fallback: Create a simple popup
		var popup = AcceptDialog.new()
		popup.title = "Temple Sentinel"
		popup.dialog_text = message
		popup.exclusive = false
		popup.confirmed.connect(func(): popup.queue_free())
		get_tree().current_scene.add_child(popup)
		popup.popup_centered()
