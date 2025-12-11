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
	
	# Only process on local player for UI and quest request
	if not player.is_local_player:
		return
	
	# Request quest addition from server (only once per interaction)
	if sign_data.quest_id_to_add != "" and not has_requested_quest:
		var player_name = player.get("player_name") if player.has_method("get") else ""
		
		# Check if player is the correct class for this quest
		var is_witch_quest = sign_data.quest_id_to_add == "find_obelisk"
		var is_hunter_quest = sign_data.quest_id_to_add == "kill_spiders"
		
		if (is_witch_quest and player_name == "Witch") or (is_hunter_quest and player_name == "Hunter"):
			print("[Sign] ", player_name, " player reading sign, requesting quest: ", sign_data.quest_id_to_add)
			has_requested_quest = true  # Prevent multiple requests
			var player_id = player.get("player_id")
			
			if multiplayer.is_server():
				# Host can add directly
				_add_quest_on_server(sign_data.quest_id_to_add, player_id)
				# Give poison vial to hunter when accepting spider quest
				if is_hunter_quest:
					_give_poison_vial_to_player(player_id)
			else:
				# Client sends request through NetworkManager
				var network_manager = get_node_or_null("/root/NetworkManager")
				if network_manager:
					network_manager.rpc_id(1, "request_add_quest", sign_data.quest_id_to_add, player_id)
					# Request poison vial for hunter quest
					if is_hunter_quest:
						network_manager.rpc_id(1, "request_give_item", "poison_vial", player_id)
				else:
					print("[Sign] ERROR: Could not find NetworkManager")
		else:
			print("[Sign] Non-matching player class reading sign, quest not added")
	
	# Show sign UI
	var sign_ui = player.get_tree().current_scene.get_node_or_null("UILayers/SignUILayer/SignUI")
	if sign_ui and sign_ui.has_method("show_sign"):
		sign_ui.show_sign(sign_data)

var has_requested_quest: bool = false

## Add quest on server for specific player
func _add_quest_on_server(quest_id: String, player_id: int) -> void:
	if QuestManager and QuestManager.has_method("add_quest_by_id"):
		print("[Sign] Server adding quest: ", quest_id, " for player ", player_id)
		QuestManager.add_quest_by_id(quest_id, player_id)
	else:
		print("[Sign] ERROR: Could not find QuestManager or add_quest_by_id method")

## Give poison vial to hunter on server
func _give_poison_vial_to_player(player_id: int) -> void:
	# Find the player and add poison vial to their inventory
	var players = get_tree().get_nodes_in_group("players")
	for player in players:
		if player and is_instance_valid(player) and player.get("player_id") == player_id:
			if InventoryManager and InventoryManager.has_method("add_item_to_player"):
				var poison_vial = load("res://resources/items/poison_vial.tres")
				if poison_vial:
					InventoryManager.add_item_to_player(poison_vial, 1, player_id)
					print("[Sign] Gave poison vial to hunter player: ", player_id)
				else:
					print("[Sign] ERROR: Could not load poison_vial.tres")
			break

## Called when player stops interacting (walks away or releases E)
func stop_interact(player: Node) -> void:
	# Only process on local player
	if not player.is_local_player:
		return
	
	# Reset quest request flag so it can be requested again
	has_requested_quest = false
	
	# Hide sign UI
	var sign_ui = player.get_tree().current_scene.get_node_or_null("UILayers/SignUILayer/SignUI")
	if sign_ui and sign_ui.has_method("hide_sign"):
		sign_ui.hide_sign()

func can_interact() -> bool:
	return sign_data != null
