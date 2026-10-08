extends Control

const DeathPlane = preload("res://LS5Framework/Objects/Gameplay/DeathPlane.gd")
const ONLINE_TELEPORT_STATE_WAIT_FRAMES: int = 180
const PAUSE_PREVIEW_ACTION: StringName = &"hide_pause_menu"
const CHARACTER_SETTINGS_MENU_SCENE: PackedScene = preload("res://LS5Framework/Scenes/UI/CharacterSettingsMenu.tscn")
const HELD_BUTTON_PROMPT_SCENE: PackedScene = preload("res://LS5Framework/Scenes/UI/HeldButtonPrompt.tscn")

## Controller checkpoint shortcut hold time required to restart an available race.
@export_range(0.1, 3.0, 0.05, "suffix:s") var race_restart_hold_duration: float = 0.7

## Arranges compact shortcuts beneath the pause frame.
var _shortcut_prompts: HBoxContainer
## Displays device-aware shortcut glyphs and hold progress.
var _shortcut_cards: Array[HeldButtonPrompt] = []
var _shortcut_pending: StringName = &""
var _shortcut_hold_time: float = 0.0
var _shortcut_hold_consumed: bool = false
var _shortcut_signature: String = ""

func _create_pause_shortcut_prompts() -> void:
	_shortcut_prompts = HBoxContainer.new()
	_shortcut_prompts.name = "ShortcutPrompts"
	_shortcut_prompts.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_shortcut_prompts.add_theme_constant_override("separation", 8)
	panel_pause.add_child(_shortcut_prompts)
	_shortcut_prompts.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	_shortcut_prompts.offset_top = 8.0
	_shortcut_prompts.offset_bottom = 80.0
	for index: int in range(3):
		var card: HeldButtonPrompt = HELD_BUTTON_PROMPT_SCENE.instantiate()
		card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		_shortcut_prompts.add_child(card)
		_shortcut_cards.append(card)

func _can_use_pause_shortcuts() -> bool:
	return _is_open and panel_pause.visible and not panel_options.visible and not _pause_preview_hidden and not _is_input_binding_active() and not is_instance_valid(_character_settings_menu) and not graphics_confirm_dialog.visible and not unsaved_graphics_dialog.visible and not reset_defaults_dialog.visible and not _is_text_input_focused()

func _cancel_pause_shortcut_hold() -> void:
	_shortcut_pending = &""
	_shortcut_hold_time = 0.0
	_shortcut_hold_consumed = false
	if _shortcut_cards.size() == 3:
		_shortcut_cards[2].set_hold_progress(0.0)

func _update_pause_shortcuts(delta: float) -> void:
	if _shortcut_prompts == null:
		return
	_shortcut_prompts.visible = _can_use_pause_shortcuts()
	if not _shortcut_prompts.visible:
		_cancel_pause_shortcut_hold()
		return
	var controller: bool = SettingsManager.is_controller_input_active()
	var restart_available: bool = _can_quick_restart()
	var device: int = SettingsManager.get_preferred_joypad_device() if controller else -1
	var signature: String = "%s:%s:%s:%s" % [controller, restart_available, device, race_restart_hold_duration]
	if signature != _shortcut_signature:
		_shortcut_signature = signature
		_shortcut_cards[0].configure(InputBindingGlyphs.get_slot_glyph(&"shortcut_respawn" if controller else &"respawn", controller), "Respawn")
		_shortcut_cards[1].configure(InputBindingGlyphs.get_slot_glyph(&"shortcut_checkpoint" if controller else &"respawn_checkpoint", controller), "Checkpoint")
		_shortcut_cards[2].configure(InputBindingGlyphs.get_slot_glyph(&"shortcut_checkpoint" if controller else quick_restart_action, controller), "Hold %.1fs\nRestart Race" % race_restart_hold_duration if controller else "Restart Race", controller)
		_shortcut_cards[2].visible = restart_available
	if _shortcut_pending == &"shortcut_checkpoint" and not _shortcut_hold_consumed and restart_available:
		_shortcut_hold_time += maxf(delta, 0.0)
		_shortcut_cards[2].set_hold_progress(_shortcut_hold_time / race_restart_hold_duration)
		if _shortcut_hold_time >= race_restart_hold_duration:
			_shortcut_hold_consumed = true
			_do_quick_restart()
	var scale_factor: float = minf(1.0, minf(maxf(size.y - 40.0, 1.0) / (panel_pause.size.y + 96.0), maxf(size.x - 32.0, 1.0) / (1000.0 if online_panel.visible else 560.0)))
	panel_pause.pivot_offset = panel_pause.size * 0.5
	panel_pause.scale = Vector2.ONE * scale_factor
	panel_pause.offset_top = -panel_pause.size.y * 0.5 - 44.0 * scale_factor
	panel_pause.offset_bottom = panel_pause.offset_top + panel_pause.size.y
	if online_panel.visible:
		panel_pause.offset_left = -280.0 + 190.0 * scale_factor
		panel_pause.offset_right = panel_pause.offset_left + 560.0
		online_panel.pivot_offset = online_panel.size * 0.5
		online_panel.scale = Vector2.ONE * scale_factor
		online_panel.offset_left = -180.0 - 290.0 * scale_factor
		online_panel.offset_right = online_panel.offset_left + 360.0

func _handle_pause_shortcut(event: InputEvent) -> bool:
	if event is InputEventKey and event.echo:
		return false
	if event is InputEventJoypadButton:
		for action: StringName in [&"shortcut_respawn", &"shortcut_checkpoint"]:
			if event.is_action_pressed(action):
				_cancel_pause_shortcut_hold()
				_shortcut_pending = action
				return true
			if event.is_action_released(action):
				var execute: bool = _shortcut_pending == action and not _shortcut_hold_consumed
				_cancel_pause_shortcut_hold()
				if execute:
					if action == &"shortcut_respawn":
						_on_ButtonRespawnStart_pressed()
					else:
						_on_ButtonRespawnCheckpoint_pressed()
				return true
	elif event.is_action_pressed("respawn"):
		_on_ButtonRespawnStart_pressed()
		return true
	elif event.is_action_pressed("respawn_checkpoint"):
		_on_ButtonRespawnCheckpoint_pressed()
		return true
	return false

## Character loadout menu displayed over the keybind options.
var _character_settings_menu: CharacterSettingsMenu = null

@export_file("*.tscn") var main_menu_scene: String = "res://LS5Framework/Scenes/MainMenu/MainMenu.tscn"
@export var hud: Node = null
@export var quick_restart_action: StringName = &"quick_restart"

## Full-screen dimmer hidden while previewing the paused game view.
@onready var dimmer: ColorRect = $Dimmer
## Contains all pause panels hidden during pause previews.
@onready var overlay: Control = $Overlay
@onready var panel_pause: Control   = $Overlay/PausePanel
@onready var panel_options: Control = $Overlay/OptionsPanel

@onready var online_panel: Control = $Overlay/OnlinePanel
@onready var label_connection: Label = $Overlay/OnlinePanel/VBoxOnline/LabelConnection
@onready var label_diagnostics: Label = $Overlay/OnlinePanel/VBoxOnline/LabelDiagnostics
@onready var row_invite: HBoxContainer = $Overlay/OnlinePanel/VBoxOnline/HBoxInvite
@onready var edit_invite: LineEdit = $Overlay/OnlinePanel/VBoxOnline/HBoxInvite/LineEditInvite
@onready var button_copy_invite: Button = $Overlay/OnlinePanel/VBoxOnline/HBoxInvite/ButtonCopyInvite
@onready var label_race_queue: Label = $Overlay/OnlinePanel/VBoxOnline/LabelRaceQueue
@onready var button_leave_queue: Button = $Overlay/OnlinePanel/VBoxOnline/ButtonLeaveQueue
@onready var player_list: VBoxContainer = $Overlay/OnlinePanel/VBoxOnline/ScrollPlayers/PlayerList
@onready var button_leave_race: Button = $Overlay/PausePanel/VBoxPause/ButtonLeaveRace
@onready var button_return_hub: Button = $Overlay/PausePanel/VBoxPause/ButtonReturnHub
@onready var button_quick_restart: Button = $Overlay/PausePanel/VBoxPause/ButtonQuickRestart
@onready var button_respawn_start: Button = $Overlay/PausePanel/VBoxPause/HBoxRespawn/ButtonRespawnStart
@onready var button_respawn_checkpoint: Button = $Overlay/PausePanel/VBoxPause/HBoxRespawn/ButtonRespawnCheckpoint

@onready var tabs_options: TabContainer = $Overlay/OptionsPanel/Panel/VBoxOptions/TabsOptions
@onready var tab_controls: Control = $Overlay/OptionsPanel/Panel/VBoxOptions/TabsOptions/TabControls
@onready var tab_bindings: Control = $Overlay/OptionsPanel/Panel/VBoxOptions/TabsOptions/TabBindings
@onready var tab_graphics: Control = $Overlay/OptionsPanel/Panel/VBoxOptions/TabsOptions/TabGraphics
@onready var tab_audio: Control = $Overlay/OptionsPanel/Panel/VBoxOptions/TabsOptions/TabAudio
@onready var tab_gameplay: Control = $Overlay/OptionsPanel/Panel/VBoxOptions/TabsOptions/TabGameplay
## Restores every configurable option and binding to the packaged defaults.
@onready var button_reset_defaults: Button = $Overlay/OptionsPanel/Panel/VBoxOptions/ButtonResetDefaults
## Confirms full settings resets before changing saved configuration.
@onready var reset_defaults_dialog: Control = $Overlay/ResetDefaultsDialog
## Applies the confirmed settings reset.
@onready var button_confirm_reset_defaults: Button = $Overlay/ResetDefaultsDialog/WarningFrame/Margin/Content/Buttons/ButtonReset
## Closes the settings-reset confirmation without changing settings.
@onready var button_cancel_reset_defaults: Button = $Overlay/ResetDefaultsDialog/WarningFrame/Margin/Content/Buttons/ButtonCancel
## Blocks menu input while newly applied graphics settings await confirmation.
@onready var graphics_confirm_dialog: Control = $Overlay/GraphicsConfirmDialog
## Displays the graphics-settings confirmation countdown.
@onready var graphics_confirm_body: Label = $Overlay/GraphicsConfirmDialog/WarningFrame/Margin/Content/Body
## Keeps newly applied graphics settings.
@onready var button_confirm_graphics: Button = $Overlay/GraphicsConfirmDialog/WarningFrame/Margin/Content/Buttons/ButtonYes
## Restores the previous graphics settings.
@onready var button_revert_graphics: Button = $Overlay/GraphicsConfirmDialog/WarningFrame/Margin/Content/Buttons/ButtonNo
## Blocks navigation while unapplied graphics settings await a decision.
@onready var unsaved_graphics_dialog: Control = $Overlay/UnsavedGraphicsDialog
## Applies unapplied graphics settings before continuing navigation.
@onready var button_save_unsaved_graphics: Button = $Overlay/UnsavedGraphicsDialog/WarningFrame/Margin/Content/Buttons/ButtonSave
## Restores saved graphics settings before continuing navigation.
@onready var button_discard_unsaved_graphics: Button = $Overlay/UnsavedGraphicsDialog/WarningFrame/Margin/Content/Buttons/ButtonDiscard
## Returns to the graphics settings without changing navigation.
@onready var button_go_back_unsaved_graphics: Button = $Overlay/UnsavedGraphicsDialog/WarningFrame/Margin/Content/Buttons/ButtonGoBack
## Runtime camera settings tab.
var tab_camera: Control = null
## Scrollable camera settings content container.
var camera_content: VBoxContainer = null
## Runtime HUD and reticle settings tab.
var tab_displays: Control = null
## Scrollable display settings content container.
var displays_content: VBoxContainer = null
## Controls whether the gameplay HUD and reticles are shown.
var check_hud_visible: CheckBox = null
## Controls normal and contextual ability prompt visibility.
var check_action_prompts: CheckBox = null
## Controls whether the frame-rate counter is shown.
var check_fps_counter: CheckBox = null
## Runtime game-data settings tab.
var tab_data: Control = null
## Opens the local game-data directory.
var button_open_local_files: Button = null
## Rewrites the settings file from the active validated settings.
var button_repair_settings_file: Button = null
## Displays the result of the settings-file repair action.
var label_settings_repair_status: Label = null
## Controls whether each level load writes a diagnostic log.
var check_level_load_logging: CheckBox = null
## Saved player tracking mode selector.
var opt_player_tracking_mode: OptionButton = null

@onready var opt_resolution: OptionButton = $Overlay/OptionsPanel/Panel/VBoxOptions/TabsOptions/TabGraphics/ScrollGraphics/GraphicsContent/HBoxResolution/OptionResolution
## Selects the 3D viewport scaling algorithm.
@onready var opt_render_scale_mode: OptionButton = $Overlay/OptionsPanel/Panel/VBoxOptions/TabsOptions/TabGraphics/ScrollGraphics/GraphicsContent/HBoxRenderScaleMode/OptionRenderScaleMode
## Selects the internal 3D rendering ratio.
@onready var opt_render_scale_ratio: OptionButton = $Overlay/OptionsPanel/Panel/VBoxOptions/TabsOptions/TabGraphics/ScrollGraphics/GraphicsContent/HBoxRenderScaleRatio/OptionRenderScaleRatio
## Selects the atlas size used by 3D shadows.
@onready var opt_shadow_resolution: OptionButton = $Overlay/OptionsPanel/Panel/VBoxOptions/TabsOptions/TabGraphics/ScrollGraphics/GraphicsContent/HBoxShadowResolution/OptionShadowResolution
## Selects the density multiplier used by 3D particles.
@onready var opt_particle_quality: OptionButton = $Overlay/OptionsPanel/Panel/VBoxOptions/TabsOptions/TabGraphics/ScrollGraphics/GraphicsContent/HBoxParticleQuality/OptionParticleQuality
## Applies every staged graphics setting.
@onready var button_apply_resolution: Button = $Overlay/OptionsPanel/Panel/VBoxOptions/TabsOptions/TabGraphics/ScrollGraphics/GraphicsContent/ButtonApplyResolution
@onready var chk_fullscreen: CheckBox = $Overlay/OptionsPanel/Panel/VBoxOptions/TabsOptions/TabGraphics/ScrollGraphics/GraphicsContent/HBoxFullscreen/CheckFullscreen
@onready var chk_vsync: CheckBox      = $Overlay/OptionsPanel/Panel/VBoxOptions/TabsOptions/TabGraphics/ScrollGraphics/GraphicsContent/HBoxVsync/CheckVsync
@onready var chk_ssr: CheckBox        = $Overlay/OptionsPanel/Panel/VBoxOptions/TabsOptions/TabGraphics/ScrollGraphics/GraphicsContent/GridGraphics/CheckSSR
@onready var chk_ssao: CheckBox       = $Overlay/OptionsPanel/Panel/VBoxOptions/TabsOptions/TabGraphics/ScrollGraphics/GraphicsContent/GridGraphics/CheckSSAO
@onready var chk_ssil: CheckBox       = $Overlay/OptionsPanel/Panel/VBoxOptions/TabsOptions/TabGraphics/ScrollGraphics/GraphicsContent/GridGraphics/CheckSSIL
@onready var chk_sdfgi: CheckBox      = $Overlay/OptionsPanel/Panel/VBoxOptions/TabsOptions/TabGraphics/ScrollGraphics/GraphicsContent/GridGraphics/CheckSDFGI
@onready var chk_shadows: CheckBox    = $Overlay/OptionsPanel/Panel/VBoxOptions/TabsOptions/TabGraphics/ScrollGraphics/GraphicsContent/GridGraphics/CheckShadows
@onready var chk_glow: CheckBox       = $Overlay/OptionsPanel/Panel/VBoxOptions/TabsOptions/TabGraphics/ScrollGraphics/GraphicsContent/GridGraphics/CheckGlow
@onready var chk_depth_of_field: CheckBox = $Overlay/OptionsPanel/Panel/VBoxOptions/TabsOptions/TabGraphics/ScrollGraphics/GraphicsContent/GridGraphics/CheckDepthOfField
## Enables each level's configured volumetric fog.
@onready var chk_volumetric_fog: CheckBox = $Overlay/OptionsPanel/Panel/VBoxOptions/TabsOptions/TabGraphics/ScrollGraphics/GraphicsContent/GridGraphics/CheckVolumetricFog
## Enables rain cover probes and particle collision heightfields.
@onready var chk_weather_occlusion: CheckBox = $Overlay/OptionsPanel/Panel/VBoxOptions/TabsOptions/TabGraphics/ScrollGraphics/GraphicsContent/GridGraphics/CheckWeatherOcclusion
@onready var chk_water_displacement: CheckBox = $Overlay/OptionsPanel/Panel/VBoxOptions/TabsOptions/TabGraphics/ScrollGraphics/GraphicsContent/GridGraphics/CheckWaterDisplacement
@onready var chk_water_refraction: CheckBox = $Overlay/OptionsPanel/Panel/VBoxOptions/TabsOptions/TabGraphics/ScrollGraphics/GraphicsContent/GridGraphics/CheckWaterRefraction
@onready var chk_water_normals: CheckBox = $Overlay/OptionsPanel/Panel/VBoxOptions/TabsOptions/TabGraphics/ScrollGraphics/GraphicsContent/GridGraphics/CheckWaterNormals
@onready var chk_water_depth_fx: CheckBox = $Overlay/OptionsPanel/Panel/VBoxOptions/TabsOptions/TabGraphics/ScrollGraphics/GraphicsContent/GridGraphics/CheckWaterDepthFx
## Selects the global multiplier applied to object LOD transition distances.
@onready var opt_lod_distance: OptionButton = $Overlay/OptionsPanel/Panel/VBoxOptions/TabsOptions/TabGraphics/ScrollGraphics/GraphicsContent/HBoxLOD/OptionLOD

