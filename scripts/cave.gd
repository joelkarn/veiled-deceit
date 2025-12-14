extends Node3D

## Cave area that manages darkness and lighting
## Players entering the cave will experience darkness unless they have a torch

@onready var darkness_area: Area3D = $DarknessArea
@onready var holy_symbols_container: Node3D = $HolySymbols

var players_in_cave: Array = []
var holy_symbol_scene: PackedScene = preload("res://scenes/holy_symbol.tscn")
var alchemy_text_scene: PackedScene = preload("res://scenes/alchemy_text.tscn")

# Key symbol/text tracking for the mystery
var key_symbol_index: int = -1
var key_text_index: int = -1

func _ready() -> void:
	# Connect area signals to detect players entering/exiting
	if darkness_area:
		darkness_area.body_entered.connect(_on_body_entered)
		darkness_area.body_exited.connect(_on_body_exited)

	# Wait a frame for CaveMysteryManager to be ready
	await get_tree().process_frame

	# Get the key symbol/text from mystery manager
	if CaveMysteryManager:
		key_symbol_index = CaveMysteryManager.get_key_symbol_index()
		key_text_index = CaveMysteryManager.get_key_text_index()

	# Spawn random holy symbols and alchemy texts on walls
	_spawn_holy_symbols()
	_spawn_alchemy_texts()

	print("[Cave] Cave initialized at ", global_position)

func _spawn_holy_symbols() -> void:
	"""Spawn randomized holy symbols on cave walls"""
	if not holy_symbols_container:
		return

	# Clear existing symbols
	for child in holy_symbols_container.get_children():
		child.queue_free()

	randomize()

	# North wall: 20 symbols (facing south, into cave)
	_spawn_symbols_on_wall(20, Vector3(-30, 5, -44), Vector3(15, 6, 0), Vector3(0, 0, 1))

	# South wall: 20 symbols (facing north, into cave)
	_spawn_symbols_on_wall(20, Vector3(-30, 5, -16), Vector3(15, 6, 0), Vector3(0, 0, -1))

	# West wall: 20 symbols (facing east, into cave)
	_spawn_symbols_on_wall(20, Vector3(-44, 5, -30), Vector3(0, 6, 15), Vector3(1, 0, 0))

func _spawn_symbols_on_wall(count: int, center: Vector3, spread: Vector3, forward: Vector3) -> void:
	"""Spawn symbols on a specific wall with random positions and sizes"""
	# Calculate how many should be the key symbol (10-15% of total)
	# Lower percentage since there are 67 symbols, making it subtle but noticeable
	var key_symbol_count = int(count * randf_range(0.1, 0.15))
	var symbols_to_spawn = []

	# Add key symbol indices
	for i in range(key_symbol_count):
		symbols_to_spawn.append(key_symbol_index)

	# Fill the rest with random symbol indices from all available symbols
	for i in range(count - key_symbol_count):
		var random_symbol = randi() % CaveMysteryManager.SYMBOL_INTERPRETATIONS.size()
		symbols_to_spawn.append(random_symbol)

	# Shuffle so key symbols are distributed randomly
	symbols_to_spawn.shuffle()
	var placed_positions: Array = []
	var min_distance: float = 1.5  # Minimum distance between symbols to prevent overlap
	var max_attempts: int = 50  # Max attempts to find non-overlapping position

	var spawned_count = 0
	for i in range(count):
		var position: Vector3
		var random_scale: float
		var valid_position = false

		# Try to find a non-overlapping position
		for attempt in range(max_attempts):
			# Random position within spread area
			var random_offset = Vector3(
				randf_range(-spread.x, spread.x),
				randf_range(-spread.y, spread.y),
				randf_range(-spread.z, spread.z)
			)

			# Offset the symbol towards cave interior (along forward direction) to prevent z-fighting
			var wall_offset = forward * 0.15  # 0.15 units into the cave
			position = center + random_offset + wall_offset

			# Random size between 0.3x and 0.8x
			random_scale = randf_range(0.3, 0.8)

			# Check if this position is far enough from all other symbols
			var too_close = false
			for placed_pos in placed_positions:
				var distance = position.distance_to(placed_pos)
				if distance < min_distance:
					too_close = true
					break

			if not too_close:
				valid_position = true
				placed_positions.append(position)
				break

		# Skip if couldn't find valid position
		if not valid_position:
			continue

		var symbol = holy_symbol_scene.instantiate()

		# Set the symbol index to use
		if symbol.has_method("set_symbol_index"):
			symbol.set_symbol_index(symbols_to_spawn[i])

		# Calculate rotation to face into the cave (quad's -Z points along forward vector)
		# Default quad faces -Z, we need to rotate it to match the forward direction
		var basis: Basis
		if forward.x > 0:
			# West wall - facing east (+X)
			basis = Basis(Vector3(0, 1, 0), -PI / 2.0)
		elif forward.x < 0:
			# East wall - facing west (-X)
			basis = Basis(Vector3(0, 1, 0), PI / 2.0)
		elif forward.z > 0:
			# North wall - facing south (+Z)
			basis = Basis()  # Default orientation
		elif forward.z < 0:
			# South wall - facing north (-Z)
			basis = Basis(Vector3(0, 1, 0), PI)

		# Apply scale to basis
		basis = basis.scaled(Vector3(random_scale, random_scale, 1.0))

		symbol.transform = Transform3D(basis, position)
		holy_symbols_container.add_child(symbol)
		spawned_count += 1

	print("[Cave] Spawned ", spawned_count, "/", count, " symbols on wall at ", center)

