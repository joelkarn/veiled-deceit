extends Node

## Debug helper for Cave Mystery System
## Add this to your debug console or create keybinds for testing

## Print the current temple name and key items
func print_mystery_solution() -> void:
	if not CaveMysteryManager:
		print("[DEBUG] CaveMysteryManager not found!")
		return
	
	var temple_name = CaveMysteryManager.get_temple_name()
	var symbol_idx = CaveMysteryManager.get_key_symbol_index()
	var text_idx = CaveMysteryManager.get_key_text_index()
	
	if symbol_idx < 0 or text_idx < 0:
		print("[DEBUG] Mystery not yet initialized!")
		return
	
	var symbol_data = CaveMysteryManager.get_symbol_interpretation(symbol_idx)
	var text_data = CaveMysteryManager.get_text_interpretation(text_idx)
	
	print("========================================")
	print("CAVE MYSTERY SOLUTION (DEBUG)")
	print("========================================")
	print("Temple Name: ", temple_name)
	print("")
	print("Key Symbol (Index ", symbol_idx, "):")
	print("  Name: ", symbol_data["name"])
	print("  Syllable: ", symbol_data["syllable"])
	print("  Meaning: ", symbol_data["meaning"])
	print("")
	print("Key Text (Index ", text_idx, "):")
	print("  Text: ", text_data["text"])
	print("  Syllable: ", text_data["syllable"])
	print("  Meaning: ", text_data["meaning"])
	print("")
	print("Combined: ", symbol_data["syllable"], " + ", text_data["syllable"], " = ", temple_name)
	print("========================================")

## Print the contents of the priest's book
func print_book_contents() -> void:
	if not CaveMysteryManager:
		print("[DEBUG] CaveMysteryManager not found!")
		return
	
	var book_symbols = CaveMysteryManager.get_book_symbols()
	var book_texts = CaveMysteryManager.get_book_texts()
	
	if book_symbols.is_empty() or book_texts.is_empty():
		print("[DEBUG] Book not yet generated!")
		return
	
	print("========================================")
	print("PRIEST'S BOOK CONTENTS (DEBUG)")
	print("========================================")
	print("Symbols in Book:")
	for idx in book_symbols:
		var data = CaveMysteryManager.get_symbol_interpretation(idx)
		print("  [", idx, "] ", data["name"], " - Syllable: ", data["syllable"])
	
	print("")
	print("Texts in Book:")
	for idx in book_texts:
		var data = CaveMysteryManager.get_text_interpretation(idx)
		print("  [", idx, "] ", data["text"], " - Syllable: ", data["syllable"])
	print("========================================")

## Validate a temple name (for testing)
func test_temple_name(name: String) -> void:
	if not CaveMysteryManager:
		print("[DEBUG] CaveMysteryManager not found!")
		return
	
	var is_valid = CaveMysteryManager.validate_temple_name(name)
	var correct_name = CaveMysteryManager.get_temple_name()
	
	print("========================================")
	print("TEMPLE NAME VALIDATION (DEBUG)")
	print("========================================")
	print("Tested Name: ", name)
	print("Correct Name: ", correct_name)
	print("Result: ", "VALID" if is_valid else "INVALID")
	print("========================================")

## Force initialize the mystery (server only)
func force_initialize_mystery() -> void:
	if not multiplayer.is_server():
		print("[DEBUG] Can only initialize on server!")
		return
	
	if not CaveMysteryManager:
		print("[DEBUG] CaveMysteryManager not found!")
		return
	
	CaveMysteryManager.initialize_mystery()
	print("[DEBUG] Mystery force initialized!")
	print_mystery_solution()

## Give torch to local player (debug)
func give_torch() -> void:
	var local_player_id = multiplayer.get_unique_id()
	if InventoryManager:
		InventoryManager.add_item(local_player_id, "torch", 1)
		print("[DEBUG] Gave torch to player ", local_player_id)
	else:
		print("[DEBUG] InventoryManager not found!")

## Give book to local player (debug)
func give_book() -> void:
	var local_player_id = multiplayer.get_unique_id()
	if InventoryManager:
		InventoryManager.add_item(local_player_id, "book", 1)
		print("[DEBUG] Gave book to player ", local_player_id)
	else:
		print("[DEBUG] InventoryManager not found!")

## List all possible temple names
func list_all_possible_names() -> void:
	print("========================================")
	print("ALL POSSIBLE TEMPLE NAMES (120 total)")
	print("========================================")
	
	for s_idx in range(8):
		var symbol = CaveMysteryManager.get_symbol_interpretation(s_idx)
		for t_idx in range(15):
			var text = CaveMysteryManager.get_text_interpretation(t_idx)
			var name = symbol["syllable"] + text["syllable"]
			print(name, " - ", symbol["name"], " + ", text["text"])
	
	print("========================================")


# Example usage in console:
# CaveMysteryDebug.print_mystery_solution()
# CaveMysteryDebug.print_book_contents()
# CaveMysteryDebug.test_temple_name("VERTAS")
# CaveMysteryDebug.give_torch()
# CaveMysteryDebug.give_book()
