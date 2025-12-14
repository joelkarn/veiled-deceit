extends VBoxContainer

## Text row for the Book of Interpretations
## Displays an alchemy text with its syllable and meaning

@onready var text_title: Label = $TextTitle
@onready var syllable: Label = $Syllable
@onready var meaning: Label = $Meaning

func set_text_data(interpretation: Dictionary) -> void:
	"""Set the text data to display"""
	if text_title:
		text_title.text = interpretation.get("text", "UNKNOWN TEXT")
	if syllable:
		syllable.text = "Syllable: " + interpretation.get("syllable", "???")
	if meaning:
		meaning.text = interpretation.get("meaning", "")