@onready var slider_master: HSlider = $Overlay/OptionsPanel/Panel/VBoxOptions/TabsOptions/TabAudio/ScrollAudio/AudioContent/HBoxMaster/SliderMaster
@onready var slider_music: HSlider  = $Overlay/OptionsPanel/Panel/VBoxOptions/TabsOptions/TabAudio/ScrollAudio/AudioContent/HBoxMusic/SliderMusic
@onready var slider_sfx: HSlider    = $Overlay/OptionsPanel/Panel/VBoxOptions/TabsOptions/TabAudio/ScrollAudio/AudioContent/HBoxSfx/SliderSfx
## Controls the UI audio bus volume from the pause menu.
@onready var slider_ui: HSlider = $Overlay/OptionsPanel/Panel/VBoxOptions/TabsOptions/TabAudio/ScrollAudio/AudioContent/HBoxUi/SliderUi
@onready var slider_voice: HSlider  = $Overlay/OptionsPanel/Panel/VBoxOptions/TabsOptions/TabAudio/ScrollAudio/AudioContent/HBoxVoice/SliderVoice
@onready var slider_camera_far: HSlider = $Overlay/OptionsPanel/Panel/VBoxOptions/TabsOptions/TabGraphics/ScrollGraphics/GraphicsContent/HBoxCameraFar/SliderCameraFar
@onready var slider_camera_fov: HSlider = $Overlay/OptionsPanel/Panel/VBoxOptions/TabsOptions/TabGraphics/ScrollGraphics/GraphicsContent/HBoxCameraFov/SliderCameraFov
@onready var opt_homing_target_mode: OptionButton = $Overlay/OptionsPanel/Panel/VBoxOptions/TabsOptions/TabGameplay/ScrollGameplay/GameplayContent/HBoxHomingTargetMode/OptionHomingTargetMode
## Labels the primary or controller-specific homing targeting selector.
@onready var label_homing_target_mode: Label = $Overlay/OptionsPanel/Panel/VBoxOptions/TabsOptions/TabGameplay/ScrollGameplay/GameplayContent/HBoxHomingTargetMode/LabelHomingTargetMode
## Enables separate homing targeting modes for controller and mouse input.
@onready var chk_separate_homing_targeting: CheckBox = $Overlay/OptionsPanel/Panel/VBoxOptions/TabsOptions/TabGameplay/ScrollGameplay/GameplayContent/HBoxSeparateHomingTargeting/CheckSeparateHomingTargeting
## Contains the mouse-specific homing targeting selector.
@onready var row_mouse_homing_target_mode: HBoxContainer = $Overlay/OptionsPanel/Panel/VBoxOptions/TabsOptions/TabGameplay/ScrollGameplay/GameplayContent/HBoxMouseHomingTargetMode
## Selects the homing targeting mode used after mouse or keyboard input.
@onready var opt_mouse_homing_target_mode: OptionButton = $Overlay/OptionsPanel/Panel/VBoxOptions/TabsOptions/TabGameplay/ScrollGameplay/GameplayContent/HBoxMouseHomingTargetMode/OptionMouseHomingTargetMode
@onready var opt_lightspeed_dash_target_mode: OptionButton = $Overlay/OptionsPanel/Panel/VBoxOptions/TabsOptions/TabGameplay/ScrollGameplay/GameplayContent/HBoxLightspeedDashTargetMode/OptionLightspeedDashTargetMode
@onready var slider_homing_radius: HSlider = $Overlay/OptionsPanel/Panel/VBoxOptions/TabsOptions/TabGameplay/ScrollGameplay/GameplayContent/HBoxHomingCameraRadius/SliderHomingRadius
@onready var slider_camera_follow_smoothing: HSlider = $Overlay/OptionsPanel/Panel/VBoxOptions/TabsOptions/TabGameplay/ScrollGameplay/GameplayContent/HBoxCameraFollowSmoothing/SliderCameraFollowSmoothing
## Enables the velocity-matched positional camera dolly.
@onready var chk_camera_dolly: CheckBox = $Overlay/OptionsPanel/Panel/VBoxOptions/TabsOptions/TabGameplay/ScrollGameplay/GameplayContent/HBoxCameraDolly/CheckCameraDolly
## Enables predictive target tracking for the camera dolly.
@onready var chk_camera_target_lookahead: CheckBox = $Overlay/OptionsPanel/Panel/VBoxOptions/TabsOptions/TabGameplay/ScrollGameplay/GameplayContent/HBoxCameraTargetLookahead/CheckCameraTargetLookahead
## Controls the strength of the camera dolly's target lookahead.
@onready var slider_camera_target_lookahead: HSlider = $Overlay/OptionsPanel/Panel/VBoxOptions/TabsOptions/TabGameplay/ScrollGameplay/GameplayContent/HBoxCameraTargetLookaheadAmount/SliderCameraTargetLookaheadAmount
@onready var chk_auto_follow_camera: CheckBox = $Overlay/OptionsPanel/Panel/VBoxOptions/TabsOptions/TabGameplay/ScrollGameplay/GameplayContent/HBoxAutoFollowCamera/CheckAutoFollowCamera
## Restricts camera auto-follow behavior to the active controller input scheme.
@onready var chk_auto_follow_controller_only: CheckBox = $Overlay/OptionsPanel/Panel/VBoxOptions/TabsOptions/TabGameplay/ScrollGameplay/GameplayContent/HBoxAutoFollowControllerOnly/CheckAutoFollowControllerOnly
@onready var slider_auto_follow_sensitivity: HSlider = $Overlay/OptionsPanel/Panel/VBoxOptions/TabsOptions/TabGameplay/ScrollGameplay/GameplayContent/HBoxAutoFollowSensitivity/SliderAutoFollowSensitivity
@onready var slider_auto_follow_interrupt_delay: HSlider = $Overlay/OptionsPanel/Panel/VBoxOptions/TabsOptions/TabGameplay/ScrollGameplay/GameplayContent/HBoxAutoFollowInterruptDelay/SliderAutoFollowInterruptDelay
@onready var chk_center_reticle: CheckBox = $Overlay/OptionsPanel/Panel/VBoxOptions/TabsOptions/TabGameplay/ScrollGameplay/GameplayContent/HBoxCenterReticle/CheckCenterReticle
@onready var slider_center_reticle_scale: HSlider = $Overlay/OptionsPanel/Panel/VBoxOptions/TabsOptions/TabGameplay/ScrollGameplay/GameplayContent/HBoxCenterReticleScale/SliderCenterReticleScale
@onready var slider_center_reticle_opacity: HSlider = $Overlay/OptionsPanel/Panel/VBoxOptions/TabsOptions/TabGameplay/ScrollGameplay/GameplayContent/HBoxCenterReticleOpacity/SliderCenterReticleOpacity
@onready var color_center_reticle: ColorPickerButton = $Overlay/OptionsPanel/Panel/VBoxOptions/TabsOptions/TabGameplay/ScrollGameplay/GameplayContent/HBoxCenterReticleColor/ColorCenterReticle
## Controls whether the emote wheel remembers its last used page.
@onready var chk_remember_emote_page: CheckBox = $Overlay/OptionsPanel/Panel/VBoxOptions/TabsOptions/TabGameplay/ScrollGameplay/GameplayContent/HBoxRememberEmotePage/CheckRememberEmotePage
@onready var chk_combo_system: CheckBox = $Overlay/OptionsPanel/Panel/VBoxOptions/TabsOptions/TabGameplay/ScrollGameplay/GameplayContent/HBoxComboSystem/CheckComboSystem
@onready var slider_reticle_vertical_offset: HSlider = $Overlay/OptionsPanel/Panel/VBoxOptions/TabsOptions/TabGameplay/ScrollGameplay/GameplayContent/HBoxReticleVerticalOffset/SliderReticleVerticalOffset
@onready var chk_use_character_colors_offline: CheckBox = $Overlay/OptionsPanel/Panel/VBoxOptions/TabsOptions/TabGameplay/ScrollGameplay/GameplayContent/HBoxUseCharacterColorsOffline/CheckUseCharacterColorsOffline
@onready var color_offline_primary: ColorPickerButton = $Overlay/OptionsPanel/Panel/VBoxOptions/TabsOptions/TabGameplay/ScrollGameplay/GameplayContent/HBoxOfflinePrimaryColor/ColorOfflinePrimary
@onready var color_offline_secondary: ColorPickerButton = $Overlay/OptionsPanel/Panel/VBoxOptions/TabsOptions/TabGameplay/ScrollGameplay/GameplayContent/HBoxOfflineSecondaryColor/ColorOfflineSecondary
@onready var color_offline_trail: ColorPickerButton = $Overlay/OptionsPanel/Panel/VBoxOptions/TabsOptions/TabGameplay/ScrollGameplay/GameplayContent/HBoxOfflineTrailColor/ColorOfflineTrail
## Controls whether eligible single-player race runs are captured for optional saving.
@onready var chk_record_race_ghosts: CheckBox = $Overlay/OptionsPanel/Panel/VBoxOptions/TabsOptions/TabGameplay/ScrollGameplay/GameplayContent/HBoxRecordRaceGhosts/CheckRecordRaceGhosts
## Selects the sampling rate used for new race ghost recordings.
@onready var opt_ghost_recording_rate: OptionButton = $Overlay/OptionsPanel/Panel/VBoxOptions/TabsOptions/TabGameplay/ScrollGameplay/GameplayContent/HBoxGhostRecordingRate/OptionGhostRecordingRate
## Caps how frequently ghost playback poses are applied.
@onready var opt_ghost_playback_rate: OptionButton = $Overlay/OptionsPanel/Panel/VBoxOptions/TabsOptions/TabGameplay/ScrollGameplay/GameplayContent/HBoxGhostPlaybackRate/OptionGhostPlaybackRate
## Describes the current race ghost recording and playback policy.
@onready var label_ghost_recording_hint: Label = $Overlay/OptionsPanel/Panel/VBoxOptions/TabsOptions/TabGameplay/ScrollGameplay/GameplayContent/GhostRecordingHint

var slider_auto_follow_deadzone: HSlider
var slider_auto_follow_max_deviation: HSlider
var chk_auto_follow_vertical_enabled: CheckBox
var slider_auto_follow_vertical_max_tilt: HSlider
var slider_auto_follow_level_pitch: HSlider

var _deadzone_visual: Control

var _is_open: bool = false
var _hud_cached = null
var _net_session = null
var _sfx_player: AudioStreamPlayer = null
var _network_stats_accum: float = 0.0
var _pause_preview_hidden: bool = false
var _pause_preview_focus_owner: Control = null
var _pause_preview_binding_suppressed: bool = false
var _graphics_previous_snapshot: Dictionary = {}
var _graphics_confirmation_remaining: float = 0.0
var _last_options_tab: int = 0
var _pending_options_tab: int = -1
var _pending_options_exit: bool = false
var _changing_options_tab: bool = false
const GRAPHICS_CONFIRMATION_DURATION: float = 15.0

@export_group("Sounds")
@export var sfx_bus: StringName = &"UI"
@export var sfx_pause: AudioStream = preload("res://LS5Framework/Sounds/Menu/Pause.wav")
@export var sfx_unpause: AudioStream = preload("res://LS5Framework/Sounds/Menu/Unpause.wav")
## Audio cue played when a blocking warning or confirmation opens.
@export var sfx_warning: AudioStream = preload("res://LS5Framework/Sounds/Menu/ui_warning.wav")


func _is_online() -> bool:
	return multiplayer != null and multiplayer.has_multiplayer_peer()


func _get_local_player() -> Node:
	var list = get_tree().get_nodes_in_group("Player")
	for p in list:
		if p != null and p.has_method("set_local_pause_enabled"):
			# In online, only the authority should be locally paused.
			if not _is_online() or p.is_multiplayer_authority():
				return p
	return null


func _get_hud_node() -> Node:
	if hud != null:
		return hud
	if _hud_cached != null:
		return _hud_cached

	var found = null
	if get_tree() != null:
		var cs = get_tree().current_scene
		if cs != null:
			found = cs.get_node_or_null("HUD")
	if found == null:
		found = get_node_or_null("../HUD")

	_hud_cached = found
	return found


func _set_hud_visible(value: bool) -> void:
	var h = _get_hud_node()
	if h != null:
		h.visible = value and SettingsManager.hud_visible


func _ready() -> void:
	_create_pause_shortcut_prompts()
	SettingsManager.input_bindings_changed.connect(func() -> void: _shortcut_signature = "")
	Input.joy_connection_changed.connect(func(_device: int, connected: bool) -> void:
		if not connected:
			_cancel_pause_shortcut_hold()
	)
	tab_bindings.loadout_mapping_requested.connect(_on_loadout_mapping_requested)
	add_to_group("PauseMenu")
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_process(true)
	set_process_input(true)
	set_process_unhandled_input(true)
	visible = false
	_show_pause_panel()
	_ensure_camera_tab()
	_ensure_displays_tab()
	_ensure_data_tab()
	_ensure_player_tracking_setting()
	_organize_options_tabs()
	_configure_graphics_apply_button()
	_configure_options_tab_focus()
	_apply_tab_titles()
	_populate_resolution_list()
	_populate_render_scaling_options()
	_populate_graphics_quality_options()
	_populate_lod_distance_options()
	_populate_homing_target_mode()
	_populate_lightspeed_dash_target_mode()
	_populate_ghost_recording_rates()
	_populate_ghost_playback_rates()
	_build_auto_follow_tuning_ui()
	_organize_gameplay_sections()
	_sync_options_from_settings()
	_last_options_tab = tabs_options.current_tab
	if tabs_options != null and not tabs_options.tab_changed.is_connected(_on_options_tab_changed):
		tabs_options.tab_changed.connect(_on_options_tab_changed)
	_wire_online_signals()
	if button_copy_invite != null:
		button_copy_invite.pressed.connect(_on_copy_invite_pressed)


