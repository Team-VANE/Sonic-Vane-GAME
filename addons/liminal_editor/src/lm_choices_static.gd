@tool
class_name LMChoicesStatic extends LMChoicesProvider

@export var items: Dictionary

func get_choices() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for label in items:
		result.append({"label": label, "value": items[label]})
	return result

