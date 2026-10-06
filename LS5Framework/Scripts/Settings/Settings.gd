extends Node

const CONFIG_PATH := "user://settings.cfg"

# --- Graphics toggles ---
var ssr_enabled: bool = true
var ssao_enabled: bool = true
var ssil_enabled: bool = true
var sdfgi_enabled: bool = true
var glow_enabled: bool = true
var shadows_enabled: bool = true  # global "prefer shadows on lights"

# --- Resolution ---
var window_size: Vector2i = Vector2i(1280, 720)

func _ready() -> void:
	load_settings()


func load_settings() -> void:
	var cfg: ConfigFile = ConfigFile.new()
	var err: Error = cfg.load(CONFIG_PATH)
	if err != OK:
		return

	ssr_enabled = _get_bool_value(cfg, "graphics", "ssr_enabled", ssr_enabled)
	ssao_enabled = _get_bool_value(cfg, "graphics", "ssao_enabled", ssao_enabled)
	ssil_enabled = _get_bool_value(cfg, "graphics", "ssil_enabled", ssil_enabled)
	sdfgi_enabled = _get_bool_value(cfg, "graphics", "sdfgi_enabled", sdfgi_enabled)
	glow_enabled = _get_bool_value(cfg, "graphics", "glow_enabled", glow_enabled)
	shadows_enabled = _get_bool_value(cfg, "graphics", "shadows_enabled", shadows_enabled)

	var w: int = _get_int_value(cfg, "video", "width", window_size.x)
	var h: int = _get_int_value(cfg, "video", "height", window_size.y)
	w = max(w, 1)
	h = max(h, 1)
	window_size = Vector2i(w, h)


func _get_bool_value(cfg: ConfigFile, section: String, key: String, default_value: bool) -> bool:
	var value: Variant = cfg.get_value(section, key, default_value)
	return value if value is bool else default_value


func _get_int_value(cfg: ConfigFile, section: String, key: String, default_value: int) -> int:
	var value: Variant = cfg.get_value(section, key, default_value)
	if value is int or value is float:
		var numeric_value: float = float(value)
		if is_finite(numeric_value):
			return int(numeric_value)
	return default_value


func save_settings() -> void:
	var cfg: ConfigFile = ConfigFile.new()
	var load_error: Error = cfg.load(CONFIG_PATH)
	if load_error != OK:
		cfg = ConfigFile.new()

	cfg.set_value("graphics", "ssr_enabled",     ssr_enabled)
	cfg.set_value("graphics", "ssao_enabled",    ssao_enabled)
	cfg.set_value("graphics", "ssil_enabled",    ssil_enabled)
	cfg.set_value("graphics", "sdfgi_enabled",   sdfgi_enabled)
	cfg.set_value("graphics", "glow_enabled",    glow_enabled)
	cfg.set_value("graphics", "shadows_enabled", shadows_enabled)

	cfg.set_value("video", "width",  window_size.x)
	cfg.set_value("video", "height", window_size.y)

	var save_error: Error = cfg.save(CONFIG_PATH)
	if save_error != OK:
		push_warning("Settings: failed to save settings.cfg: %s" % error_string(save_error))


func apply_to_world_environment(world_env: WorldEnvironment) -> void:
	if world_env == null or world_env.environment == null:
		return

	var env := world_env.environment

	# These names map to Environment resource properties in Godot 4.x
	env.ss_reflections_enabled = ssr_enabled
	env.ssao_enabled           = ssao_enabled
	env.ssil_enabled           = ssil_enabled
	env.sdfgi_enabled          = sdfgi_enabled
	env.glow_enabled           = glow_enabled


func apply_shadows_to_lights(root: Node) -> void:
	# Optional helper: call this in your level scene to turn all lights' shadows on/off
	for child in root.get_children():
		if child is DirectionalLight3D or child is OmniLight3D or child is SpotLight3D:
			child.shadow_enabled = shadows_enabled
		if child is Node:
			apply_shadows_to_lights(child)


func apply_resolution() -> void:
	DisplayServer.window_set_size(window_size)
