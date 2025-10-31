extends Control

@onready var settings_button: Button = $VBoxContainer/Settings
@onready var exit_button: Button = $VBoxContainer/Exit
@onready var settings_menu: Control = $SettingsMenu

func _ready() -> void:
	visible = false
	mouse_filter = Control.MOUSE_FILTER_STOP  # Ensure we can receive mouse input
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
	visible = true
	settings_menu.visible = false
	# Show the buttons when menu is opened (unless settings is open)
	if not settings_menu.visible:
		$VBoxContainer.visible = true

func _on_menu_closed() -> void:
	visible = false
	settings_menu.visible = false

func _on_settings_pressed() -> void:
	settings_menu.visible = true
	# Hide the buttons when settings menu is open
	$VBoxContainer.visible = false

func _on_exit_pressed() -> void:
	get_tree().quit()
