extends InteractableBase
class_name AngelNPC

## Angel NPC that can give quests to players

@export var npc_name: String = "Angel"
@export var initial_quest: String = "talk_to_angel"  # Quest ID that gets completed when first talking
@export var initial_dialogue: String = "Greetings, traveler. You have found me. May divine light guide your path."
@export var follow_up_dialogue: String = "You have proven yourself worthy. I have a task suited to your path."
@export var completed_dialogue: String = "May you continue to walk in the light, brave one."

# Class-specific follow-up quests
var class_quests: Dictionary = {
	"Witch": "find_obelisk",
	"Hunter": "kill_spiders",
	"Knight": "kill_enemies"
}

@onready var question_marker: Node3D = $QuestionMarker
@onready var name_label_3d: Label3D = $NameLabel3D
@onready var visuals: Node3D = $Visuals

var players_who_completed_initial: Dictionary = {}  # player_id -> bool
var players_who_completed_followup: Dictionary = {}  # player_id -> bool

# Hovering animation variables
var hover_time: float = 0.0
var hover_speed: float = 1.0  # Speed of hovering
var hover_height: float = 0.3  # How far up and down to hover

func _ready() -> void:
	super._ready()
	interact_prompt = "Press E to talk to " + npc_name

	# Connect to quest signals to update markers
	if QuestManager:
		QuestManager.quest_completed.connect(_on_quest_completed)
		QuestManager.quest_progress_updated.connect(_on_quest_progress_updated)
		QuestManager.quests_changed.connect(_on_quests_changed)

	# Initially show question mark
	if question_marker:
		question_marker.visible = true

func _process(_delta: float) -> void:
	# Hovering animation
	hover_time += _delta * hover_speed
	if visuals:
		visuals.position.y = sin(hover_time) * hover_height

	# Make name label and question mark face the camera
	if name_label_3d:
		var camera = get_viewport().get_camera_3d()
		if camera:
			name_label_3d.look_at(camera.global_position, Vector3.UP)

	if question_marker:
		var camera = get_viewport().get_camera_3d()
		if camera:
			question_marker.look_at(camera.global_position, Vector3.UP)

func _on_quest_completed(quest_id: String, player_id: int) -> void:
	# Update marker when LOCAL player's angel quest is completed
	var local_player_id = multiplayer.get_unique_id()
	print("[MARKER] _on_quest_completed: quest=", quest_id, " player=", player_id, " local=", local_player_id)
	if player_id == local_player_id and (quest_id == initial_quest or quest_id in class_quests.values()):
		print("[MARKER] Quest completed for local player, updating marker")
		_check_marker_visibility()

func _on_quest_progress_updated(quest_id: String, player_id: int) -> void:
	# Update marker when LOCAL player's angel quest progress changes
	var local_player_id = multiplayer.get_unique_id()
	print("[MARKER] _on_quest_progress_updated: quest=", quest_id, " player=", player_id, " local=", local_player_id)
	if player_id == local_player_id and (quest_id == initial_quest or quest_id in class_quests.values()):
		print("[MARKER] Quest progress for local player, updating marker")
		_check_marker_visibility()

func _on_quests_changed(player_id: int) -> void:
	# Update marker when LOCAL player's quests change (added/removed)
	var local_player_id = multiplayer.get_unique_id()
	print("[MARKER] _on_quests_changed: player=", player_id, " local=", local_player_id)
	if player_id == local_player_id:
		print("[MARKER] Quests changed for local player, updating marker")
		_check_marker_visibility()

func interact(player: Node) -> void:
	super.interact(player)

	if not player:
		return

	# Get player ID and class
	var player_id = player.get("player_id")
	var player_class = player.get("player_name")  # "Witch", "Hunter", or "Knight"

	# Server: Process interaction and send data to client
	if multiplayer.is_server():
		_process_interaction(player_id, player_class, player)
	# This should never be called on a client directly, but just in case
	elif player.is_local_player:
		# Local player on client - this shouldn't happen as player.gd sends RPC
		print("Warning: Angel interact called on client for local player - this shouldn't happen")
		rpc_id(1, "_server_request_interaction", player_id, player_class)

