extends Control

## Book UI - Shows interpretation book for the Priest with symbol and text meanings

@onready var left_page: Panel = $BookContainer/HBoxContainer/LeftPage
@onready var right_page: Panel = $BookContainer/HBoxContainer/RightPage
@onready var left_text: Label = $BookContainer/HBoxContainer/LeftPage/LeftText
@onready var right_text: Label = $BookContainer/HBoxContainer/RightPage/RightText
@onready var close_button: Button = $BookContainer/CloseButton

# Containers for symbol/text rows
var left_symbol_container: VBoxContainer = null
var right_text_container: VBoxContainer = null

var current_book_data: BookData = null
var is_interpretation_book: bool = false

# Preload the row scenes
var symbol_row_scene: PackedScene = preload("res://scenes/ui/book_symbol_row.tscn")
var text_row_scene: PackedScene = preload("res://scenes/ui/book_text_row.tscn")

func _ready() -> void:
	hide()
	mouse_filter = Control.MOUSE_FILTER_IGNORE

	if close_button:
		close_button.pressed.connect(_on_close_pressed)

	# Create containers for the rows
	_create_row_containers()

func _create_row_containers() -> void:
	"""Create ScrollContainers for displaying symbol and text rows"""
	# Left page - symbols
	if left_page and not left_symbol_container:
		# Hide the default text label
		if left_text:
			left_text.hide()

		var scroll = ScrollContainer.new()
		scroll.name = "SymbolScroll"
		scroll.position = Vector2(10, 10)
		scroll.size = Vector2(380, 540)  # Adjust to fit your book page size
		scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED

		left_symbol_container = VBoxContainer.new()
		left_symbol_container.name = "SymbolContainer"
		left_symbol_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		scroll.add_child(left_symbol_container)
		left_page.add_child(scroll)

	# Right page - texts
	if right_page and not right_text_container:
		# Hide the default text label
		if right_text:
			right_text.hide()

		var scroll = ScrollContainer.new()
		scroll.name = "TextScroll"
		scroll.position = Vector2(10, 10)
		scroll.size = Vector2(380, 540)  # Adjust to fit your book page size
		scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED

		right_text_container = VBoxContainer.new()
		right_text_container.name = "TextContainer"
		right_text_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		scroll.add_child(right_text_container)
		right_page.add_child(scroll)

func _on_close_pressed() -> void:
	hide_book()

func show_book(book_data: BookData) -> void:
	if not book_data:
		return

	current_book_data = book_data
	is_interpretation_book = false

	# Show the text labels and hide containers for regular books
	if left_text:
		left_text.show()
		left_text.text = book_data.left_page_text
	if right_text:
		right_text.show()
		right_text.text = book_data.right_page_text

	# Hide interpretation containers
	if left_symbol_container and left_symbol_container.get_parent():
		left_symbol_container.get_parent().hide()
	if right_text_container and right_text_container.get_parent():
		right_text_container.get_parent().hide()

	# Show the book UI
	show()
	mouse_filter = Control.MOUSE_FILTER_STOP

func show_interpretation_book() -> void:
	"""Show the priest's interpretation book with symbols and texts"""
	if not CaveMysteryManager:
		print("[BookUI] CaveMysteryManager not found!")
		return

	is_interpretation_book = true

	# Hide text labels for interpretation book
	if left_text:
		left_text.hide()
	if right_text:
		right_text.hide()

	# Show and populate containers
	if left_symbol_container and left_symbol_container.get_parent():
		left_symbol_container.get_parent().show()
	if right_text_container and right_text_container.get_parent():
		right_text_container.get_parent().show()

	# Clear existing rows
	_clear_row_containers()

	# Add title to left page
	var left_title = Label.new()
	left_title.text = "Sacred Symbols"
	left_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	left_title.add_theme_font_size_override("font_size", 20)
	left_symbol_container.add_child(left_title)

	var left_separator = HSeparator.new()
	left_symbol_container.add_child(left_separator)

	# Add symbol rows
	var book_symbols = CaveMysteryManager.get_book_symbols()
	for symbol_idx in book_symbols:
		var interpretation = CaveMysteryManager.get_symbol_interpretation(symbol_idx)
		if interpretation:
			var row = symbol_row_scene.instantiate()
			left_symbol_container.add_child(row)
			# Wait for row to be ready before setting data
			await get_tree().process_frame
			row.set_symbol_data(symbol_idx, interpretation)

	# Add title to right page
	var right_title = Label.new()
	right_title.text = "Ancient Texts"
	right_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	right_title.add_theme_font_size_override("font_size", 20)
	right_text_container.add_child(right_title)

	var right_separator = HSeparator.new()
	right_text_container.add_child(right_separator)

	# Add text rows
	var book_texts = CaveMysteryManager.get_book_texts()
	for text_idx in book_texts:
		var interpretation = CaveMysteryManager.get_text_interpretation(text_idx)
		if interpretation:
			var row = text_row_scene.instantiate()
			right_text_container.add_child(row)
			# Wait for row to be ready before setting data
			await get_tree().process_frame
			row.set_text_data(interpretation)

	# Add hint at bottom of right page
	var spacer = Control.new()
	spacer.custom_minimum_size = Vector2(0, 20)
	right_text_container.add_child(spacer)

	var hint = Label.new()
	hint.text = "Observe the cave closely.\nThe most frequent symbol and text\nhold the key to the temple."
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.add_theme_font_size_override("font_size", 12)
	hint.modulate = Color(0.8, 0.8, 0.8)
	right_text_container.add_child(hint)

	# Show the book UI
	show()
	mouse_filter = Control.MOUSE_FILTER_STOP
	print("[BookUI] Showing interpretation book")

func _clear_row_containers() -> void:
	"""Clear all rows from containers"""
	if left_symbol_container:
		for child in left_symbol_container.get_children():
			child.queue_free()
	if right_text_container:
		for child in right_text_container.get_children():
			child.queue_free()

func hide_book() -> void:
	hide()
	current_book_data = null
	is_interpretation_book = false
	mouse_filter = Control.MOUSE_FILTER_IGNORE