func _wire_online_signals() -> void:
	_net_session = _get_network_session()
	if _net_session == null:
		return
	if _net_session.has_signal("peer_name_changed"):
		if not _net_session.peer_name_changed.is_connected(_on_peer_name_changed):
			_net_session.peer_name_changed.connect(_on_peer_name_changed)
	if _net_session.has_signal("race_queue_updated"):
		if not _net_session.race_queue_updated.is_connected(_on_race_queue_updated):
			_net_session.race_queue_updated.connect(_on_race_queue_updated)


func _process(delta: float) -> void:
	_update_pause_shortcuts(delta)
	if is_instance_valid(_character_settings_menu):
		return
	if graphics_confirm_dialog.visible:
		_update_graphics_confirmation(delta)
		return
	if unsaved_graphics_dialog.visible:
		return
	if reset_defaults_dialog.visible:
		return
	_update_pause_preview_visibility()
	if _is_open and _is_online():
		_network_stats_accum += max(delta, 0.0)
		if _network_stats_accum >= 0.25:
			_network_stats_accum = 0.0
			_refresh_connection_info()
	if _is_input_binding_active():
		return
	if _pause_preview_hidden:
		return
	if quick_restart_action != &"" and SettingsManager.is_gameplay_action_just_pressed(quick_restart_action) and not (_is_open and SettingsManager.is_controller_input_active()):
		if not _is_text_input_focused() and _can_quick_restart():
			_do_quick_restart()
			return
	if _is_open:
		_handle_right_stick_scroll(delta)


func _update_pause_preview_visibility() -> void:
	if _is_input_binding_active():
		_pause_preview_binding_suppressed = true
		_set_pause_preview_hidden(false)
		return
	if _pause_preview_binding_suppressed:
		var preview_still_pressed: bool = InputMap.has_action(PAUSE_PREVIEW_ACTION) and Input.is_action_pressed(PAUSE_PREVIEW_ACTION)
		if preview_still_pressed:
			_set_pause_preview_hidden(false)
			return
		_pause_preview_binding_suppressed = false
	var should_hide: bool = false
	if _is_open and InputMap.has_action(PAUSE_PREVIEW_ACTION):
		should_hide = Input.is_action_pressed(PAUSE_PREVIEW_ACTION)
	_set_pause_preview_hidden(should_hide)


func _set_pause_preview_hidden(hidden: bool) -> void:
	if _pause_preview_hidden == hidden:
		return
	_pause_preview_hidden = hidden
	if hidden:
		var focus_owner: Control = get_viewport().gui_get_focus_owner()
		if focus_owner != null and overlay.is_ancestor_of(focus_owner):
			_pause_preview_focus_owner = focus_owner
		dimmer.visible = false
		overlay.visible = false
		_set_hud_visible(true)
		var player: Node = _get_local_player()
		if player != null and player.has_method("refresh_pause_preview_ui"):
			player.call("refresh_pause_preview_ui")
		return

	dimmer.visible = true
	overlay.visible = true
	if _is_open:
		_set_hud_visible(false)
		if _pause_preview_focus_owner != null and is_instance_valid(_pause_preview_focus_owner) and _pause_preview_focus_owner.is_visible_in_tree():
			_pause_preview_focus_owner.call_deferred("grab_focus")
		else:
			call_deferred("_focus_visible_panel")
	_pause_preview_focus_owner = null


func _input(event: InputEvent) -> void:
	if is_instance_valid(_character_settings_menu):
		return
	if _is_input_binding_active():
		return
	if not _is_open:
		return
	if graphics_confirm_dialog.visible:
		return
	if unsaved_graphics_dialog.visible:
		return
	if reset_defaults_dialog.visible:
		return
	if _pause_preview_hidden:
		return
	if _handle_options_tab_input(event):
		get_viewport().set_input_as_handled()
		return
	if not panel_pause.visible or panel_options.visible:
		return
	if _can_use_pause_shortcuts() and _handle_pause_shortcut(event):
		get_viewport().set_input_as_handled()
		return


func _unhandled_input(event: InputEvent) -> void:
	if is_instance_valid(_character_settings_menu):
		return
	if event == null or _is_input_binding_active():
		return
	if graphics_confirm_dialog.visible:
		if event.is_action_pressed("ui_cancel") or event.is_action_pressed("pause"):
			_on_graphics_settings_reverted()
			get_viewport().set_input_as_handled()
		return
	if unsaved_graphics_dialog.visible:
		if event.is_action_pressed("ui_cancel") or event.is_action_pressed("pause"):
			_on_unsaved_graphics_go_back_pressed()
			get_viewport().set_input_as_handled()
		return
	if reset_defaults_dialog.visible:
		if event.is_action_pressed("ui_cancel") or event.is_action_pressed("pause"):
			_on_reset_defaults_canceled()
			get_viewport().set_input_as_handled()
		return
	if get_tree() != null and get_tree().has_meta(&"chat_input_active") and bool(get_tree().get_meta(&"chat_input_active")):
		return
	var cancel_pressed: bool = event.is_action_pressed("ui_cancel")
	var pause_pressed: bool = event.is_action_pressed("pause")
	if not cancel_pressed and not pause_pressed:
		return
	if _is_open:
		get_viewport().set_input_as_handled()
		if panel_options.visible:
			_on_ButtonOptionsBack_pressed()
		else:
			_resume_game()
		return
	if not pause_pressed or _has_active_modal_menu() or not _can_open_pause():
		return
	get_viewport().set_input_as_handled()
	_open_pause()


func _has_active_modal_menu() -> bool:
	for menu in get_tree().get_nodes_in_group("ModalMenu"):
		if menu is CanvasItem and is_instance_valid(menu) and menu.is_visible_in_tree():
			return true
	return false


func _on_loadout_mapping_requested() -> void:
	if is_instance_valid(_character_settings_menu):
		return
	var entry: Dictionary = CharacterCatalog.get_selected_or_default_entry("res://LS5Framework/Characters", SettingsManager.chosen_character_id)
	_character_settings_menu = CHARACTER_SETTINGS_MENU_SCENE.instantiate() as CharacterSettingsMenu
	overlay.add_child(_character_settings_menu)
	_character_settings_menu.closed.connect(_on_character_settings_closed)
	_character_settings_menu.open_for_character(entry)


func _on_character_settings_closed() -> void:
	_character_settings_menu = null
	tab_bindings.loadout_mapping_button.call_deferred("grab_focus")


func _can_open_pause() -> bool:
	var player: Node = _get_local_player()
	if player != null and player.has_method("get"):
		var in_countdown = player.get("race_in_countdown")
		if in_countdown is bool and bool(in_countdown):
			return false
	for race_start in get_tree().get_nodes_in_group("RaceStart"):
		if race_start.get("_sequence_running"):
			return false
	return true


func _open_pause() -> void:
	_set_pause_preview_hidden(false)
	visible = true
	_show_pause_panel()
	_is_open = true
	_set_hud_visible(false)
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	_play_sfx(sfx_pause)
	var p = _get_local_player()
	if p != null:
		p.call("set_ui_input_blocked", true)
		if p.has_method("set_combo_ui_pause_hidden"):
			p.call("set_combo_ui_pause_hidden", true)
	if _is_online():
		_refresh_player_list()
		_refresh_return_hub_button()
		_refresh_quick_restart_button()
		if p != null:
			p.call("set_local_pause_enabled", true)
	else:
		get_tree().paused = true
	_refresh_race_leave_button()
	_refresh_return_hub_button()
	_refresh_quick_restart_button()


func _release_gameplay_inputs() -> void:
	var allowed: Array[StringName] = [
		&"ui_left", &"ui_right", &"ui_up", &"ui_down",
		&"ui_accept", &"ui_cancel", &"ui_select",
		&"ui_focus_next", &"ui_focus_prev",
		&"ui_page_up", &"ui_page_down", &"ui_home", &"ui_end",
		&"shortcut_respawn", &"shortcut_checkpoint", &"pause",
	]
	for action in InputMap.get_actions():
		if action in allowed:
			continue
		Input.action_release(action)


func _resume_game(lock_cursor: bool = true) -> void:
	_release_gameplay_inputs()
	_stop_camera_preview()
	_set_pause_preview_hidden(false)
	if _deadzone_visual != null:
		_deadzone_visual.visible = false
	visible = false
	panel_options.visible = false
	_is_open = false
	_set_hud_visible(true)
	if online_panel != null:
		online_panel.visible = false
	var p = _get_local_player()
	if p != null:
		p.call("set_ui_input_blocked", false)
		if p.has_method("set_combo_ui_pause_hidden"):
			p.call("set_combo_ui_pause_hidden", false)
	if _is_online():
		if p != null:
			p.call("set_local_pause_enabled", false)
	else:
		get_tree().paused = false
	if lock_cursor:
		Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
	else:
		Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	if p != null and p.has_method("restore_input_after_pause"):
		p.call_deferred("restore_input_after_pause")
	_play_sfx(sfx_unpause)


func _get_network_session() -> Node:
	if get_tree() == null:
		return null
	var cs = get_tree().current_scene
	if cs == null:
		return null
	return cs.get_node_or_null("NetworkSession")


func _on_peer_name_changed(_peer_id: int, _name: String) -> void:
	if _is_open and _is_online():
		_refresh_player_list()


func _on_race_queue_updated() -> void:
	if _is_open and _is_online():
		_refresh_player_list()


func _clear_children(node: Node) -> void:
	if node == null:
		return
	for c in node.get_children():
		if c != null:
			c.queue_free()


func _apply_tab_titles() -> void:
	_set_tab_title(tab_gameplay, "Gameplay")
	_set_tab_title(tab_controls, "Controls")
	_set_tab_title(tab_bindings, "Bindings")
	_set_tab_title(tab_camera, "Camera")
	_set_tab_title(tab_displays, "Displays")
	_set_tab_title(tab_graphics, "Graphics")
	_set_tab_title(tab_audio, "Audio")
	_set_tab_title(tab_data, "Data")


func _organize_options_tabs() -> void:
	if tabs_options == null:
		return
	tabs_options.move_child(tab_gameplay, 0)
	tabs_options.move_child(tab_controls, 1)
	tabs_options.move_child(tab_bindings, 2)
	tabs_options.move_child(tab_camera, 3)
	tabs_options.move_child(tab_displays, 4)
	tabs_options.move_child(tab_graphics, 5)
	tabs_options.move_child(tab_audio, 6)
	tabs_options.move_child(tab_data, 7)
	tabs_options.current_tab = 0


func _configure_options_tab_focus() -> void:
	if tabs_options == null:
		return
	tabs_options.focus_mode = Control.FOCUS_NONE
	var tab_bar: TabBar = tabs_options.get_tab_bar()
	if tab_bar != null:
		tab_bar.focus_mode = Control.FOCUS_NONE


func _ensure_camera_tab() -> void:
	if tabs_options == null or tab_camera != null:
		return
	var camera_tab: VBoxContainer = VBoxContainer.new()
	camera_tab.name = "TabCamera"
	camera_tab.size_flags_vertical = Control.SIZE_EXPAND_FILL
	camera_tab.add_theme_constant_override("separation", 8)
	tabs_options.add_child(camera_tab)
	tab_camera = camera_tab

	var scroll: ScrollContainer = ScrollContainer.new()
	scroll.name = "ScrollCamera"
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	camera_tab.add_child(scroll)

	camera_content = VBoxContainer.new()
	camera_content.name = "CameraContent"
	camera_content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	camera_content.add_theme_constant_override("separation", 8)
	scroll.add_child(camera_content)

	var graphics_content: Node = tab_graphics.get_node_or_null("ScrollGraphics/GraphicsContent")
	var gameplay_content: Node = tab_gameplay.get_node_or_null("ScrollGameplay/GameplayContent")
	var camera_nodes: Array[Node] = []
	if gameplay_content != null:
		var camera_heading: Node = gameplay_content.get_node_or_null("CameraHeading")
		if camera_heading != null:
			camera_nodes.append(camera_heading)
	if graphics_content != null:
		for node_name: StringName in [&"HBoxCameraFov"]:
			var graphics_camera_node: Node = graphics_content.get_node_or_null(NodePath(String(node_name)))
			if graphics_camera_node != null:
				camera_nodes.append(graphics_camera_node)
	if gameplay_content != null:
		for node_name: StringName in [&"HBoxCameraFollowSmoothing", &"HBoxCameraDolly", &"HBoxAutoFollowCamera", &"HBoxAutoFollowControllerOnly", &"HBoxAutoFollowSensitivity", &"HBoxAutoFollowInterruptDelay"]:
			var gameplay_camera_node: Node = gameplay_content.get_node_or_null(NodePath(String(node_name)))
			if gameplay_camera_node != null:
				camera_nodes.append(gameplay_camera_node)
	for camera_node: Node in camera_nodes:
		camera_node.reparent(camera_content, false)


func _ensure_displays_tab() -> void:
	if tabs_options == null or tab_displays != null:
		return
	var displays_tab: VBoxContainer = VBoxContainer.new()
	displays_tab.name = "TabDisplays"
	displays_tab.size_flags_vertical = Control.SIZE_EXPAND_FILL
	displays_tab.add_theme_constant_override("separation", 8)
	tabs_options.add_child(displays_tab)
	tab_displays = displays_tab

	var scroll: ScrollContainer = ScrollContainer.new()
	scroll.name = "ScrollDisplays"
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	displays_tab.add_child(scroll)

	displays_content = VBoxContainer.new()
	displays_content.name = "DisplaysContent"
	displays_content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	displays_content.add_theme_constant_override("separation", 8)
	scroll.add_child(displays_content)

	var hud_heading: Label = Label.new()
	hud_heading.name = "HUDHeading"
	hud_heading.text = "HUD"
	hud_heading.add_theme_color_override("font_color", Color(0.35, 0.78, 1.0, 1.0))
	hud_heading.add_theme_font_size_override("font_size", 17)
	displays_content.add_child(hud_heading)

	var hud_row: HBoxContainer = HBoxContainer.new()
	hud_row.name = "HBoxHUDVisible"
	hud_row.add_theme_constant_override("separation", 12)
	var hud_label: Label = Label.new()
	hud_label.text = "Show HUD"
	hud_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hud_row.add_child(hud_label)
	check_hud_visible = CheckBox.new()
	check_hud_visible.name = "CheckHUDVisible"
	check_hud_visible.tooltip_text = "Show gameplay HUD elements and targeting reticles. The pause menu remains available when disabled."
	check_hud_visible.button_pressed = SettingsManager.hud_visible
	check_hud_visible.add_to_group("MenuButtons")
	check_hud_visible.toggled.connect(_on_hud_visible_toggled)
	hud_row.add_child(check_hud_visible)
	displays_content.add_child(hud_row)

	var prompt_row: HBoxContainer = HBoxContainer.new()
	prompt_row.name = "HBoxActionPrompts"
	prompt_row.add_theme_constant_override("separation", 12)
	var prompt_label: Label = Label.new()
	prompt_label.text = "Show Ability Prompts"
	prompt_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	prompt_row.add_child(prompt_label)
	check_action_prompts = CheckBox.new()
	check_action_prompts.name = "CheckActionPrompts"
	check_action_prompts.tooltip_text = "Show ability prompts and urgent contextual prompts. Requires Show HUD."
	check_action_prompts.button_pressed = SettingsManager.action_prompts_visible
	check_action_prompts.add_to_group("MenuButtons")
	check_action_prompts.toggled.connect(_on_action_prompts_toggled)
	prompt_row.add_child(check_action_prompts)
	displays_content.add_child(prompt_row)

	var fps_row: HBoxContainer = HBoxContainer.new()
	fps_row.name = "HBoxFPSCounter"
	fps_row.add_theme_constant_override("separation", 12)
	var fps_label: Label = Label.new()
	fps_label.text = "Show FPS Counter"
	fps_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	fps_row.add_child(fps_label)
	check_fps_counter = CheckBox.new()
	check_fps_counter.name = "CheckFPSCounter"
	check_fps_counter.tooltip_text = "Show a small frame-rate counter in the top-right corner."
	check_fps_counter.button_pressed = SettingsManager.fps_counter_visible
	check_fps_counter.add_to_group("MenuButtons")
	check_fps_counter.toggled.connect(_on_fps_counter_toggled)
	fps_row.add_child(check_fps_counter)
	displays_content.add_child(fps_row)

	var gameplay_content: Node = tab_gameplay.get_node_or_null("ScrollGameplay/GameplayContent")
	if gameplay_content == null:
		return
	for node_name: StringName in [&"ReticleHeading", &"HBoxCenterReticle", &"HBoxCenterReticleScale", &"HBoxCenterReticleOpacity", &"HBoxCenterReticleColor", &"HBoxReticleVerticalOffset"]:
		var reticle_node: Node = gameplay_content.get_node_or_null(NodePath(String(node_name)))
		if reticle_node != null:
			reticle_node.reparent(displays_content, false)


