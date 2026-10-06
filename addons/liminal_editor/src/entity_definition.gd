@icon("res://addons/liminal_editor/icons/icon_entity_def.svg")
class_name LMEntityDefinition extends Resource

@export var entity_name: String
@export var description: String
@export var identifier: String
@export var properties: Array[LMEntityDefinitionProp]
@export var gizmos: Array[LMEntityGizmoDef]
@export var has_volume: bool
