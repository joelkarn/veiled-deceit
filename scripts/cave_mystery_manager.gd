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
# The index matches the texture file in the symbols folder
const SYMBOL_INTERPRETATIONS = [
	{"name": "The Eye of Truth", "syllable": "VER", "meaning": "Represents divine sight and revelation of hidden knowledge"},
	{"name": "The Spiral of Eternity", "syllable": "AEV", "meaning": "Symbolizes the endless cycle of death and rebirth"},
	{"name": "The Crossed Keys", "syllable": "CLV", "meaning": "Denotes the power to unlock sacred mysteries"},
	{"name": "The Twin Moons", "syllable": "LUN", "meaning": "Signifies duality and balance between light and shadow"},
	{"name": "The Sacred Flame", "syllable": "IGN", "meaning": "Embodies purification and divine transformation"},
	{"name": "The Serpent Crown", "syllable": "SER", "meaning": "Marks ancient wisdom and forbidden knowledge"},
	{"name": "The Star Cross", "syllable": "AST", "meaning": "Connects the heavens to the earthly realm"},
	{"name": "The Chalice", "syllable": "CAL", "meaning": "Holds the essence of spiritual nourishment"},
	{"name": "The Winged Herald", "syllable": "ALA", "meaning": "Carries divine messages across realms"},
	{"name": "The Eternal Knot", "syllable": "NOD", "meaning": "Binds fate and destiny together"},
	{"name": "The Crown of Stars", "syllable": "REG", "meaning": "Symbolizes celestial authority"},
	{"name": "The Sacred Tree", "syllable": "ARB", "meaning": "Roots in earth, branches in heaven"},
	{"name": "The Phoenix Mark", "syllable": "PHO", "meaning": "Death and glorious rebirth"},
	{"name": "The Compass Rose", "syllable": "NAV", "meaning": "Guides lost souls home"},
	{"name": "The Broken Chain", "syllable": "LIB", "meaning": "Freedom from earthly bonds"},
	{"name": "The Silver Mirror", "syllable": "REF", "meaning": "Reflects true nature of the soul"},
	{"name": "The Guardian Shield", "syllable": "PRO", "meaning": "Wards against malevolent forces"},
	{"name": "The Mystic Circle", "syllable": "ORB", "meaning": "Completeness and wholeness"},
	{"name": "The Thunder Mark", "syllable": "TON", "meaning": "Divine wrath and judgment"},
	{"name": "The Healing Hand", "syllable": "SAN", "meaning": "Restores body and spirit"},
	{"name": "The Hourglass", "syllable": "TEM", "meaning": "Measures mortal time"},
	{"name": "The Crystal Prism", "syllable": "LUX", "meaning": "Refracts truth into many colors"},
	{"name": "The Anchor", "syllable": "STA", "meaning": "Steadfastness in stormy seas"},
	{"name": "The Veil", "syllable": "OCC", "meaning": "Conceals mysteries from the unworthy"},
	{"name": "The Lantern", "syllable": "FAR", "meaning": "Illuminates the darkest path"},
	{"name": "The Thorned Rose", "syllable": "DUL", "meaning": "Beauty born of suffering"},
	{"name": "The Raven's Wing", "syllable": "COR", "meaning": "Messenger between worlds"},
	{"name": "The Golden Scales", "syllable": "JUS", "meaning": "Weighs the worth of souls"},
	{"name": "The Crescent Blade", "syllable": "FAL", "meaning": "Cuts away illusion"},
	{"name": "The Pearl", "syllable": "GEM", "meaning": "Wisdom gained through trials"},
	{"name": "The Dragon's Eye", "syllable": "DRA", "meaning": "Sees all truths, however painful"},
	{"name": "The Labyrinth", "syllable": "LAB", "meaning": "Journey to the center of self"},
	{"name": "The Bell", "syllable": "SON", "meaning": "Calls faithful to prayer"},
	{"name": "The Oak Leaf", "syllable": "FOR", "meaning": "Strength and endurance"},
	{"name": "The Fountain", "syllable": "FON", "meaning": "Source of eternal life"},
	{"name": "The Scepter", "syllable": "REX", "meaning": "Rules with divine mandate"},
	{"name": "The Owl's Gaze", "syllable": "SAP", "meaning": "Wisdom in darkness"},
	{"name": "The Lion's Mane", "syllable": "LEO", "meaning": "Courage and nobility"},
	{"name": "The Crystal Cave", "syllable": "CAV", "meaning": "Hidden sanctuary"},
	{"name": "The Morning Star", "syllable": "EOS", "meaning": "Dawn of enlightenment"},
	{"name": "The Silent Bell", "syllable": "SIL", "meaning": "Unspoken truths"},
	{"name": "The Weeping Willow", "syllable": "DOL", "meaning": "Sorrow and remembrance"},
	{"name": "The Iron Gate", "syllable": "POR", "meaning": "Threshold between realms"},
	{"name": "The Silver Cord", "syllable": "VIN", "meaning": "Binds soul to body"},
	{"name": "The Moonwell", "syllable": "PUT", "meaning": "Reflects celestial mysteries"},
	{"name": "The Rune Stone", "syllable": "RUN", "meaning": "Ancient power carved in rock"},
	{"name": "The Sacred Book", "syllable": "COD", "meaning": "Repository of divine law"},
	{"name": "The Candle Flame", "syllable": "CER", "meaning": "Single light against darkness"},
	{"name": "The Butterfly", "syllable": "MET", "meaning": "Transformation and rebirth"},
	{"name": "The Mountain Peak", "syllable": "MON", "meaning": "Aspiration to higher realms"},
	{"name": "The River", "syllable": "FLU", "meaning": "Ever-flowing change"},
	{"name": "The Seed", "syllable": "SEM", "meaning": "Potential for growth"},
	{"name": "The Storm Cloud", "syllable": "NUB", "meaning": "Gathering divine fury"},
	{"name": "The Rainbow", "syllable": "ARC", "meaning": "Promise and covenant"},
	{"name": "The Feather", "syllable": "PLU", "meaning": "Lightness of being"},
	{"name": "The Frost Crystal", "syllable": "GEL", "meaning": "Preserved in time"},
	{"name": "The Hearth Fire", "syllable": "FOC", "meaning": "Warmth and home"},
	{"name": "The Spider's Web", "syllable": "TEX", "meaning": "Interconnected fate"},
	{"name": "The Stag's Horn", "syllable": "CER", "meaning": "Wilderness and freedom"},
	{"name": "The Coin", "syllable": "NUM", "meaning": "Value and exchange"},
	{"name": "The Sundial", "syllable": "HOR", "meaning": "Marks the hours of destiny"},
	{"name": "The Scroll", "syllable": "VOL", "meaning": "Written wisdom unfurls"},
	{"name": "The Eclipse", "syllable": "ECL", "meaning": "Shadow over light"},
	{"name": "The Lotus", "syllable": "PAD", "meaning": "Purity rising from mud"},
	{"name": "The Silver Dove", "syllable": "PAX", "meaning": "Peace and reconciliation"},
	{"name": "The Eternal Flame", "syllable": "FLA", "meaning": "Light that never dies"},
	{"name": "The Celestial Crown", "syllable": "CEL", "meaning": "Authority granted by the heavens"},
]

