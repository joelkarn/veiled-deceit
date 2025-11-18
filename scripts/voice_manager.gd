extends Node

# Voice Manager - Handles VOIP audio capture and playback for all players

# Audio capture settings
const SAMPLE_RATE = 48000
const MIX_RATE = 48000
const BUFFER_LENGTH = 0.1  # 100ms buffer
const PACKET_SIZE = 480  # ~10ms of audio at 48kHz (960 bytes, well under MTU)

# Audio capture components
var audio_stream_player: AudioStreamPlayer
var audio_effect_capture: AudioEffectCapture
var mic_bus_index: int = -1

# Audio playback - one AudioStreamGenerator per connected peer
var peer_audio_players: Dictionary = {}  # peer_id -> AudioStreamPlayer
var peer_audio_generators: Dictionary = {}  # peer_id -> AudioStreamGenerator
var peer_audio_playbacks: Dictionary = {}  # peer_id -> AudioStreamGeneratorPlayback

# Voice transmission state
var voice_transmission_enabled: bool = true
var send_timer: float = 0.0
const SEND_INTERVAL: float = 0.02  # Send every 20ms

# Push-to-talk (enabled by default - press V to talk)
var push_to_talk_enabled: bool = true
var is_talking: bool = false

# Voice activity detection (simple volume threshold)
var vad_enabled: bool = false
var vad_threshold: float = 0.01  # Minimum volume to transmit
var silence_frames: int = 0
const MAX_SILENCE_FRAMES: int = 5  # Stop transmitting after this many silent frames

# UI indicator
var talk_indicator: Label = null
var talking_players_list: VBoxContainer = null
var talking_players_labels: Dictionary = {}  # peer_id -> Label

# Track who is currently talking
var currently_talking: Dictionary = {}  # peer_id -> bool

func _ready() -> void:
	print("VoiceManager: Initializing...")
	print("🎤 Push-to-talk ENABLED - Press and hold V to speak!")

	# Wait a frame to ensure audio server is ready
	await get_tree().process_frame

	_setup_audio_bus()
	_setup_microphone_capture()

	# Connect to multiplayer signals
	if multiplayer:
		multiplayer.peer_connected.connect(_on_peer_connected)
		multiplayer.peer_disconnected.connect(_on_peer_disconnected)

	# Create on-screen talk indicator
	_create_talk_indicator()
	_create_talking_players_list()

	print("VoiceManager: Ready! Voice chat enabled.")

func _setup_audio_bus() -> void:
	"""Create and configure the 'Mic' audio bus for capture"""
	# Check if 'Mic' bus already exists
	mic_bus_index = AudioServer.get_bus_index("Mic")

	if mic_bus_index == -1:
		# Create new bus
		AudioServer.add_bus()
		mic_bus_index = AudioServer.bus_count - 1
		AudioServer.set_bus_name(mic_bus_index, "Mic")
		print("VoiceManager: Created 'Mic' audio bus at index ", mic_bus_index)
	else:
		print("VoiceManager: Using existing 'Mic' audio bus at index ", mic_bus_index)

	# Mute the bus so we don't hear ourselves
	AudioServer.set_bus_mute(mic_bus_index, true)

	# Add AudioEffectCapture if not present
	var has_capture = false
	for i in range(AudioServer.get_bus_effect_count(mic_bus_index)):
		var effect = AudioServer.get_bus_effect(mic_bus_index, i)
		if effect is AudioEffectCapture:
			audio_effect_capture = effect
			has_capture = true
			break

	if not has_capture:
		audio_effect_capture = AudioEffectCapture.new()
		audio_effect_capture.buffer_length = BUFFER_LENGTH
		AudioServer.add_bus_effect(mic_bus_index, audio_effect_capture)
		print("VoiceManager: Added AudioEffectCapture to 'Mic' bus")
	else:
		print("VoiceManager: Using existing AudioEffectCapture")

func _setup_microphone_capture() -> void:
	"""Set up AudioStreamPlayer with microphone input"""
	audio_stream_player = AudioStreamPlayer.new()
	audio_stream_player.stream = AudioStreamMicrophone.new()
	audio_stream_player.bus = "Mic"
	audio_stream_player.autoplay = true
	add_child(audio_stream_player)