func _ensure_data_tab() -> void:
	if tabs_options == null or tab_data != null:
		return
	tab_data = VBoxContainer.new()
	tab_data.name = "TabData"
	tab_data.size_flags_vertical = Control.SIZE_EXPAND_FILL
	tab_data.add_theme_constant_override("separation", 12)
	tabs_options.add_child(tab_data)

	var heading: Label = Label.new()
	heading.text = "LOCAL GAME DATA"
	heading.add_theme_color_override("font_color", Color(0.35, 0.78, 1.0, 1.0))
	heading.add_theme_font_size_override("font_size", 17)
	tab_data.add_child(heading)

	var description: Label = Label.new()
	description.text = "Open the folder containing settings, ghost recordings, and other locally saved data."
	description.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	tab_data.add_child(description)

	check_level_load_logging = CheckBox.new()
	check_level_load_logging.name = "CheckLevelLoadLogging"
	check_level_load_logging.text = "Write Level Load Log"
	check_level_load_logging.tooltip_text = "Overwrite level_load.log with resource and scene setup timings each time a level loads."
	check_level_load_logging.custom_minimum_size.y = 48.0
	check_level_load_logging.button_pressed = SettingsManager.level_load_logging_enabled
	check_level_load_logging.add_to_group("MenuButtons")
	check_level_load_logging.toggled.connect(_on_level_load_logging_toggled)
	tab_data.add_child(check_level_load_logging)

	var repair_description: Label = Label.new()
	repair_description.name = "RepairSettingsDescription"
	repair_description.text = "If level loading hangs or repeatedly takes too long, repair settings.cfg and restart the game. This keeps the currently active settings while removing invalid or obsolete file data."
	repair_description.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	tab_data.add_child(repair_description)

	button_repair_settings_file = Button.new()
	button_repair_settings_file.name = "ButtonRepairSettingsFile"
	button_repair_settings_file.text = "Repair Settings File"
	button_repair_settings_file.tooltip_text = "Rewrite settings.cfg using the currently active validated settings."
	button_repair_settings_file.custom_minimum_size.y = 48.0
	button_repair_settings_file.add_to_group("MenuButtons")
	button_repair_settings_file.pressed.connect(_on_repair_settings_file_pressed)
	tab_data.add_child(button_repair_settings_file)

	label_settings_repair_status = Label.new()
	label_settings_repair_status.name = "RepairSettingsStatus"
	label_settings_repair_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label_settings_repair_status.visible = false
	tab_data.add_child(label_settings_repair_status)

	button_open_local_files = Button.new()
	button_open_local_files.name = "ButtonOpenLocalFiles"
	button_open_local_files.text = "Open Local Files"
	button_open_local_files.tooltip_text = "Open the LS5 Engine 3 local data folder in File Explorer."
	button_open_local_files.custom_minimum_size.y = 48.0
	button_open_local_files.add_to_group("MenuButtons")
	button_open_local_files.pressed.connect(_on_open_local_files_pressed)
	tab_data.add_child(button_open_local_files)


func _on_open_local_files_pressed() -> void:
	var data_directory: String = OS.get_user_data_dir()
	if not DirAccess.dir_exists_absolute(data_directory):
		var create_error: Error = DirAccess.make_dir_recursive_absolute(data_directory)
		if create_error != OK:
			push_warning("Could not create local data directory: %s" % data_directory)
			return
	var open_error: Error = OS.shell_open(data_directory)
	if open_error != OK:
		push_warning("Could not open local data directory: %s" % data_directory)


func _on_repair_settings_file_pressed() -> void:
	var repair_error: Error = SettingsManager.repair_settings_file()
	if label_settings_repair_status == null:
		return
	label_settings_repair_status.visible = true
	if repair_error == OK:
		label_settings_repair_status.text = "Settings file repaired. Restart the game before retrying the affected level."
		label_settings_repair_status.add_theme_color_override(&"font_color", Color(0.45, 1.0, 0.62, 1.0))
	else:
		label_settings_repair_status.text = "Settings file repair failed: %s" % error_string(repair_error)
		label_settings_repair_status.add_theme_color_override(&"font_color", Color(1.0, 0.42, 0.28, 1.0))


func _on_level_load_logging_toggled(pressed: bool) -> void:
	SettingsManager.set_level_load_logging_enabled(pressed)
	SettingsManager.save_now()


func _ensure_player_tracking_setting() -> void:
	if opt_player_tracking_mode != null:
		return
	var content: VBoxContainer = tab_gameplay.get_node_or_null("ScrollGameplay/GameplayContent") as VBoxContainer
	if content == null:
		return
	var heading: Label = Label.new()
	heading.name = "OnlineHeading"
	heading.text = "ONLINE"
	heading.add_theme_color_override("font_color", Color(0.35, 0.78, 1.0, 1.0))
	heading.add_theme_font_size_override("font_size", 17)
	content.add_child(heading)
	content.move_child(heading, 0)

	var row: HBoxContainer = HBoxContainer.new()
	row.name = "HBoxPlayerTrackingMode"
	row.add_theme_constant_override("separation", 12)
	var label: Label = Label.new()
	label.text = "Player Tracking"
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(label)
	opt_player_tracking_mode = OptionButton.new()
	opt_player_tracking_mode.name = "OptionPlayerTrackingMode"
	opt_player_tracking_mode.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	opt_player_tracking_mode.add_item("Full", SettingsManager.PLAYER_TRACKING_MODE_FULL)
	opt_player_tracking_mode.add_item("Minimal", SettingsManager.PLAYER_TRACKING_MODE_MINIMAL)
	opt_player_tracking_mode.add_item("Off", SettingsManager.PLAYER_TRACKING_MODE_OFF)
	opt_player_tracking_mode.add_to_group("MenuButtons")
	opt_player_tracking_mode.item_selected.connect(_on_OptionPlayerTrackingMode_item_selected)
	row.add_child(opt_player_tracking_mode)
	content.add_child(row)
	content.move_child(row, 1)



func _organize_gameplay_sections() -> void:
	var content: VBoxContainer = get_node_or_null("Overlay/OptionsPanel/Panel/VBoxOptions/TabsOptions/TabGameplay/ScrollGameplay/GameplayContent") as VBoxContainer
	if content == null:
		return
	var race_heading: Node = content.get_node_or_null("GhostReplayHeading")
	var combo_row: Node = content.get_node_or_null("HBoxComboSystem")
	var reticle_offset_row: Node = content.get_node_or_null("HBoxReticleVerticalOffset")
	if race_heading != null and combo_row != null:
		content.move_child(race_heading, combo_row.get_index())
	if reticle_offset_row != null and race_heading != null:
		content.move_child(reticle_offset_row, race_heading.get_index())


func _handle_options_tab_input(event: InputEvent) -> bool:
	if not panel_options.visible or tabs_options == null:
		return false
	var direction: int = 0
	if event.is_action_pressed("ui_page_up"):
		direction = -1
	elif event.is_action_pressed("ui_page_down"):
		direction = 1
	elif event is InputEventJoypadButton:
		var joy_event: InputEventJoypadButton = event
		if joy_event.pressed:
			if joy_event.button_index == JOY_BUTTON_LEFT_SHOULDER:
				direction = -1
			elif joy_event.button_index == JOY_BUTTON_RIGHT_SHOULDER:
				direction = 1
	if direction == 0:
		return false
	_stop_camera_preview()
	var tab_count: int = tabs_options.get_tab_count()
	if tab_count <= 0:
		return false
	tabs_options.current_tab = wrapi(tabs_options.current_tab + direction, 0, tab_count)
	call_deferred("_focus_visible_panel")
	return true


func _on_options_tab_changed(tab: int) -> void:
	if _changing_options_tab:
		return
	if panel_options.visible and _has_unsaved_graphics_changes():
		_pending_options_tab = tab
		_pending_options_exit = false
		_changing_options_tab = true
		tabs_options.current_tab = _last_options_tab
		_changing_options_tab = false
		_show_unsaved_graphics_dialog()
		return
	_last_options_tab = tab
	if panel_options.visible:
		call_deferred("_focus_visible_panel")


func _set_tab_title(tab_node: Control, title: String) -> void:
	if tabs_options == null:
		return
	if tab_node == null:
		return
	var tab_index: int = tabs_options.get_tab_idx_from_control(tab_node)
	if tab_index >= 0:
		tabs_options.set_tab_title(tab_index, title)


func _refresh_player_list() -> void:
	if online_panel == null:
		return
	online_panel.visible = _is_online()
	_update_pause_panel_layout()
	if not _is_online():
		return
	_refresh_connection_info()

	_net_session = _get_network_session()
	if _net_session == null:
		return
	if player_list == null:
		return

	_clear_children(player_list)

	var peers: Array = []
	if _net_session.has_method("get_peer_info_list"):
		peers = _net_session.call("get_peer_info_list")

	var race_active: bool = false
	var race_remaining: float = 0.0
	var race_starter_id: int = 0
	var race_joined: bool = false
	var race_joinable: bool = false
	if _net_session.has_method("get_race_queue_state"):
		var st = _net_session.call("get_race_queue_state")
		if st is Dictionary:
			race_active = bool(st.get("active", false))
			race_remaining = float(st.get("remaining", 0.0))
			race_starter_id = int(st.get("starter_id", 0))
			race_joined = bool(st.get("joined", false))
			race_joinable = bool(st.get("joinable", false))

	if label_race_queue != null:
		if race_active:
			label_race_queue.text = "Race queue: %0.0fs" % max(race_remaining, 0.0)
		else:
			label_race_queue.text = ""

	if button_leave_queue != null:
		button_leave_queue.visible = race_active and race_joined

	for info in peers:
		if not (info is Dictionary):
			continue
		var peer_id: int = int(info.get("peer_id", 0))
		var pname: String = String(info.get("name", "Player"))
		var pcolor: Color = Color(1, 1, 1, 1)
		var c = info.get("color")
		if c is Color:
			pcolor = c

		var row := HBoxContainer.new()
		row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		player_list.add_child(row)

		var name_label := Label.new()
		name_label.text = pname
		name_label.modulate = pcolor
		name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(name_label)

		var btn_tp := Button.new()
		btn_tp.text = "Teleport"
		btn_tp.pressed.connect(_on_teleport_pressed.bind(peer_id))
		row.add_child(btn_tp)

		if race_active and peer_id == race_starter_id:
			var btn_join := Button.new()
			if race_joined:
				btn_join.text = "Joined"
				btn_join.disabled = true
			elif not race_joinable:
				btn_join.text = "Race starting..."
				btn_join.disabled = true
			else:
				btn_join.text = "Join Race"
				btn_join.disabled = false
				btn_join.pressed.connect(_on_join_race_pressed.bind(btn_join))
			row.add_child(btn_join)
	call_deferred("_configure_pause_frame_focus")


func _refresh_connection_info() -> void:
	var net: Node = get_node_or_null("/root/NetworkManager")
	if net == null:
		return
	if label_connection != null and net.has_method("get_connection_summary"):
		label_connection.text = String(net.call("get_connection_summary"))
	if label_diagnostics != null and net.has_method("get_diagnostics_summary"):
		label_diagnostics.text = String(net.call("get_diagnostics_summary"))
	var invite_code: String = ""
	var show_invite: bool = net.has_method("is_internet_host") and bool(net.call("is_internet_host"))
	if show_invite and net.has_method("get_invite_code"):
		invite_code = String(net.call("get_invite_code"))
		show_invite = not invite_code.is_empty()
	if row_invite != null:
		row_invite.visible = show_invite
	if edit_invite != null:
		edit_invite.text = invite_code


func _on_copy_invite_pressed() -> void:
	if edit_invite == null or edit_invite.text.is_empty():
		return
	DisplayServer.clipboard_set(edit_invite.text)
	if button_copy_invite != null:
		button_copy_invite.text = "Copied"
		call_deferred("_reset_copy_invite_button")


func _reset_copy_invite_button() -> void:
	await get_tree().create_timer(1.0, true).timeout
	if button_copy_invite != null:
		button_copy_invite.text = "Copy"


func _on_join_race_pressed(button: Button = null) -> void:
	if button != null:
		button.text = "Joining..."
		button.disabled = true
	_net_session = _get_network_session()
	if _net_session == null:
		return
	if _net_session.has_method("request_join_race"):
		_net_session.call("request_join_race")
	_refresh_player_list()


func _on_ButtonLeaveQueue_pressed() -> void:
	_net_session = _get_network_session()
	if _net_session == null:
		return
	if _net_session.has_method("leave_queue"):
		_net_session.call("leave_queue")
	_refresh_player_list()


func _on_teleport_pressed(peer_id: int) -> void:
	var local_player = _get_local_player()
	if local_player == null:
		return
	_net_session = _get_network_session()
	if _net_session == null:
		return
	var target = null
	if _net_session.has_method("get_player_node"):
		target = _net_session.call("get_player_node", peer_id)
	if target == null or not is_instance_valid(target):
		return
	if not (target is Node3D):
		return

	_resume_game(true)
	_teleport_to_online_player(local_player, target as Node3D)


