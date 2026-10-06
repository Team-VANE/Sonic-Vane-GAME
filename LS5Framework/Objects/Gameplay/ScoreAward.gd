extends Node
class_name ScoreAward

signal score_awarded(recipient: Node, amount: int)
signal score_award_failed(recipient: Node, amount: int)

## Enables score awards from this component.
@export var enabled: bool = true
## Default score granted when no amount override is supplied.
@export_range(0, 1000000, 1, "or_greater") var score_amount: int = 100
## Prevents this component from awarding score more than once before it is reset.
@export var one_shot: bool = true

var _awarded: bool = false


func award(recipient: Node, amount_override: int = -1) -> bool:
	if not enabled or (one_shot and _awarded):
		return false
	var amount: int = score_amount if amount_override < 0 else amount_override
	if amount <= 0:
		return false
	var score_recipient: Node = _resolve_score_recipient(recipient)
	if not score_recipient:
		score_award_failed.emit(recipient, amount)
		return false
	score_recipient.call("add_score", amount)
	if one_shot:
		_awarded = true
	score_awarded.emit(score_recipient, amount)
	return true


func reset_award() -> void:
	_awarded = false


func has_awarded() -> bool:
	return _awarded


func _resolve_score_recipient(recipient: Node) -> Node:
	var pending: Array[Node] = []
	var visited: Dictionary = {}
	if recipient:
		pending.append(recipient)
	while not pending.is_empty():
		var current: Node = pending.pop_front() as Node
		var instance_id: int = current.get_instance_id()
		if visited.has(instance_id):
			continue
		visited[instance_id] = true
		if current.has_method("add_score"):
			return current
		if current.has_method("get_score_award_recipient"):
			var resolved_value: Variant = current.call("get_score_award_recipient")
			if resolved_value is Node and resolved_value != current:
				pending.append(resolved_value as Node)
		if current.has_meta(&"score_award_recipient"):
			var metadata_value: Variant = current.get_meta(&"score_award_recipient")
			if metadata_value is Node and metadata_value != current:
				pending.append(metadata_value as Node)
		var parent: Node = current.get_parent()
		if parent:
			pending.append(parent)
	return null
