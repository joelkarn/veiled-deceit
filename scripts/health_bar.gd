extends Node3D

enum BarType { ENEMY, ALLY, PLAYER }

@export var bar_type: BarType = BarType.ENEMY
@export var offset_y: float = 1.5  # Default height above character (overridden by parent if available)
@export var bar_width: int = 100  # Max width in pixels (2D screen space) - this is the size at close distance
@export var bar_height: int = 10  # Max height in pixels (2D screen space) - this is the size at close distance
@export var max_distance: float = 50.0  # Maximum distance from camera before health bar is hidden
@export var min_distance: float = 2.0  # Minimum distance (closest) - bars are at max size at this distance

var health_bar_ui: Control
var background_rect: ColorRect
var foreground_rect: ColorRect
var border_top: ColorRect
var border_bottom: ColorRect
var border_left: ColorRect
var border_right: ColorRect

var current_health: float = 100.0
var max_health: float = 100.0
var health_bar_ready: bool = false
var current_scale: float = 1.0  # Current scale of the health bar

static var sort_scheduled_per_parent: Dictionary = {}


func _ready() -> void:
	# Wait one frame to ensure parent transform is ready
	await get_tree().process_frame

	var parent = get_parent()
	if parent:
		# Get offset_y from parent if available (works like health)
		if parent.get("health_bar_offset_y") != null:
			offset_y = parent.health_bar_offset_y

		# Get initial health from parent node (enemy/player)
		if parent.get("max_health") != null and parent.get("health") != null:
			max_health = parent.max_health
			current_health = parent.health

	# Position the health bar above the character in 3D space
	position.y = offset_y

	# Create the 2D UI health bar
	_create_2d_health_bar()
	update_health(current_health, max_health)

func _process(_delta: float) -> void:
	# Only process if health bar is ready
	if not health_bar_ready:
		return

	# Update health from parent node if available
	var parent = get_parent()
	if parent and parent.get("max_health") != null and parent.get("health") != null:
		if parent.health != current_health or parent.max_health != max_health:
			update_health(parent.health, parent.max_health)

	# Update 2D position based on 3D world position
	_update_2d_position()

func _create_2d_health_bar() -> void:
	# Get or create UI layer in the main scene
	var ui_layer = _get_ui_layer()
	if not ui_layer:
		push_error("Could not find UI layer for health bar")
		return

	# Create the health bar Control node
	health_bar_ui = Control.new()
	health_bar_ui.name = "HealthBar_" + str(get_instance_id())
	health_bar_ui.mouse_filter = Control.MOUSE_FILTER_IGNORE
	health_bar_ui.set_anchors_preset(Control.PRESET_TOP_LEFT)
	health_bar_ui.size = Vector2(bar_width, bar_height)
	health_bar_ui.clip_contents = true

	# Background (dark gray)
	background_rect = ColorRect.new()
	background_rect.color = Color(0.2, 0.2, 0.2, 1.0)
	background_rect.set_anchors_preset(Control.PRESET_TOP_LEFT)
	background_rect.position = Vector2(0, 0)
	background_rect.size = Vector2(bar_width, bar_height)
	health_bar_ui.add_child(background_rect)

	# Foreground (health fill)
	foreground_rect = ColorRect.new()
	foreground_rect.set_anchors_preset(Control.PRESET_TOP_LEFT)
	foreground_rect.size = Vector2(bar_width, bar_height)
	health_bar_ui.add_child(foreground_rect)

	# Border (black outline) - store references
	border_top = ColorRect.new()
	border_top.color = Color.BLACK
	border_top.size = Vector2(bar_width, 1)
	border_top.position = Vector2(0, 0)
	health_bar_ui.add_child(border_top)

	border_bottom = ColorRect.new()
	border_bottom.color = Color.BLACK
	border_bottom.size = Vector2(bar_width, 1)
	border_bottom.position = Vector2(0, bar_height - 1)
	health_bar_ui.add_child(border_bottom)

	border_left = ColorRect.new()
	border_left.color = Color.BLACK
	border_left.size = Vector2(1, bar_height)
	border_left.position = Vector2(0, 0)
	health_bar_ui.add_child(border_left)

	border_right = ColorRect.new()
	border_right.color = Color.BLACK
	border_right.size = Vector2(1, bar_height)
	border_right.position = Vector2(bar_width - 1, 0)
	health_bar_ui.add_child(border_right)

	# Add to UI layer
	ui_layer.add_child(health_bar_ui)

	# Set initial color
	_update_bar_color()

	# Mark as ready
	health_bar_ready = true

