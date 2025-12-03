extends InteractableBase

## Ancient obelisk that points to a constellation
## Completing the witch's quest requires interacting with it

@export var target_constellation_index: int = -1  # Which constellation this obelisk points to
var constellation_manager: Node = null

func _ready() -> void:
	super._ready()
	interact_prompt = "Press E to examine the obelisk"

	# Find constellation manager (it's a sibling of the map node)
	var world_node = get_tree().current_scene
	if world_node:
		constellation_manager = world_node.get_node_or_null("ConstellationManager")

	if not constellation_manager:
		print("[Obelisk] ERROR: Could not find ConstellationManager!")

	# Wait for target to be set by spawner (server will assign it)
	if target_constellation_index >= 0:
		call_deferred("_align_to_constellation")

func _align_to_constellation() -> void:
	if not constellation_manager or target_constellation_index < 0:
		print("[Obelisk] Cannot align: manager=", constellation_manager != null, " index=", target_constellation_index)
		return

	if target_constellation_index >= constellation_manager.constellation_positions.size():
		print("[Obelisk] ERROR: Index out of bounds")
		return

	# Get the direction to the constellation (normalized direction on unit sphere)
	var constellation_dir = constellation_manager.constellation_positions[target_constellation_index].normalized()
	print("[Obelisk] Constellation direction: ", constellation_dir)

	# Get constellation name for debugging
	var constellation_name = constellation_manager.get_constellation_name(target_constellation_index)
	print("[Obelisk] Aligning to constellation: ", constellation_name)

	# Point the obelisk directly at the constellation in the sky
	# The obelisk's local up axis should point toward the constellation
	var obelisk_tip_position = global_position + Vector3.UP * 4.0  # Tip is about 4 units up
	var target_point = obelisk_tip_position + constellation_dir * 100.0  # Point far in that direction

	# Make the obelisk look at the constellation point
	look_at(target_point, Vector3.UP)

	# The obelisk is now rotated, but we need to tilt it so the top points at the constellation
	# Rotate 90 degrees so the top (not front) points at target
	rotate_object_local(Vector3.RIGHT, -deg_to_rad(90))

	print("[Obelisk] Aligned! Rotation: ", rotation_degrees)

func interact(player: Node) -> void:
	super.interact(player)

	# Only process on server (clients send request via RPC)
	if not multiplayer.is_server():
		return

	# Check if player is witch
	if player.player_name != "Witch":
		# Show generic message for non-witch players
		print("[Obelisk] Only the witch can decipher this ancient structure")
		return

	# Get quest manager (use autoload)
	if not QuestManager:
		print("[Obelisk] ERROR: Could not find QuestManager")
		return

	# Complete the quest for the witch player
	var witch_player_id = player.get("player_id")
	var quest = QuestManager.get_quest("find_obelisk", witch_player_id)
	print("[Obelisk] Quest lookup result: ", quest, " is_completed=", quest.is_completed if quest else "N/A")
	if quest and not quest.is_completed:
		print("[Obelisk] Adding quest progress...")
		QuestManager.add_quest_progress("find_obelisk", 1, witch_player_id)
		print("[Obelisk] Quest completed! The obelisk reveals its secrets to the witch.")

		# Optional: Show which constellation it points to
		if constellation_manager and target_constellation_index >= 0:
			var constellation_name = constellation_manager.get_constellation_name(target_constellation_index)
			print("[Obelisk] The obelisk points to: ", constellation_name)
	else:
		if not quest:
			print("[Obelisk] Quest not found in QuestManager!")
		else:
			print("[Obelisk] You've already discovered this obelisk's secrets.")
