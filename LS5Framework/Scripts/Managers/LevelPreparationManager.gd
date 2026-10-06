extends Node

signal level_preparation_started(generation: int, scene_path: String)
signal level_preparation_completed(generation: int, scene_path: String)
signal level_preparation_failed(generation: int, scene_path: String, reason: String)
signal runtime_cache_miss(resource_path: String, consumer: StringName, generation: int)

const SCOPE_CORE: StringName = &"core"
const SCOPE_CHARACTER: StringName = &"character"
const SCOPE_LEVEL: StringName = &"level"
const SCOPE_LOOKAHEAD: StringName = &"lookahead"
const CACHE_SETTING_PATH: StringName = &"ls5/loading/preparation_cache_enabled"

enum PreparationState {
	IDLE,
	LOADING_RESOURCES,
	INITIALIZING,
	READY,
	FAILED
}

var _scopes: Dictionary = {
	SCOPE_CORE: {},
	SCOPE_CHARACTER: {},
	SCOPE_LEVEL: {},
	SCOPE_LOOKAHEAD: {}
}
var _generation: int = 0
var _target_scene_path: String = ""
var _state: int = PreparationState.IDLE
var _failure_reason: String = ""
var _required_resources: Dictionary = {}
var _completed_resources: Dictionary = {}
var _failed_resources: Dictionary = {}
var _character_manifest_signature: String = ""
var _runtime_cache_misses: Dictionary = {}


func is_cache_enabled() -> bool:
	return bool(ProjectSettings.get_setting(CACHE_SETTING_PATH, false))


func begin_level_preparation(scene_path: String) -> int:
	_generation += 1
	_target_scene_path = scene_path.strip_edges()
	_state = PreparationState.LOADING_RESOURCES
	_failure_reason = ""
	_required_resources.clear()
	_completed_resources.clear()
	_failed_resources.clear()
	_runtime_cache_misses.clear()
	release_scope(SCOPE_LEVEL)
	release_scope(SCOPE_LOOKAHEAD)
	if not is_cache_enabled():
		release_scope(SCOPE_CORE)
		release_scope(SCOPE_CHARACTER)
		_character_manifest_signature = ""
	level_preparation_started.emit(_generation, _target_scene_path)
	return _generation


func register_required_resource(resource_path: String, scope: StringName, generation: int) -> bool:
	if not is_cache_enabled():
		return false
	var normalized_path: String = resource_path.strip_edges()
	if normalized_path == "" or not _accepts_generation(scope, generation):
		return false
	_required_resources[normalized_path] = scope
	return true


func store_resource(
		resource_path: String,
		resource: Resource,
		scope: StringName,
		generation: int = -1
	) -> bool:
	if not is_cache_enabled():
		return false
	var normalized_path: String = resource_path.strip_edges()
	if normalized_path == "" or resource == null or not _is_valid_scope(scope):
		return false
	if not _accepts_generation(scope, generation):
		return false
	var scope_cache: Dictionary = _scopes.get(scope, {})
	scope_cache[normalized_path] = resource
	_scopes[scope] = scope_cache
	if generation == _generation:
		_completed_resources[normalized_path] = true
	return true


func mark_resource_failed(resource_path: String, error_message: String, generation: int) -> void:
	if generation != _generation:
		return
	var normalized_path: String = resource_path.strip_edges()
	if normalized_path == "":
		return
	_failed_resources[normalized_path] = error_message


func finish_resource_loading(generation: int) -> bool:
	if generation != _generation:
		return false
	if _state == PreparationState.READY:
		return true
	if _state != PreparationState.LOADING_RESOURCES and _state != PreparationState.INITIALIZING:
		return false
	if not _failed_resources.is_empty():
		var failed_path: String = String(_failed_resources.keys()[0])
		fail_level_preparation(
			generation,
			"Resource failed to load: %s (%s)" % [failed_path, String(_failed_resources[failed_path])]
		)
		return false
	for resource_value: Variant in _required_resources.keys():
		var resource_path: String = String(resource_value)
		if not _completed_resources.has(resource_path):
			fail_level_preparation(generation, "Required resource did not load: %s" % resource_path)
			return false
	_state = PreparationState.INITIALIZING
	return true


func load_resources_threaded(
		resource_paths: Array[String],
		scope: StringName,
		generation: int
	) -> bool:
	if not is_cache_enabled():
		return true
	if generation != _generation or not _is_valid_scope(scope):
		return false
	if _state != PreparationState.LOADING_RESOURCES and _state != PreparationState.INITIALIZING:
		return false
	var pending: Dictionary = {}
	# Finish each root before requesting another graph with shared dependencies.
	for resource_path: String in resource_paths:
		if generation != _generation:
			return false
		var normalized_path: String = resource_path.strip_edges()
		if normalized_path == "" or pending.has(normalized_path):
			continue
		register_required_resource(normalized_path, scope, generation)
		var retained_resource: Resource = get_resource(normalized_path, scope)
		if retained_resource != null:
			store_resource(normalized_path, retained_resource, scope, generation)
			continue
		var request_error: Error = ResourceLoader.load_threaded_request(normalized_path)
		if request_error != OK and request_error != ERR_BUSY:
			mark_resource_failed(normalized_path, error_string(request_error), generation)
			continue
		pending[normalized_path] = true
		while not pending.is_empty():
			if generation != _generation:
				return false
			for path_value: Variant in pending.keys():
				var path: String = String(path_value)
				var status: int = ResourceLoader.load_threaded_get_status(path)
				if status == ResourceLoader.THREAD_LOAD_LOADED:
					var resource: Resource = ResourceLoader.load_threaded_get(path)
					if resource != null:
						store_resource(path, resource, scope, generation)
					else:
						mark_resource_failed(path, error_string(FAILED), generation)
					pending.erase(path)
				elif status == ResourceLoader.THREAD_LOAD_FAILED or status == ResourceLoader.THREAD_LOAD_INVALID_RESOURCE:
					mark_resource_failed(path, error_string(FAILED), generation)
					pending.erase(path)
			if not pending.is_empty():
				if get_tree() == null:
					fail_level_preparation(generation, "Resource loading stopped before completion.")
					return false
				await get_tree().process_frame
	return finish_resource_loading(generation)


