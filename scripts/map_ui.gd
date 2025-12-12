extends Control

# Map settings
@export var map_size: Vector2 = Vector2(400, 400)  # Size of the map UI
@export var world_size: float = 100.0  # How much of the world to show (radius from player)
@export var update_interval: float = 0.1  # How often to update map (seconds)

# Colors for markers
@export var player_color: Color = Color.GREEN
@export var other_player_color: Color = Color.CYAN
@export var enemy_color: Color = Color.RED
@export var npc_color: Color = Color.YELLOW

# References
var local_player: Node3D = null
var update_timer: float = 0.0

# UI nodes
@onready var map_panel: Panel = $MapPanel
@onready var map_container: Control = $MapPanel/MapContainer

func _ready() -> void:
	visible = false
	mouse_filter = Control.MOUSE_FILTER_STOP

func _process(delta: float) -> void:
	if not visible:
		return
	
	update_timer += delta
	if update_timer >= update_interval:
		update_timer = 0.0
		update_map()

func show_map() -> void:
	visible = true
	find_local_player()
	update_map()

func hide_map() -> void:
	visible = false

func toggle_map() -> void:
	if visible:
		hide_map()
	else:
		show_map()

func find_local_player() -> void:
	# Find the local player in the scene
	var scene = get_tree().current_scene
	if not scene:
		return
	
	for child in scene.get_children():
		if child.name.begins_with("Player_") and child.has_method("get") and child.get("is_local_player"):
			if child.is_local_player:
				local_player = child
				return

func update_map() -> void:
	if not local_player:
		find_local_player()
		if not local_player:
			return
	
	# Clear previous markers
	for child in map_container.get_children():
		child.queue_free()
	
	var player_pos = local_player.global_position
	
	# Get all entities in the scene
	var scene = get_tree().current_scene
	if not scene:
		return
	
	# Draw enemies first (bottom layer)
	var enemies = get_tree().get_nodes_in_group("enemies")
	print("=== MAP UPDATE - Found ", enemies.size(), " enemies in group ===")
	for enemy in enemies:
		if is_instance_valid(enemy) and enemy is Node3D:
			draw_enemy_marker(enemy, player_pos)
	
	# Draw players next (middle layer)
	for child in scene.get_children():
		if child.name.begins_with("Player_"):
			draw_player_marker(child, player_pos)
	
	# Draw NPCs last (top layer - so quest markers appear above players)
	for child in scene.get_children():
		if child.name.begins_with("AngelNPC") or "NPC" in child.name:
			# Check if NPC has a quest marker
			var marker_type = ""
			if child.has_method("get_quest_marker_for_local_player"):
				marker_type = child.get_quest_marker_for_local_player()
			draw_npc_marker(child, player_pos, marker_type)

func draw_player_marker(player: Node3D, center_pos: Vector3) -> void:
	var is_local = player.has_method("get") and player.get("is_local_player") and player.is_local_player
	var marker_pos = world_to_map(player.global_position, center_pos)
	
	if marker_pos == Vector2(-1, -1):
		return  # Out of bounds
	
	var marker = ColorRect.new()
	marker.size = Vector2(12, 12) if is_local else Vector2(8, 8)
	marker.position = marker_pos - marker.size / 2
	marker.color = player_color if is_local else other_player_color
	map_container.add_child(marker)
	
	# Add label for local player
	if is_local:
		var label = Label.new()
		label.text = "You"
		label.position = marker_pos + Vector2(-15, -25)
		label.add_theme_color_override("font_color", Color.WHITE)
		map_container.add_child(label)

func draw_enemy_marker(enemy: Node3D, center_pos: Vector3) -> void:
	var marker_pos = world_to_map(enemy.global_position, center_pos)
	
	if marker_pos == Vector2(-1, -1):
		return  # Out of bounds
	
	var marker = ColorRect.new()
	marker.size = Vector2(6, 6)
	marker.position = marker_pos - marker.size / 2
	marker.color = enemy_color
	map_container.add_child(marker)

func draw_npc_marker(npc: Node3D, center_pos: Vector3, quest_marker: String = "") -> void:
	var marker_pos = world_to_map(npc.global_position, center_pos)
	
	if marker_pos == Vector2(-1, -1):
		return  # Out of bounds
	
	# Only draw background marker if there's no quest marker
	if quest_marker == "":
		var marker = ColorRect.new()
		marker.size = Vector2(10, 10)
		marker.position = marker_pos - marker.size / 2
		marker.color = npc_color
		map_container.add_child(marker)
	
	# Add label (quest marker or NPC text)
	var label = Label.new()
	var label_text = "NPC"
	if quest_marker == "!":
		label_text = "!"
		label.add_theme_color_override("font_color", Color.YELLOW)
	elif quest_marker == "?":
		label_text = "?"
		label.add_theme_color_override("font_color", Color.YELLOW)
	else:
		label.add_theme_color_override("font_color", npc_color)
	
	label.text = label_text
	label.position = marker_pos + Vector2(-6, -8) if quest_marker else Vector2(-12, -20)
	label.add_theme_font_size_override("font_size", 20 if quest_marker else 10)
	map_container.add_child(label)

func world_to_map(world_pos: Vector3, center_pos: Vector3) -> Vector2:
	# Convert 3D world position to 2D map coordinates
	var relative_pos = Vector2(world_pos.x - center_pos.x, world_pos.z - center_pos.z)
	
	# Check if within world_size bounds
	if relative_pos.length() > world_size:
		return Vector2(-1, -1)  # Out of bounds marker
	
	# Map to screen coordinates (center of map)
	var map_center = map_size / 2
	var scale = map_size.x / (world_size * 2)
	
	var screen_pos = map_center + relative_pos * scale
	return screen_pos