func _teleport_to_online_player(local_player: Node, target_player: Node3D) -> void:
	if local_player == null or target_player == null:
		return
	if not is_instance_valid(local_player) or not is_instance_valid(target_player):
		return

	var target_level_id: StringName = _get_online_level_id_from_player(target_player)
	var level_manager = _get_level_manager()
	var current_level_id: StringName = &""
	var current_scene_path: String = ""

	if level_manager != null:
		if level_manager.has_method("get_current_level_id"):
			var v = level_manager.call("get_current_level_id")
			if v is StringName:
				current_level_id = v
			elif v is String:
				current_level_id = StringName(v)
		if level_manager.has_method("get_current_level_scene_path"):
			current_scene_path = String(level_manager.call("get_current_level_scene_path"))

	if current_scene_path == "" and get_tree() != null and get_tree().current_scene != null:
		current_scene_path = String(get_tree().current_scene.scene_file_path)

	var already_in_target: bool = false
	if target_level_id != &"":
		if current_level_id != &"":
			if target_level_id == current_level_id:
				already_in_target = true
		if not already_in_target and current_scene_path != "":
			var target_level_text: String = String(target_level_id)
			if target_level_text == current_scene_path:
				already_in_target = true

	if level_manager != null and target_level_id != &"" and not already_in_target:
		var target_level_text: String = String(target_level_id)
		var is_scene_path: bool = false
		if target_level_text.begins_with("res://"):
			is_scene_path = true
		elif target_level_text.ends_with(".tscn"):
			is_scene_path = true

		var level_ready: bool = false
		if is_scene_path:
			if level_manager.has_method("ensure_level_ready_by_scene_path"):
				level_ready = bool(await level_manager.call(
					"ensure_level_ready_by_scene_path",
					target_level_text,
					StringName(""),
					NodePath("PlayerSpawn"),
					true,
					true
				))
		else:
			if level_manager.has_method("ensure_level_ready_by_id"):
				level_ready = bool(await level_manager.call(
					"ensure_level_ready_by_id",
					target_level_id,
					NodePath("PlayerSpawn"),
					true,
					true
				))
		if not level_ready:
			if local_player.has_method("show_prompt"):
				local_player.call("show_prompt", "Unable to load that player's level.", 3.0)
			return

	var state_sequence: int = _get_online_player_state_sequence(target_player)
	if target_player.has_method("_network_request_authoritative_teleport"):
		target_player.call("_network_request_authoritative_teleport")
	var received_fresh_state: bool = await _wait_for_online_player_state(target_player, state_sequence)
	if not received_fresh_state:
		if local_player.has_method("show_prompt"):
			local_player.call("show_prompt", "That player's position is not ready yet.", 3.0)
		return
	if local_player.has_method("teleport_near_node"):
		local_player.call("teleport_near_node", target_player)


func _wait_for_online_player_state(target_player: Node, previous_sequence: int) -> bool:
	for _frame_index: int in range(ONLINE_TELEPORT_STATE_WAIT_FRAMES):
		if target_player == null or not is_instance_valid(target_player):
			return false
		var current_sequence: int = _get_online_player_state_sequence(target_player)
		if current_sequence > 0 and current_sequence != previous_sequence:
			return true
		if get_tree() == null:
			return false
		await get_tree().process_frame
	return false


func _get_online_player_state_sequence(player: Node) -> int:
	if player == null or not is_instance_valid(player):
		return 0
	if player.has_method("_network_get_state_sequence"):
		return int(player.call("_network_get_state_sequence"))
	return 0


func _get_online_level_id_from_player(player: Node) -> StringName:
	# SUMMARY: Pull the online level id stored on player nodes by NetworkSession.
	if player == null:
		return &""
	if not is_instance_valid(player):
		return &""
	if not player.has_meta("online_level_id"):
		return &""
	var raw = player.get_meta("online_level_id")
	if raw is StringName:
		return raw
	if raw is String:
		return StringName(raw)
	return &""


func _refresh_race_leave_button() -> void:
	if button_leave_race == null:
		return
	var p = _get_local_player()
	if p == null or not p.has_method("get"):
		button_leave_race.visible = false
		return
	if _is_online():
		var joined = p.get("race_session_joined")
		button_leave_race.visible = joined is bool and bool(joined)
		button_leave_race.text = "Leave Race"
		return

	var in_race = false
	var v = p.get("race_in_countdown")
	if v is bool and bool(v):
		in_race = true
	var v2 = p.get("race_active")
	if v2 is bool and bool(v2):
		in_race = true
	var finished = p.get("race_finished")
	if finished is bool and bool(finished):
		in_race = false
	button_leave_race.visible = in_race
	button_leave_race.text = "Leave Race"


func _refresh_return_hub_button() -> void:
	if button_return_hub == null:
		return
	button_return_hub.visible = not _is_in_hub_level()


func _is_in_hub_level() -> bool:
	var level_manager = _get_level_manager()
	var hub_id: StringName = &""
	var current_id: StringName = &""
	var current_scene: String = ""
	if level_manager != null:
		if level_manager.has_method("get"):
			var v = level_manager.get("hub_level_id")
			if v is StringName:
				hub_id = v
			elif v is String:
				hub_id = StringName(v)
		if level_manager.has_method("get_current_level_id"):
			var v2 = level_manager.call("get_current_level_id")
			if v2 is StringName:
				current_id = v2
			elif v2 is String:
				current_id = StringName(v2)
		if level_manager.has_method("get_current_level_scene_path"):
			current_scene = String(level_manager.call("get_current_level_scene_path"))

	if hub_id != &"" and current_id != &"":
		return hub_id == current_id

	if current_scene == "":
		if get_tree() != null and get_tree().current_scene != null:
			current_scene = String(get_tree().current_scene.scene_file_path)

	return current_scene == "res://LS5Framework/Scenes/Levels/NikoTest/niko_test.tscn"


func _refresh_quick_restart_button() -> void:
	if button_quick_restart == null:
		return
	button_quick_restart.visible = _can_quick_restart()


func _can_quick_restart() -> bool:
	var p = _get_local_player()
	if p == null or not p.has_method("get"):
		return false
	if _is_death_sequence_active(p):
		return false
	
	var race_active = p.get("race_active")
	if not (race_active is bool) or not bool(race_active):
		return false

	var race_finished = p.get("race_finished")
	if race_finished is bool and bool(race_finished):
		return false
	
	var race_starts = get_tree().get_nodes_in_group("RaceStart")
	for rs in race_starts:
		if rs.get("_sequence_running"):
			return false

	return true


func _is_death_sequence_active(player: Node) -> bool:
	if player != null and player.has_method("is_death_sequence_active"):
		if bool(player.call("is_death_sequence_active")):
			return true
	return DeathPlane.is_death_sequence_in_progress()


func _is_online_solo() -> bool:
	var total_peers: int = 0
	_net_session = _get_network_session()
	if _net_session != null and _net_session.has_method("get_peer_info_list"):
		var peers = _net_session.call("get_peer_info_list")
		if peers is Array:
			total_peers = peers.size()
	if total_peers <= 0 and multiplayer != null and multiplayer.has_multiplayer_peer():
		total_peers = 1 + multiplayer.get_peers().size()
	return total_peers <= 1


func _on_ButtonLeaveRace_pressed() -> void:
	var p = _get_local_player()
	if p != null and p.has_method("leave_race"):
		p.call("leave_race", false)
	_resume_game(true)


func _on_ButtonQuickRestart_pressed() -> void:
	if not _can_quick_restart():
		return
	_do_quick_restart()


func _on_ButtonReturnHub_pressed() -> void:
	_resume_game(true)
	_cleanup_race_ui()
	_return_to_hub()


func _show_pause_panel() -> void:
	_stop_camera_preview()
	if _deadzone_visual != null:
		_deadzone_visual.visible = false
	panel_pause.visible = true
	panel_options.visible = false
	online_panel.visible = _is_online()
	_update_pause_panel_layout()
	call_deferred("_configure_pause_frame_focus")
	call_deferred("_focus_visible_panel")


func _update_pause_panel_layout() -> void:
	if panel_pause == null:
		return
	if online_panel.visible:
		panel_pause.offset_left = -90.0
		panel_pause.offset_right = 470.0
	else:
		panel_pause.offset_left = -280.0
		panel_pause.offset_right = 280.0


func _configure_pause_frame_focus() -> void:
	_configure_frame_vertical_focus(panel_pause)
	_configure_frame_vertical_focus(online_panel)


func _configure_frame_vertical_focus(frame: Control) -> void:
	if frame == null or not frame.is_visible_in_tree():
		return
	var targets: Array[Control] = []
	_collect_frame_focus_targets(frame, targets)
	if targets.is_empty():
		return
	for target in targets:
		var center: Vector2 = target.get_global_rect().get_center()
		var above: Control = null
		var below: Control = null
		var above_distance: float = INF
		var below_distance: float = INF
		for candidate in targets:
			if candidate == target:
				continue
			var candidate_center: Vector2 = candidate.get_global_rect().get_center()
			var vertical: float = candidate_center.y - center.y
			var horizontal: float = absf(candidate_center.x - center.x)
			if vertical < -2.0:
				var distance: float = -vertical * 1000.0 + horizontal
				if distance < above_distance:
					above_distance = distance
					above = candidate
			elif vertical > 2.0:
				var distance: float = vertical * 1000.0 + horizontal
				if distance < below_distance:
					below_distance = distance
					below = candidate
		if above == null:
			above = _frame_edge_focus_target(targets, true, center.x)
		if below == null:
			below = _frame_edge_focus_target(targets, false, center.x)
		target.focus_neighbor_top = target.get_path_to(above)
		target.focus_neighbor_bottom = target.get_path_to(below)


func _frame_edge_focus_target(targets: Array[Control], bottom: bool, from_x: float) -> Control:
	var chosen: Control = targets[0]
	for target in targets:
		var target_center: Vector2 = target.get_global_rect().get_center()
		var chosen_center: Vector2 = chosen.get_global_rect().get_center()
		if (bottom and target_center.y > chosen_center.y + 2.0) or (not bottom and target_center.y < chosen_center.y - 2.0):
			chosen = target
		elif absf(target_center.y - chosen_center.y) <= 2.0 and absf(target_center.x - from_x) < absf(chosen_center.x - from_x):
			chosen = target
	return chosen


func _collect_frame_focus_targets(root: Node, targets: Array[Control]) -> void:
	for child in root.get_children():
		if child is Control:
			var control: Control = child
			if control.is_visible_in_tree() and control.focus_mode != Control.FOCUS_NONE and _is_menu_focus_target(control):
				if not (control is BaseButton and (control as BaseButton).disabled):
					targets.append(control)
		_collect_frame_focus_targets(child, targets)


func _show_options_panel() -> void:
	panel_pause.visible = false
	panel_options.visible = true
	online_panel.visible = false
	call_deferred("_focus_visible_panel")


func _on_ButtonResume_pressed() -> void:
	_resume_game(true)


func _on_ButtonOptions_pressed() -> void:
	_show_options_panel()


func _on_ButtonRestart_pressed() -> void:
	_do_reload_level()


func _do_quick_restart() -> void:
	if not _can_quick_restart():
		return
	if _is_open:
		_resume_game(true)

	var p = _get_local_player()
	if p == null:
		return

	var rs = _resolve_race_start(p)

	if _is_online() and p.has_method("leave_race"):
		p.call("leave_race", false)
	if rs == null or not is_instance_valid(rs):
		if not _is_online():
			if p.has_method("reset_gameplay_run_state"):
				p.call("reset_gameplay_run_state", true)
			_cleanup_race_ui()
			get_tree().reload_current_scene()
		return

	if _is_online():
		var session = _get_network_session()
		if session != null and session.has_method("request_start_race"):
			var level_scene_path: String = ""
			var race_start_path: String = ""
			var level_manager = _get_level_manager()
			if level_manager != null:
				if level_manager.has_method("get_current_level_scene_path"):
					level_scene_path = String(level_manager.call("get_current_level_scene_path"))
				if level_manager.has_method("get_path_in_current_level"):
					var pth = level_manager.call("get_path_in_current_level", rs)
					if pth is NodePath:
						race_start_path = String(pth)
			if level_scene_path == "" or race_start_path == "":
				if get_tree() != null and get_tree().current_scene != null:
					level_scene_path = String(get_tree().current_scene.scene_file_path)
					race_start_path = String(get_tree().current_scene.get_path_to(rs))
			if level_scene_path != "" and race_start_path != "":
				session.call("request_start_race", level_scene_path, race_start_path)
		return

	if rs.has_method("cancel_for_player"):
		rs.call("cancel_for_player", p)
	DeathPlane.cancel_death_sequence()
	if rs.has_method("start_race_for_player"):
		rs.call("start_race_for_player", p, false)


func _do_reload_level() -> void:
	if _is_open:
		_resume_game(true)

	var p = _get_local_player()
	if p != null:
		if p.has_method("force_leave_race_for_scene_change"):
			p.call("force_leave_race_for_scene_change")
		elif p.has_method("leave_race"):
			p.call("leave_race", false)

	_cleanup_race_ui()

	var level_manager = _get_level_manager()
	if level_manager != null:
		var scene_path := ""
		if level_manager.has_method("get_current_level_scene_path"):
			scene_path = String(level_manager.call("get_current_level_scene_path"))
		if scene_path.strip_edges() == "" and level_manager.has_method("get_current_level"):
			var level_node = level_manager.call("get_current_level")
			if level_node is Node:
				scene_path = String((level_node as Node).scene_file_path)
		if scene_path.strip_edges() != "" and level_manager.has_method("load_level_by_scene_path"):
			var level_id: StringName = &""
			if level_manager.has_method("get_current_level_id"):
				var v = level_manager.call("get_current_level_id")
				if v is StringName:
					level_id = v
				elif v is String:
					level_id = StringName(v)
			level_manager.call("load_level_by_scene_path", scene_path, level_id, NodePath("PlayerSpawn"), true, true)
			return

	if get_tree() != null:
		get_tree().reload_current_scene()


func _on_ButtonRespawnStart_pressed() -> void:
	var p = _get_local_player()
	if p != null and p.has_method("respawn_now"):
		p.call("respawn_now")
	if _is_open:
		await get_tree().process_frame
		if is_instance_valid(self):
			_resume_game(true)


func _on_ButtonRespawnCheckpoint_pressed() -> void:
	var p = _get_local_player()
	if p != null and p.has_method("respawn_checkpoint_now"):
		p.call("respawn_checkpoint_now")
	if _is_open:
		await get_tree().process_frame
		if is_instance_valid(self):
			_resume_game(true)


func _focus_visible_panel() -> void:
	if graphics_confirm_dialog.visible:
		button_confirm_graphics.grab_focus()
		return
	if unsaved_graphics_dialog.visible:
		button_save_unsaved_graphics.grab_focus()
		return
	if panel_options.visible:
		var current_tab: Control = null
		if tabs_options != null and tabs_options.current_tab >= 0:
			current_tab = tabs_options.get_tab_control(tabs_options.current_tab)
		if current_tab != null and _focus_first_focusable_control(current_tab):
			return
		if _focus_first_focusable_control(panel_options):
			return
	if panel_pause.visible:
		if _focus_first_focusable_control(panel_pause):
			return
	if online_panel.visible:
		if _focus_first_focusable_control(online_panel):
			return


func _focus_first_focusable_control(root: Node) -> bool:
	if root == null or not is_instance_valid(root):
		return false
	if root is Control:
		var control: Control = root
		if control.is_visible_in_tree() and control.focus_mode != Control.FOCUS_NONE and _is_menu_focus_target(control):
			control.grab_focus()
			call_deferred("_ensure_control_visible", control)
			return true
	for child in root.get_children():
		if _focus_first_focusable_control(child):
			return true
	return false


func _is_menu_focus_target(control: Control) -> bool:
	return control is BaseButton or control is LineEdit or control is TextEdit or control is Range or control is ItemList


func _ensure_control_visible(control: Control) -> void:
	if control == null or not is_instance_valid(control):
		return
	if SettingsManager.is_mouse_input_active():
		return
	var scroll_container: ScrollContainer = _find_scroll_container_upwards(control, panel_options)
	if scroll_container != null:
		scroll_container.ensure_control_visible(control)