func prepare_character_scope(manifest_signature: String, generation: int) -> bool:
	if not is_cache_enabled():
		return generation == _generation
	if generation != _generation:
		return false
	var normalized_signature: String = manifest_signature.strip_edges()
	if normalized_signature == _character_manifest_signature:
		return true
	release_scope(SCOPE_CHARACTER)
	_character_manifest_signature = normalized_signature
	return true


func complete_level_preparation(generation: int, scene_path: String) -> bool:
	if generation != _generation or _state != PreparationState.INITIALIZING:
		return false
	if scene_path.strip_edges() != _target_scene_path:
		fail_level_preparation(generation, "Prepared scene does not match the requested level.")
		return false
	_state = PreparationState.READY
	level_preparation_completed.emit(_generation, _target_scene_path)
	return true


func fail_level_preparation(generation: int, reason: String) -> void:
	if generation != _generation:
		return
	_state = PreparationState.FAILED
	_failure_reason = reason.strip_edges()
	level_preparation_failed.emit(_generation, _target_scene_path, _failure_reason)


func is_level_ready(scene_path: String) -> bool:
	return _state == PreparationState.READY and scene_path.strip_edges() == _target_scene_path


func get_resource(resource_path: String, preferred_scope: StringName = &"") -> Resource:
	if not is_cache_enabled():
		return null
	var normalized_path: String = resource_path.strip_edges()
	if normalized_path == "":
		return null
	if preferred_scope != &"" and _is_valid_scope(preferred_scope):
		var preferred_cache: Dictionary = _scopes.get(preferred_scope, {})
		var preferred_value: Variant = preferred_cache.get(normalized_path)
		if preferred_value is Resource:
			return preferred_value as Resource
	var scope_order: Array[StringName] = [SCOPE_LEVEL, SCOPE_CHARACTER, SCOPE_CORE, SCOPE_LOOKAHEAD]
	for scope: StringName in scope_order:
		var scope_cache: Dictionary = _scopes.get(scope, {})
		var value: Variant = scope_cache.get(normalized_path)
		if value is Resource:
			return value as Resource
	return null


func get_prepared_resource(
		resource_path: String,
		preferred_scope: StringName = &"",
		consumer: StringName = &"Runtime"
	) -> Resource:
	if not is_cache_enabled():
		return null
	var resource: Resource = get_resource(resource_path, preferred_scope)
	if resource != null or _state != PreparationState.READY:
		return resource
	var normalized_path: String = resource_path.strip_edges()
	if normalized_path == "":
		return null
	var miss_key: String = "%s|%s" % [String(consumer), normalized_path]
	var miss_count: int = int(_runtime_cache_misses.get(miss_key, 0)) + 1
	_runtime_cache_misses[miss_key] = miss_count
	if miss_count == 1:
		push_error(
			"LevelPreparationManager: runtime cache miss for %s requested by %s." % [
				normalized_path,
				String(consumer),
			]
		)
		runtime_cache_miss.emit(normalized_path, consumer, _generation)
	return null


func has_resource(resource_path: String, preferred_scope: StringName = &"") -> bool:
	return get_resource(resource_path, preferred_scope) != null


func release_scope(scope: StringName) -> void:
	if not _is_valid_scope(scope):
		return
	var scope_cache: Dictionary = _scopes.get(scope, {})
	scope_cache.clear()
	_scopes[scope] = scope_cache


func get_scope_resource_count(scope: StringName) -> int:
	if not _is_valid_scope(scope):
		return 0
	var scope_cache: Dictionary = _scopes.get(scope, {})
	return scope_cache.size()


func get_current_generation() -> int:
	return _generation


func get_target_scene_path() -> String:
	return _target_scene_path


func get_preparation_state() -> int:
	return _state


func get_failure_reason() -> String:
	return _failure_reason


func get_runtime_cache_misses() -> Dictionary:
	return _runtime_cache_misses.duplicate()


func _accepts_generation(scope: StringName, generation: int) -> bool:
	if scope == SCOPE_CORE or scope == SCOPE_CHARACTER:
		return generation < 0 or generation == _generation
	return generation == _generation


func _is_valid_scope(scope: StringName) -> bool:
	return _scopes.has(scope)