func _process_interaction(player_id: int, player_class: String, player: Node = null) -> void:
	# Get class-specific follow-up quest
	var follow_up_quest = class_quests.get(player_class, "kill_enemies")  # Default to kill_enemies

	# Determine which quest to show
	var initial_quest_obj = QuestManager.get_quest(initial_quest, player_id)
	var follow_up_quest_obj = QuestManager.get_quest(follow_up_quest, player_id)

	var dialogue_to_show = initial_dialogue
	var quest_to_show = initial_quest_obj

	# Check if initial quest has been turned in (player is in completed list but quest no longer exists)
	var initial_turned_in = players_who_completed_initial.get(player_id, false)

	# Check quest status
	if initial_quest_obj and initial_quest_obj.is_completed and not initial_turned_in:
		# Initial quest is ready to turn in
		dialogue_to_show = "You have completed your task! Return to me for your reward."
		quest_to_show = initial_quest_obj
	elif initial_turned_in or (initial_quest_obj == null and initial_turned_in):
		# Initial quest already turned in, check follow-up
		var followup_turned_in = players_who_completed_followup.get(player_id, false)

		if follow_up_quest_obj == null and not followup_turned_in:
			# No follow-up quest yet - offer it (only if not already completed)
			var next_quest_info = get_next_quest_info(player_id, player_class)
			if next_quest_info["has_quest"]:
				dialogue_to_show = follow_up_dialogue
				# Create a temporary quest data for display
				var quest_data = next_quest_info["quest_data"]
				quest_to_show = quest_data
			else:
				dialogue_to_show = completed_dialogue
				quest_to_show = null
		elif follow_up_quest_obj and follow_up_quest_obj.is_completed and not followup_turned_in:
			# Follow-up quest ready to turn in (only if not already turned in)
			dialogue_to_show = "Excellent work! You have proven yourself worthy."
			quest_to_show = follow_up_quest_obj
		elif follow_up_quest_obj and not follow_up_quest_obj.is_completed:
			# Working on follow-up quest
			dialogue_to_show = follow_up_dialogue
			quest_to_show = follow_up_quest_obj
		else:
			# All quests completed
			dialogue_to_show = completed_dialogue
			quest_to_show = null
	elif initial_quest_obj and not initial_quest_obj.is_completed:
		# Working on initial quest
		if initial_quest_obj.current_progress < initial_quest_obj.goal:
			# Mark as talked to (progress the quest to 100%, then auto-completes)
			initial_quest_obj.add_progress(1)
			QuestManager.quest_progress_updated.emit(initial_quest, player_id)
		quest_to_show = initial_quest_obj
	else:
		# No initial quest exists and not turned in - this shouldn't happen but handle it
		dialogue_to_show = initial_dialogue
		quest_to_show = null

	# Don't call _check_marker_visibility here - it will be updated via quest signals

	# If on server, send UI data to client (if not host)
	if multiplayer.is_server():
		# Check if this is a remote client (not the host)
		if player_id != 1:
			# Serialize quest data for network transmission
			var quest_dict = {}  # Use empty dict instead of null
			if quest_to_show:
				# Check if this is a new quest offer (not yet in QuestManager)
				var is_new_offer = (QuestManager.get_quest(quest_to_show.quest_id, player_id) == null)

				quest_dict = {
					"quest_id": quest_to_show.quest_id,
					"quest_name": quest_to_show.quest_name,
					"description": quest_to_show.description,
					"is_completed": quest_to_show.is_completed,
					"current_progress": quest_to_show.current_progress,
					"goal": quest_to_show.goal,
					"is_new_offer": is_new_offer
				}

			# Send to the client who interacted (quest_dict will be empty {} if no quest)
			rpc_id(player_id, "_client_show_ui", dialogue_to_show, quest_dict)
			# Tell the client to update their marker after interaction
			rpc_id(player_id, "_client_update_marker")
		else:
			# Host is interacting - show UI directly only if this player is the host
			if player and player.is_local_player:
				_show_angel_ui(dialogue_to_show, quest_to_show, player)
				# Update marker for host after interaction
				_check_marker_visibility()

