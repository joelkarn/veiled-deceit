extends Node

## Quest Manager - manages active quests and tracks progress

signal quest_progress_updated(quest_id: String)
signal quest_completed(quest_id: String)
signal quests_changed()

var active_quests: Array[QuestData] = []
var quest_database: Dictionary = {}

func _ready() -> void:
	_load_quest_database()
	_initialize_starter_quests()

## Load all quest resources
func _load_quest_database() -> void:
	# For now, we'll register quests manually when they're created
	# In the future, you could scan a directory for .tres files
	print("QuestManager: Quest database ready")

## Initialize the three starter quests
func _initialize_starter_quests() -> void:
	# Load the three quests from resources
	var berries_quest = load("res://resources/quests/collect_berries.tres")
	var enemies_quest = load("res://resources/quests/kill_enemies.tres")
	var book_quest = load("res://resources/quests/read_book.tres")
	
	if berries_quest:
		active_quests.append(berries_quest)
		quest_database[berries_quest.quest_id] = berries_quest
	
	if enemies_quest:
		active_quests.append(enemies_quest)
		quest_database[enemies_quest.quest_id] = enemies_quest
	
	if book_quest:
		active_quests.append(book_quest)
		quest_database[book_quest.quest_id] = book_quest
	
	print("QuestManager: Loaded ", active_quests.size(), " starter quests")
	quests_changed.emit()

## Get all active quests
func get_active_quests() -> Array[QuestData]:
	return active_quests

## Add progress to a quest by ID
func add_quest_progress(quest_id: String, amount: int = 1) -> void:
	if not quest_database.has(quest_id):
		print("QuestManager: Quest not found: ", quest_id)
		return
	
	var quest = quest_database[quest_id]
	var was_completed = quest.is_completed
	
	quest.add_progress(amount)
	quest_progress_updated.emit(quest_id)
	
	# Check if newly completed
	if not was_completed and quest.is_completed:
		quest_completed.emit(quest_id)
		print("QuestManager: Quest completed! ", quest.quest_name)

## Add progress based on quest type
func add_progress_by_type(quest_type: QuestData.QuestType, amount: int = 1) -> void:
	for quest in active_quests:
		if quest.quest_type == quest_type and not quest.is_completed:
			add_quest_progress(quest.quest_id, amount)

## Check if a quest is completed
func is_quest_completed(quest_id: String) -> bool:
	if quest_database.has(quest_id):
		return quest_database[quest_id].is_completed
	return false

## Get quest by ID
func get_quest(quest_id: String) -> QuestData:
	if quest_database.has(quest_id):
		return quest_database[quest_id]
	return null

## Add a quest by ID (loads from resources/quests/)
func add_quest_by_id(quest_id: String) -> bool:
	# Check if quest already exists
	if quest_database.has(quest_id):
		print("QuestManager: Quest already exists: ", quest_id)
		return false
	
	# Try to load the quest resource
	var quest_path = "res://resources/quests/" + quest_id + ".tres"
	var quest = load(quest_path)
	
	if not quest:
		print("QuestManager: Failed to load quest: ", quest_path)
		return false
	
	# Add to active quests and database
	active_quests.append(quest)
	quest_database[quest_id] = quest
	quests_changed.emit()
	
	print("QuestManager: Added quest: ", quest.quest_name)
	return true

## Reset all quests (for testing)
func reset_all_quests() -> void:
	for quest in active_quests:
		quest.reset()
	quests_changed.emit()
	print("QuestManager: All quests reset")
