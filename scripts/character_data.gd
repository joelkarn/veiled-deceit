extends Resource
class_name CharacterData

## Defines a playable character (Witch, Hunter, Knight)

@export var character_name: String = ""
@export var description: String = ""
@export var color: Color = Color.WHITE  # Visual identifier for character selection UI
# Future: Add model/texture/animation references when you have character-specific visuals
# @export var character_model: PackedScene
# @export var character_texture: Texture2D