func _spawn_alchemy_texts() -> void:
	"""Spawn randomized alchemy texts on cave walls between symbols"""
	if not holy_symbols_container:
		return

	randomize()

	# North wall: 25 texts
	_spawn_texts_on_wall(25, Vector3(-30, 5, -44), Vector3(15, 6, 0), Vector3(0, 0, 1))

	# South wall: 25 texts
	_spawn_texts_on_wall(25, Vector3(-30, 5, -16), Vector3(15, 6, 0), Vector3(0, 0, -1))

	# West wall: 25 texts
	_spawn_texts_on_wall(25, Vector3(-44, 5, -30), Vector3(0, 6, 15), Vector3(1, 0, 0))

func _spawn_texts_on_wall(count: int, center: Vector3, spread: Vector3, forward: Vector3) -> void:
	"""Spawn alchemy texts on a specific wall"""
	# Calculate how many should be the key text (10-15% of total)
	# Same ratio as symbols for consistency
	var key_text_count = int(count * randf_range(0.1, 0.15))
	var texts_to_spawn = []

	# Add key text indices
	for i in range(key_text_count):
		texts_to_spawn.append(key_text_index)

	# Fill with random text indices from all available texts
	for i in range(count - key_text_count):
		var random_text = randi() % CaveMysteryManager.TEXT_INTERPRETATIONS.size()
		texts_to_spawn.append(random_text)

	# Shuffle so key texts are distributed randomly
	texts_to_spawn.shuffle()

	for i in range(count):
		# Random position within spread area
		var random_offset = Vector3(
			randf_range(-spread.x, spread.x),
			randf_range(-spread.y, spread.y),
			randf_range(-spread.z, spread.z)
		)

		# Offset slightly more to prevent z-fighting
		var wall_offset = forward * 0.2
		var position = center + random_offset + wall_offset

		# Random size between 0.8x and 1.5x
		var random_scale = randf_range(0.8, 1.5)

		var text = alchemy_text_scene.instantiate()

		# Set the text index to use
		if text.has_method("set_text_index"):
			text.set_text_index(texts_to_spawn[i])

		# Calculate rotation to face into the cave
		# Different rotation per wall - Label3D behaves differently than MeshInstance3D
		var basis: Basis
		if forward.x > 0:
			# West wall at x=-44 - facing east (+X) into cave
			# Try flipping: use positive PI/2 for Label3D
			basis = Basis(Vector3(0, 1, 0), PI / 2.0)
		elif forward.x < 0:
			# East wall - facing west (-X)
			basis = Basis(Vector3(0, 1, 0), PI / 2.0)
		elif forward.z > 0:
			# North wall - facing south (+Z)
			basis = Basis()
		elif forward.z < 0:
			# South wall - facing north (-Z)
			basis = Basis(Vector3(0, 1, 0), PI)

		# Apply scale to basis
		basis = basis.scaled(Vector3(random_scale, random_scale, 1.0))

		text.transform = Transform3D(basis, position)
		holy_symbols_container.add_child(text)

	print("[Cave] Spawned ", count, " alchemy texts on wall at ", center)

func _on_body_entered(body: Node3D) -> void:
	# Check if it's a player
	if body.is_in_group("players"):
		if not body in players_in_cave:
			players_in_cave.append(body)
			_apply_darkness_to_player(body)
			print("[Cave] Player entered cave: ", body.name)

func _on_body_exited(body: Node3D) -> void:
	# Check if it's a player
	if body.is_in_group("players"):
		if body in players_in_cave:
			players_in_cave.erase(body)
			_remove_darkness_from_player(body)
			print("[Cave] Player exited cave: ", body.name)

func _apply_darkness_to_player(player: Node) -> void:
	"""Apply darkness effect to player when entering cave"""
	# Only apply to local player
	if not player.get("is_local_player"):
		return

	if not player.is_local_player:
		return

	# Darken the player's view
	if player.has_node("Camera3D"):
		var camera = player.get_node("Camera3D")

		# Create darkness overlay if it doesn't exist
		if not camera.has_node("DarknessOverlay"):
			var darkness = ColorRect.new()
			darkness.name = "DarknessOverlay"
			darkness.color = Color(0, 0, 0, 0.85)  # Very dark overlay
			darkness.mouse_filter = Control.MOUSE_FILTER_IGNORE

			# Make it cover the entire screen
			darkness.set_anchors_preset(Control.PRESET_FULL_RECT)
			darkness.z_index = 100

			# Add to camera's canvas layer or create one
			var canvas_layer = CanvasLayer.new()
			canvas_layer.name = "CaveDarknessLayer"
			canvas_layer.layer = 100
			camera.add_child(canvas_layer)
			canvas_layer.add_child(darkness)

			print("[Cave] Applied darkness overlay to player")

func _remove_darkness_from_player(player: Node) -> void:
	"""Remove darkness effect from player when exiting cave"""
	# Only remove from local player
	if not player.get("is_local_player"):
		return

	if not player.is_local_player:
		return

	# Remove darkness overlay
	if player.has_node("Camera3D"):
		var camera = player.get_node("Camera3D")

		if camera.has_node("CaveDarknessLayer"):
			camera.get_node("CaveDarknessLayer").queue_free()
			print("[Cave] Removed darkness overlay from player")
