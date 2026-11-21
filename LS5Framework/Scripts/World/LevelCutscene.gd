extends Node3D

signal finished(completed: bool)
signal gameplay_wait_finished(condition: StringName, reached: bool)

const ActorHandler = preload("res://LS5Framework/Scripts/World/CutsceneActorHandler.gd")
const SKIP_ACTION: StringName = &"interact"
const SKIP_HOLD_SECONDS: float = 1.0
const SKIP_VISIBLE_SECONDS: float = 1.6
const SKIP_FADE_SECONDS: float = 0.2
const SKIP_PROMPT_SCENE: PackedScene = preload("res://LS5Framework/Scenes/UI/HeldButtonPrompt.tscn")

## Native timeline containing the shot, actor staging, and player motion cues.
@export var timeline: AnimationPlayer
## Resolves and plays role-based presentation cues for the registered actors.
@export var actor_handler: ActorHandler
## Animation in the timeline that starts when the trigger is entered.
@export var sequence: StringName
## Area entered by the current playable character.
@export var trigger: Area3D
## Starts playback on trigger entry. Disable to call play_for from another event.
@export var start_on_enter: bool = true
## Prevents a completed cutscene from playing again until the level reloads.
@export var play_once: bool = true
## Camera made current while the timeline plays.
@export var shot_camera: Camera3D
## Animated marker that drives the live player's position and facing.
@export var player_pose: Marker3D
## Preserve the player's offset from the first pose for triggers inside the staging area.
@export var preserve_entry_offset: bool = false
## Starts with native player physics and locomotion. PlayerPose is used in keyframed mode.
@export var gameplay_movement: bool = false
## Optional route used by follow_player_route. Keep its scale at one.
@export var gameplay_route: Path3D
## Safe gameplay pose used when skipping a sequence with scripted movement.
@export var gameplay_skip_pose: Marker3D
## Animation track paths affected by gameplay overlays. An empty list allows full-body poses.
@export var gameplay_overlay_tracks: Array[NodePath] = []
## Allows the Interact hold shortcut and the pause menu's Skip Cutscene action.
@export var skippable: bool = true
## Hides the gameplay HUD until the cutscene releases the player.
@export var hide_player_hud: bool = true
## Presentation state sampled from the native timeline.
@export_enum("Idle", "Walk") var player_motion: int = 0
## Level-relative actors available by role. The triggering player binds as player.
@export var actor_paths: Dictionary[StringName, NodePath] = {}
## Preplaced actors that are visible only while the cutscene plays.
@export var staged_roles: Array[StringName] = []
## Fallback animation names for the player idle cue.
@export var idle_clips: Array[StringName] = [&"Idle", &"IDLE", &"idle"]
## Fallback animation names for the player walk cue.
@export var walk_clips: Array[StringName] = [&"Move1_Walk", &"Walk", &"WALK", &"walk"]

## Voice clip played by the bound player when the timeline calls play_player_dialogue.
@export var player_dialogue: AudioStream
## Required character ID for this voice clip. Leave empty to allow any character.
@export var dialogue_character_id: StringName = &""

var _actors: Dictionary[StringName, Node3D] = {}
var _player: PlayerController
var _current_motion: int = -1
var _entry_offset: Vector3
var _previous_camera: Camera3D
var _running: bool = false
var _played: bool = false
var _gameplay_active: bool = false
var _move_target: Node3D
var _following_route: bool = false
var _route_progress: float = 0.0
var _route_lookahead: float = 2.0
var _move_speed: float = 0.0
var _wait_condition: StringName
var _wait_marker: Node3D
var _wait_radius: float = 1.0
var _wait_remaining: float = 0.0
var _wait_needs_airborne: bool = false
var _hidden_hud: CanvasLayer
var _skip_layer: CanvasLayer
var _skip_prompt: HeldButtonPrompt
var _skip_hold_time: float = 0.0
var _skip_visible_time: float = 0.0
var _skip_uses_controller: bool = false
var _skip_device: int = -1


