extends Control

## Dialogue UI - shows NPC dialogue text

@onready var panel: Panel = $Panel
@onready var npc_name_label: Label = $Panel/MarginContainer/VBoxContainer/NPCNameLabel
@onready var dialogue_label: Label = $Panel/MarginContainer/VBoxContainer/DialogueLabel

func _ready() -> void:
	hide_dialogue()

func show_dialogue(npc_name: String, text: String) -> void:
	npc_name_label.text = npc_name
	dialogue_label.text = text
	visible = true

func hide_dialogue() -> void:
	visible = false
