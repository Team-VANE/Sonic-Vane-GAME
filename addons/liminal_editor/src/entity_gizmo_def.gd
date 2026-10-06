class_name LMEntityGizmoDef extends Resource

@export var type: String
@export var radius: String
@export var length: String
@export var angle: String
@export var fov: String
@export var near: String
@export var far: String
@export var size: String
@export var size_x: String
@export var size_y: String
@export var size_z: String
@export var icon: String
@export var text: String
@export var color: String
@export var style: String
@export var alpha: String
@export var offset: String
@export var euler: String
@export var mode: String
@export var closed: String
@export var bindings: Dictionary = {}



func bind(field: String, prop: String) -> LMEntityGizmoDef:
	bindings[field] = prop
	return self


func filled(p_alpha := "") -> LMEntityGizmoDef:
	style = "solid"
	alpha = p_alpha
	return self



static func sphere(p_radius := "") -> LMEntityGizmoDef:
	var g := LMEntityGizmoDef.new()
	g.type = "sphere"
	g.radius = p_radius
	return g


static func arrow(p_length := "") -> LMEntityGizmoDef:
	var g := LMEntityGizmoDef.new()
	g.type = "arrow"
	g.length = p_length
	return g


static func cone(p_length := "", p_angle := "") -> LMEntityGizmoDef:
	var g := LMEntityGizmoDef.new()
	g.type = "cone"
	g.length = p_length
	g.angle = p_angle
	return g


static func box(p_size := "") -> LMEntityGizmoDef:
	var g := LMEntityGizmoDef.new()
	g.type = "box"
	g.size = p_size
	return g


static func frustum(p_fov := "", p_near := "", p_far := "") -> LMEntityGizmoDef:
	var g := LMEntityGizmoDef.new()
	g.type = "frustum"
	g.fov = p_fov
	g.near = p_near
	g.far = p_far
	return g


static func billboard(p_size := "") -> LMEntityGizmoDef:
	var g := LMEntityGizmoDef.new()
	g.type = "billboard"
	g.size = p_size
	return g


static func path_gizmo(p_mode := "", p_closed := "") -> LMEntityGizmoDef:
	var g := LMEntityGizmoDef.new()
	g.type = "path"
	g.mode = p_mode
	g.closed = p_closed
	return g


static func text_gizmo(p_text := "") -> LMEntityGizmoDef:
	var g := LMEntityGizmoDef.new()
	g.type = "text"
	g.text = p_text
	return g
