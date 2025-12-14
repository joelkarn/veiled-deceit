extends Node

## Cave Mystery Manager
## Manages the randomly selected "key" symbol and text for the temple entrance puzzle
## At game start, selects one symbol and one text that will appear more frequently in the cave
## The priest must interpret these using their book to discover the temple name

# Temple name syllables
var symbol_syllable: String = ""  # First syllable from symbol interpretation
var text_syllable: String = ""    # Second syllable from text interpretation
var temple_name: String = ""      # Combined full name

# Selected key items (indices into the arrays)
var key_symbol_index: int = -1
var key_text_index: int = -1

# Symbol data: Each symbol has an interpretation and syllable
# The index matches the texture file number (holy_symbol_1.png, etc.)
const SYMBOL_INTERPRETATIONS = [
	{"name": "The Eye of Truth", "syllable": "VER", "meaning": "Represents divine sight and revelation of hidden knowledge"},
	{"name": "The Spiral of Eternity", "syllable": "AEV", "meaning": "Symbolizes the endless cycle of death and rebirth"},
	{"name": "The Crossed Keys", "syllable": "CLV", "meaning": "Denotes the power to unlock sacred mysteries"},
	{"name": "The Twin Moons", "syllable": "LUN", "meaning": "Signifies duality and balance between light and shadow"},
	{"name": "The Sacred Flame", "syllable": "IGN", "meaning": "Embodies purification and divine transformation"},
	{"name": "The Serpent Crown", "syllable": "SER", "meaning": "Marks ancient wisdom and forbidden knowledge"},
	{"name": "The Star Cross", "syllable": "AST", "meaning": "Connects the heavens to the earthly realm"},
	{"name": "The Chalice", "syllable": "CAL", "meaning": "Holds the essence of spiritual nourishment"},
]

# Text interpretations: Each alchemy text has a meaning and syllable
# These correspond to texts from alchemy_text_sprite.gd
const TEXT_INTERPRETATIONS = [
	{"text": "SOLVE ET COAGULA", "syllable": "TAS", "meaning": "The great cycle - destroy and rebuild"},
	{"text": "V.I.T.R.I.O.L", "syllable": "ITA", "meaning": "Visit the interior of earth, find the hidden stone"},
	{"text": "AS ABOVE SO BELOW", "syllable": "TEM", "meaning": "The heavens mirror the earthly plane"},
	{"text": "PRIMA MATERIA", "syllable": "PER", "meaning": "The first matter from which all is born"},
	{"text": "OPUS MAGNUM", "syllable": "NUM", "meaning": "The greatest work of transformation"},
	{"text": "AZOTH", "syllable": "ZOT", "meaning": "The universal medicine and perfect substance"},
	{"text": "PHILOSOPHER'S STONE", "syllable": "LIS", "meaning": "The ultimate goal of the great work"},
	{"text": "TRANSMUTATION", "syllable": "MUT", "meaning": "To change base matter into gold, flesh into spirit"},
	{"text": "QUINTESSENCE", "syllable": "SEN", "meaning": "The purest essence, the fifth element"},
	{"text": "ELIXIR VITAE", "syllable": "VIT", "meaning": "The water of life eternal"},
	{"text": "ANIMA MUNDI", "syllable": "ANI", "meaning": "The soul of the world itself"},
	{"text": "SPIRITUS MUNDI", "syllable": "SPI", "meaning": "The spirit that moves through all things"},
	{"text": "REBIS", "syllable": "BIS", "meaning": "The union of opposites made whole"},
	{"text": "OUROBOROS", "syllable": "ROS", "meaning": "The serpent consuming its tail - eternal return"},
	{"text": "ALKAHEST", "syllable": "HES", "meaning": "The universal solvent that dissolves all"},
]

# Book content for the priest (randomized selection + guaranteed key items)
var priest_book_symbols: Array = []  # Subset of symbols that appear in the book
var priest_book_texts: Array = []    # Subset of texts that appear in the book

func _ready() -> void:
	print("[CaveMysteryManager] Initializing...")

