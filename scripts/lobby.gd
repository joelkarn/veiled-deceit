extends Control
# Signal for entering character select
signal entered_character_select

# Connection view nodes
@onready var connection_view: Control = $Panel/ConnectionView
@onready var host_button: Button = $Panel/ConnectionView/VBoxContainer/HostButton
@onready var join_button: Button = $Panel/ConnectionView/VBoxContainer/HBoxContainer/JoinButton
@onready var ip_input: LineEdit = $Panel/ConnectionView/VBoxContainer/HBoxContainer/IPInput
@onready var status_label: Label = $Panel/ConnectionView/VBoxContainer/StatusLabel

# Character selection view nodes
@onready var character_view: Control = $Panel/CharacterView
@onready var witch_button: Button = $Panel/CharacterView/VBoxContainer/CharacterButtons/WitchButton
@onready var hunter_button: Button = $Panel/CharacterView/VBoxContainer/CharacterButtons/HunterButton
@onready var knight_button: Button = $Panel/CharacterView/VBoxContainer/CharacterButtons/KnightButton
@onready var necromancer_button: Button = $Panel/CharacterView/VBoxContainer/CharacterButtons/NecromancerButton
@onready var priest_button: Button = $Panel/CharacterView/VBoxContainer/CharacterButtons/PriestButton
@onready var player_list: Label = $Panel/CharacterView/VBoxContainer/PlayerList
@onready var start_button: Button = $Panel/CharacterView/VBoxContainer/StartButton

var network_manager: Node
var is_host: bool = false

func _ready() -> void:
	# Show mouse cursor when lobby is visible
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

	# Use autoloaded NetworkManager singleton
	network_manager = NetworkManager
	if not network_manager:
		status_label.text = "Error: NetworkManager not found as autoload!"
		print("ERROR: NetworkManager not found as autoload!")
		return

	# Connect button signals
	host_button.pressed.connect(_on_host_button_pressed)
	join_button.pressed.connect(_on_join_button_pressed)
	witch_button.pressed.connect(func(): _on_character_selected("Witch"))
	hunter_button.pressed.connect(func(): _on_character_selected("Hunter"))
	knight_button.pressed.connect(func(): _on_character_selected("Knight"))
	necromancer_button.pressed.connect(func(): _on_character_selected("Necromancer"))
	priest_button.pressed.connect(func(): _on_character_selected("Priest"))
	start_button.pressed.connect(_on_start_button_pressed)

	# Connect NetworkManager signals
	network_manager.player_list_updated.connect(_on_player_list_updated)
	network_manager.host_started.connect(_on_host_started)

	# Connect to multiplayer signals
	if not multiplayer.connected_to_server.is_connected(_on_connected_to_server):
		multiplayer.connected_to_server.connect(_on_connected_to_server)
	if not multiplayer.connection_failed.is_connected(_on_connection_failed):
		multiplayer.connection_failed.connect(_on_connection_failed)

	# Show connection view initially
	_show_connection_view()
	status_label.text = "Ready - Choose Host or Join"

	# Connect entered_character_select signal to voice chat logic
	entered_character_select.connect(_on_entered_character_select)

func _on_entered_character_select() -> void:
	if VoiceManager:
		VoiceManager.activate_voice_manager()
	else:
		print("[Lobby] VoiceManager singleton NOT found!")

func _show_connection_view() -> void:
	connection_view.visible = true
	character_view.visible = false

func _show_character_view() -> void:
	connection_view.visible = false
	character_view.visible = true
	_update_player_list()
	_update_character_buttons()

	# Only host can start the game
	start_button.visible = is_host

	entered_character_select.emit()
func _on_host_button_pressed() -> void:
	if not network_manager:
		status_label.text = "Error: NetworkManager not found!"
		return

	status_label.text = "Starting host..."
	host_button.disabled = true
	join_button.disabled = true
	is_host = true

	network_manager.host_game()

func _on_join_button_pressed() -> void:
	if not network_manager:
		status_label.text = "Error: NetworkManager not found!"
		return

	var ip = ip_input.text.strip_edges()
	if ip.is_empty():
		ip = "localhost"  # Default to localhost if empty

	status_label.text = "Connecting to " + ip + "..."
	host_button.disabled = true
	join_button.disabled = true
	is_host = false

	network_manager.join_game(ip)

func _on_host_started() -> void:
	status_label.text = "Host started! Select your character..."
	await get_tree().create_timer(0.5).timeout
	_show_character_view()

func _on_player_list_updated() -> void:
	_update_player_list()
	_update_character_buttons()

func _on_connected_to_server() -> void:
	status_label.text = "Connected to server! Select your character..."
	await get_tree().create_timer(0.5).timeout
	_show_character_view()

func _on_connection_failed() -> void:
	status_label.text = "Connection failed!"
	host_button.disabled = false
	join_button.disabled = false
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

func _on_character_selected(character_name: String) -> void:
	if not network_manager:
		return

	print("Selected character: ", character_name)
	network_manager.request_character_selection(character_name)
	_update_character_buttons()

func _update_player_list() -> void:
	if not network_manager:
		return

	var text = "Players:\n"
	var player_chars = network_manager.player_characters

	# Gather all connected peers, including self
	var connected_peers = []
	if multiplayer.multiplayer_peer:
		connected_peers.append_array(multiplayer.get_peers())
		connected_peers.append(multiplayer.get_unique_id())
	else:
		connected_peers = [1]  # Fallback for singleplayer or host
	connected_peers = connected_peers.duplicate()
	var unique_peers = []
	for peer in connected_peers:
		if peer not in unique_peers:
			unique_peers.append(peer)
	connected_peers = unique_peers

	for peer_id in connected_peers:
		var character_name = player_chars.get(peer_id, "Not selected")
		var peer_label = "Player " + str(peer_id)
		if peer_id == multiplayer.get_unique_id():
			peer_label += " (You)"
		text += peer_label + ": " + character_name + "\n"

	player_list.text = text

	# Update start button enabled state
	if is_host:
		start_button.disabled = not network_manager.all_players_ready()

func _update_character_buttons() -> void:
	if not network_manager:
		return

	var available = network_manager.get_available_characters()
	var my_peer_id = multiplayer.get_unique_id()
	var my_character = network_manager.player_characters.get(my_peer_id, "")

	# Enable buttons for available characters or if it's the one we selected
	witch_button.disabled = not ("Witch" in available or my_character == "Witch")
	hunter_button.disabled = not ("Hunter" in available or my_character == "Hunter")
	knight_button.disabled = not ("Knight" in available or my_character == "Knight")
	necromancer_button.disabled = not ("Necromancer" in available or my_character == "Necromancer")
	priest_button.disabled = not ("Priest" in available or my_character == "Priest")

	# Highlight selected character
	witch_button.text = "🧙 Witch" if my_character == "Witch" else "Witch"
	hunter_button.text = "🏹 Hunter" if my_character == "Hunter" else "Hunter"
	knight_button.text = "⚔️ Knight" if my_character == "Knight" else "Knight"
	necromancer_button.text = "💀 Necromancer" if my_character == "Necromancer" else "Necromancer"
	priest_button.text = "✨ Priest" if my_character == "Priest" else "Priest"

func _on_start_button_pressed() -> void:
	if not network_manager or not is_host:
		return

	if not network_manager.all_players_ready():
		print("Cannot start - not all players have selected characters")
		return

	print("Starting game!")
	network_manager.start_game()