func _process(delta: float) -> void:
	# Update talking timers (hide indicators after timeout)
	if has_meta("talking_timers"):
		var timers = get_meta("talking_timers")
		var to_remove = []
		for peer_id in timers.keys():
			timers[peer_id] -= delta
			if timers[peer_id] <= 0:
				_set_player_talking(peer_id, false)
				to_remove.append(peer_id)
		for peer_id in to_remove:
			timers.erase(peer_id)

	# Only capture and send audio if we're connected to multiplayer
	if not multiplayer or not multiplayer.multiplayer_peer:
		return

	# Don't send if voice is disabled
	if not voice_transmission_enabled:
		return

	# Check push-to-talk
	if push_to_talk_enabled:
		var was_talking = is_talking
		is_talking = Input.is_action_pressed("voice_chat")

		# Update talk indicator whenever push-to-talk state changes
		_update_talk_indicator()

		if not is_talking:
			return
	else:
		is_talking = true
		_update_talk_indicator()

	# Send audio packets periodically
	send_timer += delta
	if send_timer >= SEND_INTERVAL:
		send_timer = 0.0
		_capture_and_send_audio()

func _capture_and_send_audio() -> void:
	"""Capture audio from microphone and send to all peers"""
	if not audio_effect_capture:
		print("VoiceManager: ERROR - audio_effect_capture is null!")
		return

	# Get available frames
	var available_frames = audio_effect_capture.get_frames_available()

	if available_frames < PACKET_SIZE:
		return  # Not enough audio data yet

	# Read audio frames
	var audio_frames = audio_effect_capture.get_buffer(PACKET_SIZE)

	if audio_frames.size() == 0:
		return

	# Voice activity detection (VAD)
	if vad_enabled:
		var volume = _calculate_audio_volume(audio_frames)
		if volume < vad_threshold:
			silence_frames += 1
			if silence_frames > MAX_SILENCE_FRAMES:
				return  # Don't send silent audio
		else:
			silence_frames = 0

	# Convert audio frames to PackedByteArray
	var audio_data = _convert_frames_to_bytes(audio_frames)

	if audio_data.size() == 0:
		return

	# Send to all peers via RPC
	var my_peer_id = multiplayer.get_unique_id()

	# Use unreliable RPC for voice (we don't need guaranteed delivery)
	# If a packet is lost, the next one will arrive soon anyway
	_send_voice_data(audio_data, my_peer_id)

func _calculate_audio_volume(frames: PackedVector2Array) -> float:
	"""Calculate average volume of audio frames"""
	if frames.size() == 0:
		return 0.0

	var total = 0.0
	for frame in frames:
		# Use left channel (mono microphone input)
		total += abs(frame.x)

	return total / frames.size()

func _convert_frames_to_bytes(frames: PackedVector2Array) -> PackedByteArray:
	"""Convert audio frames to bytes for transmission"""
	var bytes = PackedByteArray()

	for frame in frames:
		# Convert stereo to mono (take left channel)
		var sample = frame.x

		# Convert float (-1.0 to 1.0) to 16-bit signed integer
		var int_sample = int(clamp(sample, -1.0, 1.0) * 32767.0)

		# Pack as little-endian 16-bit integer
		bytes.append(int_sample & 0xFF)
		bytes.append((int_sample >> 8) & 0xFF)

	return bytes

func _send_voice_data(audio_data: PackedByteArray, from_peer_id: int) -> void:
	"""Send voice data to all peers (called locally, then RPCed)"""
	# Verify connection before sending
	if not multiplayer or not multiplayer.multiplayer_peer:
		return

	var peer = multiplayer.multiplayer_peer
	if peer.get_connection_status() != MultiplayerPeer.CONNECTION_CONNECTED:
		# Not connected yet, skip this packet
		return

	# Don't send if no other players are connected
	if multiplayer.is_server():
		if multiplayer.get_peers().size() == 0:
			return  # No clients connected yet
		# Host sends to all clients
		rpc("receive_voice_data", audio_data, from_peer_id)
	else:
		# Client sends to host, which will relay to others
		rpc_id(1, "receive_voice_data", audio_data, from_peer_id)

@rpc("any_peer", "unreliable", "call_remote")
func receive_voice_data(audio_data: PackedByteArray, from_peer_id: int) -> void:
	"""Receive voice data from a peer and play it"""
	var my_peer_id = multiplayer.get_unique_id()

	# Don't play our own voice back to ourselves
	if from_peer_id == my_peer_id:
		return

	# If we're the host, relay to all other clients (except the sender)
	if multiplayer.is_server() and from_peer_id != 1:
		# Relay to all clients except the sender
		for peer_id in multiplayer.get_peers():
			if peer_id != from_peer_id:
				rpc_id(peer_id, "receive_voice_data", audio_data, from_peer_id)

	# Mark this peer as talking (they're sending audio)
	_set_player_talking(from_peer_id, true)

	# Auto-hide talking indicator after a short delay if no more packets
	if not has_meta("talking_timers"):
		set_meta("talking_timers", {})
	var timers = get_meta("talking_timers")

	# Reset or create timer for this peer
	if timers.has(from_peer_id):
		timers[from_peer_id] = 0.3  # Reset to 300ms
	else:
		timers[from_peer_id] = 0.3

	# Play audio from this peer locally
	# - Host plays audio from clients
	# - Clients play audio from host
	# - Clients don't play audio from other clients (they receive it via relay)
	_play_audio_from_peer(from_peer_id, audio_data)

