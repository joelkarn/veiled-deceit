extends InteractableBase

## Interactable sign that displays text when player interacts
## Player must stay near and hold E to keep reading

@export var sign_data: SignData

func _ready() -> void:
	super._ready()
	if sign_data:
		interact_prompt = "Press E to read " + sign_data.sign_title
	else:
		interact_prompt = "Press E to read sign"

## Called when player presses E while nearby
func interact(player: Node) -> void:
	if not sign_data:
		return
	
	# Only process on local player
	if not player.is_local_player:
		return
	
	# Add quest if specified
	if sign_data.quest_id_to_add != "":
		print("[Sign] Attempting to add quest: ", sign_data.quest_id_to_add)
		if QuestManager and QuestManager.has_method("add_quest_by_id"):
			print("[Sign] Found QuestManager, adding quest")
			QuestManager.add_quest_by_id(sign_data.quest_id_to_add)
		else:
			print("[Sign] ERROR: Could not find QuestManager or add_quest_by_id method")
	
	# Show sign UI
	var sign_ui = player.get_tree().current_scene.get_node_or_null("UILayers/SignUILayer/SignUI")
	if sign_ui and sign_ui.has_method("show_sign"):
		sign_ui.show_sign(sign_data)

## Called when player stops interacting (walks away or releases E)
func stop_interact(player: Node) -> void:
	# Only process on local player
	if not player.is_local_player:
		return
	
	# Hide sign UI
	var sign_ui = player.get_tree().current_scene.get_node_or_null("UILayers/SignUILayer/SignUI")
	if sign_ui and sign_ui.has_method("hide_sign"):
		sign_ui.hide_sign()

func can_interact() -> bool:
	return sign_data != null
