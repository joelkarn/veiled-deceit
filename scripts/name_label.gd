extends Node3D

## Displays player name above the health bar

@export var offset_y: float = 2.0  # Height above character
@export var max_distance: float = 50.0  # Maximum distance from camera
@export var font_size: int = 16

var name_label_ui: Label
var player_name: String = ""
var label_ready: bool = false

func _ready() -> void:
	# Wait one frame to ensure parent transform is ready
	await get_tree().process_frame

	var parent = get_parent()
	if parent:
		# Get name from parent player
		if parent.get("player_name") != null:
			player_name = parent.player_name

		# Get offset_y from parent if available
		if parent.get("health_bar_offset_y") != null:
			offset_y = parent.health_bar_offset_y + 0.3  # Slightly above health bar

	# Position the label above the character in 3D space
	position.y = offset_y

	# Create the 2D UI label
	_create_2d_label()
	label_ready = true

func _process(_delta: float) -> void:
	if not label_ready or not name_label_ui or not is_instance_valid(name_label_ui):
		return

	# Update player name if changed
	var parent = get_parent()
	if parent and parent.get("player_name") != null:
		if parent.player_name != player_name:
			player_name = parent.player_name
			name_label_ui.text = player_name

	# Update 2D position based on 3D world position
	_update_2d_position()

func _create_2d_label() -> void:
	var ui_layer = _get_ui_layer()
	if not ui_layer:
		push_error("Could not find UI layer for name label")
		return

	# Create the label
	name_label_ui = Label.new()
	name_label_ui.name = "NameLabel_" + str(get_instance_id())
	name_label_ui.text = player_name
	name_label_ui.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_label_ui.vertical_alignment = VERTICAL_ALIGNMENT_CENTER

	# Style the label
	name_label_ui.add_theme_font_size_override("font_size", font_size)
	name_label_ui.add_theme_color_override("font_color", Color.WHITE)
	name_label_ui.add_theme_color_override("font_outline_color", Color.BLACK)
	name_label_ui.add_theme_constant_override("outline_size", 2)

	# Add to UI layer
	ui_layer.add_child(name_label_ui)

func _get_ui_layer() -> Control:
	var main_scene = get_tree().current_scene
	if not main_scene:
		return null

	# Look for HealthBarsLayer CanvasLayer
	var health_bars_layer = main_scene.find_child("HealthBarsLayer", true, false)
	if health_bars_layer and health_bars_layer is CanvasLayer:
		for child in health_bars_layer.get_children():
			if child is Control and child.name == "UILayer":
				return child
		var ui_control_health_bars_layer = Control.new()
		ui_control_health_bars_layer.name = "UILayer"
		ui_control_health_bars_layer.set_anchors_preset(Control.PRESET_FULL_RECT)
		health_bars_layer.add_child(ui_control_health_bars_layer)
		return ui_control_health_bars_layer

	# Fallback: look for existing CanvasLayer
	var canvas_layer = main_scene.find_child("UI", false, false)
	if not canvas_layer:
		for child in main_scene.get_children():
			if child is CanvasLayer:
				canvas_layer = child
				break

	if canvas_layer and canvas_layer is CanvasLayer:
		for child in canvas_layer.get_children():
			if child is Control and child.name == "UILayer":
				return child
		var ui_control_canvas_layer = Control.new()
		ui_control_canvas_layer.name = "UILayer"
		ui_control_canvas_layer.set_anchors_preset(Control.PRESET_FULL_RECT)
		canvas_layer.add_child(ui_control_canvas_layer)
		return ui_control_canvas_layer

	# Create new CanvasLayer
	var new_canvas_layer = CanvasLayer.new()
	new_canvas_layer.name = "UI"
	new_canvas_layer.layer = 1
	main_scene.add_child(new_canvas_layer)

	var ui_control_new_canvas_layer = Control.new()
	ui_control_new_canvas_layer.name = "UILayer"
	ui_control_new_canvas_layer.set_anchors_preset(Control.PRESET_FULL_RECT)
	new_canvas_layer.add_child(ui_control_new_canvas_layer)
	return ui_control_new_canvas_layer

func _update_2d_position() -> void:
	if not name_label_ui or not is_instance_valid(name_label_ui):
		return

	var camera = get_viewport().get_camera_3d()
	if not camera:
		camera = get_tree().get_first_node_in_group("camera")

	if not camera:
		name_label_ui.visible = false
		return

	var world_pos = global_position
	var camera_pos = camera.global_position

	# Check if behind camera
	var camera_forward = -camera.global_transform.basis.z
	var to_world_pos = (world_pos - camera_pos).normalized()
	if to_world_pos.dot(camera_forward) < 0:
		name_label_ui.visible = false
		return

	var distance = world_pos.distance_to(camera_pos)
	if distance > max_distance:
		name_label_ui.visible = false
		return

	var screen_pos = camera.unproject_position(world_pos)
	var viewport_size = get_viewport().get_visible_rect().size

	# Get label size for centering
	var label_size = name_label_ui.size
	if label_size.x == 0:
		# Force label to update its size
		name_label_ui.reset_size()
		label_size = name_label_ui.size

	if screen_pos.x < -label_size.x or screen_pos.x > viewport_size.x + label_size.x or screen_pos.y < -label_size.y or screen_pos.y > viewport_size.y + label_size.y:
		name_label_ui.visible = false
		return

	name_label_ui.visible = true

	# Center the label
	screen_pos.x -= label_size.x / 2.0
	screen_pos.y -= label_size.y / 2.0
	name_label_ui.position = screen_pos

func _exit_tree() -> void:
	if name_label_ui and is_instance_valid(name_label_ui):
		name_label_ui.queue_free()