func _get_ui_layer() -> Control:
	# Find the main scene and look for a UI layer (CanvasLayer or Control node)
	var main_scene = get_tree().current_scene
	if not main_scene:
		return null

	# First, try to find the HealthBarsLayer CanvasLayer (for proper z-ordering)
	var health_bars_layer = main_scene.find_child("HealthBarsLayer", true, false)
	if health_bars_layer and health_bars_layer is CanvasLayer:
		# Return the first child Control, or create one
		for child in health_bars_layer.get_children():
			if child is Control and child.name == "UILayer":
				return child
		# No Control found, create one
		var ui_control = Control.new()
		ui_control.name = "UILayer"
		ui_control.set_anchors_preset(Control.PRESET_FULL_RECT)
		health_bars_layer.add_child(ui_control)
		return ui_control

	# Look for existing CanvasLayer in the scene (fallback)
	var canvas_layer = main_scene.find_child("UI", false, false)
	if not canvas_layer:
		# Try to find any CanvasLayer
		for child in main_scene.get_children():
			if child is CanvasLayer:
				canvas_layer = child
				break

	if canvas_layer and canvas_layer is CanvasLayer:
		# Return the first child Control, or create one
		for child in canvas_layer.get_children():
			if child is Control and child.name == "UILayer":
				return child
		# No Control found, create one
		var ui_control = Control.new()
		ui_control.name = "UILayer"
		ui_control.set_anchors_preset(Control.PRESET_FULL_RECT)
		canvas_layer.add_child(ui_control)
		return ui_control

	# No CanvasLayer found, create one at root with layer 1 for health bars
	var new_canvas_layer = CanvasLayer.new()
	new_canvas_layer.name = "UI"
	new_canvas_layer.layer = 1
	main_scene.add_child(new_canvas_layer)

	var ui_control = Control.new()
	ui_control.name = "UILayer"
	ui_control.set_anchors_preset(Control.PRESET_FULL_RECT)
	new_canvas_layer.add_child(ui_control)
	return ui_control

func _update_2d_position() -> void:
	if not health_bar_ui or not is_instance_valid(health_bar_ui):
		return

	var camera = get_viewport().get_camera_3d()
	if not camera:
		camera = get_tree().get_first_node_in_group("camera")
		if not camera:
			var player = get_tree().get_first_node_in_group("player")
			if not player:
				var main_scene = get_tree().current_scene
				if main_scene:
					var player_node = main_scene.find_child("player", true, false)
					if player_node and player_node.has_node("camera_mount/Camera3D"):
						camera = player_node.get_node("camera_mount/Camera3D")

	if not camera:
		health_bar_ui.visible = false
		return

	var world_pos = global_position
	var camera_pos = camera.global_position

	# Check if behind camera
	var camera_forward = -camera.global_transform.basis.z
	var to_world_pos = (world_pos - camera_pos).normalized()
	if to_world_pos.dot(camera_forward) < 0:
		health_bar_ui.visible = false
		return

	var distance = world_pos.distance_to(camera_pos)
	if distance > max_distance:
		health_bar_ui.visible = false
		return

	# Calculate scale based on distance
	var scale: float = 1.0
	if bar_type != BarType.PLAYER:
		if distance <= min_distance:
			scale = 1.0
		else:
			var distance_range = max_distance - min_distance
			if distance_range > 0:
				var normalized_distance = (distance - min_distance) / distance_range
				scale = lerp(1.0, 0.2, normalized_distance)
				scale = clamp(scale, 0.2, 1.0)
			else:
				scale = 1.0

	if scale != current_scale:
		current_scale = scale
		_update_bar_size(scale)

	var screen_pos = camera.unproject_position(world_pos)
	var scaled_width = bar_width * scale
	var scaled_height = bar_height * scale

	var viewport_size = get_viewport().get_visible_rect().size
	if screen_pos.x < -scaled_width or screen_pos.x > viewport_size.x + scaled_width or screen_pos.y < -scaled_height or screen_pos.y > viewport_size.y + scaled_height:
		health_bar_ui.visible = false
		return

	health_bar_ui.visible = true
	health_bar_ui.set_meta("distance", distance)

	# Defer sorting once per frame to prevent race conditions
	var parent_node = health_bar_ui.get_parent()
	if parent_node:
		var parent_id = parent_node.get_instance_id()
		var current_frame = get_tree().get_frame()
		if sort_scheduled_per_parent.get(parent_id, -1) != current_frame:
			sort_scheduled_per_parent[parent_id] = current_frame
			call_deferred("_sort_health_bars_deferred", parent_node)

	screen_pos.x -= scaled_width / 2.0
	screen_pos.y -= scaled_height / 2.0
	health_bar_ui.position = screen_pos