func _handle_right_stick_scroll(delta: float) -> void:
	if _is_text_input_focused():
		return
	var scroll_input: float = SettingsManager.get_signed_action_axis(&"camera_down", &"camera_up", SettingsManager.get_right_stick_deadzone(), &"gamepad")
	if absf(scroll_input) < 0.05:
		return
	var scroll_container: ScrollContainer = _get_active_scroll_container()
	if scroll_container == null:
		return
	var scroll_bar: VScrollBar = scroll_container.get_v_scroll_bar()
	if scroll_bar == null:
		return
	var new_scroll: float = float(scroll_container.scroll_vertical) - scroll_input * 900.0 * delta
	scroll_container.scroll_vertical = int(clamp(new_scroll, 0.0, scroll_bar.max_value))


func _get_active_scroll_container() -> ScrollContainer:
	var root: Node = null
	if panel_options.visible:
		if tabs_options != null and tabs_options.current_tab >= 0:
			root = tabs_options.get_tab_control(tabs_options.current_tab)
		if root == null:
			root = panel_options
	else:
		root = panel_pause
	if root == null:
		return null
	var focus_owner: Control = get_viewport().gui_get_focus_owner()
	if focus_owner != null and focus_owner.is_visible_in_tree():
		var focused_scroll: ScrollContainer = _find_scroll_container_upwards(focus_owner, root)
		if focused_scroll != null:
			return focused_scroll
	return _find_first_scroll_container(root)


func _find_scroll_container_upwards(node: Node, root: Node) -> ScrollContainer:
	var current: Node = node
	while current != null:
		if current is ScrollContainer and current.is_visible_in_tree():
			return current
		if current == root:
			break
		current = current.get_parent()
	return null


func _find_first_scroll_container(root: Node) -> ScrollContainer:
	if root == null or not is_instance_valid(root):
		return null
	if root is ScrollContainer and root.is_visible_in_tree():
		return root
	for child in root.get_children():
		var found: ScrollContainer = _find_first_scroll_container(child)
		if found != null:
			return found
	return null


func _resolve_race_start(player: Node = null) -> Node:
	if get_tree() == null:
		return null
	var list = get_tree().get_nodes_in_group("RaceStart")
	if player != null and is_instance_valid(player):
		for race_start: Node in list:
			if race_start != null and is_instance_valid(race_start) and race_start.has_method("is_active_for_player"):
				if bool(race_start.call("is_active_for_player", player)):
					return race_start
	if list != null and list.size() > 0:
		return list[0]
	return null


func _get_level_manager() -> Node:
	if get_tree() == null:
		return null
	var list = get_tree().get_nodes_in_group("LevelManager")
	if list != null and list.size() > 0:
		return list[0]
	return get_tree().root.find_child("LevelManager", true, false)


func _is_text_input_focused() -> bool:
	var vp = get_viewport()
	if vp == null:
		return false
	var focus = vp.gui_get_focus_owner()
	return focus is LineEdit or focus is TextEdit


func _is_input_binding_active() -> bool:
	var tree: SceneTree = get_tree()
	if tree == null:
		return false
	return bool(tree.get_meta("input_binding_active", false))


func _get_sfx_player() -> AudioStreamPlayer:
	if _sfx_player != null and is_instance_valid(_sfx_player):
		return _sfx_player
	var p := AudioStreamPlayer.new()
	p.bus = sfx_bus
	add_child(p)
	_sfx_player = p
	return _sfx_player


func _play_sfx(stream: AudioStream) -> void:
	if stream == null:
		return
	var p = _get_sfx_player()
	if p == null:
		return
	p.stream = stream
	p.play()


func _on_ButtonOptionsBack_pressed() -> void:
	if _has_unsaved_graphics_changes():
		_pending_options_exit = true
		_pending_options_tab = -1
		_show_unsaved_graphics_dialog()
		return
	_leave_options_menu()


func _leave_options_menu() -> void:
	SettingsManager.save_now()
	_show_pause_panel()


func _on_ButtonResetDefaults_pressed() -> void:
	reset_defaults_dialog.visible = true
	_play_sfx(sfx_warning)
	call_deferred("_focus_reset_defaults_cancel")


func _focus_reset_defaults_cancel() -> void:
	if reset_defaults_dialog.visible:
		button_cancel_reset_defaults.grab_focus()


func _on_reset_defaults_canceled() -> void:
	reset_defaults_dialog.visible = false
	button_reset_defaults.grab_focus()


func _on_reset_defaults_confirmed() -> void:
	reset_defaults_dialog.visible = false
	var err: Error = SettingsManager.reset_all_settings_to_defaults()
	if err != OK:
		push_warning("PauseMenu: failed to reset settings: %s" % error_string(err))
		return
	_populate_resolution_list()
	_sync_options_from_settings()
	if tab_controls.has_method("refresh_from_settings"):
		tab_controls.call("refresh_from_settings")
	if tab_bindings.has_method("refresh_from_settings"):
		tab_bindings.call("refresh_from_settings")
	button_reset_defaults.grab_focus()


func _on_ButtonMenu_pressed() -> void:
	_resume_game(false)
	_cleanup_race_ui()
	var net = get_node_or_null("/root/NetworkManager")
	if net != null:
		net.call("leave")
	if main_menu_scene != "":
		get_tree().change_scene_to_file(main_menu_scene)


func _return_to_hub() -> void:
	var level_manager = _get_level_manager()
	if level_manager != null:
		var hub_id: StringName = &""
		if level_manager.has_method("get"):
			var v = level_manager.get("hub_level_id")
			if v is StringName:
				hub_id = v
			elif v is String:
				hub_id = StringName(v)
		if hub_id != &"" and level_manager.has_method("load_level_by_id"):
			level_manager.call("load_level_by_id", hub_id, NodePath("PlayerSpawn"))
			return
		if level_manager.has_method("load_level_by_scene_path"):
			level_manager.call("load_level_by_scene_path", "res://LS5Framework/Scenes/Levels/NikoTest/niko_test.tscn", StringName(""), NodePath("PlayerSpawn"))
			return

	if get_tree() == null:
		return
	get_tree().set_meta("pending_level_scene", "res://LS5Framework/Scenes/Levels/NikoTest/niko_test.tscn")
	if _is_online():
		var net = get_node_or_null("/root/NetworkManager")
		if net != null and net.has_method("change_scene_keep_session"):
			net.call("change_scene_keep_session", "res://LS5Framework/Scenes/Main.tscn")
			return
	var packed = load("res://LS5Framework/Scenes/Main.tscn")
	if packed is PackedScene:
		get_tree().change_scene_to_packed(packed)
	else:
		get_tree().change_scene_to_file("res://LS5Framework/Scenes/Main.tscn")


func _cleanup_race_ui() -> void:
	if get_tree() == null:
		return
	for n in get_tree().get_nodes_in_group("RaceUI"):
		if n != null and is_instance_valid(n):
			n.queue_free()
	for n in get_tree().get_nodes_in_group("RaceQueueBanner"):
		if n != null and is_instance_valid(n):
			n.queue_free()
	for n in get_tree().get_nodes_in_group("RaceFinishBanner"):
		if n != null and is_instance_valid(n):
			n.queue_free()
	for n in get_tree().get_nodes_in_group("RaceDNFBanner"):
		if n != null and is_instance_valid(n):
			n.queue_free()


func _configure_graphics_apply_button() -> void:
	var graphics_content: VBoxContainer = button_apply_resolution.get_parent() as VBoxContainer
	if graphics_content != null:
		graphics_content.move_child(button_apply_resolution, 0)
	button_apply_resolution.text = "Apply Settings"
	button_apply_resolution.tooltip_text = "Apply all staged graphics and display settings."
	button_apply_resolution.disabled = false


func _populate_render_scaling_options() -> void:
	opt_render_scale_mode.clear()
	opt_render_scale_mode.add_item("Direct Scaling", SettingsManager.RENDER_SCALE_MODE_DIRECT)
	opt_render_scale_mode.add_item("FSR 1.0", SettingsManager.RENDER_SCALE_MODE_FSR)
	opt_render_scale_ratio.clear()
	opt_render_scale_ratio.add_item("Native (100%)", 0)
	opt_render_scale_ratio.add_item("High Quality (77%)", 1)
	opt_render_scale_ratio.add_item("Quality (67%)", 2)
	opt_render_scale_ratio.add_item("Balanced (59%)", 3)
	opt_render_scale_ratio.add_item("Performance (50%)", 4)
	opt_render_scale_ratio.add_item("High Performance (40%)", 5)


func _populate_graphics_quality_options() -> void:
	opt_shadow_resolution.clear()
	opt_shadow_resolution.add_item("Low (1024)", SettingsManager.SHADOW_RESOLUTION_LOW)
	opt_shadow_resolution.add_item("Medium (2048)", SettingsManager.SHADOW_RESOLUTION_MEDIUM)
	opt_shadow_resolution.add_item("High (4096)", SettingsManager.SHADOW_RESOLUTION_HIGH)
	opt_shadow_resolution.add_item("Ultra (8192)", SettingsManager.SHADOW_RESOLUTION_ULTRA)
	opt_particle_quality.clear()
	opt_particle_quality.add_item("Low (35%)", SettingsManager.PARTICLE_QUALITY_LOW)
	opt_particle_quality.add_item("Medium (60%)", SettingsManager.PARTICLE_QUALITY_MEDIUM)
	opt_particle_quality.add_item("High (80%)", SettingsManager.PARTICLE_QUALITY_HIGH)
	opt_particle_quality.add_item("Ultra (100%)", SettingsManager.PARTICLE_QUALITY_ULTRA)


func _get_selected_render_scale_ratio() -> float:
	match opt_render_scale_ratio.get_selected_id():
		1:
			return SettingsManager.RENDER_SCALE_HIGH_QUALITY
		2:
			return SettingsManager.RENDER_SCALE_QUALITY
		3:
			return SettingsManager.RENDER_SCALE_BALANCED
		4:
			return SettingsManager.RENDER_SCALE_PERFORMANCE
		5:
			return SettingsManager.RENDER_SCALE_HIGH_PERFORMANCE
		_:
			return SettingsManager.RENDER_SCALE_NATIVE


func _select_render_scale_ratio(value: float) -> void:
	var ratios: Array[float] = [
		SettingsManager.RENDER_SCALE_NATIVE,
		SettingsManager.RENDER_SCALE_HIGH_QUALITY,
		SettingsManager.RENDER_SCALE_QUALITY,
		SettingsManager.RENDER_SCALE_BALANCED,
		SettingsManager.RENDER_SCALE_PERFORMANCE,
		SettingsManager.RENDER_SCALE_HIGH_PERFORMANCE,
	]
	var closest_index: int = 0
	var closest_distance: float = absf(value - ratios[0])
	for index: int in range(1, ratios.size()):
		var distance: float = absf(value - ratios[index])
		if distance < closest_distance:
			closest_index = index
			closest_distance = distance
	opt_render_scale_ratio.select(closest_index)


func _collect_graphics_snapshot_from_ui() -> Dictionary:
	var resolution_index: int = opt_resolution.get_selected_id()
	if resolution_index < 0:
		resolution_index = SettingsManager.get_resolution_index()
	return {
		"resolution_index": resolution_index,
		"fullscreen": chk_fullscreen.button_pressed,
		"vsync_enabled": chk_vsync.button_pressed,
		"render_scale_mode": opt_render_scale_mode.get_selected_id(),
		"render_scale_ratio": _get_selected_render_scale_ratio(),
		"volumetric_fog_enabled": chk_volumetric_fog.button_pressed,
		"shadow_resolution": opt_shadow_resolution.get_selected_id(),
		"particle_quality": opt_particle_quality.get_selected_id(),
		"weather_occlusion_enabled": chk_weather_occlusion.button_pressed,
		"ssr": chk_ssr.button_pressed,
		"ssao": chk_ssao.button_pressed,
		"ssil": chk_ssil.button_pressed,
		"sdfgi": chk_sdfgi.button_pressed,
		"shadows": chk_shadows.button_pressed,
		"glow": chk_glow.button_pressed,
		"depth_of_field_enabled": chk_depth_of_field.button_pressed,
		"lod_distance_quality": opt_lod_distance.get_selected_id(),
		"water_displacement_enabled": chk_water_displacement.button_pressed,
		"water_refraction_enabled": chk_water_refraction.button_pressed,
		"water_normal_maps_enabled": chk_water_normals.button_pressed,
		"water_depth_effects_enabled": chk_water_depth_fx.button_pressed,
		"camera_far_cutoff": float(slider_camera_far.value),
	}


func _populate_resolution_list() -> void:
	opt_resolution.clear()
	opt_resolution.tooltip_text = "Fullscreen uses the desktop resolution and aspect ratio."
	for aspect: String in SettingsManager.get_resolution_aspect_categories():
		opt_resolution.add_separator(aspect)
		for resolution_index: int in range(SettingsManager.get_resolution_count()):
			if SettingsManager.get_resolution_aspect(resolution_index) != aspect:
				continue
			var label: String = SettingsManager.get_resolution_label(resolution_index)
			opt_resolution.add_item(label, resolution_index)
	var selected_index: int = opt_resolution.get_item_index(SettingsManager.get_resolution_index())
	if selected_index >= 0:
		opt_resolution.selected = selected_index
	_update_resolution_control_state()


func _update_resolution_control_state() -> void:
	opt_resolution.disabled = chk_fullscreen.button_pressed