## Client RPC: Show Angel UI
@rpc("authority", "call_remote", "reliable")
func _client_show_ui(dialogue: String, quest_dict: Dictionary) -> void:
	# Find local player
	var local_player = null
	for p in get_tree().get_nodes_in_group("players"):
		if p.is_local_player:
			local_player = p
			break

	if not local_player:
		return

	# Reconstruct quest data or use null
	var quest_to_show = null
	var is_new_offer = false
	if quest_dict:
		# Create a temporary QuestData object for UI display
		quest_to_show = QuestData.new()
		quest_to_show.quest_id = quest_dict.get("quest_id", "")
		quest_to_show.quest_name = quest_dict.get("quest_name", "")
		quest_to_show.description = quest_dict.get("description", "")
		quest_to_show.is_completed = quest_dict.get("is_completed", false)
		quest_to_show.current_progress = quest_dict.get("current_progress", 0)
		quest_to_show.goal = quest_dict.get("goal", 1)
		is_new_offer = quest_dict.get("is_new_offer", false)

	# Show Angel UI
	var angel_ui = local_player.get_tree().current_scene.get_node_or_null("UILayers/AngelUILayer/AngelUI")
	if angel_ui and angel_ui.has_method("show_angel"):
		angel_ui.show_angel(self, npc_name, dialogue, quest_to_show, is_new_offer)

## Client RPC: Update marker after interaction
@rpc("authority", "call_remote", "reliable")
func _client_update_marker() -> void:
	print("[MARKER] _client_update_marker called")
	_check_marker_visibility()

## Server RPC: Handle interaction request from client
@rpc("any_peer", "call_remote", "reliable")
func _server_request_interaction(player_id: int, player_class: String) -> void:
	if not multiplayer.is_server():
		return

	# Validate sender
	var sender_id = multiplayer.get_remote_sender_id()
	if sender_id != player_id:
		return

	_process_interaction(player_id, player_class, null)

func _show_angel_ui(dialogue: String, quest: QuestData, player: Node) -> void:
	# Show Angel UI
	var angel_ui = player.get_tree().current_scene.get_node_or_null("UILayers/AngelUILayer/AngelUI")
	if angel_ui and angel_ui.has_method("show_angel"):
		# Check if this is an unadded quest (offered but not accepted)
		var player_id = player.get("player_id")
		var is_new_quest_offer = false
		if quest and not QuestManager.get_quest(quest.quest_id, player_id):
			is_new_quest_offer = true
		angel_ui.show_angel(self, npc_name, dialogue, quest, is_new_quest_offer)

## Get the next quest info for a player without adding it
func get_next_quest_info(player_id: int, player_class: String) -> Dictionary:
	var result = {"has_quest": false, "quest_id": "", "quest_data": null}

	# Check if initial quest is turned in AND follow-up not already completed
	if players_who_completed_initial.get(player_id, false) and not players_who_completed_followup.get(player_id, false):
		# Check if they have the follow-up quest already
		var follow_up_quest = class_quests.get(player_class, "kill_enemies")
		var follow_up_quest_obj = QuestManager.get_quest(follow_up_quest, player_id)

		if follow_up_quest_obj == null:
			# They don't have it yet, load the quest data for preview
			var quest_path = "res://resources/quests/" + follow_up_quest + ".tres"
			var quest_data = load(quest_path)
			if quest_data:
				result["has_quest"] = true
				result["quest_id"] = follow_up_quest
				result["quest_data"] = quest_data

	return result

