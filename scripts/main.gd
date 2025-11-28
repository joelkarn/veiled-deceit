extends Node3D
@onready var loading_screen = $UILayers/LoadingLayer/LoadingUI

func _ready() -> void:
	NetworkManager.handshake_complete.connect(_on_handshake_complete)

func _on_handshake_complete():
	if loading_screen:
		loading_screen.hide()