func _sync_options_from_settings() -> void:
	var selected_resolution_index: int = opt_resolution.get_item_index(SettingsManager.get_resolution_index())
	if selected_resolution_index >= 0:
		opt_resolution.selected = selected_resolution_index
	chk_fullscreen.button_pressed = SettingsManager.fullscreen
	_update_resolution_control_state()
	chk_vsync.button_pressed = SettingsManager.vsync_enabled
	var render_mode_index: int = opt_render_scale_mode.get_item_index(SettingsManager.render_scale_mode)
	if render_mode_index >= 0:
		opt_render_scale_mode.select(render_mode_index)
	_select_render_scale_ratio(SettingsManager.render_scale_ratio)
	var shadow_resolution_index: int = opt_shadow_resolution.get_item_index(SettingsManager.shadow_resolution)
	if shadow_resolution_index >= 0:
		opt_shadow_resolution.select(shadow_resolution_index)
	var particle_quality_index: int = opt_particle_quality.get_item_index(SettingsManager.particle_quality)
	if particle_quality_index >= 0:
		opt_particle_quality.select(particle_quality_index)
	chk_volumetric_fog.button_pressed = SettingsManager.volumetric_fog_enabled
	chk_weather_occlusion.button_pressed = SettingsManager.weather_occlusion_enabled
	if check_level_load_logging != null:
		check_level_load_logging.button_pressed = SettingsManager.level_load_logging_enabled
	chk_ssr.button_pressed = SettingsManager.ssr
	chk_ssao.button_pressed = SettingsManager.ssao
	chk_ssil.button_pressed = SettingsManager.ssil
	chk_sdfgi.button_pressed = SettingsManager.sdfgi
	chk_shadows.button_pressed = SettingsManager.shadows
	chk_glow.button_pressed = SettingsManager.glow
	chk_depth_of_field.button_pressed = SettingsManager.depth_of_field_enabled
	chk_water_displacement.button_pressed = SettingsManager.water_displacement_enabled
	chk_water_refraction.button_pressed = SettingsManager.water_refraction_enabled
	chk_water_normals.button_pressed = SettingsManager.water_normal_maps_enabled
	chk_water_depth_fx.button_pressed = SettingsManager.water_depth_effects_enabled
	var lod_index: int = opt_lod_distance.get_item_index(SettingsManager.lod_distance_quality)
	if lod_index >= 0:
		opt_lod_distance.selected = lod_index
	slider_master.value = SettingsManager.get_master_volume_percent()
	slider_music.value = SettingsManager.get_music_volume_percent()
	slider_sfx.value = SettingsManager.get_sfx_volume_percent()
	slider_ui.value = SettingsManager.get_ui_volume_percent()
	slider_voice.value = SettingsManager.get_voice_volume_percent()
	if slider_camera_far != null:
		slider_camera_far.value = SettingsManager.camera_far_cutoff
	if slider_camera_fov != null:
		slider_camera_fov.value = SettingsManager.camera_default_fov
	if opt_player_tracking_mode != null:
		var tracking_mode_index: int = opt_player_tracking_mode.get_item_index(SettingsManager.player_tracking_mode)
		if tracking_mode_index >= 0:
			opt_player_tracking_mode.selected = tracking_mode_index
	if opt_homing_target_mode != null:
		var mode_index: int = opt_homing_target_mode.get_item_index(SettingsManager.homing_targeting_mode)
		if mode_index >= 0:
			opt_homing_target_mode.selected = mode_index
	if chk_separate_homing_targeting:
		chk_separate_homing_targeting.button_pressed = SettingsManager.homing_targeting_separate_by_device
	if opt_mouse_homing_target_mode:
		var mouse_mode_index: int = opt_mouse_homing_target_mode.get_item_index(SettingsManager.homing_mouse_targeting_mode)
		if mouse_mode_index >= 0:
			opt_mouse_homing_target_mode.selected = mouse_mode_index
	_update_homing_targeting_device_ui()
	if opt_lightspeed_dash_target_mode != null:
		var ls_mode_index: int = opt_lightspeed_dash_target_mode.get_item_index(SettingsManager.lightspeed_dash_targeting_mode)
		if ls_mode_index >= 0:
			opt_lightspeed_dash_target_mode.selected = ls_mode_index
	if slider_homing_radius != null:
		slider_homing_radius.value = SettingsManager.homing_camera_radius
	if slider_camera_follow_smoothing != null:
		slider_camera_follow_smoothing.value = SettingsManager.camera_follow_smoothing
	if chk_camera_dolly != null:
		chk_camera_dolly.button_pressed = SettingsManager.camera_dolly_enabled
	if chk_camera_target_lookahead != null:
		chk_camera_target_lookahead.button_pressed = SettingsManager.camera_target_lookahead_enabled
	if slider_camera_target_lookahead != null:
		slider_camera_target_lookahead.value = SettingsManager.camera_target_lookahead_amount
	_update_camera_lookahead_ui()
	if chk_auto_follow_camera != null:
		chk_auto_follow_camera.button_pressed = SettingsManager.camera_auto_follow_enabled
	if chk_auto_follow_controller_only:
		chk_auto_follow_controller_only.button_pressed = SettingsManager.camera_auto_follow_controller_only
	if slider_auto_follow_sensitivity != null:
		slider_auto_follow_sensitivity.value = SettingsManager.camera_auto_follow_sensitivity
	if slider_auto_follow_interrupt_delay != null:
		slider_auto_follow_interrupt_delay.value = SettingsManager.camera_auto_follow_interrupt_delay
	if slider_auto_follow_deadzone != null:
		slider_auto_follow_deadzone.value = SettingsManager.camera_auto_follow_deadzone_deg
	if slider_auto_follow_max_deviation != null:
		slider_auto_follow_max_deviation.value = SettingsManager.camera_auto_follow_max_deviation_deg
	if chk_auto_follow_vertical_enabled != null:
		chk_auto_follow_vertical_enabled.button_pressed = SettingsManager.camera_auto_follow_vertical_enabled
	if slider_auto_follow_vertical_max_tilt != null:
		slider_auto_follow_vertical_max_tilt.value = SettingsManager.camera_auto_follow_vertical_max_tilt
	if slider_auto_follow_level_pitch != null:
		slider_auto_follow_level_pitch.value = SettingsManager.camera_auto_follow_level_pitch_deg
	if check_hud_visible != null:
		check_hud_visible.button_pressed = SettingsManager.hud_visible
	if check_action_prompts != null:
		check_action_prompts.button_pressed = SettingsManager.action_prompts_visible
	if check_fps_counter != null:
		check_fps_counter.button_pressed = SettingsManager.fps_counter_visible
	if chk_center_reticle != null:
		chk_center_reticle.button_pressed = SettingsManager.center_reticle_enabled
	if slider_center_reticle_scale != null:
		slider_center_reticle_scale.value = SettingsManager.center_reticle_scale
	if slider_center_reticle_opacity != null:
		slider_center_reticle_opacity.value = SettingsManager.center_reticle_opacity
	if color_center_reticle != null:
		color_center_reticle.color = SettingsManager.center_reticle_color
	if slider_reticle_vertical_offset != null:
		slider_reticle_vertical_offset.value = SettingsManager.reticle_vertical_offset
	if chk_remember_emote_page:
		chk_remember_emote_page.set_pressed_no_signal(SettingsManager.remember_emote_page)
	if chk_combo_system != null:
		chk_combo_system.button_pressed = SettingsManager.combo_system_enabled
	if chk_record_race_ghosts != null:
		chk_record_race_ghosts.button_pressed = SettingsManager.race_record_ghost_data
	if opt_ghost_recording_rate != null:
		var ghost_rate_index: int = opt_ghost_recording_rate.get_item_index(SettingsManager.race_ghost_recording_rate)
		if ghost_rate_index >= 0:
			opt_ghost_recording_rate.selected = ghost_rate_index
	if opt_ghost_playback_rate != null:
		var playback_rate_index: int = opt_ghost_playback_rate.get_item_index(SettingsManager.race_ghost_playback_rate)
		if playback_rate_index >= 0:
			opt_ghost_playback_rate.selected = playback_rate_index
	_update_ghost_recording_hint()
	if chk_use_character_colors_offline != null:
		chk_use_character_colors_offline.button_pressed = SettingsManager.use_character_colors
	if color_offline_primary != null:
		color_offline_primary.color = SettingsManager.character_primary_color
	if color_offline_secondary != null:
		color_offline_secondary.color = SettingsManager.character_secondary_color
	if color_offline_trail != null:
		color_offline_trail.color = SettingsManager.character_trail_color


func _on_OptionResolution_item_selected(_index: int) -> void:
	pass


func _on_ButtonApplyResolution_pressed() -> void:
	if graphics_confirm_dialog.visible:
		return
	_graphics_previous_snapshot = SettingsManager.get_graphics_snapshot()
	SettingsManager.apply_graphics_snapshot(_collect_graphics_snapshot_from_ui())
	_graphics_confirmation_remaining = GRAPHICS_CONFIRMATION_DURATION
	_update_graphics_confirmation_text()
	graphics_confirm_dialog.visible = true
	_play_sfx(sfx_warning)
	button_confirm_graphics.grab_focus()


func _on_graphics_settings_confirmed() -> void:
	if not graphics_confirm_dialog.visible:
		return
	SettingsManager.save_now()
	graphics_confirm_dialog.visible = false
	_graphics_previous_snapshot.clear()
	button_apply_resolution.grab_focus()


func _on_graphics_settings_reverted() -> void:
	if not graphics_confirm_dialog.visible:
		return
	if not _graphics_previous_snapshot.is_empty():
		SettingsManager.apply_graphics_snapshot(_graphics_previous_snapshot)
	graphics_confirm_dialog.visible = false
	_graphics_previous_snapshot.clear()
	_sync_options_from_settings()
	button_apply_resolution.grab_focus()


func _has_unsaved_graphics_changes() -> bool:
	return _collect_graphics_snapshot_from_ui() != SettingsManager.get_graphics_snapshot()


func _show_unsaved_graphics_dialog() -> void:
	unsaved_graphics_dialog.visible = true
	_play_sfx(sfx_warning)
	button_save_unsaved_graphics.grab_focus()


func _on_unsaved_graphics_save_pressed() -> void:
	if not unsaved_graphics_dialog.visible:
		return
	SettingsManager.apply_graphics_snapshot(_collect_graphics_snapshot_from_ui())
	SettingsManager.save_now()
	unsaved_graphics_dialog.visible = false
	_complete_pending_options_navigation()


func _on_unsaved_graphics_discard_pressed() -> void:
	if not unsaved_graphics_dialog.visible:
		return
	_sync_options_from_settings()
	unsaved_graphics_dialog.visible = false
	_complete_pending_options_navigation()


func _on_unsaved_graphics_go_back_pressed() -> void:
	if not unsaved_graphics_dialog.visible:
		return
	unsaved_graphics_dialog.visible = false
	_pending_options_tab = -1
	_pending_options_exit = false
	call_deferred("_focus_visible_panel")


func _complete_pending_options_navigation() -> void:
	var target_tab: int = _pending_options_tab
	var should_exit: bool = _pending_options_exit
	_pending_options_tab = -1
	_pending_options_exit = false
	if should_exit:
		_leave_options_menu()
		return
	if target_tab < 0 or target_tab >= tabs_options.get_tab_count():
		call_deferred("_focus_visible_panel")
		return
	_changing_options_tab = true
	tabs_options.current_tab = target_tab
	_changing_options_tab = false
	_last_options_tab = target_tab
	call_deferred("_focus_visible_panel")


func _update_graphics_confirmation(delta: float) -> void:
	_graphics_confirmation_remaining = maxf(_graphics_confirmation_remaining - maxf(delta, 0.0), 0.0)
	_update_graphics_confirmation_text()
	if _graphics_confirmation_remaining <= 0.0:
		_on_graphics_settings_reverted()


func _update_graphics_confirmation_text() -> void:
	var seconds_remaining: int = maxi(0, ceili(_graphics_confirmation_remaining))
	graphics_confirm_body.text = "Keep these graphics settings?\nReverting in %d seconds." % seconds_remaining


func _on_CheckFullscreen_toggled(_pressed: bool) -> void:
	_update_resolution_control_state()


func _on_CheckVsync_toggled(_pressed: bool) -> void:
	pass


func _on_CheckSSR_toggled(_pressed: bool) -> void:
	pass


func _on_CheckSSAO_toggled(_pressed: bool) -> void:
	pass


func _on_CheckSSIL_toggled(_pressed: bool) -> void:
	pass


func _on_CheckSDFGI_toggled(_pressed: bool) -> void:
	pass


func _on_CheckShadows_toggled(_pressed: bool) -> void:
	pass


func _on_CheckGlow_toggled(_pressed: bool) -> void:
	pass


func _on_CheckDepthOfField_toggled(_pressed: bool) -> void:
	pass


func _populate_lod_distance_options() -> void:
	opt_lod_distance.clear()
	opt_lod_distance.add_item("Low", SettingsManager.LOD_DISTANCE_LOW)
	opt_lod_distance.add_item("Medium", SettingsManager.LOD_DISTANCE_MEDIUM)
	opt_lod_distance.add_item("High", SettingsManager.LOD_DISTANCE_HIGH)
	opt_lod_distance.add_item("Juiced", SettingsManager.LOD_DISTANCE_JUICED)


func _on_OptionLOD_item_selected(_index: int) -> void:
	pass


func _on_CheckWaterDisplacement_toggled(_pressed: bool) -> void:
	pass


func _on_CheckWaterRefraction_toggled(_pressed: bool) -> void:
	pass


func _on_CheckWaterNormals_toggled(_pressed: bool) -> void:
	pass


func _on_CheckWaterDepthFx_toggled(_pressed: bool) -> void:
	pass


func _on_SliderMaster_value_changed(value: float) -> void:
	SettingsManager.set_master_volume_percent(value)
	SettingsManager.save_now()


func _on_SliderMusic_value_changed(value: float) -> void:
	SettingsManager.set_music_volume_percent(value)
	SettingsManager.save_now()


func _on_SliderSfx_value_changed(value: float) -> void:
	SettingsManager.set_sfx_volume_percent(value)
	SettingsManager.save_now()


func _on_SliderUi_value_changed(value: float) -> void:
	SettingsManager.set_ui_volume_percent(value)
	SettingsManager.save_now()


func _on_SliderVoice_value_changed(value: float) -> void:
	SettingsManager.set_voice_volume_percent(value)
	SettingsManager.save_now()


func _on_SliderCameraFar_value_changed(_value: float) -> void:
	pass

func _on_SliderCameraFov_value_changed(value: float) -> void:
	SettingsManager.set_camera_default_fov(value)
	SettingsManager.save_now()


func _populate_homing_target_mode() -> void:
	if opt_homing_target_mode == null:
		return
	opt_homing_target_mode.clear()
	opt_homing_target_mode.add_item("Movement", SettingsManager.HOMING_TARGETING_MOVEMENT)
	opt_homing_target_mode.add_item("Camera", SettingsManager.HOMING_TARGETING_CAMERA)
	opt_homing_target_mode.add_item("Hybrid", SettingsManager.HOMING_TARGETING_HYBRID)
	if opt_mouse_homing_target_mode:
		opt_mouse_homing_target_mode.clear()
		opt_mouse_homing_target_mode.add_item("Movement", SettingsManager.HOMING_TARGETING_MOVEMENT)
		opt_mouse_homing_target_mode.add_item("Camera", SettingsManager.HOMING_TARGETING_CAMERA)
		opt_mouse_homing_target_mode.add_item("Hybrid", SettingsManager.HOMING_TARGETING_HYBRID)


func _update_homing_targeting_device_ui() -> void:
	var separate_by_device: bool = SettingsManager.homing_targeting_separate_by_device
	if label_homing_target_mode:
		label_homing_target_mode.text = "Controller Homing Targeting" if separate_by_device else "Homing Targeting"
	if row_mouse_homing_target_mode:
		row_mouse_homing_target_mode.visible = separate_by_device


func _populate_lightspeed_dash_target_mode() -> void:
	if opt_lightspeed_dash_target_mode == null:
		return
	opt_lightspeed_dash_target_mode.clear()
	opt_lightspeed_dash_target_mode.add_item("Movement", SettingsManager.LIGHTSPEED_DASH_TARGETING_MOVEMENT)
	opt_lightspeed_dash_target_mode.add_item("Camera", SettingsManager.LIGHTSPEED_DASH_TARGETING_CAMERA)
	opt_lightspeed_dash_target_mode.add_item("Hybrid", SettingsManager.LIGHTSPEED_DASH_TARGETING_HYBRID)


func _populate_ghost_recording_rates() -> void:
	if opt_ghost_recording_rate == null:
		return
	opt_ghost_recording_rate.clear()
	opt_ghost_recording_rate.add_item("15 Hz - Compact", 15)
	opt_ghost_recording_rate.add_item("30 Hz - Balanced", 30)
	opt_ghost_recording_rate.add_item("60 Hz - High fidelity", 60)


func _populate_ghost_playback_rates() -> void:
	if opt_ghost_playback_rate == null:
		return
	opt_ghost_playback_rate.clear()
	opt_ghost_playback_rate.add_item("15 Hz - Performance", 15)
	opt_ghost_playback_rate.add_item("30 Hz - Balanced", 30)
	opt_ghost_playback_rate.add_item("60 Hz - Smooth", 60)


func _update_ghost_recording_hint() -> void:
	if opt_ghost_recording_rate != null:
		opt_ghost_recording_rate.disabled = not SettingsManager.race_record_ghost_data
	if label_ghost_recording_hint == null:
		return
	if not SettingsManager.race_record_ghost_data:
		label_ghost_recording_hint.text = "Recording is off. Existing ghosts play at up to %d Hz." % SettingsManager.race_ghost_playback_rate
		return
	var tick_rate: int = SettingsManager.race_ghost_recording_rate
	var quality_text: String = "compact" if tick_rate == 15 else ("high fidelity" if tick_rate == 60 else "balanced")
	label_ghost_recording_hint.text = "Runs are captured at %d Hz (%s) and ghosts play at up to %d Hz. Choose Save Ghost after finishing; otherwise the run is discarded." % [tick_rate, quality_text, SettingsManager.race_ghost_playback_rate]


