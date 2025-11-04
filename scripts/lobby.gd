extends Control

@onready var host_button: Button = $Panel/VBoxContainer/HostButton
@onready var join_button: Button = $Panel/VBoxContainer/HBoxContainer/JoinButton
@onready var ip_input: LineEdit = $Panel/VBoxContainer/HBoxContainer/IPInput
@onready var status_label: Label = $Panel/VBoxContainer/StatusLabel

var network_manager: Node

func _ready() -> void:
	# Connect button signals
	host_button.pressed.connect(_on_host_button_pressed)
	join_button.pressed.connect(_on_join_button_pressed)
	
	# Show mouse cursor when lobby is visible (like pause menu)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	
	# Find NetworkManager - try multiple paths
	network_manager = get_node_or_null("/root/world/NetworkManager")
	if not network_manager:
		network_manager = get_tree().get_first_node_in_group("network_manager")
	if not network_manager:
		# Try getting from current scene
		var scene = get_tree().current_scene
		if scene:
			network_manager = scene.get_node_or_null("NetworkManager")
	
	if not network_manager:
		status_label.text = "Error: NetworkManager not found!"
		print("ERROR: NetworkManager not found in scene tree!")
		return
	
	# Connect to multiplayer signals
	if not multiplayer.connected_to_server.is_connected(_on_connected_to_server):
		multiplayer.connected_to_server.connect(_on_connected_to_server)
	if not multiplayer.connection_failed.is_connected(_on_connection_failed):
		multiplayer.connection_failed.connect(_on_connection_failed)
	
	status_label.text = "Ready - Choose Host or Join"

func _on_host_button_pressed() -> void:
	if not network_manager:
		status_label.text = "Error: NetworkManager not found!"
		return
	
	status_label.text = "Starting host..."
	host_button.disabled = true
	join_button.disabled = true
	
	network_manager.host_game()

func _on_join_button_pressed() -> void:
	if not network_manager:
		status_label.text = "Error: NetworkManager not found!"
		return
	
	var ip = ip_input.text.strip_edges()
	if ip.is_empty():
		ip = "localhost"  # Default to localhost if empty
	
	status_label.text = "Connecting to " + ip + "..."
	host_button.disabled = true
	join_button.disabled = true
	
	network_manager.join_game(ip)

func _on_host_started() -> void:
	status_label.text = "Host started! Waiting for players..."
	# Hide lobby after host starts
	await get_tree().create_timer(1.0).timeout
	hide_lobby()

func _on_connected_to_server() -> void:
	status_label.text = "Connected to server!"
	# Small delay before hiding lobby
	await get_tree().create_timer(1.0).timeout
	hide_lobby()

func _on_connection_failed() -> void:
	status_label.text = "Connection failed!"
	host_button.disabled = false
	join_button.disabled = false
	# Ensure mouse is still visible on failure
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

func hide_lobby() -> void:
	# Hide the lobby UI when connected
	visible = false
	# Capture mouse again for gameplay (like closing pause menu)
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

