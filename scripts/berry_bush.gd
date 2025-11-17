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

@onready var mesh_instance: MeshInstance3D = $MeshInstance3D

func _ready() -> void:
	super._ready()
	interact_prompt = "Hold E to harvest berries"
	update_appearance()

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
			var harvest_ui = get_node_or_null("/root/HarvestUIManager")
			if harvest_ui:
				harvest_ui.update_harvest_progress(harvest_progress, harvest_duration)

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
		var harvest_ui = get_node_or_null("/root/HarvestUIManager")
		if harvest_ui:
			harvest_ui.start_harvest_ui(self, harvest_duration)

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
			var harvest_ui = get_node_or_null("/root/HarvestUIManager")
			if harvest_ui:
				harvest_ui.cancel_harvest_ui()

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
		has_berries = false
		is_being_harvested = false
		harvesting_player = null
		harvest_progress = 0.0

		# Hide UI for local player (host) if they were harvesting
		var local_player_id = multiplayer.get_unique_id()
		if player_id == local_player_id:
			var harvest_ui = get_node_or_null("/root/HarvestUIManager")
			if harvest_ui:
				harvest_ui.cancel_harvest_ui()

		update_appearance()
		rpc("sync_bush_state", false)
		rpc("sync_harvest_completed")

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
	if not mesh_instance:
		return

	# Create or get material
	var material = mesh_instance.get_surface_override_material(0)
	if not material:
		material = StandardMaterial3D.new()
		mesh_instance.set_surface_override_material(0, material)

	if has_berries:
		# Bush has berries - green
		material.albedo_color = Color(0.2, 0.8, 0.2)
	else:
		# Bush is empty - brown
		material.albedo_color = Color(0.6, 0.4, 0.2)

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
		var harvest_ui = get_node_or_null("/root/HarvestUIManager")
		if harvest_ui:
			harvest_ui.start_harvest_ui(self, harvest_duration)

@rpc("authority", "call_remote", "reliable")
func sync_harvest_progress(progress: float) -> void:
	harvest_progress = progress

	# Update UI if we have one visible (means we're harvesting)
	var harvest_ui = get_node_or_null("/root/HarvestUIManager")
	if harvest_ui and harvest_ui.current_harvest_bar and harvest_ui.current_harvest_bar.visible:
		harvest_ui.update_harvest_progress(progress, harvest_duration)

@rpc("authority", "call_remote", "reliable")
func sync_harvest_cancelled() -> void:
	is_being_harvested = false
	harvest_progress = 0.0

	# Hide UI for local player
	var harvest_ui = get_node_or_null("/root/HarvestUIManager")
	if harvest_ui:
		harvest_ui.cancel_harvest_ui()

@rpc("authority", "call_remote", "reliable")
func sync_harvest_completed() -> void:
	is_being_harvested = false
	harvest_progress = 0.0

	# Hide UI for local player
	var harvest_ui = get_node_or_null("/root/HarvestUIManager")
	if harvest_ui:
		harvest_ui.cancel_harvest_ui()

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
