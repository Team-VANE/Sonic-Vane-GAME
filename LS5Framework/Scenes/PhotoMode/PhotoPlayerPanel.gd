extends ScrollContainer

const SCRUB_FPS: float = 60.0
const FACE_LAYER_COUNT: int = 3

class BodyPose extends SkeletonModifier3D:
	var pose: Dictionary = {}

	func _process_modification_with_delta(_delta: float) -> void:
		var skeleton: Skeleton3D = get_skeleton()
		for bone: int in pose:
			var values: Dictionary = pose[bone]
			if values.has(Animation.TYPE_POSITION_3D):
				skeleton.set_bone_pose_position(bone, values[Animation.TYPE_POSITION_3D])
			if values.has(Animation.TYPE_ROTATION_3D):
				skeleton.set_bone_pose_rotation(bone, values[Animation.TYPE_ROTATION_3D])
			if values.has(Animation.TYPE_SCALE_3D):
				skeleton.set_bone_pose_scale(bone, values[Animation.TYPE_SCALE_3D])


## Tracks the photo camera while enabled.
@onready var _face_camera: CheckButton = %FaceCamera
## Clears the tracked gaze and returns to the authored eye and head pose.
@onready var _reset_gaze: Button = %ResetGaze
## Selects a skeletal animation from the current player's library.
@onready var _body_animation: OptionButton = %BodyAnimation
## Scrubs the selected body animation in 60 fps increments.
@onready var _body_frame: HSlider = %BodyFrame
## Shows the selected body frame and time.
@onready var _body_frame_label: Label = %BodyFrameLabel
## Holds the independently weighted facial animation layers.
@onready var _face_layers: VBoxContainer = %FaceLayers
## Indicates whether the character provides a lip-sync profile.
@onready var _face_status: Label = %FaceStatus
## Clears the body override and all facial layers.
@onready var _reset_pose: Button = %ResetPose

## Camera position used as the live gaze target.
var _camera: Camera3D
## Character gaze modifiers temporarily controlled by the photo session.
var _gaze: Array[GazeTrackingModifier3D] = []
## Skeletons that need a manual presentation refresh during pause.
var _skeletons: Array[Skeleton3D] = []
## Body pose modifiers evaluated before gaze and other facial adjustments.
var _body_modifiers: Dictionary = {}
## Animation tracks grouped by target skeleton.
var _body_tracks: Dictionary = {}
## Temporary facial pose mixer.
var _face_mixer: LipSyncDriver
## Animation selected for the body override.
var _clip: Animation
var _layers: Array[Dictionary] = []


func _ready() -> void:
	_face_camera.toggled.connect(_on_face_camera)
	_reset_gaze.pressed.connect(_clear_gaze)
	_body_animation.item_selected.connect(_select_body)
	_body_frame.value_changed.connect(_sample_body)
	_reset_pose.pressed.connect(_clear_pose)
	for index: int in range(FACE_LAYER_COUNT):
		_add_face_layer(index)


func open(player: Node3D, camera: Camera3D) -> void:
	_camera = camera
	_face_camera.set_pressed_no_signal(false)
	var profile_driver: LipSyncDriver
	for node: Node in player.find_children("*", "SkeletonModifier3D", true, false):
		if node is GazeTrackingModifier3D and node.has_valid_head_bone():
			_gaze.append(node)
			node.begin_photo_gaze()
			_register_skeleton(node.get_skeleton())
		elif node is LipSyncDriver and node.profile and not profile_driver:
			profile_driver = node
	_face_camera.disabled = _gaze.is_empty()
	_reset_gaze.disabled = _gaze.is_empty()
	if profile_driver and profile_driver.get_skeleton():
		var skeleton: Skeleton3D = profile_driver.get_skeleton()
		_register_skeleton(skeleton)
		_face_mixer = LipSyncDriver.new()
		_face_mixer.profile = profile_driver.profile
		skeleton.add_child(_face_mixer)
		_face_mixer.set_process(false)
	_fill_body_animations(player)
	_fill_face_animations()