func _ready() -> void:
	set_process(false)
	set_physics_process(false)
	set_process_input(false)
	if not actor_handler:
		actor_handler = ActorHandler.new()
		actor_handler.name = "ActorHandler"
		add_child(actor_handler)
	if shot_camera:
		shot_camera.add_to_group(&"SceneDiagnosticsCameraOverride")
	for role: StringName in actor_paths:
		var actor: Node3D = get_node_or_null(actor_paths[role]) as Node3D
		if actor:
			register_actor(role, actor)
	if trigger and start_on_enter:
		trigger.body_entered.connect(_on_body_entered)
	if timeline:
		timeline.callback_mode_method = AnimationMixer.ANIMATION_CALLBACK_MODE_METHOD_DEFERRED
		timeline.mixer_applied.connect(_apply_pose)
		timeline.animation_finished.connect(_on_animation_finished)


func register_actor(role: StringName, actor: Node3D) -> void:
	_actors[role] = actor
	if role in staged_roles:
		actor.process_mode = Node.PROCESS_MODE_DISABLED
		actor.visible = _running


func get_actor(role: StringName) -> Node3D:
	var actor: Node3D = _actors.get(role)
	return actor if is_instance_valid(actor) else null


func play_for(player: PlayerController) -> bool:
	if _running or (play_once and _played) or not player or not player_pose or not shot_camera or not timeline or not timeline.has_animation(sequence):
		return false
	for role: StringName in staged_roles:
		if not get_actor(role):
			return false
	if not player.acquire_cutscene_pose(self, gameplay_movement):
		return false

	_player = player
	_player.cutscene_pose_interrupted.connect(cancel)
	register_actor(&"player", player)
	actor_handler.begin(_actors, {&"idle": PackedStringArray(idle_clips), &"walk": PackedStringArray(walk_clips)})
	_gameplay_active = gameplay_movement
	if _gameplay_active:
		actor_handler.set_gameplay_player(player, gameplay_overlay_tracks)
	_previous_camera = get_viewport().get_camera_3d()
	timeline.play(sequence)
	timeline.seek(0.0, true, true)
	_entry_offset = player.global_position - player_pose.global_position if preserve_entry_offset else Vector3.ZERO
	_running = true
	set_physics_process(_gameplay_active)
	add_to_group(&"ActiveCutscene")
	if hide_player_hud:
		var hud: CanvasLayer = get_tree().get_first_node_in_group(&"HUD") as CanvasLayer
		if hud and hud.has_method("set_cutscene_hidden"):
			_hidden_hud = hud
			_hidden_hud.set_cutscene_hidden(true)
	_current_motion = -1
	for role: StringName in staged_roles:
		get_actor(role).show()
	shot_camera.make_current()
	_apply_pose()
	player.reset_physics_interpolation()
	if skippable:
		_show_skip_prompt()
		set_process(true)
		set_process_input(true)
	return true


func skip() -> void:
	if not _running or not skippable:
		return
	# Apply the final frame and its keys without replaying intervening cues.
	timeline.seek(timeline.current_animation_length, true)
	if _gameplay_active and gameplay_skip_pose and is_instance_valid(_player):
		_player.apply_teleport(gameplay_skip_pose.global_transform, false, true, Vector3.ZERO)
	reset_physics_interpolation()
	for actor: Node3D in _actors.values():
		if is_instance_valid(actor):
			actor.reset_physics_interpolation()
	_finish(true)


func cancel() -> void:
	_finish(false)


func set_player_gameplay_movement(enabled: bool) -> void:
	if not _running or not is_instance_valid(_player) or not _player.owns_cutscene_pose(self) or _gameplay_active == enabled:
		return
	if not enabled:
		actor_handler.set_gameplay_player(null, [])
	if not _player.set_cutscene_gameplay_motion(self, enabled):
		return
	_gameplay_active = enabled
	set_physics_process(enabled)
	_clear_drive()
	if _wait_condition != &"":
		_resume_player_wait(false)
	if enabled:
		actor_handler.set_gameplay_player(_player, gameplay_overlay_tracks)
	else:
		_current_motion = -1
		_apply_pose()
		_player.reset_physics_interpolation()


