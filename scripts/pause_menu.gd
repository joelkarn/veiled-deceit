extends Control

@onready var settings_button: Button = $VBoxContainer/Settings
@onready var exit_button: Button = $VBoxContainer/Exit
@onready var settings_menu: Control = $SettingsMenu

func _ready() -> void:
	visible = false
	mouse_filter = Control.MOUSE_FILTER_STOP
	settings_button.pressed.connect(_on_settings_pressed)
	exit_button.pressed.connect(_on_exit_pressed)
	
	# Connect to UI manager signals - try different paths
	var ui_manager = get_node_or_null("../../UIManager")  # Up to UILayers, then to root
	if ui_manager == null:
		ui_manager = get_node_or_null("../UIManager")
	if ui_manager == null:
		ui_manager = get_node_or_null("/root/world/UIManager")
	if ui_manager:
		ui_manager.menu_opened.connect(_on_menu_opened)
		ui_manager.menu_closed.connect(_on_menu_closed)

func _on_menu_opened() -> void:
	# Check if we're shutting down to prevent crashes
	var network_manager = get_tree().current_scene.get_node_or_null("NetworkManager")
	if network_manager and network_manager.is_shutting_down:
		return
	
	visible = true
	settings_menu.visible = false
	if not settings_menu.visible:
		$VBoxContainer.visible = true

func _on_menu_closed() -> void:
	# Check if we're shutting down to prevent crashes
	var network_manager = get_tree().current_scene.get_node_or_null("NetworkManager")
	if network_manager and network_manager.is_shutting_down:
		return
	
	visible = false
	settings_menu.visible = false

func _on_settings_pressed() -> void:
	# Check if we're shutting down to prevent crashes
	var network_manager = get_tree().current_scene.get_node_or_null("NetworkManager")
	if network_manager and network_manager.is_shutting_down:
		return
	
	settings_menu.visible = true
	$VBoxContainer.visible = false

func _on_exit_pressed() -> void:
	# Check if we're shutting down to prevent crashes
	var network_manager = get_tree().current_scene.get_node_or_null("NetworkManager")
	if network_manager and network_manager.is_shutting_down:
		return
	
	# If we're the host, properly shut down the server first
	if network_manager and multiplayer.is_server():
		network_manager.shutdown_host()
	else:
		# Client: Just quit (server disconnect will handle cleanup)
		get_tree().quit()
