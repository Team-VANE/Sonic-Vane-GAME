extends SceneTree

const ADDON_PATH: String = "res://_blender/sonic_vane_placements/"
const SAMPLE_COUNT: int = 96


func _initialize() -> void:
	var catalog: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(ADDON_PATH + "catalog.json"))
	var fields: Dictionary = catalog["environment"]
	var profiles: Dictionary = {}
	for id: String in fields["sky_profile"]["options"]:
		var profile: Resource = load(fields["sky_profile"]["options"][id]["path"])
		var samples: Array[Array] = []
		for index: int in range(SAMPLE_COUNT):
			var phase: float = float(index) / SAMPLE_COUNT
			var zenith: Color = profile.call("sample_color", profile.get("zenith_color"), phase, Color(0.12, 0.38, 0.9))
			var horizon: Color = profile.call("sample_color", profile.get("horizon_color"), phase, Color(0.62, 0.78, 1.0))
			var fog: Color = profile.call("sample_color", profile.get("fog_color"), phase, Color(0.58, 0.7, 0.84))
			var density: float = profile.call("sample_value", profile.get("fog_density"), phase, 0.0002) if profile.get("fog_enabled") else 0.0
			samples.append([_rgb(zenith), _rgb(horizon), _rgb(fog), snappedf(density, 0.0000001)])
		profiles[id] = {"sun_visible": float(profile.get("sun_disk_intensity")) > 0.0, "samples": samples}
	var weather: Dictionary = {}
	for id: String in fields["starting_weather"]["options"]:
		var option: Dictionary = fields["starting_weather"]["options"][id]
		if not option.has("path"):
			continue
		var preset: Resource = load(option["path"])
		var sky: Resource = preset.get("sky_weather")
		weather[id] = [
			sky.get("cloud_coverage"), sky.get("overcast_light_multiplier"),
			sky.get("fog_density_multiplier"), sky.get("saturation_multiplier"),
		]
	var file: FileAccess = FileAccess.open(ADDON_PATH + "environment_preview_data.json", FileAccess.WRITE)
	if not file:
		push_error("Could not write the environment preview catalog.")
		quit(1)
		return
	file.store_line(JSON.stringify({"profiles": profiles, "weather": weather}, "", true))
	file.close()
	quit()


func _rgb(color: Color) -> Array[float]:
	return [snappedf(color.r, 0.0001), snappedf(color.g, 0.0001), snappedf(color.b, 0.0001)]
