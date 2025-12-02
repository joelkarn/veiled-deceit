extends Resource
class_name ConstellationData

## Defines a constellation pattern with star positions and connections

@export var constellation_name: String = ""
@export var star_positions: Array[Vector3] = []  # Relative positions from center
@export var connections: Array[Vector2i] = []  # Pairs of star indices to connect
@export var radius: float = 0.2  # Detection radius in sky space
@export var description: String = ""  # Lore text when discovered