func _play_audio_from_peer(peer_id: int, audio_data: PackedByteArray) -> void:
	"""Play received audio data from a specific peer"""
	# Get or create audio player for this peer
	if not peer_audio_players.has(peer_id):
		_create_audio_player_for_peer(peer_id)

	var playback: AudioStreamGeneratorPlayback = peer_audio_playbacks.get(peer_id)
	if not playback:
		return

	# Convert bytes back to audio frames
	var frames = _convert_bytes_to_frames(audio_data)

	# Push frames to audio stream
	for frame in frames:
		if playback.can_push_buffer(1):
			playback.push_frame(frame)

func _convert_bytes_to_frames(audio_data: PackedByteArray) -> PackedVector2Array:
	"""Convert received bytes back to audio frames"""
	var frames = PackedVector2Array()

	# Each sample is 2 bytes (16-bit)
	for i in range(0, audio_data.size(), 2):
		if i + 1 >= audio_data.size():
			break

		# Unpack little-endian 16-bit signed integer
		var low_byte = audio_data[i]
		var high_byte = audio_data[i + 1]
		var int_sample = low_byte | (high_byte << 8)

		# Handle sign extension for negative numbers
		if int_sample >= 32768:
			int_sample -= 65536

		# Convert back to float (-1.0 to 1.0)
		var sample = float(int_sample) / 32767.0

		# Create stereo frame (same audio in both channels)
		frames.append(Vector2(sample, sample))

	return frames

func _create_audio_player_for_peer(peer_id: int) -> void:
	"""Create an AudioStreamPlayer with generator for a specific peer"""
	print("VoiceManager: Creating audio player for peer ", peer_id)

	# Create AudioStreamGenerator
	var generator = AudioStreamGenerator.new()
	generator.mix_rate = MIX_RATE
	generator.buffer_length = BUFFER_LENGTH

	# Create AudioStreamPlayer
	var player = AudioStreamPlayer.new()
	player.stream = generator
	player.autoplay = true
	player.bus = "Master"  # Play through master bus
	add_child(player)

	# Get playback interface
	await get_tree().process_frame  # Wait for player to be ready
	var playback = player.get_stream_playback() as AudioStreamGeneratorPlayback

	# Store references
	peer_audio_players[peer_id] = player
	peer_audio_generators[peer_id] = generator
	peer_audio_playbacks[peer_id] = playback

	print("VoiceManager: Audio player ready for peer ", peer_id)

func _on_peer_connected(peer_id: int) -> void:
	"""Called when a new peer connects"""
	print("VoiceManager: Peer ", peer_id, " connected - will create audio player when first audio received")
	# Audio player will be created when we first receive audio from this peer

func _on_peer_disconnected(peer_id: int) -> void:
	"""Called when a peer disconnects - cleanup their audio player"""
	print("VoiceManager: Peer ", peer_id, " disconnected - cleaning up audio player")

	# Remove audio player
	if peer_audio_players.has(peer_id):
		var player = peer_audio_players[peer_id]
		if player:
			player.queue_free()
		peer_audio_players.erase(peer_id)

	# Remove references
	peer_audio_generators.erase(peer_id)
	peer_audio_playbacks.erase(peer_id)

func _create_talk_indicator() -> void:
	"""Create an on-screen indicator showing when push-to-talk is active"""
	talk_indicator = Label.new()
	talk_indicator.text = "🎤 TALKING (Hold V)"
	talk_indicator.visible = false

	# Style the label
	talk_indicator.add_theme_font_size_override("font_size", 20)
	talk_indicator.modulate = Color(0.2, 1.0, 0.2, 1.0)  # Green

	# Position at bottom center
	talk_indicator.anchor_left = 0.5
	talk_indicator.anchor_top = 1.0
	talk_indicator.anchor_right = 0.5
	talk_indicator.anchor_bottom = 1.0
	talk_indicator.offset_left = -100
	talk_indicator.offset_top = -60
	talk_indicator.offset_right = 100
	talk_indicator.offset_bottom = -30
	talk_indicator.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER

	# Add to scene tree
	var canvas_layer = CanvasLayer.new()
	canvas_layer.layer = 100  # Draw on top of everything
	add_child(canvas_layer)
	canvas_layer.add_child(talk_indicator)