## Called when a quest is turned in at the Angel
func on_quest_turned_in(player_id: int, quest_id: String, player_class: String = "") -> void:
	# If client, send request to server
	if not multiplayer.is_server():
		rpc_id(1, "_server_turn_in_quest", player_id, quest_id, player_class)
		return

	# Server: Process turn-in
	# Check which quest was turned in
	if quest_id == initial_quest:
		# Initial quest turned in - mark as complete, but don't give next quest yet
		if not players_who_completed_initial.get(player_id, false):
			players_who_completed_initial[player_id] = true
			# TODO: Give rewards (items, experience, etc.)
			print("Angel: Player ", player_id, " turned in quest: ", quest_id)
			# Sync to all clients
			rpc("_sync_turn_in_state", player_id, quest_id)
	else:
		# Follow-up quest turned in (any class-specific quest)
		print("Angel: Player ", player_id, " completed all angel quests!")
		players_who_completed_followup[player_id] = true
		# TODO: Give final rewards
		# Sync to all clients
		rpc("_sync_turn_in_state", player_id, quest_id)

	_check_marker_visibility()

## Server RPC: Turn in quest
@rpc("any_peer", "call_remote", "reliable")
func _server_turn_in_quest(player_id: int, quest_id: String, player_class: String) -> void:
	if not multiplayer.is_server():
		return

	# Validate that the request is from the correct player
	var sender_id = multiplayer.get_remote_sender_id()
	if sender_id != player_id:
		print("Angel: Invalid turn-in request from ", sender_id, " for player ", player_id)
		return

	on_quest_turned_in(player_id, quest_id, player_class)

	# Get next quest info and send to client
	var next_quest_info = get_next_quest_info(player_id, player_class)
	if next_quest_info["has_quest"]:
		var quest_data = next_quest_info["quest_data"]
		var quest_dict = {
			"quest_id": next_quest_info["quest_id"],
			"quest_name": quest_data.quest_name,
			"description": quest_data.description
		}
		rpc_id(player_id, "_client_receive_next_quest", quest_dict)
	else:
		# No next quest available
		rpc_id(player_id, "_client_receive_next_quest", {})## Client RPC: Sync turn-in state
@rpc("authority", "call_remote", "reliable")
func _sync_turn_in_state(player_id: int, quest_id: String) -> void:
	print("[MARKER] _sync_turn_in_state called: player=", player_id, " quest=", quest_id, " local_player=", multiplayer.get_unique_id())
	# Update local state on clients
	if quest_id == initial_quest:
		players_who_completed_initial[player_id] = true
	elif quest_id in class_quests.values():
		# Follow-up quest completed
		players_who_completed_followup[player_id] = true

	# Only update marker visibility if this is the local player's quest
	var local_player_id = multiplayer.get_unique_id()
	if player_id == local_player_id:
		print("[MARKER] Updating marker for local player")
		_check_marker_visibility()
	else:
		print("[MARKER] NOT updating marker (not local player)")

## Client RPC: Receive next quest info after turn-in
@rpc("authority", "call_remote", "reliable")
func _client_receive_next_quest(quest_dict: Dictionary) -> void:
	# Find the Angel UI and update it with next quest info
	var angel_ui = get_tree().current_scene.get_node_or_null("UILayers/AngelUILayer/AngelUI")
	if angel_ui and angel_ui.has_method("show_next_quest"):
		angel_ui.show_next_quest(quest_dict)## Called when player accepts a quest from the Angel
func on_quest_accepted(player_id: int, quest_id: String) -> void:
	# If client, send request to server
	if not multiplayer.is_server():
		rpc_id(1, "_server_accept_quest", player_id, quest_id)
		return

	# Server: Add the quest to the player
	if QuestManager.add_quest_by_id(quest_id, player_id):
		print("Angel: Player ", player_id, " accepted quest: ", quest_id)
		# Sync to all clients that quest was accepted
		rpc("_sync_quest_accepted", player_id, quest_id)

## Server RPC: Accept quest
@rpc("any_peer", "call_remote", "reliable")
func _server_accept_quest(player_id: int, quest_id: String) -> void:
	if not multiplayer.is_server():
		return

	# Validate that the request is from the correct player
	var sender_id = multiplayer.get_remote_sender_id()
	if sender_id != player_id:
		print("Angel: Invalid accept quest request from ", sender_id, " for player ", player_id)
		return

	on_quest_accepted(player_id, quest_id)

