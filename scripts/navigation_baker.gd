extends NavigationRegion3D

func _ready():
	# Wait for the scene to be fully loaded
	await get_tree().process_frame
	
	# Create and configure navigation mesh if not already set
	if not navigation_mesh:
		navigation_mesh = NavigationMesh.new()
	
	# Configure navigation mesh settings
	navigation_mesh.agent_height = 2.0
	navigation_mesh.agent_radius = 0.5
	navigation_mesh.agent_max_climb = 0.5
	navigation_mesh.agent_max_slope = 45.0
	navigation_mesh.region_min_size = 2.0
	navigation_mesh.region_merge_size = 20.0
	navigation_mesh.cell_size = 0.25
	navigation_mesh.cell_height = 0.2
	
	# Bake the navigation mesh from the geometry
	bake_navigation_mesh()
	print("Navigation mesh baked successfully!")
