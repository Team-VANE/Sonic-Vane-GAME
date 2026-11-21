@tool
extends Node3D

var character_id: StringName
var cue_profile: Resource
var animation_player: AnimationPlayer


func get_cutscene_character_id() -> StringName:
	return character_id


func get_cutscene_profile() -> Resource:
	return cue_profile


func get_cutscene_animation_player() -> AnimationPlayer:
	return animation_player
