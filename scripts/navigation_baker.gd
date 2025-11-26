extends NavigationRegion3D

func _ready():
	# Wait for the scene to be fully loaded
	await get_tree().process_frame

	# Only bake if navigation_mesh is assigned in the editor
	if navigation_mesh:
		bake_navigation_mesh()
		print("Navigation mesh baked successfully!")
