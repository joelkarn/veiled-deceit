extends Control

## Angel UI - shows current quest and allows completion

var angel_node: Node = null
var player_id: int = 0
var current_quest: QuestData = null
var next_quest_id: String = ""
var is_showing_new_quest: bool = false

@onready var panel: PanelContainer = $Panel
@onready var npc_name_label: Label = $Panel/VBoxContainer/NPCNameLabel
@onready var dialogue_label: Label = $Panel/VBoxContainer/DialogueLabel
@onready var quest_container: VBoxContainer = $Panel/VBoxContainer/QuestContainer
@onready var quest_title_label: Label = $Panel/VBoxContainer/QuestContainer/QuestTitle
@onready var quest_description_label: Label = $Panel/VBoxContainer/QuestContainer/QuestDescription
@onready var turn_in_button: Button = $Panel/VBoxContainer/QuestContainer/TurnInButton
@onready var accept_button: Button = $Panel/VBoxContainer/QuestContainer/AcceptButton
@onready var close_button: Button = $Panel/VBoxContainer/CloseButton

func _ready() -> void:
	visible = false
	close_button.pressed.connect(_on_close_button_pressed)
	turn_in_button.pressed.connect(_on_turn_in_button_pressed)
	accept_button.pressed.connect(_on_accept_button_pressed)

	# Register with UI manager
	var ui_manager = get_tree().current_scene.get_node_or_null("UIManager")
	if ui_manager and ui_manager.has_method("register_angel_ui"):
		ui_manager.register_angel_ui(self)

func _input(event: InputEvent) -> void:
	if not visible:
		return

	if event.is_action_pressed("ui_cancel"):
		close_ui()
		get_viewport().set_input_as_handled()

func show_angel(angel: Node, npc_name: String, dialogue: String, quest: QuestData, is_new_quest_offer: bool = false) -> void:
	angel_node = angel
	player_id = multiplayer.get_unique_id()
	current_quest = quest
	is_showing_new_quest = is_new_quest_offer
	next_quest_id = ""

	npc_name_label.text = npc_name
	dialogue_label.text = dialogue

	# Show quest info if available
	if quest:
		quest_container.visible = true
		quest_title_label.text = quest.quest_name
		quest_description_label.text = quest.description

		# If this is a new quest offer (not yet accepted), show accept button
		if is_new_quest_offer:
			next_quest_id = quest.quest_id
			turn_in_button.visible = false
			accept_button.visible = true
		# Show turn-in button only if quest is completed and already accepted
		elif quest.is_completed:
			turn_in_button.visible = true
			accept_button.visible = false
		else:
			turn_in_button.visible = false
			accept_button.visible = false
	else:
		quest_container.visible = false
		turn_in_button.visible = false
		accept_button.visible = false

	visible = true

	# Release mouse for UI interaction
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

func close_ui() -> void:
	visible = false
	angel_node = null
	current_quest = null
	is_showing_new_quest = false
	next_quest_id = ""

	# Re-capture mouse
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

func _on_close_button_pressed() -> void:
	close_ui()

func _on_turn_in_button_pressed() -> void:
	if not current_quest or not current_quest.is_completed:
		return

	# Get player class
	var players = get_tree().get_nodes_in_group("players")
	var player_class = ""
	for player in players:
		if player.get("player_id") == player_id:
			player_class = player.get("player_name")
			break

	var quest_id_to_remove = current_quest.quest_id

	# Turn in the completed quest
	if angel_node and angel_node.has_method("on_quest_turned_in"):
		angel_node.on_quest_turned_in(player_id, quest_id_to_remove, player_class)

	# Remove the quest from quest manager after turning in
	if QuestManager and QuestManager.has_method("remove_quest"):
		QuestManager.remove_quest(quest_id_to_remove, player_id)

	# For host, check next quest immediately
	# For clients, wait for server RPC (_client_receive_next_quest)
	if multiplayer.is_server():
		if angel_node and angel_node.has_method("get_next_quest_info"):
			var next_quest_info = angel_node.get_next_quest_info(player_id, player_class)
			if next_quest_info["has_quest"]:
				# Show the new quest
				var new_quest = next_quest_info["quest_data"]
				next_quest_id = next_quest_info["quest_id"]
				is_showing_new_quest = true

				dialogue_label.text = "I have a new task for you, if you're willing to accept it."
				quest_title_label.text = new_quest.quest_name
				quest_description_label.text = new_quest.description

				turn_in_button.visible = false
				accept_button.visible = true
			else:
				# No more quests, close UI
				close_ui()
		else:
			close_ui()
	# Clients: don't close UI yet, wait for server response

func _on_accept_button_pressed() -> void:
	if not is_showing_new_quest or next_quest_id.is_empty():
		return

	# Accept the quest
	if angel_node and angel_node.has_method("on_quest_accepted"):
		angel_node.on_quest_accepted(player_id, next_quest_id)

	# Close the UI
	close_ui()

## Called by server RPC to show next quest after turn-in
func show_next_quest(quest_dict: Dictionary) -> void:
	if quest_dict.is_empty():
		# No next quest, close UI
		close_ui()
		return

	# Show the new quest
	next_quest_id = quest_dict.get("quest_id", "")
	is_showing_new_quest = true

	dialogue_label.text = "I have a new task for you, if you're willing to accept it."
	quest_title_label.text = quest_dict.get("quest_name", "Unknown Quest")
	quest_description_label.text = quest_dict.get("description", "")

	turn_in_button.visible = false
	accept_button.visible = true