func follow_player_route(speed: float, lookahead: float = 2.0) -> void:
	if not _running or not _gameplay_active or not gameplay_route or not gameplay_route.curve:
		return
	if gameplay_route.curve.get_baked_length() <= 0.0:
		return
	_move_target = null
	_following_route = true
	_route_progress = gameplay_route.curve.get_closest_offset(gameplay_route.to_local(_player.global_position))
	_route_lookahead = maxf(lookahead, 0.1)
	_move_speed = maxf(speed, 0.0)
	_drive_player()


func move_player_to(marker_path: NodePath, speed: float) -> void:
	if not _running or not _gameplay_active:
		return
	_move_target = get_node_or_null(marker_path) as Node3D
	_following_route = false
	_move_speed = maxf(speed, 0.0)
	_drive_player()


func stop_player_movement() -> void:
	_clear_drive()
	if _running and is_instance_valid(_player):
		_player.set_cutscene_movement_intent(self, Vector3.ZERO, 0.0)


func face_player_actor(role: StringName, degrees_per_second: float = 360.0) -> void:
	if _running and _gameplay_active and is_instance_valid(_player):
		_player.set_cutscene_facing_target(self, get_actor(role), degrees_per_second)


func clear_player_facing() -> void:
	face_player_actor(&"")


func jump_player(hold_seconds: float = 0.15) -> void:
	if _running and _gameplay_active and is_instance_valid(_player):
		_player.request_cutscene_jump(self, hold_seconds)


func fade_player_overlay(weight: float = 0.0, seconds: float = 0.12) -> void:
	if _running and _gameplay_active and is_instance_valid(_player):
		_player.get_animation_director().set_cutscene_overlay_weight(weight, seconds)


func wait_for_player_marker(marker_path: NodePath, radius: float = 1.0, timeout: float = 3.0) -> void:
	if not _running or not _gameplay_active:
		return
	_wait_marker = get_node_or_null(marker_path) as Node3D
	if _wait_marker:
		_wait_radius = maxf(radius, 0.05)
		_begin_player_wait(&"marker", timeout)
	else:
		gameplay_wait_finished.emit(&"marker", false)


func wait_for_player_grounded(timeout: float = 3.0) -> void:
	_wait_needs_airborne = false
	_begin_player_wait(&"grounded", timeout)


func wait_for_player_landing(timeout: float = 3.0) -> void:
	_wait_needs_airborne = true
	_begin_player_wait(&"grounded", timeout)


func wait_for_player_airborne(timeout: float = 3.0) -> void:
	_begin_player_wait(&"airborne", timeout)


func _begin_player_wait(condition: StringName, timeout: float) -> void:
	if not _running or not _gameplay_active or timeout <= 0.0:
		return
	_wait_condition = condition
	_wait_remaining = timeout
	timeline.pause()


func _physics_process(delta: float) -> void:
	if not is_instance_valid(_player) or not _player.owns_cutscene_pose(self):
		cancel()
		return
	if not _gameplay_active:
		return
	_drive_player()
	if _wait_condition == &"":
		return
	_wait_remaining -= delta
	var ready: bool = false
	var marker_missing: bool = false
	match _wait_condition:
		&"marker":
			marker_missing = not is_instance_valid(_wait_marker)
			ready = not marker_missing and (_to_marker(_wait_marker).length() <= _wait_radius or _passed_route_marker(_wait_marker))
		&"grounded":
			if not _player.attached:
				_wait_needs_airborne = false
			ready = _player.attached and not _wait_needs_airborne
		&"airborne":
			ready = not _player.attached
	if ready or marker_missing or _wait_remaining <= 0.0:
		_resume_player_wait(ready)


