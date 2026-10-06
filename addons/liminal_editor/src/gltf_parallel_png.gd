@tool
class_name LMGLTFParallelPNG extends GLTFDocumentExtension


const IMAGE_FORMAT := "LMParallelPNG"

static var last_encode_ms: float = 0.0

var _primed := false
var _next := 0
var _sources: Array[Image] = []
var _encoded: Array[PackedByteArray] = []

func _get_saveable_image_formats() -> PackedStringArray:
	return PackedStringArray([IMAGE_FORMAT])

func _export_preserialize(_state: GLTFState) -> Error:
	_primed = false
	_next = 0
	_sources.clear()
	_encoded.clear()
	last_encode_ms = 0.0
	return OK

func _encode_all(state: GLTFState) -> void:
	for tex in state.get_images():
		_sources.append(tex.get_image() if tex != null else null)
	_encoded.resize(_sources.size())
	if _sources.is_empty():
		return
	var t0 := Time.get_ticks_msec()
	var gid := WorkerThreadPool.add_group_task(_encode_one, _sources.size(), -1, true)
	WorkerThreadPool.wait_for_group_task_completion(gid)
	last_encode_ms = Time.get_ticks_msec() - t0

func _encode_one(i: int) -> void:
	if _sources[i] != null:
		_encoded[i] = _encode_png(_sources[i])

static func _encode_png(source: Image) -> PackedByteArray:
	var img := source
	if img.is_compressed():
		img = img.duplicate()
		if img.decompress() != OK:
			return PackedByteArray()
	return img.save_png_to_buffer()

func _serialize_image_to_bytes(state: GLTFState, image: Image, image_dict: Dictionary, _image_format: String, _lossy_quality: float) -> PackedByteArray:
	if not _primed:
		_primed = true
		_encode_all(state)
	image_dict["mimeType"] = "image/png"
	var idx := _next
	_next += 1
	if idx < _encoded.size() and not _encoded[idx].is_empty() \
			and _sources[idx].get_width() == image.get_width() \
			and _sources[idx].get_height() == image.get_height():
		return _encoded[idx]
	return _encode_png(image)

func _serialize_texture_json(_state: GLTFState, texture_json: Dictionary, gltf_texture: GLTFTexture, _image_format: String) -> Error:
	texture_json["source"] = gltf_texture.src_image
	return OK
