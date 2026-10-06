class_name CharacterAbility
extends CharacterAction

@export_group("Ability")
@export_subgroup("Input Slot")
## Generic input slot used when the character profile does not override this ability.
@export var slot_id: StringName = &"ability_slot_01"
## Legacy numeric slot retained for older character scenes.
@export var slot_index: int = 0


func _on_action_initialized() -> void:
	if input_action == &"":
		input_action = slot_id


func on_action_pressed() -> void:
	execute({"reason": &"input"})


func physics_update(delta: float) -> void:
	physics_update_action(delta)


func process_input_event(input_name: StringName, mode: ActionTrigger) -> bool:
	if should_trigger_from_input(input_name, mode):
		on_action_pressed()
		return true
	return false
