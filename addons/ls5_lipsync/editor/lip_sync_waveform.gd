@tool
extends RefCounted


static func analyze(stream: AudioStream, bin_count: int = 2048) -> Dictionary:
	var result: Dictionary = {"peaks": PackedFloat32Array(), "start": 0.0, "end": stream.get_length() if stream else 0.0, "reason": "No voice audio assigned."}
	if not stream:
		return result
	if stream is AudioStreamOggVorbis or stream is AudioStreamMP3:
		return _analyze_playback(stream, bin_count)
	var decoded: AudioStreamWAV = stream as AudioStreamWAV
	if not decoded or decoded.format not in [AudioStreamWAV.FORMAT_8_BITS, AudioStreamWAV.FORMAT_16_BITS]:
		var source: String = stream.resource_path
		if not source.to_lower().ends_with(".wav") or not FileAccess.file_exists(source):
			if decoded:
				return _analyze_playback(stream, bin_count)
			result["reason"] = "Waveform unavailable: assign a WAV source with readable sample data."
			return result
		var options: Dictionary = {}
		var import_settings: ConfigFile = ConfigFile.new()
		if import_settings.load(source + ".import") == OK and import_settings.has_section("params"):
			for key: String in import_settings.get_section_keys("params"):
				options[key] = import_settings.get_value("params", key)
		options["compress/mode"] = 0
		var source_bytes: PackedByteArray = FileAccess.get_file_as_bytes(source)
		if source_bytes.size() >= 12 and source_bytes.slice(0, 4).get_string_from_ascii() == "RIFF" and source_bytes.decode_u32(4) > source_bytes.size() - 8:
			source_bytes.encode_u32(4, source_bytes.size() - 8)
		decoded = AudioStreamWAV.load_from_buffer(source_bytes, options)
	if not decoded or decoded.format not in [AudioStreamWAV.FORMAT_8_BITS, AudioStreamWAV.FORMAT_16_BITS]:
		result["reason"] = "Waveform unavailable: the WAV source could not be decoded."
		return result
	var bytes: PackedByteArray = decoded.data
	var channels: int = 2 if decoded.stereo else 1
	var sample_bytes: int = 2 if decoded.format == AudioStreamWAV.FORMAT_16_BITS else 1
	var frame_bytes: int = channels * sample_bytes
	var frame_count: int = bytes.size() / frame_bytes
	if frame_count <= 0 or stream.get_length() <= 0.0:
		result["reason"] = "Waveform unavailable: voice audio contains no sample frames."
		return result
	bin_count = clampi(bin_count, 1, frame_count)
	var peaks: PackedFloat32Array = PackedFloat32Array()
	peaks.resize(bin_count)
	for bin_index: int in range(bin_count):
		var first_frame: int = bin_index * frame_count / bin_count
		var last_frame: int = (bin_index + 1) * frame_count / bin_count
		var stride: int = maxi(1, (last_frame - first_frame) / 32)
		var peak: float = 0.0
		for frame: int in range(first_frame, last_frame, stride):
			for channel: int in range(channels):
				var offset: int = frame * frame_bytes + channel * sample_bytes
				var sample: float = absf(float(bytes.decode_s16(offset)) / 32768.0) if sample_bytes == 2 else absf(float(bytes.decode_s8(offset)) / 128.0)
				peak = maxf(peak, sample)
		peaks[bin_index] = peak
	result["peaks"] = peaks
	result["reason"] = ""
	_apply_audible_range(result, peaks, stream.get_length())
	return result


static func _analyze_playback(stream: AudioStream, bin_count: int) -> Dictionary:
	var duration: float = stream.get_length()
	var result: Dictionary = {"peaks": PackedFloat32Array(), "start": 0.0, "end": duration, "reason": "Waveform unavailable: audio could not be decoded."}
	if duration <= 0.0:
		return result
	var playback: AudioStreamPlayback = stream.instantiate_playback()
	if not playback:
		return result
	var mix_rate: float = AudioServer.get_mix_rate()
	var frame_count: int = maxi(1, ceili(duration * mix_rate))
	bin_count = clampi(bin_count, 1, frame_count)
	var peaks: PackedFloat32Array = PackedFloat32Array()
	peaks.resize(bin_count)
	var stride: int = maxi(1, frame_count / bin_count / 32)
	var decoded_frames: int = 0
	playback.start(0.0)
	while decoded_frames < frame_count:
		var frames: PackedVector2Array = playback.mix_audio(1.0, mini(4096, frame_count - decoded_frames))
		if frames.is_empty():
			break
		for index: int in range(0, frames.size(), stride):
			var bin_index: int = mini(bin_count - 1, (decoded_frames + index) * bin_count / frame_count)
			var sample: Vector2 = frames[index]
			peaks[bin_index] = maxf(peaks[bin_index], maxf(absf(sample.x), absf(sample.y)))
		decoded_frames += frames.size()
	playback.stop()
	if decoded_frames <= 0:
		return result
	result["peaks"] = peaks
	result["reason"] = ""
	_apply_audible_range(result, peaks, duration)
	return result


static func _apply_audible_range(result: Dictionary, peaks: PackedFloat32Array, duration: float) -> void:
	var maximum: float = 0.0
	for peak: float in peaks:
		maximum = maxf(maximum, peak)
	if maximum <= 0.0:
		return
	var threshold: float = maxf(0.018, maximum * 0.08)
	for index: int in range(peaks.size()):
		if peaks[index] >= threshold:
			result["start"] = float(index) / float(peaks.size()) * duration
			break
	for index: int in range(peaks.size() - 1, -1, -1):
		if peaks[index] >= threshold:
			result["end"] = float(index + 1) / float(peaks.size()) * duration
			break