func _build_auto_follow_tuning_ui() -> void:
	var content: Node = camera_content
	if content == null:
		return
	var insert_after: Node = content.get_node_or_null("HBoxAutoFollowInterruptDelay")
	var insert_index: int = -1
	if insert_after != null:
		insert_index = insert_after.get_index() + 1

	var _add_row := func(label_text: String, control: Control, row_name: String) -> void:
		var row := HBoxContainer.new()
		row.name = row_name
		row.add_theme_constant_override("separation", 12)
		var lbl := Label.new()
		lbl.text = label_text
		row.add_child(lbl)
		control.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(control)
		content.add_child(row)
		if insert_index >= 0:
			content.move_child(row, insert_index)
			insert_index += 1

	# Deadzone visual widget (positioned to the right of the panel)
	var panel: Control = $Overlay/OptionsPanel/Panel
	_deadzone_visual = preload("res://LS5Framework/Scenes/UI/DeadzoneVisual.gd").new()
	_deadzone_visual.visible = false
	_deadzone_visual.position = Vector2(panel.size.x - 140.0, 80.0)
	panel.add_child(_deadzone_visual)

	slider_auto_follow_deadzone = HSlider.new()
	slider_auto_follow_deadzone.min_value = 0.0
	slider_auto_follow_deadzone.max_value = 45.0
	slider_auto_follow_deadzone.step = 1.0
	slider_auto_follow_deadzone.value = SettingsManager.camera_auto_follow_deadzone_deg
	slider_auto_follow_deadzone.value_changed.connect(_on_SliderAutoFollowDeadzone_value_changed)
	slider_auto_follow_deadzone.focus_entered.connect(_on_DeadzoneSlider_focus_entered)
	slider_auto_follow_deadzone.focus_exited.connect(_on_DeadzoneSlider_focus_exited)
	_add_row.call("Auto Follow Deadzone", slider_auto_follow_deadzone, "HBoxAutoFollowDeadzone")

	slider_auto_follow_max_deviation = HSlider.new()
	slider_auto_follow_max_deviation.min_value = 15.0
	slider_auto_follow_max_deviation.max_value = 180.0
	slider_auto_follow_max_deviation.step = 5.0
	slider_auto_follow_max_deviation.value = SettingsManager.camera_auto_follow_max_deviation_deg
	slider_auto_follow_max_deviation.value_changed.connect(_on_SliderAutoFollowMaxDeviation_value_changed)
	slider_auto_follow_max_deviation.focus_entered.connect(_start_camera_preview.bind("horizontal"))
	slider_auto_follow_max_deviation.focus_exited.connect(_stop_camera_preview)
	_add_row.call("Auto Follow Max Deviation", slider_auto_follow_max_deviation, "HBoxAutoFollowMaxDeviation")

	chk_auto_follow_vertical_enabled = CheckBox.new()
	chk_auto_follow_vertical_enabled.button_pressed = SettingsManager.camera_auto_follow_vertical_enabled
	chk_auto_follow_vertical_enabled.toggled.connect(_on_CheckAutoFollowVerticalEnabled_toggled)
	chk_auto_follow_vertical_enabled.focus_entered.connect(_start_camera_preview.bind("combined"))
	chk_auto_follow_vertical_enabled.focus_exited.connect(_stop_camera_preview)
	_add_row.call("Auto Follow Vertical", chk_auto_follow_vertical_enabled, "HBoxAutoFollowVerticalEnabled")

	slider_auto_follow_vertical_max_tilt = HSlider.new()
	slider_auto_follow_vertical_max_tilt.min_value = 0.0
	slider_auto_follow_vertical_max_tilt.max_value = 45.0
	slider_auto_follow_vertical_max_tilt.step = 1.0
	slider_auto_follow_vertical_max_tilt.value = SettingsManager.camera_auto_follow_vertical_max_tilt
	slider_auto_follow_vertical_max_tilt.value_changed.connect(_on_SliderAutoFollowVerticalMaxTilt_value_changed)
	slider_auto_follow_vertical_max_tilt.focus_entered.connect(_start_camera_preview.bind("combined"))
	slider_auto_follow_vertical_max_tilt.focus_exited.connect(_stop_camera_preview)
	_add_row.call("Auto Follow Vertical Strength", slider_auto_follow_vertical_max_tilt, "HBoxAutoFollowVerticalMaxTilt")

	slider_auto_follow_level_pitch = HSlider.new()
	slider_auto_follow_level_pitch.min_value = -45.0
	slider_auto_follow_level_pitch.max_value = 45.0
	slider_auto_follow_level_pitch.step = 1.0
	slider_auto_follow_level_pitch.value = SettingsManager.camera_auto_follow_level_pitch_deg
	slider_auto_follow_level_pitch.value_changed.connect(_on_SliderAutoFollowLevelPitch_value_changed)
	slider_auto_follow_level_pitch.focus_entered.connect(_start_camera_preview.bind("level"))
	slider_auto_follow_level_pitch.focus_exited.connect(_stop_camera_preview)
	_add_row.call("Auto Follow Level Pitch", slider_auto_follow_level_pitch, "HBoxAutoFollowLevelPitch")


func _on_OptionHomingTargetMode_item_selected(index: int) -> void:
	var mode: int = opt_homing_target_mode.get_item_id(index)
	SettingsManager.set_homing_targeting_mode(mode)
	SettingsManager.save_now()


func _on_OptionPlayerTrackingMode_item_selected(index: int) -> void:
	var mode: int = opt_player_tracking_mode.get_item_id(index)
	SettingsManager.set_player_tracking_mode(mode)
	SettingsManager.save_now()


func _on_CheckSeparateHomingTargeting_toggled(pressed: bool) -> void:
	SettingsManager.set_homing_targeting_separate_by_device(pressed)
	_update_homing_targeting_device_ui()
	SettingsManager.save_now()


func _on_OptionMouseHomingTargetMode_item_selected(index: int) -> void:
	var mode: int = opt_mouse_homing_target_mode.get_item_id(index)
	SettingsManager.set_homing_mouse_targeting_mode(mode)
	SettingsManager.save_now()


func _on_OptionLightspeedDashTargetMode_item_selected(index: int) -> void:
	var mode: int = opt_lightspeed_dash_target_mode.get_item_id(index)
	SettingsManager.set_lightspeed_dash_targeting_mode(mode)
	SettingsManager.save_now()


func _on_SliderHomingRadius_value_changed(value: float) -> void:
	SettingsManager.set_homing_camera_radius(value)
	SettingsManager.save_now()


func _on_SliderCameraFollowSmoothing_value_changed(value: float) -> void:
	SettingsManager.set_camera_follow_smoothing(value)
	SettingsManager.save_now()


func _on_CheckCameraDolly_toggled(pressed: bool) -> void:
	SettingsManager.set_camera_dolly_enabled(pressed)
	SettingsManager.save_now()


func _on_CheckCameraTargetLookahead_toggled(pressed: bool) -> void:
	SettingsManager.set_camera_target_lookahead_enabled(pressed)
	_update_camera_lookahead_ui()
	SettingsManager.save_now()


func _on_SliderCameraTargetLookaheadAmount_value_changed(value: float) -> void:
	SettingsManager.set_camera_target_lookahead_amount(value)
	SettingsManager.save_now()


func _update_camera_lookahead_ui() -> void:
	if slider_camera_target_lookahead != null and chk_camera_target_lookahead != null:
		var lookahead_enabled: bool = chk_camera_target_lookahead.button_pressed
		slider_camera_target_lookahead.editable = lookahead_enabled
		slider_camera_target_lookahead.focus_mode = Control.FOCUS_ALL if lookahead_enabled else Control.FOCUS_NONE


func _on_CheckAutoFollowCamera_toggled(pressed: bool) -> void:
	SettingsManager.set_camera_auto_follow_enabled(pressed)
	SettingsManager.save_now()


func _on_CheckAutoFollowControllerOnly_toggled(pressed: bool) -> void:
	SettingsManager.set_camera_auto_follow_controller_only(pressed)
	SettingsManager.save_now()


func _on_SliderAutoFollowSensitivity_value_changed(value: float) -> void:
	SettingsManager.set_camera_auto_follow_sensitivity(value)
	SettingsManager.save_now()


func _on_SliderAutoFollowInterruptDelay_value_changed(value: float) -> void:
	SettingsManager.set_camera_auto_follow_interrupt_delay(value)
	SettingsManager.save_now()


func _on_SliderAutoFollowDeadzone_value_changed(value: float) -> void:
	SettingsManager.set_camera_auto_follow_deadzone_deg(value)
	if _deadzone_visual != null:
		_deadzone_visual.set_deadzone(value)
	SettingsManager.save_now()


func _on_DeadzoneSlider_focus_entered() -> void:
	_start_camera_preview("horizontal")
	if _deadzone_visual != null:
		_deadzone_visual.visible = true
		_deadzone_visual.set_deadzone(slider_auto_follow_deadzone.value)
		_deadzone_visual.set_max_deviation(slider_auto_follow_max_deviation.value)


func _on_DeadzoneSlider_focus_exited() -> void:
	_stop_camera_preview()
	if _deadzone_visual != null:
		_deadzone_visual.visible = false


func _on_SliderAutoFollowMaxDeviation_value_changed(value: float) -> void:
	SettingsManager.set_camera_auto_follow_max_deviation_deg(value)
	SettingsManager.save_now()


func _on_CheckAutoFollowVerticalEnabled_toggled(pressed: bool) -> void:
	SettingsManager.set_camera_auto_follow_vertical_enabled(pressed)
	SettingsManager.save_now()


func _on_SliderAutoFollowVerticalMaxTilt_value_changed(value: float) -> void:
	SettingsManager.set_camera_auto_follow_vertical_max_tilt(value)
	SettingsManager.save_now()


func _on_SliderAutoFollowLevelPitch_value_changed(value: float) -> void:
	SettingsManager.set_camera_auto_follow_level_pitch_deg(value)
	SettingsManager.save_now()


func _on_CheckCenterReticle_toggled(pressed: bool) -> void:
	SettingsManager.set_center_reticle_enabled(pressed)
	SettingsManager.save_now()


func _on_hud_visible_toggled(pressed: bool) -> void:
	SettingsManager.set_hud_visible(pressed)
	if _is_open and not _pause_preview_hidden:
		_set_hud_visible(false)
	SettingsManager.save_now()


func _on_action_prompts_toggled(pressed: bool) -> void:
	SettingsManager.set_action_prompts_visible(pressed)
	SettingsManager.save_now()


func _on_fps_counter_toggled(pressed: bool) -> void:
	SettingsManager.set_fps_counter_visible(pressed)
	SettingsManager.save_now()


func _on_SliderCenterReticleScale_value_changed(value: float) -> void:
	SettingsManager.set_center_reticle_scale(value)
	SettingsManager.save_now()


func _on_SliderCenterReticleOpacity_value_changed(value: float) -> void:
	SettingsManager.set_center_reticle_opacity(value)
	SettingsManager.save_now()


func _on_ColorCenterReticle_color_changed(color: Color) -> void:
	SettingsManager.set_center_reticle_color(color)
	SettingsManager.save_now()


func _on_SliderReticleVerticalOffset_value_changed(value: float) -> void:
	SettingsManager.set_reticle_vertical_offset(value)
	SettingsManager.save_now()

func _on_CheckComboSystem_toggled(pressed: bool) -> void:
	SettingsManager.set_combo_system_enabled(pressed)
	SettingsManager.save_now()


func _on_CheckRecordRaceGhosts_toggled(pressed: bool) -> void:
	SettingsManager.set_race_record_ghost_data(pressed)
	SettingsManager.save_now()
	_update_ghost_recording_hint()


func _on_OptionGhostRecordingRate_item_selected(index: int) -> void:
	if opt_ghost_recording_rate == null:
		return
	var tick_rate: int = opt_ghost_recording_rate.get_item_id(index)
	SettingsManager.set_race_ghost_recording_rate(tick_rate)
	SettingsManager.save_now()
	_update_ghost_recording_hint()


func _on_OptionGhostPlaybackRate_item_selected(index: int) -> void:
	if opt_ghost_playback_rate == null:
		return
	var tick_rate: int = opt_ghost_playback_rate.get_item_id(index)
	SettingsManager.set_race_ghost_playback_rate(tick_rate)
	SettingsManager.save_now()
	_update_ghost_recording_hint()

func _on_CheckUseCharacterColorsOffline_toggled(pressed: bool) -> void:
	SettingsManager.set_use_character_colors(pressed)
	SettingsManager.save_now()
	_refresh_offline_colors_now()

func _on_ColorOfflinePrimary_color_changed(color: Color) -> void:
	SettingsManager.set_character_primary_color(color)
	SettingsManager.save_now()
	_refresh_offline_colors_now()

func _on_ColorOfflineSecondary_color_changed(color: Color) -> void:
	SettingsManager.set_character_secondary_color(color)
	SettingsManager.save_now()
	_refresh_offline_colors_now()

func _on_ColorOfflineTrail_color_changed(color: Color) -> void:
	SettingsManager.set_character_trail_color(color)
	SettingsManager.save_now()
	_refresh_offline_colors_now()


## Asks the in-scene NetworkSession (if any) to push the current character colors to the live player state.
## Safe to call from menu callbacks.
func _refresh_offline_colors_now() -> void:
	var tree = get_tree()
	if tree == null:
		return
	var ns = _get_network_session()
	if ns != null:
		if ns.has_method("refresh_local_character_colors"):
			ns.call("refresh_local_character_colors")
			return
		if ns.has_method("refresh_local_colors_if_offline"):
			ns.call("refresh_local_colors_if_offline")
			return
	var player = _get_local_player()
	if player == null or not player.has_method("set_character_colors"):
		return
	var pri: Color = Color(0.18, 0.52, 1.0, 1.0)
	var sec: Color = Color(1, 1, 1, 1)
	var trl: Color = Color(0.2, 0.8, 1.0, 1.0)
	if SettingsManager.use_character_colors:
		pri = SettingsManager.character_primary_color
		sec = SettingsManager.character_secondary_color
		trl = SettingsManager.character_trail_color
	player.call("set_character_colors", pri, sec, trl)


func _get_camera_rig() -> Node:
	if get_tree() == null:
		return null
	for rig in get_tree().get_nodes_in_group("CameraRig"):
		if rig != null and is_instance_valid(rig) and rig.has_method("set_auto_follow_preview"):
			return rig
	return null


func _start_camera_preview(setting_type: String) -> void:
	var rig: Node = _get_camera_rig()
	if rig == null:
		return
	var velocity: Vector3 = Vector3.ZERO
	match setting_type:
		"horizontal":
			velocity = Vector3(100.0, 0.0, 0.0)
		"combined":
			velocity = Vector3(55.0, 55.0, 0.0)
		"level":
			velocity = Vector3(80.0, 0.0, 0.0)
	rig.call("set_auto_follow_preview", true, velocity)


func _stop_camera_preview() -> void:
	var rig: Node = _get_camera_rig()
	if rig == null:
		return
	rig.call("set_auto_follow_preview", false, Vector3.ZERO)


func _on_CheckRememberEmotePage_toggled(pressed: bool) -> void:
	SettingsManager.set_remember_emote_page(pressed)
	SettingsManager.save_now()
