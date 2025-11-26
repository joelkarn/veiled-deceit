extends Control

## Harvest progress bar - shows above toolbar during harvesting (similar to health bar)

var background_rect: ColorRect
var foreground_rect: ColorRect
var border_top: ColorRect
var border_bottom: ColorRect
var border_left: ColorRect
var border_right: ColorRect

var bar_width: int = 300
var bar_height: int = 20
var current_progress: float = 0.0
var max_progress: float = 1.0

func _ready() -> void:
	hide()
	_create_harvest_bar()

func _create_harvest_bar() -> void:
	# Set control size
	custom_minimum_size = Vector2(bar_width, bar_height)
	size = Vector2(bar_width, bar_height)

	# Background (dark gray)
	background_rect = ColorRect.new()
	background_rect.color = Color(0.2, 0.2, 0.2, 1.0)
	background_rect.set_anchors_preset(Control.PRESET_TOP_LEFT)
	background_rect.position = Vector2(0, 0)
	background_rect.size = Vector2(bar_width, bar_height)
	add_child(background_rect)

	# Foreground (harvest fill - yellow/orange color)
	foreground_rect = ColorRect.new()
	foreground_rect.color = Color(0.9, 0.7, 0.2, 1.0)  # Yellow-orange
	foreground_rect.set_anchors_preset(Control.PRESET_TOP_LEFT)
	foreground_rect.position = Vector2(0, 0)
	foreground_rect.size = Vector2(0, bar_height)
	add_child(foreground_rect)

	# Black border
	border_top = ColorRect.new()
	border_top.color = Color.BLACK
	border_top.size = Vector2(bar_width, 2)
	border_top.position = Vector2(0, 0)
	add_child(border_top)

	border_bottom = ColorRect.new()
	border_bottom.color = Color.BLACK
	border_bottom.size = Vector2(bar_width, 2)
	border_bottom.position = Vector2(0, bar_height - 2)
	add_child(border_bottom)

	border_left = ColorRect.new()
	border_left.color = Color.BLACK
	border_left.size = Vector2(2, bar_height)
	border_left.position = Vector2(0, 0)
	add_child(border_left)

	border_right = ColorRect.new()
	border_right.color = Color.BLACK
	border_right.size = Vector2(2, bar_height)
	border_right.position = Vector2(bar_width - 2, 0)
	add_child(border_right)

func start_harvest(_target: Node3D, duration: float) -> void:
	current_progress = 0.0
	max_progress = duration
	_update_bar_fill()
	show()

func update_progress(progress: float, duration: float) -> void:
	current_progress = progress
	max_progress = duration
	_update_bar_fill()

func _update_bar_fill() -> void:
	if not foreground_rect:
		return

	var fill_percentage = current_progress / max_progress if max_progress > 0 else 0.0
	fill_percentage = clamp(fill_percentage, 0.0, 1.0)

	var fill_width = bar_width * fill_percentage
	foreground_rect.size = Vector2(fill_width, bar_height)

func cancel_harvest() -> void:
	hide()
