class_name LMEntityDefinitionProp extends Resource

@export var name: String
@export var type: String
@export var description: String
@export var default_value: Variant
@export var choices: LMChoicesProvider


static func source(p_name: String, p_desc := "") -> LMEntityDefinitionProp:
	var p := LMEntityDefinitionProp.new()
	p.name = p_name
	p.type = "source"
	p.description = p_desc
	return p


static func dest(p_name: String, p_desc := "") -> LMEntityDefinitionProp:
	var p := LMEntityDefinitionProp.new()
	p.name = p_name
	p.type = "destination"
	p.description = p_desc
	return p


static func bare(p_name: String, p_desc := "") -> LMEntityDefinitionProp:
	var p := LMEntityDefinitionProp.new()
	p.name = p_name
	p.description = p_desc
	return p


static func with_choices(p_name: String, p_choices: LMChoicesProvider, p_desc := "") -> LMEntityDefinitionProp:
	var p := LMEntityDefinitionProp.new()
	p.name = p_name
	p.type = "choices"
	p.choices = p_choices
	p.description = p_desc
	return p


static func with_multi_choices(p_name: String, p_choices: LMChoicesProvider, p_desc := "") -> LMEntityDefinitionProp:
	var p := LMEntityDefinitionProp.new()
	p.name = p_name
	p.type = "multi_choices"
	p.choices = p_choices
	p.description = p_desc
	return p
