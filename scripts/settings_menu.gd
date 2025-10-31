extends Control

@onready var master_volume_slider: HSlider = $VBoxContainer/MasterVolumeContainer/HSlider
@onready var master_volume_label: Label = $VBoxContainer/MasterVolumeContainer/Label
@onready var music_volume_slider: HSlider = $VBoxContainer/MusicVolumeContainer/HSlider
@onready var music_volume_label: Label = $VBoxContainer/MusicVolumeContainer/Label
@onready var sfx_volume_slider: HSlider = $VBoxContainer/SFXVolumeContainer/HSlider
@onready var sfx_volume_label: Label = $VBoxContainer/SFXVolumeContainer/Label
@onready var graphics_quality_option: OptionButton = $VBoxContainer/GraphicsQualityContainer/OptionButton
@onready var fullscreen_checkbox: CheckBox = $VBoxContainer/FullscreenContainer/CheckBox
@onready var vsync_option: OptionButton = $VBoxContainer/VSyncContainer/OptionButton
@onready var back_button: Button = $VBoxContainer/BackButton

const QUALITY_LOW = 0
const QUALITY_MEDIUM = 1
const QUALITY_HIGH = 2
const QUALITY_ULTRA = 3

var master_bus_index: int
var music_bus_index: int
var sfx_bus_index: int

func _ready() -> void:
	visible = false
	mouse_filter = Control.MOUSE_FILTER_STOP  # Ensure we can receive mouse input
	
	# Get audio bus indices
	master_bus_index = AudioServer.get_bus_index("Master")
	music_bus_index = AudioServer.get_bus_index("Music")
	sfx_bus_index = AudioServer.get_bus_index("SFX")
	
	# Create audio buses if they don't exist
	if master_bus_index == -1:
		master_bus_index = 0
	
	# Create Music and SFX buses if they don't exist
	if music_bus_index == -1:
		AudioServer.add_bus(1)
		music_bus_index = AudioServer.bus_count - 1
		AudioServer.set_bus_name(music_bus_index, "Music")
	
	if sfx_bus_index == -1:
		AudioServer.add_bus(2)
		sfx_bus_index = AudioServer.bus_count - 1
		AudioServer.set_bus_name(sfx_bus_index, "SFX")
	
	# Populate option buttons
	graphics_quality_option.add_item("Low")
	graphics_quality_option.add_item("Medium")
	graphics_quality_option.add_item("High")
	graphics_quality_option.add_item("Ultra")
	
	vsync_option.add_item("Disabled")
	vsync_option.add_item("Enabled")
	vsync_option.add_item("Adaptive")
	
	# Initialize UI from saved settings
	_load_settings()
	
	# Connect signals
	master_volume_slider.value_changed.connect(_on_master_volume_changed)
	music_volume_slider.value_changed.connect(_on_music_volume_changed)
	sfx_volume_slider.value_changed.connect(_on_sfx_volume_changed)
	graphics_quality_option.item_selected.connect(_on_graphics_quality_selected)
	fullscreen_checkbox.toggled.connect(_on_fullscreen_toggled)
	vsync_option.item_selected.connect(_on_vsync_selected)
	back_button.pressed.connect(_on_back_pressed)
	
	_update_volume_labels()

func _input(event: InputEvent) -> void:
	# Close settings menu with ESC
	if visible and event.is_action_pressed("ui_cancel"):
		_on_back_pressed()
		get_viewport().set_input_as_handled()  # Prevent other nodes from handling this event

func _load_settings() -> void:
	# Load volume settings from config file, or use defaults
	var master_volume = ConfigFile.new()
	var err = master_volume.load("user://settings.cfg")
	if err == OK:
		master_volume_slider.value = master_volume.get_value("audio", "master_volume", 1.0)
		music_volume_slider.value = master_volume.get_value("audio", "music_volume", 1.0)
		sfx_volume_slider.value = master_volume.get_value("audio", "sfx_volume", 1.0)
		graphics_quality_option.selected = master_volume.get_value("graphics", "quality", QUALITY_MEDIUM)
		fullscreen_checkbox.button_pressed = master_volume.get_value("graphics", "fullscreen", false)
		vsync_option.selected = master_volume.get_value("graphics", "vsync", 1)
	else:
		# Default values
		master_volume_slider.value = 1.0
		music_volume_slider.value = 1.0
		sfx_volume_slider.value = 1.0
		graphics_quality_option.selected = QUALITY_MEDIUM
		fullscreen_checkbox.button_pressed = false
		vsync_option.selected = 1
	
	# Apply settings
	_apply_volume_settings()
	_apply_graphics_settings()

