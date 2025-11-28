extends InteractableBase

## Berry bush - collectible berries that respawn with harvest time

@export var berry_item_id: String = "berries"
@export var berries_per_harvest: int = 3
@export var respawn_time: float = 30.0  # seconds
@export var harvest_duration: float = 2.0  # Time to harvest in seconds

var has_berries: bool = true
var is_being_harvested: bool = false
var harvesting_player: Node = null
var harvest_progress: float = 0.0

@onready var berry_bush_model: Node3D = $berry_bush_model
var berry_objects: Array[Node3D] = []

func _ready() -> void:
	super._ready()
	interact_prompt = "Hold E to harvest berries"
	_find_berry_objects()
	update_appearance()

func _find_berry_objects() -> void:
	"""Find all berry objects (Berry_A, Berry_B, etc.) in the model"""
	berry_objects.clear()
	if not berry_bush_model:
		print("BerryBush: berry_bush_model is null!")
		return

	_find_berries_recursive(berry_bush_model)


func _find_node_by_name(root: Node, name: String) -> Node:
	"""Find a node by name recursively"""
	if root.name == name:
		return root

	for child in root.get_children():
		var found = _find_node_by_name(child, name)
		if found:
			return found

	return null

func _find_berries_recursive(node: Node) -> void:
	"""Recursively search for berry objects"""
	var node_name = node.name
	# Match nodes that start with "Berry" (case-sensitive to match Berry_A, Berry_B, etc.)
	if node_name.begins_with("Berry"):
		# Make sure it's a Node3D (MeshInstance3D is a subclass of Node3D)
		if node is Node3D:
			berry_objects.append(node as Node3D)

	# Continue searching children
	for child in node.get_children():
		_find_berries_recursive(child)

# Send current state to a specific client (for late joiners)
func sync_state_to_client(peer_id: int) -> void:
	if multiplayer.is_server():
		rpc_id(peer_id, "sync_bush_state", has_berries)

func _process(delta: float) -> void:
	# Only process on server, and only if multiplayer is properly set up
	if not multiplayer.has_multiplayer_peer() or not multiplayer.is_server():
		return

	# Update harvest progress
	if is_being_harvested and harvesting_player:
		# Check if player is still valid and connected
		if not is_instance_valid(harvesting_player):
			cancel_harvest()
			return

		harvest_progress += delta

		# Update local UI if the harvesting player is the host
		var player_id = harvesting_player.get("player_id")
		var local_player_id = multiplayer.get_unique_id()
		if player_id == local_player_id:
			if HarvestUIManager:
				HarvestUIManager.update_harvest_progress(harvest_progress, harvest_duration)

		# Notify clients of progress (not the host, they update locally above)
		rpc("sync_harvest_progress", harvest_progress)

		# Check if harvest completed
		if harvest_progress >= harvest_duration:
			_complete_harvest()

func start_harvest(player: Node) -> void:
	"""Called when player starts holding interact key"""
	if not multiplayer.is_server():
		return

	if not has_berries or is_being_harvested:
		return

	is_being_harvested = true
	harvesting_player = player
	harvest_progress = 0.0

	var player_id = player.get("player_id")

	# Show UI for the harvesting player (if they're local/host)
	var local_player_id = multiplayer.get_unique_id()
	if player_id == local_player_id:
		if HarvestUIManager:
			HarvestUIManager.start_harvest_ui(self, harvest_duration)

	# Notify OTHER clients that harvesting started
	# For non-host clients in the peers list
	for peer_id in multiplayer.get_peers():
		if peer_id != player_id:
			rpc_id(peer_id, "sync_harvest_started", player_id)

	# Special case: if the host (peer ID 1) is harvesting, they won't be in get_peers()
	# So we need to also check if we should send to the host
	# This handles the case where another client is viewing the host harvest
	# (though the host already showed UI locally above)

func cancel_harvest() -> void:
	"""Called when player releases interact key or moves away"""
	if not multiplayer.is_server():
		return

	if not is_being_harvested:
		return

	var player_id = null
	if harvesting_player:
		player_id = harvesting_player.get("player_id")

	is_being_harvested = false
	harvesting_player = null
	harvest_progress = 0.0

	# Hide UI for local player (host) if they were harvesting
	if player_id != null:
		var local_player_id = multiplayer.get_unique_id()
		if player_id == local_player_id:
			if HarvestUIManager:
				HarvestUIManager.cancel_harvest_ui()

	# Notify clients
	rpc("sync_harvest_cancelled")

