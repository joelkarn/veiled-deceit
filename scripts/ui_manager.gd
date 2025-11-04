extends Node

signal menu_opened
signal menu_closed

var is_menu_open := false

func _ready() -> void:
	# Check if lobby is visible - if so, don't capture mouse yet
	var lobby = get_node_or_null("../UILayers/LobbyLayer/Lobby")
	if lobby and lobby.visible:
		# Lobby will handle mouse visibility
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	else:
		# Start with mouse captured (when lobby is hidden/connected)
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

func _input(event: InputEvent) -> void:
	# Don't process input if multiplayer is disconnected (prevents crashes during shutdown)
	if multiplayer.multiplayer_peer == null:
		return
	
	# Don't process input if network manager is shutting down
	var network_manager = get_tree().current_scene.get_node_or_null("NetworkManager")
	if network_manager and network_manager.is_shutting_down:
		return
	
	if event.is_action_pressed("ui_cancel"):  # ESC key
		# Check if settings menu is open first - try new path first, then fallback
		var pause_menu = get_node_or_null("../UILayers/MenuLayer/PauseMenu")
		if not pause_menu:
			pause_menu = get_node_or_null("../PauseMenu")
		if pause_menu:
			var settings_menu = pause_menu.get_node_or_null("SettingsMenu")
			if settings_menu and settings_menu.visible:
				# Let settings menu handle ESC (close settings menu)
				return
		# Toggle pause menu
		toggle_menu()

func toggle_menu() -> void:
	is_menu_open = !is_menu_open
	
	if is_menu_open:
		open_menu()
	else:
		close_menu()

func open_menu() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	# Don't pause the game (for future online multiplayer)
	# Instead, we disable player input in the player script
	menu_opened.emit()

func close_menu() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	menu_closed.emit()

func is_menu_active() -> bool:
	return is_menu_open

