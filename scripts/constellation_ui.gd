extends Control

## Displays constellation name at bottom of screen when hovering with astrolabe

@onready var panel: PanelContainer = $Panel
@onready var label: Label = $Panel/Label

func _ready() -> void:
	hide()  # Hidden by default
	_setup_styling()

func _setup_styling() -> void:
	# Style the label for better visibility
	if label:
		label.add_theme_color_override("font_color", Color(1.0, 0.9, 0.5, 1.0))  # Golden color
		label.add_theme_color_override("font_outline_color", Color(0.0, 0.0, 0.0, 1.0))
		label.add_theme_constant_override("outline_size", 4)
		label.add_theme_font_size_override("font_size", 40)

func show_constellation(constellation_name: String) -> void:
	if label:
		label.text = constellation_name
	show()

func hide_constellation() -> void:
	hide()
