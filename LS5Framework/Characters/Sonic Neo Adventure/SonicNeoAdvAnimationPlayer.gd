extends AnimationPlayer

const LEGACY_ARMATURE: String = "Armature/"
const SCALED_RIG: String = "Sonic Game Scale/"

static var _bound_libraries: Dictionary[AnimationLibrary, AnimationLibrary] = {}


func _enter_tree() -> void:
	var animation_root: Node = get_node_or_null(root_node)
	if not animation_root or not animation_root.has_node(SCALED_RIG + "Armature/Skeleton3D"):
		return
	for library_name: StringName in get_animation_library_list():
		var library: AnimationLibrary = get_animation_library(library_name)
		if not _bound_libraries.has(library):
			_bound_libraries[library] = _bind_library(library)
		var bound: AnimationLibrary = _bound_libraries[library]
		if bound != library:
			remove_animation_library(library_name)
			add_animation_library(library_name, bound)


func _bind_library(library: AnimationLibrary) -> AnimationLibrary:
	var bound: AnimationLibrary = null
	for animation_name: StringName in library.get_animation_list():
		var animation: Animation = library.get_animation(animation_name)
		var updated: Animation = null
		for track: int in range(animation.get_track_count()):
			var path: String = String(animation.track_get_path(track))
			if not path.begins_with(LEGACY_ARMATURE):
				continue
			if not updated:
				updated = animation.duplicate() as Animation
			updated.track_set_path(track, NodePath(SCALED_RIG + path))
		if updated:
			if not bound:
				bound = library.duplicate() as AnimationLibrary
			bound.remove_animation(animation_name)
			bound.add_animation(animation_name, updated)
	return bound if bound else library
