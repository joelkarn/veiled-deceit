extends Control

## Book UI - Shows two pages with text content when reading a book

@onready var left_page: Panel = $BookContainer/LeftPage
@onready var right_page: Panel = $BookContainer/RightPage
@onready var left_text: Label = $BookContainer/LeftPage/LeftText
@onready var right_text: Label = $BookContainer/RightPage/RightText

var current_book_data: BookData = null

func _ready() -> void:
	hide()
	mouse_filter = Control.MOUSE_FILTER_IGNORE

func show_book(book_data: BookData) -> void:
	if not book_data:
		return
	
	current_book_data = book_data
	
	# Set the text content
	if left_text:
		left_text.text = book_data.left_page_text
	if right_text:
		right_text.text = book_data.right_page_text
	
	# Show the book UI
	show()
	mouse_filter = Control.MOUSE_FILTER_STOP

func hide_book() -> void:
	hide()
	current_book_data = null
	mouse_filter = Control.MOUSE_FILTER_IGNORE