func close(detaching: bool = false) -> void:
	for modifier: GazeTrackingModifier3D in _gaze:
		if is_instance_valid(modifier):
			modifier.end_photo_gaze()
	_gaze.clear()
	for modifier: BodyPose in _body_modifiers.values():
		_remove_modifier(modifier, detaching)
	_body_modifiers.clear()
	_remove_modifier(_face_mixer, detaching)
	_face_mixer = null
	_camera = null
	_clip = null
	_body_tracks.clear()
	_body_animation.clear()
	for layer: Dictionary in _layers:
		(layer["picker"] as OptionButton).clear()
	if not detaching:
		_refresh_pose()
	_skeletons.clear()


func _remove_modifier(modifier: SkeletonModifier3D, detaching: bool) -> void:
	if not is_instance_valid(modifier):
		return
	modifier.active = false
	if not detaching and modifier.get_parent():
		modifier.get_parent().remove_child(modifier)
	modifier.queue_free()


func update_camera_gaze() -> void:
	if not _face_camera.button_pressed or not is_instance_valid(_camera):
		return
	var target: Vector3 = _camera.get_camera_transform().origin
	var changed: bool = false
	for modifier: GazeTrackingModifier3D in _gaze:
		if is_instance_valid(modifier) and (not modifier.tracking_active or not modifier.target_global_position.is_equal_approx(target)):
			modifier.aim_photo_gaze(target)
			changed = true
	if changed:
		_refresh_pose()


func get_default_focus() -> Control:
	if not _face_camera.disabled:
		return _face_camera
	return _body_animation if not _body_animation.disabled else _reset_pose


func _on_face_camera(pressed: bool) -> void:
	if pressed:
		update_camera_gaze()


func _clear_gaze() -> void:
	_face_camera.set_pressed_no_signal(false)
	for modifier: GazeTrackingModifier3D in _gaze:
		if is_instance_valid(modifier):
			modifier.reset_photo_gaze()
	_refresh_pose()


func _register_skeleton(skeleton: Skeleton3D) -> void:
	if skeleton and not _skeletons.has(skeleton):
		_skeletons.append(skeleton)


func _refresh_pose() -> void:
	for skeleton: Skeleton3D in _skeletons:
		if is_instance_valid(skeleton) and skeleton.is_inside_tree():
			skeleton.advance(0.0)


func _find_animation_player(player: Node3D) -> AnimationPlayer:
	var tree: AnimationTree = player.get("anim_tree") as AnimationTree if "anim_tree" in player else null
	if not tree:
		tree = player.find_child("AnimationTree", true, false) as AnimationTree
	if tree and tree.has_node(tree.anim_player):
		return tree.get_node(tree.anim_player) as AnimationPlayer
	return player.find_child("AnimationPlayer", true, false) as AnimationPlayer


func _fill_body_animations(player: Node3D) -> void:
	_body_animation.clear()
	_body_animation.add_item("Current Pose")
	_body_animation.select(0)
	var animator: AnimationPlayer = _find_animation_player(player)
	var root: Node = animator.get_node_or_null(animator.root_node) if animator else null
	if root:
		for animation_name: String in animator.get_animation_list():
			var short_name: String = animation_name.get_file().to_upper()
			if short_name == "RESET" or short_name.begins_with("VIS_") or short_name.begins_with("EXP_") or short_name.begins_with("EYES_"):
				continue
			var animation: Animation = animator.get_animation(animation_name)
			var tracks: Dictionary = _find_body_tracks(player, root, animation)
			if tracks.is_empty():
				continue
			_body_animation.add_item(animation_name)
			_body_animation.set_item_metadata(_body_animation.item_count - 1, {"clip": animation, "tracks": tracks})
	_body_animation.disabled = _body_animation.item_count == 1
	_select_body(0)


