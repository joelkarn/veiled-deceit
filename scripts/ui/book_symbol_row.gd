extends HBoxContainer

## Symbol row for the Book of Interpretations
## Displays a symbol icon with its name, syllable, and meaning

@onready var symbol_icon: TextureRect = $SymbolIcon
@onready var symbol_name: Label = $InfoContainer/SymbolName
@onready var syllable: Label = $InfoContainer/Syllable
@onready var meaning: Label = $InfoContainer/Meaning

const SYMBOL_FOLDER = "res://assets/textures/holy_symbols_folder/"

func set_symbol_data(symbol_index: int, interpretation: Dictionary) -> void:
	"""Set the symbol data to display"""
	# Get list of symbol textures (same way as holy_symbol.gd)
	var symbol_textures = _get_symbol_textures()

	# Load symbol texture by index
	if symbol_index >= 0 and symbol_index < symbol_textures.size():
		var texture_path = SYMBOL_FOLDER + symbol_textures[symbol_index]
		if ResourceLoader.exists(texture_path):
			symbol_icon.texture = load(texture_path)
			print("[BookSymbolRow] Loaded symbol texture: ", texture_path)
		else:
			print("[BookSymbolRow] Symbol texture not found: ", texture_path)
	else:
		print("[BookSymbolRow] Symbol index out of range: ", symbol_index, " (max: ", symbol_textures.size() - 1, ")")

	# Set text data
	if symbol_name:
		symbol_name.text = interpretation.get("name", "Unknown Symbol")
	if syllable:
		syllable.text = "Syllable: " + interpretation.get("syllable", "???")
	if meaning:
		meaning.text = interpretation.get("meaning", "")

func _get_symbol_textures() -> Array:
	"""Get all symbol texture filenames from the folder"""
	var textures = []
	var dir = DirAccess.open(SYMBOL_FOLDER)

	if dir:
		dir.list_dir_begin()
		var file_name = dir.get_next()

		while file_name != "":
			# Only get PNG files (not .import files)
			if file_name.ends_with(".png") and not file_name.ends_with(".import"):
				textures.append(file_name)
			file_name = dir.get_next()

		dir.list_dir_end()

	return textures