# Text interpretations: Each alchemy text has a meaning and syllable
# MUST match the order in alchemy_text_sprite.gd ALCHEMY_TEXTS array exactly!
const TEXT_INTERPRETATIONS = [
	{"text": "SOLVE ET COAGULA", "syllable": "TAS", "meaning": "The great cycle - destroy and rebuild"},
	{"text": "V.I.T.R.I.O.L", "syllable": "ITA", "meaning": "Visit the interior of earth, find the hidden stone"},
	{"text": "AS ABOVE SO BELOW", "syllable": "TEM", "meaning": "The heavens mirror the earthly plane"},
	{"text": "PRIMA MATERIA", "syllable": "PER", "meaning": "The first matter from which all is born"},
	{"text": "OPUS MAGNUM", "syllable": "NUM", "meaning": "The greatest work of transformation"},
	{"text": "AZOTH", "syllable": "ZOT", "meaning": "The universal medicine and perfect substance"},
	{"text": "PHILOSOPHER'S STONE", "syllable": "LIS", "meaning": "The ultimate goal of the great work"},
	{"text": "TRANSMUTATION", "syllable": "MUT", "meaning": "To change base matter into gold, flesh into spirit"},
	{"text": "CAPUT MORTUUM", "syllable": "MOR", "meaning": "Death's head - the worthless remains"},
	{"text": "ALBEDO", "syllable": "ALB", "meaning": "The whitening stage of purification"},
	{"text": "RUBEDO", "syllable": "RUB", "meaning": "The reddening stage of completion"},
	{"text": "NIGREDO", "syllable": "NIG", "meaning": "The blackening stage of decomposition"},
	{"text": "QUINTESSENCE", "syllable": "SEN", "meaning": "The purest essence, the fifth element"},
	{"text": "ELIXIR VITAE", "syllable": "VIT", "meaning": "The water of life eternal"},
	{"text": "MERCURIUS", "syllable": "MER", "meaning": "The mercury principle - transformation"},
	{"text": "SULFUR ET SAL", "syllable": "SAL", "meaning": "Sulfur and salt - the active principles"},
	{"text": "IGNIS ET AQUA", "syllable": "IGN", "meaning": "Fire and water - opposing elements united"},
	{"text": "ANIMA MUNDI", "syllable": "ANI", "meaning": "The soul of the world itself"},
	{"text": "SPIRITUS MUNDI", "syllable": "SPI", "meaning": "The spirit that moves through all things"},
	{"text": "CORPUS", "syllable": "COR", "meaning": "The body - physical manifestation"},
	{"text": "ANIMA", "syllable": "ANA", "meaning": "The soul - vital essence"},
	{"text": "SPIRITUS", "syllable": "SPR", "meaning": "The spirit - divine spark"},
	{"text": "MATERIA PRIMA", "syllable": "MAT", "meaning": "The first matter before creation"},
	{"text": "LAPIS PHILOSOPHORUM", "syllable": "LAP", "meaning": "The philosophers stone in Latin"},
	{"text": "MAGNUM OPUS", "syllable": "MAG", "meaning": "The great work of transformation"},
	{"text": "AURUM POTABILE", "syllable": "AUR", "meaning": "Drinkable gold - liquid immortality"},
	{"text": "CHRYSOPOEIA", "syllable": "CHR", "meaning": "The art of gold-making"},
	{"text": "AQUA REGIA", "syllable": "REG", "meaning": "Royal water that dissolves gold"},
	{"text": "AQUA VITAE", "syllable": "AQU", "meaning": "Water of life"},
	{"text": "ARBOR PHILOSOPHICA", "syllable": "ARB", "meaning": "The philosophical tree of wisdom"},
	{"text": "CAUDA PAVONIS", "syllable": "PAV", "meaning": "Peacock's tail - many colors becoming one"},
	{"text": "CIRCULATUM", "syllable": "CIR", "meaning": "The circular process of refinement"},
	{"text": "MORTIFICATIO", "syllable": "MRT", "meaning": "Death and putrefaction"},
	{"text": "SEPARATIO", "syllable": "SEP", "meaning": "The separation of elements"},
	{"text": "CONJUNCTIO", "syllable": "CON", "meaning": "The sacred marriage of opposites"},
	{"text": "PUTREFACTIO", "syllable": "PUT", "meaning": "Putrefaction and decay"},
	{"text": "CALCINATIO", "syllable": "CAL", "meaning": "Burning away impurities"},
	{"text": "SUBLIMATIO", "syllable": "SUB", "meaning": "Rising from base to refined"},
	{"text": "FERMENTATIO", "syllable": "FER", "meaning": "Fermentation and quickening"},
	{"text": "MULTIPLICATIO", "syllable": "MLT", "meaning": "Multiplication of power"},
	{"text": "PROJECTIO", "syllable": "PRO", "meaning": "The final projection onto base metal"},
	{"text": "OPUS CIRCULATORIUM", "syllable": "OPC", "meaning": "The circular work without end"},
	{"text": "REBIS", "syllable": "BIS", "meaning": "The union of opposites made whole"},
	{"text": "LUNA ET SOL", "syllable": "LUN", "meaning": "Moon and sun - feminine and masculine"},
	{"text": "REX ET REGINA", "syllable": "REX", "meaning": "King and queen united"},
	{"text": "SERPENS", "syllable": "SER", "meaning": "The serpent of wisdom"},
	{"text": "OUROBOROS", "syllable": "ROS", "meaning": "The serpent consuming its tail - eternal return"},
	{"text": "CHAOS", "syllable": "CHA", "meaning": "Primordial chaos before order"},
	{"text": "VITRIOLUM", "syllable": "VIO", "meaning": "Visit the interior of the earth"},
	{"text": "ALKAHEST", "syllable": "HES", "meaning": "The universal solvent that dissolves all"},
	{"text": "TINCTURA", "syllable": "TIN", "meaning": "The tincture that transforms"},
	{"text": "ELIXIR", "syllable": "ELX", "meaning": "The supreme elixir"},
	{"text": "ARCANUM", "syllable": "ARC", "meaning": "The hidden secret"},
	{"text": "HERMES TRISMEGISTUS", "syllable": "HER", "meaning": "Thrice-great Hermes, founder of alchemy"},
	{"text": "TABULA SMARAGDINA", "syllable": "TAB", "meaning": "The emerald tablet of Hermes"},
	{"text": "OPUS ALCHYMICUM", "syllable": "OPA", "meaning": "The alchemical work"},
	{"text": "MYSTERIUM MAGNUM", "syllable": "MYS", "meaning": "The great mystery"},
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