func _find_body_tracks(player: Node3D, root: Node, animation: Animation) -> Dictionary:
	var result: Dictionary = {}
	for track: int in animation.get_track_count():
		var type: int = animation.track_get_type(track)
		if type not in [Animation.TYPE_POSITION_3D, Animation.TYPE_ROTATION_3D, Animation.TYPE_SCALE_3D]:
			continue
		if not animation.track_is_enabled(track) or not animation.track_get_key_count(track):
			continue
		var path: NodePath = animation.track_get_path(track)
		if path.get_subname_count() != 1:
			continue
		var skeleton: Skeleton3D = root.get_node_or_null(NodePath(path.get_concatenated_names())) as Skeleton3D
		if not skeleton or not player.is_ancestor_of(skeleton):
			continue
		var bone: int = skeleton.find_bone(path.get_subname(0))
		if bone < 0:
			continue
		if not result.has(skeleton):
			result[skeleton] = []
		(result[skeleton] as Array).append(Vector3i(track, bone, type))
	return result


func _select_body(index: int) -> void:
	var choice: Dictionary = _body_animation.get_item_metadata(index) if index > 0 else {}
	_clip = choice.get("clip") as Animation
	_body_tracks = choice.get("tracks", {})
	for skeleton: Skeleton3D in _body_tracks:
		if _body_modifiers.has(skeleton):
			continue
		var modifier: BodyPose = BodyPose.new()
		skeleton.add_child(modifier)
		skeleton.move_child(modifier, 0)
		_body_modifiers[skeleton] = modifier
		_register_skeleton(skeleton)
	_body_frame.max_value = ceilf(_clip.length * SCRUB_FPS) if _clip else 0.0
	_body_frame.editable = _clip != null
	_body_frame.set_value_no_signal(0.0)
	_sample_body(0.0)


func _sample_body(frame: float) -> void:
	var time: float = minf(frame / SCRUB_FPS, _clip.length) if _clip else 0.0
	_body_frame_label.text = "Frame %d / %d  ·  %.2f s" % [roundi(frame), roundi(_body_frame.max_value), time] if _clip else "Animation Frame"
	for modifier: BodyPose in _body_modifiers.values():
		modifier.pose.clear()
	for skeleton: Skeleton3D in _body_tracks:
		var modifier: BodyPose = _body_modifiers[skeleton]
		for info: Vector3i in _body_tracks[skeleton]:
			var value: Variant
			match info.z:
				Animation.TYPE_POSITION_3D:
					value = _clip.position_track_interpolate(info.x, time)
				Animation.TYPE_ROTATION_3D:
					value = _clip.rotation_track_interpolate(info.x, time)
				Animation.TYPE_SCALE_3D:
					value = _clip.scale_track_interpolate(info.x, time)
			if not modifier.pose.has(info.y):
				modifier.pose[info.y] = {}
			modifier.pose[info.y][info.z] = value
	_refresh_pose()


func _add_face_layer(index: int) -> void:
	var title: Label = Label.new()
	title.text = "Facial Layer %d" % (index + 1)
	title.add_theme_font_size_override("font_size", 16)
	_face_layers.add_child(title)
	var picker: OptionButton = OptionButton.new()
	picker.custom_minimum_size.y = 44.0
	picker.fit_to_longest_item = false
	picker.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	picker.add_theme_font_size_override("font_size", 17)
	picker.tooltip_text = "Select an expression or mouth shape for this layer."
	_face_layers.add_child(picker)
	var strength_label: Label = Label.new()
	strength_label.add_theme_font_size_override("font_size", 15)
	_face_layers.add_child(strength_label)
	var strength: HSlider = HSlider.new()
	strength.max_value = 1.0
	strength.step = 0.05
	strength.value = 1.0
	strength.custom_minimum_size.y = 30.0
	strength.tooltip_text = "Blends the facial layer into the current pose."
	_face_layers.add_child(strength)
	var frame_label: Label = Label.new()
	frame_label.add_theme_font_size_override("font_size", 15)
	_face_layers.add_child(frame_label)
	var frame: HSlider = HSlider.new()
	frame.step = 1.0
	frame.custom_minimum_size.y = 30.0
	frame.tooltip_text = "Samples a frame from the selected facial animation."
	_face_layers.add_child(frame)
	_layers.append({"picker": picker, "strength": strength, "strength_label": strength_label, "frame": frame, "frame_label": frame_label})
	picker.item_selected.connect(func(_selected: int) -> void:
		_configure_face_layer(index)
		_update_face_layers()
	)
	strength.value_changed.connect(func(_value: float) -> void: _update_face_layers())
	frame.value_changed.connect(func(_value: float) -> void: _update_face_layers())