func _resume_player_wait(reached: bool) -> void:
	var condition: StringName = _wait_condition
	_wait_condition = &""
	_wait_marker = null
	timeline.play()
	gameplay_wait_finished.emit(condition, reached)


func _drive_player() -> void:
	var direction: Vector3 = Vector3.ZERO
	if _following_route and is_instance_valid(gameplay_route) and gameplay_route.curve:
		var curve: Curve3D = gameplay_route.curve
		var length: float = curve.get_baked_length()
		_route_progress = maxf(_route_progress, curve.get_closest_offset(gameplay_route.to_local(_player.global_position)))
		var target: Vector3 = gameplay_route.to_global(curve.sample_baked(minf(_route_progress + _route_lookahead, length)))
		direction = (target - _player.global_position).slide(_player.get_gravity_up())
		if _route_progress >= length - 0.25:
			direction = target - gameplay_route.to_global(curve.sample_baked(maxf(length - _route_lookahead, 0.0)))
	elif is_instance_valid(_move_target):
		direction = _to_marker(_move_target)
		if direction.length_squared() < 0.0625:
			direction = Vector3.ZERO
	_player.set_cutscene_movement_intent(self, direction, _move_speed)


func _to_marker(marker: Node3D) -> Vector3:
	return (marker.global_position - _player.global_position).slide(_player.get_gravity_up())


func _passed_route_marker(marker: Node3D) -> bool:
	if not _following_route or not is_instance_valid(gameplay_route) or not gameplay_route.curve:
		return false
	var curve: Curve3D = gameplay_route.curve
	var offset: float = curve.get_closest_offset(gameplay_route.to_local(marker.global_position))
	var route_point: Vector3 = gameplay_route.to_global(curve.sample_baked(offset))
	var marker_offset: Vector3 = (route_point - marker.global_position).slide(_player.get_gravity_up())
	return _route_progress >= offset and marker_offset.length() <= _wait_radius


func _clear_drive() -> void:
	_move_target = null
	_following_route = false
	_move_speed = 0.0


func _process(delta: float) -> void:
	_skip_visible_time = maxf(0.0, _skip_visible_time - delta)
	if Input.is_action_pressed(SKIP_ACTION):
		_skip_hold_time += delta
		_skip_visible_time = SKIP_VISIBLE_SECONDS
	else:
		_skip_hold_time = 0.0
	var opacity: float = 1.0 if _skip_visible_time > 0.0 else 0.0
	_skip_prompt.modulate.a = move_toward(_skip_prompt.modulate.a, opacity, delta / SKIP_FADE_SECONDS)
	_skip_layer.visible = _skip_prompt.modulate.a > 0.0
	if _skip_layer.visible:
		_update_skip_glyph()
	_skip_prompt.set_hold_progress(_skip_hold_time / SKIP_HOLD_SECONDS)
	if _skip_hold_time >= SKIP_HOLD_SECONDS:
		skip()


func _input(event: InputEvent) -> void:
	if event.is_action(&"pause") or event.is_action(&"hide_pause_menu"):
		return
	if event is InputEventJoypadMotion:
		if absf(event.axis_value) > 0.5:
			_skip_visible_time = SKIP_VISIBLE_SECONDS
	elif (event is InputEventKey or event is InputEventJoypadButton or event is InputEventMouseButton) and event.is_pressed():
		_skip_visible_time = SKIP_VISIBLE_SECONDS


func _show_skip_prompt() -> void:
	if not _skip_layer:
		_skip_layer = CanvasLayer.new()
		_skip_layer.layer = 2
		add_child(_skip_layer)
		_skip_prompt = SKIP_PROMPT_SCENE.instantiate()
		_skip_layer.add_child(_skip_prompt)
		get_viewport().size_changed.connect(_layout_skip_prompt)
		SettingsManager.input_bindings_changed.connect(_on_skip_binding_changed)
	_update_skip_glyph(true)
	_hide_skip_prompt()


