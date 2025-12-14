@tool
extends Label3D

## Alchemy text label that glows when light is nearby
## Similar to holy symbols but for esoteric alchemy writings

@export_group("Text Selection")
@export var randomize_text: bool = true  ## Pick random text on game start
@export var random_rotation: bool = true  ## Randomly rotate text slightly

@export_group("Light Detection")
@export var detection_range: float = 15.0
@export var max_brightness: float = 3.0
@export var fade_speed: float = 2.0

# Alchemy texts with mystical formulas and phrases
const ALCHEMY_TEXTS = [
	"SOLVE ET COAGULA",      # Dissolve and coagulate
	"V.I.T.R.I.O.L",         # Visita Interiora Terrae
	"AS ABOVE SO BELOW",     # Hermetic principle
	"PRIMA MATERIA",         # First matter
	"OPUS MAGNUM",           # Great work
	"AZOTH",                 # Universal solvent
	"PHILOSOPHER'S STONE",   # Ultimate goal
	"TRANSMUTATION",         # Transformation
	"CAPUT MORTUUM",         # Death's head
	"ALBEDO",                # Whitening stage
	"RUBEDO",                # Reddening stage
	"NIGREDO",               # Blackening stage
	"QUINTESSENCE",          # Fifth element
	"ELIXIR VITAE",          # Elixir of life
	"MERCURIUS",             # Mercury principle
	"SULFUR ET SAL",         # Sulfur and salt
	"IGNIS ET AQUA",         # Fire and water
	"ANIMA MUNDI",           # World soul
	"SPIRITUS MUNDI",        # Spirit of the world
	"CORPUS",                # Body
	"ANIMA",                 # Soul
	"SPIRITUS",              # Spirit
	"MATERIA PRIMA",         # Primal matter
	"LAPIS PHILOSOPHORUM",   # Philosophers stone (Latin)
	"MAGNUM OPUS",           # Great work (alternate)
	"AURUM POTABILE",        # Drinkable gold
	"CHRYSOPOEIA",           # Gold making
	"AQUA REGIA",            # Royal water
	"AQUA VITAE",            # Water of life
	"ARBOR PHILOSOPHICA",    # Philosophical tree
	"CAUDA PAVONIS",         # Peacock's tail
	"CIRCULATUM",            # Circulation
	"MORTIFICATIO",          # Death/putrefaction
	"SEPARATIO",             # Separation
	"CONJUNCTIO",            # Conjunction
	"PUTREFACTIO",           # Putrefaction
	"CALCINATIO",            # Calcination
	"SUBLIMATIO",            # Sublimation
	"FERMENTATIO",           # Fermentation
	"MULTIPLICATIO",         # Multiplication
	"PROJECTIO",             # Projection
	"OPUS CIRCULATORIUM",    # Circular work
	"REBIS",                 # Two things
	"LUNA ET SOL",           # Moon and sun
	"REX ET REGINA",         # King and queen
	"SERPENS",               # Serpent
	"OUROBOROS",             # Tail-eating serpent
	"CHAOS",                 # Primordial chaos
	"VITRIOLUM",             # Vitriol
	"ALKAHEST",              # Universal solvent
	"TINCTURA",              # Tincture
	"ELIXIR",                # Elixir
	"ARCANUM",               # Secret
	"HERMES TRISMEGISTUS",   # Thrice-great Hermes
	"TABULA SMARAGDINA",     # Emerald tablet
	"OPUS ALCHYMICUM",       # Alchemical work
	"MYSTERIUM MAGNUM",      # Great mystery
]

var current_brightness: float = 0.0
var update_timer: float = 0.0
var update_interval: float = 0.1
var selected_text: String = ""
var text_index: int = -1  # Specific text index to use (-1 = random)

func _ready() -> void:
	# In editor, show placeholder
	if Engine.is_editor_hint():
		if text == "":
			text = "ALCHEMY TEXT"
		modulate = Color(1.0, 1.0, 1.0, 1.0)
		return

	# In game, randomize if enabled or use specific index
	if randomize_text:
		if text_index >= 0 and text_index < ALCHEMY_TEXTS.size():
			# Use specific text from CaveMysteryManager
			selected_text = ALCHEMY_TEXTS[text_index]
		else:
			# Random text
			selected_text = ALCHEMY_TEXTS[randi() % ALCHEMY_TEXTS.size()]
		text = selected_text
		print("Alchemy text set to: ", selected_text)

	# Apply random rotation if enabled
	if random_rotation:
		var random_angle = randf_range(-15.0, 15.0)  # Rotate ±15 degrees
		rotate_z(deg_to_rad(random_angle))

	# Set up glowing material (pure white like symbols)
	modulate = Color(1.0, 1.0, 1.0, 0.0)  # Pure white, start invisible

func set_text_index(index: int) -> void:
	"""Set a specific text index (must be called before _ready)"""
	text_index = index

func _process(delta: float) -> void:
	# Skip light detection in editor
	if Engine.is_editor_hint():
		return

	# Update less frequently for performance
	update_timer += delta
	if update_timer < update_interval:
		return

	update_timer = 0.0

	var target_brightness = 0.0
	var nearest_light_distance = _find_nearest_light_distance()

	if nearest_light_distance <= detection_range:
		var distance_factor = 1.0 - (nearest_light_distance / detection_range)
		distance_factor = pow(distance_factor, 0.7)
		target_brightness = max_brightness * distance_factor

	# Smoothly transition brightness
	current_brightness = lerp(current_brightness, target_brightness, fade_speed * delta * 10.0)
	var alpha = clamp(current_brightness * 0.5, 0.0, 1.0)
	modulate.a = alpha
	outline_modulate.a = alpha * 0.8  # Outline slightly less visible

func _find_nearest_light_distance() -> float:
	var nearest = detection_range + 1.0
	nearest = _find_lights_recursive(get_tree().root, nearest)
	return nearest

func _find_lights_recursive(node: Node, current_nearest: float) -> float:
	if node is OmniLight3D and node.visible and node.light_energy > 0.5:
		var distance = global_position.distance_to(node.global_position)
		if distance < current_nearest:
			current_nearest = distance

	for child in node.get_children():
		var child_nearest = _find_lights_recursive(child, current_nearest)
		if child_nearest < current_nearest:
			current_nearest = child_nearest

	return current_nearest