func initialize_mystery() -> void:
	"""Called by server at game start to select the key symbol and text"""
	if not multiplayer.is_server():
		return
	
	randomize()
	
	# Select random key symbol and text
	key_symbol_index = randi() % SYMBOL_INTERPRETATIONS.size()
	key_text_index = randi() % TEXT_INTERPRETATIONS.size()
	
	# Get the syllables for the temple name
	symbol_syllable = SYMBOL_INTERPRETATIONS[key_symbol_index]["syllable"]
	text_syllable = TEXT_INTERPRETATIONS[key_text_index]["syllable"]
	temple_name = symbol_syllable + text_syllable
	
	# Generate priest's book content (3-5 symbols and 3-5 texts, always including the key ones)
	_generate_book_content()
	
	print("[CaveMysteryManager] Mystery initialized!")
	print("  Key Symbol: ", SYMBOL_INTERPRETATIONS[key_symbol_index]["name"], " (", symbol_syllable, ")")
	print("  Key Text: ", TEXT_INTERPRETATIONS[key_text_index]["text"], " (", text_syllable, ")")
	print("  Temple Name: ", temple_name)
	
	# Sync to all clients
	rpc("_sync_mystery_data", key_symbol_index, key_text_index, priest_book_symbols, priest_book_texts)

@rpc("authority", "call_remote", "reliable")
func _sync_mystery_data(symbol_idx: int, text_idx: int, book_symbols: Array, book_texts: Array) -> void:
	"""Receive mystery data from server"""
	key_symbol_index = symbol_idx
	key_text_index = text_idx
	priest_book_symbols = book_symbols
	priest_book_texts = book_texts
	
	symbol_syllable = SYMBOL_INTERPRETATIONS[key_symbol_index]["syllable"]
	text_syllable = TEXT_INTERPRETATIONS[key_text_index]["syllable"]
	temple_name = symbol_syllable + text_syllable
	
	print("[CaveMysteryManager] Received mystery data from server")
	print("  Temple Name: ", temple_name)

func _generate_book_content() -> void:
	"""Generate the content for the priest's interpretation book"""
	# Number of random entries to include (in addition to key items)
	var num_extra_symbols = randi_range(2, 4)  # 2-4 extra symbols
	var num_extra_texts = randi_range(2, 4)    # 2-4 extra texts
	
	# Start with the key items
	priest_book_symbols = [key_symbol_index]
	priest_book_texts = [key_text_index]
	
	# Add random symbols (avoid duplicates)
	while priest_book_symbols.size() < num_extra_symbols + 1:
		var random_idx = randi() % SYMBOL_INTERPRETATIONS.size()
		if not random_idx in priest_book_symbols:
			priest_book_symbols.append(random_idx)
	
	# Add random texts (avoid duplicates)
	while priest_book_texts.size() < num_extra_texts + 1:
		var random_idx = randi() % TEXT_INTERPRETATIONS.size()
		if not random_idx in priest_book_texts:
			priest_book_texts.append(random_idx)
	
	# Shuffle so the key items aren't always first
	priest_book_symbols.shuffle()
	priest_book_texts.shuffle()
	
	print("[CaveMysteryManager] Generated book with ", priest_book_symbols.size(), " symbols and ", priest_book_texts.size(), " texts")

## Get the key symbol index (for cave spawning)
func get_key_symbol_index() -> int:
	return key_symbol_index

## Get the key text index (for cave spawning)
func get_key_text_index() -> int:
	return key_text_index

## Get symbol interpretation by index
func get_symbol_interpretation(index: int) -> Dictionary:
	if index >= 0 and index < SYMBOL_INTERPRETATIONS.size():
		return SYMBOL_INTERPRETATIONS[index]
	return {}

## Get text interpretation by index
func get_text_interpretation(index: int) -> Dictionary:
	if index >= 0 and index < TEXT_INTERPRETATIONS.size():
		return TEXT_INTERPRETATIONS[index]
	return {}

## Get the book symbols for priest
func get_book_symbols() -> Array:
	return priest_book_symbols

## Get the book texts for priest
func get_book_texts() -> Array:
	return priest_book_texts

## Check if a proposed temple name is correct
func validate_temple_name(proposed_name: String) -> bool:
	return proposed_name.to_upper() == temple_name.to_upper()

## Get the correct temple name (for debugging or admin)
func get_temple_name() -> String:
	return temple_name

## Get the text string from an interpretation index (to match with alchemy_text_sprite.gd)
func get_text_string(index: int) -> String:
	if index >= 0 and index < TEXT_INTERPRETATIONS.size():
		return TEXT_INTERPRETATIONS[index]["text"]
	return ""