func _sort_health_bars_deferred(parent_node: Control) -> void:
	_sort_health_bars_by_distance(parent_node)

func _sort_health_bars_by_distance(parent_node: Control) -> void:
	var health_bars_data = []
	for child in parent_node.get_children():
		if child is Control and child.name.begins_with("HealthBar_") and child.visible and child.has_meta("distance"):
			health_bars_data.append({"node": child, "distance": child.get_meta("distance")})

	if health_bars_data.size() < 2:
		return

	health_bars_data.sort_custom(func(a, b): return a.distance < b.distance)

	# Place furthest first, closest last
	for i in range(health_bars_data.size()):
		var node = health_bars_data[i].node
		if node.get_index() != i:
			parent_node.move_child(node, i)

	# Reverse order so closest is on top (drawn last)
	var health_bar_nodes = []
	for child in parent_node.get_children():
		if child is Control and child.name.begins_with("HealthBar_") and child.visible:
			health_bar_nodes.append(child)

	for i in range(health_bar_nodes.size()):
		parent_node.move_child(health_bar_nodes[i], health_bar_nodes.size() - 1 - i)

func _update_bar_size(scale: float) -> void:
	if not health_bar_ui:
		return

	var scaled_width = bar_width * scale
	var scaled_height = bar_height * scale

	# Update main UI control size
	health_bar_ui.size = Vector2(scaled_width, scaled_height)

	# Update background
	if background_rect:
		background_rect.size = Vector2(scaled_width, scaled_height)

	# Update foreground (maintain health percentage, so only scale size)
	if foreground_rect:
		var health_percentage = current_health / max_health if max_health > 0 else 0.0
		foreground_rect.size = Vector2(scaled_width * health_percentage, scaled_height)

	# Update borders - scale border thickness proportionally, but ensure minimum of 1 pixel
	# Original borders were 1 pixel, so we scale that but keep it visible
	var border_thickness_h = max(1, ceil(scale))
	var border_thickness_v = max(1, ceil(scale))

	if border_top:
		border_top.size = Vector2(scaled_width, border_thickness_v)
		border_top.position = Vector2(0, 0)

	if border_bottom:
		border_bottom.size = Vector2(scaled_width, border_thickness_v)
		border_bottom.position = Vector2(0, scaled_height - border_bottom.size.y)

	if border_left:
		border_left.size = Vector2(border_thickness_h, scaled_height)
		border_left.position = Vector2(0, 0)

	if border_right:
		border_right.size = Vector2(border_thickness_h, scaled_height)
		border_right.position = Vector2(scaled_width - border_right.size.x, 0)

func _update_bar_color() -> void:
	if not foreground_rect:
		return

	# Get color based on bar type
	var bar_color: Color
	match bar_type:
		BarType.ENEMY:
			bar_color = Color.RED
		BarType.ALLY:
			bar_color = Color.GREEN
		BarType.PLAYER:
			bar_color = Color(0.0, 0.5, 1.0)  # Blue

	foreground_rect.color = bar_color

func update_health(current: float, maximum: float) -> void:
	current_health = clamp(current, 0, maximum)
	max_health = maximum
	_update_bar_display()

func _update_bar_display() -> void:
	if not foreground_rect:
		return

	# Calculate health percentage
	var health_percentage = current_health / max_health if max_health > 0 else 0.0

	# Update foreground width - account for current scale
	var scaled_width = bar_width * current_scale
	var fill_width = scaled_width * health_percentage
	foreground_rect.size.x = fill_width
	foreground_rect.size.y = bar_height * current_scale

func _exit_tree() -> void:
	# Clean up UI element when this node is removed
	if health_bar_ui and is_instance_valid(health_bar_ui):
		health_bar_ui.queue_free()
