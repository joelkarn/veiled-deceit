extends Node

## Quest Manager - manages active quests and tracks progress

signal quest_progress_updated(quest_id: String, player_id: int)
signal quest_completed(quest_id: String, player_id: int)
signal quests_changed(player_id: int)

# Per-player quest tracking: {player_id: Array[QuestData]}
var player_quests: Dictionary = {}  # Dictionary can't be fully typed in GDScript, cast on return
var quest_database: Dictionary = {}

func _ready() -> void:
	_load_quest_database()
	_initialize_starter_quests()

## Load all quest resources
func _load_quest_database() -> void:
	# For now, we'll register quests manually when they're created
	# In the future, you could scan a directory for .tres files
	print("QuestManager: Quest database ready")

## Initialize the three starter quests for a specific player
func _initialize_starter_quests_for_player(player_id: int) -> void:
	# Load the three quests from resources
	var berries_quest = load("res://resources/quests/collect_berries.tres").duplicate(true)
	var enemies_quest = load("res://resources/quests/kill_enemies.tres").duplicate(true)
	var book_quest = load("res://resources/quests/read_book.tres").duplicate(true)

	if not player_quests.has(player_id):
		player_quests[player_id] = []

	if berries_quest:
		player_quests[player_id].append(berries_quest)
		quest_database[berries_quest.quest_id + "_" + str(player_id)] = berries_quest

	if enemies_quest:
		player_quests[player_id].append(enemies_quest)
		quest_database[enemies_quest.quest_id + "_" + str(player_id)] = enemies_quest

	if book_quest:
		player_quests[player_id].append(book_quest)
		quest_database[book_quest.quest_id + "_" + str(player_id)] = book_quest

	print("QuestManager: Loaded ", player_quests[player_id].size(), " starter quests for player ", player_id)
	quests_changed.emit(player_id)

## Initialize quests when a player is added to the game
func initialize_player(player_id: int) -> void:
	if not player_quests.has(player_id):
		player_quests[player_id] = []
		_initialize_starter_quests_for_player(player_id)
		print("QuestManager: Initialized quests for player ", player_id)

## Initialize the three starter quests (deprecated - calls per-player version)
func _initialize_starter_quests() -> void:
	# For backward compatibility, initialize for local player
	var local_player_id = multiplayer.get_unique_id()
	_initialize_starter_quests_for_player(local_player_id)

## Get all active quests for a specific player
func get_active_quests(player_id: int = -1) -> Array[QuestData]:
	if player_id == -1:
		player_id = multiplayer.get_unique_id()

	if not player_quests.has(player_id):
		initialize_player(player_id)

	# Cast to proper type since Dictionary values can't be fully typed
	var quests: Array[QuestData] = []
	quests.assign(player_quests[player_id])
	return quests

## Add progress to a quest by ID for a specific player
func add_quest_progress(quest_id: String, amount: int = 1, player_id: int = -1) -> void:
	if player_id == -1:
		player_id = multiplayer.get_unique_id()

	var full_quest_id = quest_id + "_" + str(player_id)

	if not quest_database.has(full_quest_id):
		print("QuestManager: Quest not found: ", full_quest_id)
		return

	var quest = quest_database[full_quest_id]
	var was_completed = quest.is_completed

	quest.add_progress(amount)
	quest_progress_updated.emit(quest_id, player_id)

	# Check if newly completed
	if not was_completed and quest.is_completed:
		quest_completed.emit(quest_id, player_id)
		print("QuestManager: Quest completed! ", quest.quest_name, " for player ", player_id)

	# Sync to clients if we're the server
	if multiplayer.is_server():
		print("QuestManager: Syncing quest progress to clients: ", quest_id, " player=", player_id, " progress=", quest.current_progress, " completed=", quest.is_completed)
		rpc("_sync_quest_progress", quest_id, player_id, quest.current_progress, quest.is_completed)

## RPC to sync quest progress to clients
@rpc("authority", "call_remote", "reliable")
func _sync_quest_progress(quest_id: String, player_id: int, new_progress: int, completed: bool) -> void:
	print("QuestManager: _sync_quest_progress RPC received for: ", quest_id, " player=", player_id, " progress=", new_progress, " completed=", completed)
	var full_quest_id = quest_id + "_" + str(player_id)

	if not quest_database.has(full_quest_id):
		print("QuestManager: Cannot sync progress, quest not found: ", full_quest_id)
		return

	var quest = quest_database[full_quest_id]
	var was_completed = quest.is_completed

	quest.current_progress = new_progress
	quest.is_completed = completed
	quest_progress_updated.emit(quest_id, player_id)

	# Check if newly completed
	if not was_completed and quest.is_completed:
		quest_completed.emit(quest_id, player_id)
		print("QuestManager: Quest completed (synced)! ", quest.quest_name, " for player ", player_id)

