extends Node

## Harvest UI Manager - handles showing/hiding harvest progress bars

var harvest_bar_scene = preload("res://scenes/ui/harvest_progress_bar.tscn")
var current_harvest_bar: Control = null
var harvest_layer: CanvasLayer = null

func _ready() -> void:
	pass # Layer setup is now deferred

func setup_harvest_layer() -> void:
	harvest_layer = get_tree().current_scene.get_node_or_null("UILayers/HarvestProgressLayer")
	if not harvest_layer:
		push_error("HarvestUIManager: Could not find HarvestProgressLayer!")

func start_harvest_ui(target: Node3D, duration: float) -> void:
	# Clean up existing bar
	if current_harvest_bar:
		current_harvest_bar.queue_free()
		current_harvest_bar = null

	# Create new progress bar
	if not harvest_layer:
		return

	current_harvest_bar = harvest_bar_scene.instantiate()
	harvest_layer.add_child(current_harvest_bar)
	current_harvest_bar.start_harvest(target, duration)

func update_harvest_progress(progress: float, max_value: float) -> void:
	if current_harvest_bar and current_harvest_bar.has_method("update_progress"):
		current_harvest_bar.update_progress(progress, max_value)

func cancel_harvest_ui() -> void:
	if current_harvest_bar:
		if current_harvest_bar.has_method("cancel_harvest"):
			current_harvest_bar.cancel_harvest()
		current_harvest_bar.queue_free()
		current_harvest_bar = null