## Client RPC: Sync quest acceptance
@rpc("authority", "call_remote", "reliable")
func _sync_quest_accepted(player_id: int, quest_id: String) -> void:
	# Update marker visibility when a quest is accepted
	print("[MARKER] _sync_quest_accepted: player=", player_id, " quest=", quest_id, " local=", multiplayer.get_unique_id())
	var local_player_id = multiplayer.get_unique_id()
	if player_id == local_player_id:
		print("[MARKER] Updating marker after quest accepted")
		_check_marker_visibility()
	else:
		print("[MARKER] NOT updating marker (not local player)")

func _check_marker_visibility() -> void:
	# Show ! for available quests (to accept) and ? for turn-in ready quests
	# This checks ONLY the local player's quest state from QuestManager
	var local_player_id = multiplayer.get_unique_id()

	if not question_marker:
		return

	# Get player's class to check the right follow-up quest
	var players = get_tree().get_nodes_in_group("players")
	var player_class = ""
	for player in players:
		if player.get("player_id") == local_player_id:
			player_class = player.get("player_name")
			break

	var follow_up_quest = class_quests.get(player_class, "kill_enemies")

	var initial_quest_obj = QuestManager.get_quest(initial_quest, local_player_id)
	var follow_up_quest_obj = QuestManager.get_quest(follow_up_quest, local_player_id)

	print("[MARKER] Player ", local_player_id, " checking marker:")
	print("  - Initial quest obj: ", initial_quest_obj, " completed: ", initial_quest_obj.is_completed if initial_quest_obj else "N/A")
	print("  - Follow-up quest obj: ", follow_up_quest_obj, " completed: ", follow_up_quest_obj.is_completed if follow_up_quest_obj else "N/A")
	print("  - Follow-up completed dict: ", players_who_completed_followup.get(local_player_id, false))

	# Determine marker state based ONLY on quest objects, not dictionaries
	var should_show = false
	var marker_text = "?"
	var reason = ""

	# Priority 1: Check if initial quest is ready to turn in
	if initial_quest_obj and initial_quest_obj.is_completed:
		should_show = true
		marker_text = "?"
		reason = "Initial quest ready to turn in"
	# Priority 2: Check if follow-up quest is ready to turn in
	elif follow_up_quest_obj and follow_up_quest_obj.is_completed:
		should_show = true
		marker_text = "?"
		reason = "Follow-up quest ready to turn in"
	# Priority 3: Check if initial quest was turned in and follow-up available
	# (initial quest doesn't exist in QuestManager = it was turned in)
	elif initial_quest_obj == null and follow_up_quest_obj == null:
		# Initial quest turned in, no follow-up yet
		# Check if all quests are done by checking the completion dictionary
		if not players_who_completed_followup.get(local_player_id, false):
			should_show = true
			marker_text = "!"
			reason = "Follow-up quest available"
		else:
			reason = "All quests completed"
	# Priority 4: Quest in progress - no marker
	elif initial_quest_obj and not initial_quest_obj.is_completed:
		should_show = false
		reason = "Initial quest in progress"
	elif follow_up_quest_obj and not follow_up_quest_obj.is_completed:
		should_show = false
		reason = "Follow-up quest in progress"

	print("  - Result: show=", should_show, " marker=", marker_text, " reason=", reason)

	question_marker.visible = should_show

	# Update marker text
	var question_label = question_marker.get_node_or_null("QuestionLabel")
	if question_label:
		question_label.text = marker_text

func has_quest_for_player(player_id: int, player_class: String = "") -> bool:
	var initial_quest_obj = QuestManager.get_quest(initial_quest, player_id)

	# Get class-specific follow-up quest
	var follow_up_quest = class_quests.get(player_class, "kill_enemies")
	var follow_up_quest_obj = QuestManager.get_quest(follow_up_quest, player_id)

	# Has quest if initial quest not completed, or follow-up quest not completed
	if initial_quest_obj and not initial_quest_obj.is_completed:
		return true
	if follow_up_quest_obj and not follow_up_quest_obj.is_completed:
		return true

	return false