func _save_settings() -> void:
	var config = ConfigFile.new()
	config.set_value("audio", "master_volume", master_volume_slider.value)
	config.set_value("audio", "music_volume", music_volume_slider.value)
	config.set_value("audio", "sfx_volume", sfx_volume_slider.value)
	config.set_value("graphics", "quality", graphics_quality_option.selected)
	config.set_value("graphics", "fullscreen", fullscreen_checkbox.button_pressed)
	config.set_value("graphics", "vsync", vsync_option.selected)
	config.save("user://settings.cfg")

func _update_volume_labels() -> void:
	master_volume_label.text = "Master Volume: %d%%" % int(master_volume_slider.value * 100)
	music_volume_label.text = "Music Volume: %d%%" % int(music_volume_slider.value * 100)
	sfx_volume_label.text = "SFX Volume: %d%%" % int(sfx_volume_slider.value * 100)

func _on_master_volume_changed(value: float) -> void:
	if master_bus_index >= 0:
		AudioServer.set_bus_volume_db(master_bus_index, linear_to_db(value))
	_update_volume_labels()
	_save_settings()

func _on_music_volume_changed(value: float) -> void:
	if music_bus_index >= 0:
		AudioServer.set_bus_volume_db(music_bus_index, linear_to_db(value))
	_update_volume_labels()
	_save_settings()

func _on_sfx_volume_changed(value: float) -> void:
	if sfx_bus_index >= 0:
		AudioServer.set_bus_volume_db(sfx_bus_index, linear_to_db(value))
	_update_volume_labels()
	_save_settings()

func _on_graphics_quality_selected(index: int) -> void:
	_apply_graphics_quality(index)
	_save_settings()

func _apply_graphics_quality(quality: int) -> void:
	var viewport_rid = get_viewport().get_viewport_rid()
	match quality:
		QUALITY_LOW:
			RenderingServer.viewport_set_msaa_3d(viewport_rid, RenderingServer.VIEWPORT_MSAA_DISABLED)
			RenderingServer.viewport_set_sdf_oversize_and_scale(viewport_rid, RenderingServer.VIEWPORT_SDF_OVERSIZE_100_PERCENT, RenderingServer.VIEWPORT_SDF_SCALE_50_PERCENT)
		QUALITY_MEDIUM:
			RenderingServer.viewport_set_msaa_3d(viewport_rid, RenderingServer.VIEWPORT_MSAA_2X)
			RenderingServer.viewport_set_sdf_oversize_and_scale(viewport_rid, RenderingServer.VIEWPORT_SDF_OVERSIZE_100_PERCENT, RenderingServer.VIEWPORT_SDF_SCALE_50_PERCENT)
		QUALITY_HIGH:
			RenderingServer.viewport_set_msaa_3d(viewport_rid, RenderingServer.VIEWPORT_MSAA_4X)
			RenderingServer.viewport_set_sdf_oversize_and_scale(viewport_rid, RenderingServer.VIEWPORT_SDF_OVERSIZE_100_PERCENT, RenderingServer.VIEWPORT_SDF_SCALE_100_PERCENT)
		QUALITY_ULTRA:
			RenderingServer.viewport_set_msaa_3d(viewport_rid, RenderingServer.VIEWPORT_MSAA_8X)
			RenderingServer.viewport_set_sdf_oversize_and_scale(viewport_rid, RenderingServer.VIEWPORT_SDF_OVERSIZE_120_PERCENT, RenderingServer.VIEWPORT_SDF_SCALE_100_PERCENT)

func _on_fullscreen_toggled(pressed: bool) -> void:
	if pressed:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
	else:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	_save_settings()

func _on_vsync_selected(index: int) -> void:
	match index:
		0:  # Disabled
			DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
		1:  # Enabled
			DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_ENABLED)
		2:  # Adaptive
			DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_ADAPTIVE)
	_save_settings()

func _apply_volume_settings() -> void:
	_on_master_volume_changed(master_volume_slider.value)
	_on_music_volume_changed(music_volume_slider.value)
	_on_sfx_volume_changed(sfx_volume_slider.value)

func _apply_graphics_settings() -> void:
	_apply_graphics_quality(graphics_quality_option.selected)
	_on_fullscreen_toggled(fullscreen_checkbox.button_pressed)
	_on_vsync_selected(vsync_option.selected)

func _on_back_pressed() -> void:
	visible = false
	_save_settings()  # Save settings when closing
	# Restore the pause menu buttons visibility
	var parent = get_parent()
	if parent and parent.has_node("VBoxContainer"):
		parent.get_node("VBoxContainer").visible = true