func _hide_skip_prompt() -> void:
	_skip_hold_time = 0.0
	_skip_visible_time = 0.0
	_skip_prompt.set_hold_progress(0.0)
	_skip_prompt.modulate.a = 0.0
	_skip_layer.hide()


func _update_skip_glyph(force: bool = false) -> void:
	var controller: bool = SettingsManager.is_controller_input_active()
	var device: int = SettingsManager.get_preferred_joypad_device() if controller else -1
	if not force and controller == _skip_uses_controller and device == _skip_device:
		return
	_skip_uses_controller = controller
	_skip_device = device
	var glyph: Dictionary = InputBindingGlyphs.get_slot_glyph(SKIP_ACTION, controller, InputBindingGlyphs.Style.AUTO, device)
	_skip_prompt.configure(glyph if glyph else {"label": "Interact"}, "Skip", true)
	_skip_prompt.fit_to_content()
	_layout_skip_prompt()


func _layout_skip_prompt() -> void:
	if not _running or not _skip_prompt:
		return
	var viewport_size: Vector2 = get_viewport().get_visible_rect().size
	var factor: float = clampf(minf(viewport_size.x / 1600.0, viewport_size.y / 900.0), 0.5, 2.4)
	_skip_prompt.scale = Vector2.ONE * factor
	_skip_prompt.position = viewport_size - (_skip_prompt.size + Vector2(24.0, 24.0)) * factor


func _on_skip_binding_changed(action: StringName) -> void:
	if _running and action == SKIP_ACTION:
		_update_skip_glyph(true)


func _notification(what: int) -> void:
	if what in [NOTIFICATION_PAUSED, NOTIFICATION_WM_WINDOW_FOCUS_OUT] and _running and _skip_layer:
		_hide_skip_prompt()


func _on_body_entered(body: Node3D) -> void:
	if body is PlayerController and body.is_in_group(&"Player"):
		play_for.call_deferred(body)


func _apply_pose() -> void:
	if not _running or _gameplay_active:
		return
	var pose: Transform3D = player_pose.global_transform
	pose.origin += _entry_offset
	if not is_instance_valid(_player) or not _player.apply_cutscene_pose(self, pose):
		cancel.call_deferred()
		return
	if player_motion == _current_motion:
		return
	_current_motion = player_motion
	actor_handler.play_animation(&"player", &"walk" if player_motion == 1 else &"idle")


func play_player_dialogue() -> void:
	if actor_handler and (dialogue_character_id == &"" or actor_handler.get_actor_character_id(&"player") == dialogue_character_id):
		actor_handler.play_dialogue_clip(&"player", player_dialogue)


func _on_animation_finished(animation: StringName) -> void:
	if animation == sequence:
		_apply_pose()
		_finish(true)


func _finish(completed: bool) -> void:
	if not _running:
		return
	_running = false
	remove_from_group(&"ActiveCutscene")
	if is_instance_valid(_hidden_hud):
		_hidden_hud.set_cutscene_hidden(false)
	_hidden_hud = null
	set_process(false)
	set_physics_process(false)
	set_process_input(false)
	_clear_drive()
	_wait_condition = &""
	_wait_marker = null
	if _skip_layer:
		_hide_skip_prompt()
	_played = completed
	if is_instance_valid(timeline):
		timeline.stop(true)
	if is_instance_valid(_previous_camera) and _previous_camera.is_inside_tree():
		_previous_camera.make_current()
	elif is_instance_valid(shot_camera) and shot_camera.is_inside_tree():
		shot_camera.clear_current()
	_previous_camera = null
	if is_instance_valid(actor_handler):
		actor_handler.end()
	if is_instance_valid(_player):
		_player.cutscene_pose_interrupted.disconnect(cancel)
		_player.release_cutscene_pose(self)
	_player = null
	_actors.erase(&"player")
	for role: StringName in staged_roles:
		var actor: Node3D = get_actor(role)
		if actor:
			actor.hide()
	finished.emit(completed)


func _exit_tree() -> void:
	cancel()