func _complete_harvest() -> void:
	"""Called when harvest bar fills completely"""
	if not has_berries or not harvesting_player:
		cancel_harvest()
		return

	var player_id = harvesting_player.get("player_id")
	if player_id == null:
		cancel_harvest()
		return

	# Add berries to inventory
	var success = InventoryManager.add_item(player_id, berry_item_id, berries_per_harvest)

	if success:
		print("BerryBush: Player ", player_id, " harvested ", berries_per_harvest, " berries")

		# Track quest progress for berry collection (only for the host if they're the harvester)
		var local_player_id = multiplayer.get_unique_id()
		if player_id == local_player_id and QuestManager:
			QuestManager.add_progress_by_type(QuestData.QuestType.COLLECT_BERRIES, berries_per_harvest)

		# Play success sound (test audio system)
		_play_pickup_sound()

		has_berries = false
		is_being_harvested = false
		harvesting_player = null
		harvest_progress = 0.0

		# Hide UI for local player (host) if they were harvesting
		if player_id == local_player_id:
			if HarvestUIManager:
				HarvestUIManager.cancel_harvest_ui()

		update_appearance()
		rpc("sync_bush_state", false)
		rpc("sync_harvest_completed", player_id, berries_per_harvest)

		# Start respawn timer
		await get_tree().create_timer(respawn_time).timeout
		has_berries = true
		update_appearance()
		rpc("sync_bush_state", true)
		print("BerryBush: Berries respawned")
	else:
		print("BerryBush: Failed to add berries (inventory full?)")
		cancel_harvest()

# Note: interact() is NOT used for berry bushes - we use start_harvest() instead
# This ensures harvesting requires holding E, not just pressing it

func update_appearance() -> void:
	"""Show or hide berry objects based on whether the bush has berries"""
	# If berry objects haven't been found yet, try to find them
	if berry_objects.is_empty() and berry_bush_model:
		_find_berry_objects()

	# Show or hide all berry objects
	for berry in berry_objects:
		if berry:
			berry.visible = has_berries

@rpc("authority", "call_remote", "reliable")
func sync_bush_state(new_has_berries: bool) -> void:
	has_berries = new_has_berries
	update_appearance()

@rpc("authority", "call_remote", "reliable")
func sync_harvest_started(player_id: int) -> void:
	is_being_harvested = true
	harvest_progress = 0.0

	# Show UI for local player who is harvesting
	var local_player_id = multiplayer.get_unique_id()
	if player_id == local_player_id:
		if HarvestUIManager:
			HarvestUIManager.start_harvest_ui(self, harvest_duration)

@rpc("authority", "call_remote", "reliable")
func sync_harvest_progress(progress: float) -> void:
	harvest_progress = progress

	# Update UI if we have one visible (means we're harvesting)
	if HarvestUIManager and HarvestUIManager.current_harvest_bar and HarvestUIManager.current_harvest_bar.visible:
		HarvestUIManager.update_harvest_progress(progress, harvest_duration)

@rpc("authority", "call_remote", "reliable")
func sync_harvest_cancelled() -> void:
	is_being_harvested = false
	harvest_progress = 0.0

	# Hide UI for local player
	if HarvestUIManager:
		HarvestUIManager.cancel_harvest_ui()

@rpc("authority", "call_remote", "reliable")
func sync_harvest_completed(harvester_id: int, berries_count: int) -> void:
	is_being_harvested = false
	harvest_progress = 0.0

	# Track quest progress only for the player who harvested
	var local_player_id = multiplayer.get_unique_id()
	if harvester_id == local_player_id and QuestManager:
		QuestManager.add_progress_by_type(QuestData.QuestType.COLLECT_BERRIES, berries_count)

	# Hide UI for local player
	if HarvestUIManager:
		HarvestUIManager.cancel_harvest_ui()

func can_interact() -> bool:
	return has_berries and not is_being_harvested

func has_been_interacted() -> bool:
	return not has_berries

func get_harvest_progress() -> float:
	return harvest_progress

func get_harvest_duration() -> float:
	return harvest_duration

func is_harvesting() -> bool:
	return is_being_harvested

func _play_pickup_sound() -> void:
	"""Play a simple beep sound when berries are collected (tests audio system)"""
	# Create a simple AudioStreamPlayer
	var audio_player = AudioStreamPlayer.new()
	add_child(audio_player)

	# Create a simple beep using AudioStreamGenerator
	var stream = AudioStreamGenerator.new()
	stream.mix_rate = 22050
	audio_player.stream = stream
	audio_player.play()

	# Generate a simple beep tone
	await get_tree().process_frame
	var playback = audio_player.get_stream_playback() as AudioStreamGeneratorPlayback
	if playback:
		var frequency = 800.0  # 800 Hz beep
		var duration = 0.1  # 100ms
		var sample_count = int(stream.mix_rate * duration)

		for i in range(sample_count):
			var t = float(i) / stream.mix_rate
			var sample = sin(2.0 * PI * frequency * t) * 0.3  # 30% volume

			# Fade out at the end
			var fade = 1.0
			if i > sample_count * 0.7:
				fade = 1.0 - (float(i - sample_count * 0.7) / (sample_count * 0.3))

			var frame = Vector2(sample * fade, sample * fade)
			if playback.can_push_buffer(1):
				playback.push_frame(frame)

	# Clean up after sound finishes
	await get_tree().create_timer(0.2).timeout
	audio_player.queue_free()

	print("🔊 BerryBush: Played pickup sound (testing audio system)")