func _fill_face_animations() -> void:
	_face_layers.visible = is_instance_valid(_face_mixer)
	_face_status.visible = not _face_layers.visible
	for index: int in range(_layers.size()):
		var picker: OptionButton = _layers[index]["picker"]
		picker.clear()
		picker.add_item("None")
		picker.select(0)
		if _face_mixer:
			for expression: bool in [false, true]:
				var poses: Array[LipSyncPose] = _face_mixer.profile.expressions if expression else _face_mixer.profile.visemes
				for pose: LipSyncPose in poses:
					if not pose or not pose.animation:
						continue
					var name_text: String = String(pose.id).substr(4) if String(pose.id).begins_with("EXP_") or String(pose.id).begins_with("VIS_") else String(pose.id)
					picker.add_item(("Expression · " if expression else "Viseme · ") + name_text.replace("_", " "))
					picker.set_item_metadata(picker.item_count - 1, {"pose": pose, "expression": expression})
		_configure_face_layer(index)
	_update_face_layers()


func _configure_face_layer(index: int) -> void:
	var layer: Dictionary = _layers[index]
	var picker: OptionButton = layer["picker"]
	var strength: HSlider = layer["strength"]
	var frame: HSlider = layer["frame"]
	var selected: bool = picker.selected > 0
	strength.editable = selected
	strength.set_value_no_signal(1.0)
	var last_frame: float = 0.0
	if selected:
		var pose: LipSyncPose = picker.get_selected_metadata()["pose"]
		last_frame = ceilf(pose.animation.length * SCRUB_FPS)
	frame.max_value = last_frame
	frame.editable = last_frame > 0.0
	frame.set_value_no_signal(0.0)
	frame.visible = frame.editable
	(layer["frame_label"] as Label).visible = frame.visible


func _update_face_layers() -> void:
	if not is_instance_valid(_face_mixer):
		return
	var samples: Array[Dictionary] = []
	for layer: Dictionary in _layers:
		var picker: OptionButton = layer["picker"]
		var strength: HSlider = layer["strength"]
		var frame: HSlider = layer["frame"]
		(layer["strength_label"] as Label).text = "Strength  %d%%" % roundi(strength.value * 100.0)
		(layer["frame_label"] as Label).text = "Facial Frame %d / %d" % [roundi(frame.value), roundi(frame.max_value)]
		if picker.selected > 0:
			var choice: Dictionary = picker.get_selected_metadata().duplicate()
			var pose: LipSyncPose = choice["pose"]
			choice["weight"] = strength.value
			choice["time"] = minf(frame.value / SCRUB_FPS, pose.animation.length)
			samples.append(choice)
	_face_mixer.set_photo_pose_layers(samples)
	_refresh_pose()


func _clear_pose() -> void:
	_body_animation.select(0)
	_select_body(0)
	for index: int in range(_layers.size()):
		(_layers[index]["picker"] as OptionButton).select(0)
		_configure_face_layer(index)
	_update_face_layers()


func reset_player_pose() -> void:
	if not is_instance_valid(_camera):
		return
	_clear_gaze()
	_clear_pose()
