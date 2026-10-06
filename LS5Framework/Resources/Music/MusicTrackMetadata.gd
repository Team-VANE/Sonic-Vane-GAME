extends Resource
class_name MusicTrackMetadata

## Audio stream described by this metadata entry.
@export var stream: AudioStream
## Display title used instead of the audio filename.
@export var title: String = ""
## Artist or author displayed beneath the title.
@export var author: String = ""
## BPM override. Negative values use BPM stored on the audio stream.
@export_range(-1.0, 1000.0, 0.01, "or_greater", "suffix:BPM") var bpm_override: float = -1.0


func matches_stream(target_stream: AudioStream) -> bool:
	if stream == null or target_stream == null:
		return false
	if stream == target_stream:
		return true
	var configured_path: String = _get_stream_source_path(stream)
	var target_path: String = _get_stream_source_path(target_stream)
	return configured_path != "" and configured_path == target_path


func _get_stream_source_path(target_stream: AudioStream) -> String:
	if target_stream.has_meta(&"source_resource_path"):
		var source_path: String = String(target_stream.get_meta(&"source_resource_path", ""))
		if source_path != "":
			return source_path
	return target_stream.resource_path