func _create_talking_players_list() -> void:
	"""Create a list showing who is currently talking"""
	var canvas_layer = CanvasLayer.new()
	canvas_layer.layer = 100
	get_tree().root.add_child(canvas_layer)

	# Create container for the list (top-right corner)
	var panel = PanelContainer.new()
	panel.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	panel.anchor_left = 1.0
	panel.anchor_top = 0.0
	panel.anchor_right = 1.0
	panel.anchor_bottom = 0.0
	panel.offset_left = -220
	panel.offset_top = 10
	panel.offset_right = -10
	panel.offset_bottom = 10
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE

	# Add a semi-transparent background
	var style = StyleBoxFlat.new()
	style.bg_color = Color(0.1, 0.1, 0.1, 0.7)
	style.border_color = Color(0.3, 0.3, 0.3, 0.8)
	style.set_border_width_all(1)
	style.set_corner_radius_all(4)
	panel.add_theme_stylebox_override("panel", style)

	# Title label
	var title_container = VBoxContainer.new()
	title_container.add_theme_constant_override("separation", 5)

	var title_label = Label.new()
	title_label.text = "🎤 Talking"
	title_label.add_theme_font_size_override("font_size", 14)
	title_label.add_theme_color_override("font_color", Color(0.9, 0.9, 0.9, 1.0))
	title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title_container.add_child(title_label)

	# VBoxContainer for player names
	talking_players_list = VBoxContainer.new()
	talking_players_list.add_theme_constant_override("separation", 3)
	title_container.add_child(talking_players_list)

	panel.add_child(title_container)
	canvas_layer.add_child(panel)

func _set_player_talking(peer_id: int, is_talking_now: bool) -> void:
	"""Update talking state for a player and refresh UI"""
	# Update tracking
	if is_talking_now:
		currently_talking[peer_id] = true
	else:
		currently_talking.erase(peer_id)

	# Update talking players list
	_update_talking_players_list()

func _update_talking_players_list() -> void:
	"""Refresh the list of talking players"""
	if not talking_players_list:
		return

	# Remove all existing labels
	for child in talking_players_list.get_children():
		child.queue_free()
	talking_players_labels.clear()

	# Add labels for currently talking players
	for peer_id in currently_talking.keys():
		var label = Label.new()
		label.text = "🟢 Player " + str(peer_id)
		label.add_theme_font_size_override("font_size", 12)
		label.add_theme_color_override("font_color", Color(0.2, 1.0, 0.2, 1.0))
		talking_players_list.add_child(label)
		talking_players_labels[peer_id] = label

func _update_talk_indicator() -> void:
	"""Update the talk indicator based on whether we're transmitting"""
	if talk_indicator:
		talk_indicator.visible = is_talking and push_to_talk_enabled

	# Update our own talking state
	var my_peer_id = multiplayer.get_unique_id()
	_set_player_talking(my_peer_id, is_talking)

# Public API

func enable_voice_chat() -> void:
	"""Enable voice chat transmission"""
	voice_transmission_enabled = true
	print("VoiceManager: Voice chat enabled")

func disable_voice_chat() -> void:
	"""Disable voice chat transmission"""
	voice_transmission_enabled = false
	print("VoiceManager: Voice chat disabled")

func toggle_voice_chat() -> void:
	"""Toggle voice chat on/off"""
	voice_transmission_enabled = !voice_transmission_enabled
	print("VoiceManager: Voice chat ", "enabled" if voice_transmission_enabled else "disabled")

func set_push_to_talk(enabled: bool) -> void:
	"""Enable or disable push-to-talk mode"""
	push_to_talk_enabled = enabled
	if enabled:
		print("🎤 VoiceManager: Push-to-talk ENABLED - Press and hold V to speak")
	else:
		print("🎤 VoiceManager: Push-to-talk DISABLED - Always transmitting (with VAD)")
	_update_talk_indicator()

func set_vad_threshold(threshold: float) -> void:
	"""Set voice activity detection threshold (0.0 to 1.0)"""
	vad_threshold = clamp(threshold, 0.0, 1.0)
	print("VoiceManager: VAD threshold set to ", vad_threshold)

func is_voice_enabled() -> bool:
	"""Check if voice chat is currently enabled"""
	return voice_transmission_enabled
