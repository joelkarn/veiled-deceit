extends Resource
class_name SignData

## Sign data - holds text content for signs

@export var sign_title: String = "Sign"
@export_multiline var sign_text: String = "This is a sign.\n\nYou can read it by standing close and pressing E."
@export var quest_id_to_add: String = ""  # If set, this quest will be added when the sign is read
