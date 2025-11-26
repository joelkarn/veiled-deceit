extends PanelContainer

## Individual inventory slot UI component

signal slot_clicked(slot_index: int)
signal slot_right_clicked(slot_index: int)

@export var slot_index: int = 0

@onready var item_icon: TextureRect = $MarginContainer/VBoxContainer/ItemIcon
@onready var quantity_label: Label = $MarginContainer/VBoxContainer/QuantityLabel
@onready var button: Button = $Button

var item_id: String = ""
var quantity: int = 0
var is_selected: bool = false

func _ready() -> void:
	if button:
		button.pressed.connect(_on_button_pressed)
		button.gui_input.connect(_on_button_gui_input)

	update_display()

func set_item(new_item_id: String, new_quantity: int) -> void:
	item_id = new_item_id
	quantity = new_quantity
	update_display()

func set_selected(selected: bool) -> void:
	is_selected = selected
	_update_selection_visual()

func update_display() -> void:
	if not item_icon or not quantity_label:
		return

	if item_id == "" or quantity <= 0:
		# Empty slot
		item_icon.texture = null
		quantity_label.text = ""
		item_icon.modulate = Color(1, 1, 1, 0.3)  # Dim when empty
		return

	# Load item data and display
	var item_data = InventoryManager.get_item_data(item_id)
	if item_data:
		item_icon.texture = item_data.icon
		item_icon.modulate = Color.WHITE

		# Show quantity if stackable
		if item_data.max_stack > 1 and quantity > 1:
			quantity_label.text = str(quantity)
		else:
			quantity_label.text = ""
	else:
		item_icon.texture = null
		quantity_label.text = "?"

func _on_button_pressed() -> void:
	slot_clicked.emit(slot_index)

func _on_button_gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		if event.pressed and event.button_index == MOUSE_BUTTON_RIGHT:
			slot_right_clicked.emit(slot_index)

func _update_selection_visual() -> void:
	# Highlight selected slot with brighter appearance
	if is_selected:
		modulate = Color(1.3, 1.3, 1.0, 1.0)  # Yellowish bright highlight
	else:
		modulate = Color(1.0, 1.0, 1.0, 1.0)  # Normal
