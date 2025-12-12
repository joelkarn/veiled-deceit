extends Control

# Minimap settings
@export var minimap_size: Vector2 = Vector2(200, 200)  # Size of the minimap UI
@export var world_size: float = 50.0  # How much of the world to show (radius from player)
@export var update_interval: float = 0.1  # How often to update minimap (seconds)

# Colors for markers
@export var player_color: Color = Color.GREEN
@export var other_player_color: Color = Color.CYAN
@export var enemy_color: Color = Color.RED
@export var npc_color: Color = Color.YELLOW

# References
var local_player: Node3D = null
var update_timer: float = 0.0

# UI nodes
@onready var minimap_panel: Panel = $MinimapPanel
@onready var minimap_container: Control = $MinimapPanel/MinimapContainer

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	minimap_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	minimap_container.mouse_filter = Control.MOUSE_FILTER_IGNORE

func _process(delta: float) -> void:
	update_timer += delta
	if update_timer >= update_interval:
		update_timer = 0.0
		update_minimap()

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

func update_minimap() -> void:
	if not local_player:
		find_local_player()
		if not local_player:
			return
	
	# Clear previous markers
	for child in minimap_container.get_children():
		child.queue_free()
	
	var player_pos = local_player.global_position
	
	# Draw enemies first (bottom layer)
	var enemies = get_tree().get_nodes_in_group("enemies")
	for enemy in enemies:
		if is_instance_valid(enemy) and enemy is Node3D:
			draw_enemy_marker(enemy, player_pos)
	
	# Draw players next (middle layer)
	var scene = get_tree().current_scene
	if scene:
		for child in scene.get_children():
			if child.name.begins_with("Player_"):
				draw_player_marker(child, player_pos)
	
	# Draw NPCs last (top layer - so quest markers appear above players)
	if scene:
		for child in scene.get_children():
			if child.name.begins_with("AngelNPC") or "NPC" in child.name:
				# Check if NPC has a quest marker
				var marker_type = ""
				if child.has_method("get_quest_marker_for_local_player"):
					marker_type = child.get_quest_marker_for_local_player()
				draw_npc_marker(child, player_pos, marker_type)

func draw_player_marker(player: Node3D, center_pos: Vector3) -> void:
	var is_local = player.has_method("get") and player.get("is_local_player") and player.is_local_player
	var marker_pos = world_to_minimap(player.global_position, center_pos)
	
	if marker_pos == Vector2(-1, -1):
		return  # Out of bounds
	
	var marker = ColorRect.new()
	marker.size = Vector2(6, 6) if is_local else Vector2(4, 4)
	marker.position = marker_pos - marker.size / 2
	marker.color = player_color if is_local else other_player_color
	minimap_container.add_child(marker)

func draw_enemy_marker(enemy: Node3D, center_pos: Vector3) -> void:
	var marker_pos = world_to_minimap(enemy.global_position, center_pos)
	
	if marker_pos == Vector2(-1, -1):
		return  # Out of bounds
	
	var marker = ColorRect.new()
	marker.size = Vector2(3, 3)
	marker.position = marker_pos - marker.size / 2
	marker.color = enemy_color
	minimap_container.add_child(marker)

func draw_npc_marker(npc: Node3D, center_pos: Vector3, quest_marker: String = "") -> void:
	var marker_pos = world_to_minimap(npc.global_position, center_pos)
	
	if marker_pos == Vector2(-1, -1):
		return  # Out of bounds
	
	# Draw quest marker as text if available
	if quest_marker == "!" or quest_marker == "?":
		var label = Label.new()
		label.text = quest_marker
		label.position = marker_pos + Vector2(-4, -6)
		label.add_theme_color_override("font_color", Color.YELLOW)
		label.add_theme_font_size_override("font_size", 12)
		minimap_container.add_child(label)
	else:
		# Draw normal NPC marker
		var marker = ColorRect.new()
		marker.size = Vector2(5, 5)
		marker.position = marker_pos - marker.size / 2
		marker.color = npc_color
		minimap_container.add_child(marker)

func world_to_minimap(world_pos: Vector3, center_pos: Vector3) -> Vector2:
	# Convert 3D world position to 2D minimap coordinates
	var relative_pos = Vector2(world_pos.x - center_pos.x, world_pos.z - center_pos.z)
	
	# Check if within world_size bounds
	if relative_pos.length() > world_size:
		return Vector2(-1, -1)  # Out of bounds marker
	
	# Map to screen coordinates (center of minimap)
	var minimap_center = minimap_size / 2
	var scale = minimap_size.x / (world_size * 2)
	
	var screen_pos = minimap_center + relative_pos * scale
	return screen_pos
