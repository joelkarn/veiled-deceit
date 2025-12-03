extends Control

## Quest Log UI - displays active quests

@onready var quest_list: VBoxContainer = $Panel/MarginContainer/VBoxContainer/ScrollContainer/QuestList

func _ready() -> void:
	# Connect to quest manager signals
	if QuestManager:
		QuestManager.quests_changed.connect(_on_quests_changed)
		QuestManager.quest_progress_updated.connect(_on_quest_progress_updated)
		QuestManager.quest_completed.connect(_on_quest_completed)

	# Initial display
	_refresh_quests()

## Called when quests change - only refresh if it's for local player
func _on_quests_changed(player_id: int) -> void:
	var local_player_id = multiplayer.get_unique_id()
	if player_id == local_player_id:
		_refresh_quests()

func _refresh_quests() -> void:
	if not quest_list:
		return

	# Clear existing quest entries
	for child in quest_list.get_children():
		child.queue_free()

	# Get active quests for the local player
	var local_player_id = multiplayer.get_unique_id()
	var quests = QuestManager.get_active_quests(local_player_id) if QuestManager else []

	# Create UI for each quest
	for quest in quests:
		_create_quest_entry(quest)

func _create_quest_entry(quest: QuestData) -> void:
	# Create container for this quest
	var quest_container = VBoxContainer.new()
	quest_container.name = "Quest_" + quest.quest_id

	# Quest title label
	var title_label = Label.new()
	title_label.text = quest.quest_name
	title_label.add_theme_font_size_override("font_size", 16)
	if quest.is_completed:
		title_label.add_theme_color_override("font_color", Color(0.3, 1.0, 0.3))  # Green for completed
	else:
		title_label.add_theme_color_override("font_color", Color(1.0, 1.0, 0.8))  # Light yellow for active
	quest_container.add_child(title_label)

	# Description label
	var desc_label = Label.new()
	desc_label.text = quest.description
	desc_label.add_theme_font_size_override("font_size", 12)
	desc_label.add_theme_color_override("font_color", Color(0.8, 0.8, 0.8))
	desc_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	quest_container.add_child(desc_label)

	# Progress label
	var progress_label = Label.new()
	progress_label.name = "Progress_" + quest.quest_id
	progress_label.text = "Progress: " + quest.get_progress_text()
	progress_label.add_theme_font_size_override("font_size", 14)
	if quest.is_completed:
		progress_label.add_theme_color_override("font_color", Color(0.3, 1.0, 0.3))
	else:
		progress_label.add_theme_color_override("font_color", Color(1.0, 1.0, 1.0))
	quest_container.add_child(progress_label)

	# Separator
	var separator = HSeparator.new()
	separator.add_theme_constant_override("separation", 10)
	quest_container.add_child(separator)

	quest_list.add_child(quest_container)

func _on_quest_progress_updated(quest_id: String, player_id: int) -> void:
	# Only update if this is for the local player
	var local_player_id = multiplayer.get_unique_id()
	if player_id != local_player_id:
		return

	# Find and update the progress label for this quest
	var quest = QuestManager.get_quest(quest_id, player_id) if QuestManager else null
	if not quest:
		return

	var progress_label = quest_list.get_node_or_null("Quest_" + quest_id + "/Progress_" + quest_id)
	if progress_label:
		progress_label.text = "Progress: " + quest.get_progress_text()
		if quest.is_completed:
			progress_label.add_theme_color_override("font_color", Color(0.3, 1.0, 0.3))

	# Update title color if completed
	if quest.is_completed:
		var quest_container = quest_list.get_node_or_null("Quest_" + quest_id)
		if quest_container:
			var title_label = quest_container.get_child(0) as Label
			if title_label:
				title_label.add_theme_color_override("font_color", Color(0.3, 1.0, 0.3))

func _on_quest_completed(quest_id: String, player_id: int) -> void:
	# Only show completion message if this is for the local player
	var local_player_id = multiplayer.get_unique_id()
	if player_id == local_player_id:
		print("Quest UI: Quest completed! ", quest_id)
	# The progress update will handle the visual changes
