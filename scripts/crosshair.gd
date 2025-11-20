extends Control

## Crosshair UI - appears when ranged weapons are equipped

@onready var crosshair_lines: Control = $CrosshairLines

func _ready() -> void:
	hide()  # Hidden by default

func show_crosshair() -> void:
	show()

func hide_crosshair() -> void:
	hide()