## Add progress based on quest type for a specific player
func add_progress_by_type(quest_type: QuestData.QuestType, amount: int = 1, player_id: int = -1) -> void:
	if player_id == -1:
		player_id = multiplayer.get_unique_id()

	if not player_quests.has(player_id):
		initialize_player(player_id)

	for quest in player_quests[player_id]:
		if quest.quest_type == quest_type and not quest.is_completed:
			add_quest_progress(quest.quest_id, amount, player_id)

## Check if a quest is completed for a specific player
func is_quest_completed(quest_id: String, player_id: int = -1) -> bool:
	if player_id == -1:
		player_id = multiplayer.get_unique_id()

	var full_quest_id = quest_id + "_" + str(player_id)
	if quest_database.has(full_quest_id):
		return quest_database[full_quest_id].is_completed
	return false

## Get quest by ID for a specific player
func get_quest(quest_id: String, player_id: int = -1) -> QuestData:
	if player_id == -1:
		player_id = multiplayer.get_unique_id()

	var full_quest_id = quest_id + "_" + str(player_id)
	if quest_database.has(full_quest_id):
		return quest_database[full_quest_id]
	return null

## Add a quest by ID to a specific player (loads from resources/quests/)
func add_quest_by_id(quest_id: String, player_id: int = -1) -> bool:
	if player_id == -1:
		player_id = multiplayer.get_unique_id()

	var full_quest_id = quest_id + "_" + str(player_id)

	# Check if quest already exists for this player
	if quest_database.has(full_quest_id):
		print("QuestManager: Quest already exists for player ", player_id, ": ", quest_id)
		return false

	# Try to load the quest resource
	var quest_path = "res://resources/quests/" + quest_id + ".tres"
	var quest = load(quest_path)

	if not quest:
		print("QuestManager: Failed to load quest: ", quest_path)
		return false

	# Duplicate the quest so each player has their own instance
	quest = quest.duplicate(true)

	# Initialize player quests if needed
	if not player_quests.has(player_id):
		player_quests[player_id] = []

	# Add to player's quests and database
	player_quests[player_id].append(quest)
	quest_database[full_quest_id] = quest
	quests_changed.emit(player_id)

	print("QuestManager: Added quest '", quest.quest_name, "' to player ", player_id)

	# Sync to clients if we're the server
	print("QuestManager: Is server? ", multiplayer.is_server())
	if multiplayer.is_server():
		print("QuestManager: Syncing quest to clients via RPC: ", quest_id, " for player ", player_id)
		rpc("_sync_quest_add", quest_id, player_id)
	else:
		print("QuestManager: Not server, not syncing")

	return true

## RPC to sync quest addition to clients
@rpc("authority", "call_remote", "reliable")
func _sync_quest_add(quest_id: String, player_id: int) -> void:
	# Client receives quest addition from server
	print("QuestManager: _sync_quest_add RPC received for: ", quest_id, " player=", player_id)
	var full_quest_id = quest_id + "_" + str(player_id)

	if quest_database.has(full_quest_id):
		print("QuestManager: Quest already exists for player ", player_id, " (from sync): ", quest_id)
		return

	var quest_path = "res://resources/quests/" + quest_id + ".tres"
	var quest = load(quest_path)

	if not quest:
		print("QuestManager: Failed to load quest (from sync): ", quest_path)
		return

	# Duplicate the quest so each player has their own instance
	quest = quest.duplicate(true)

	# Initialize player quests if needed
	if not player_quests.has(player_id):
		player_quests[player_id] = []

	player_quests[player_id].append(quest)
	quest_database[full_quest_id] = quest
	quests_changed.emit(player_id)

	print("QuestManager: Synced quest '", quest.quest_name, "' from server for player ", player_id)

## Reset all quests for a specific player (for testing)
func reset_all_quests(player_id: int = -1) -> void:
	if player_id == -1:
		player_id = multiplayer.get_unique_id()

	if not player_quests.has(player_id):
		return

	for quest in player_quests[player_id]:
		quest.reset()
	quests_changed.emit(player_id)
	print("QuestManager: All quests reset for player ", player_id)
