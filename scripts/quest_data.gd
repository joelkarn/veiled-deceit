extends Resource
class_name QuestData

## Quest data resource defining a quest

@export var quest_id: String = ""
@export var quest_name: String = ""
@export_multiline var description: String = ""
@export var goal: int = 1  # How many to complete (e.g., 5 berries, 5 enemies)
@export var current_progress: int = 0
@export var is_completed: bool = false

## Quest types for tracking
enum QuestType {
	COLLECT_BERRIES,
	KILL_ENEMIES,
	READ_BOOK,
	OTHER
}

@export var quest_type: QuestType = QuestType.OTHER

func get_progress_text() -> String:
	if is_completed:
		return "✓ Completed"
	return str(current_progress) + "/" + str(goal)

func add_progress(amount: int = 1) -> void:
	if is_completed:
		return
	
	current_progress += amount
	if current_progress >= goal:
		current_progress = goal
		is_completed = true

func reset() -> void:
	current_progress = 0
	is_completed = false
