extends Control

const ONLINE_CONNECTION_INTERNET: int = 0
const ONLINE_CONNECTION_DIRECT: int = 1

@export_file("*.tscn") var test_level_scene: String
## Allows title input to skip the startup fade and logo slide.
@export var allow_title_sequence_skip: bool = true

## Directory where LVL_*.tres docs live (including LVLTEST.tres).
@export var level_data_dir: String = "res://LS5Framework/Scenes/Levels"
## Directory where CHAR_*.tres character docs live.
@export var character_data_dir: String = "res://LS5Framework/Characters"
@export_group("Music")
## Audio stream played on the title screen.
@export var title_music: AudioStream
## Optional separate menu theme; empty keeps the title music playing.
@export var main_menu_music: AudioStream
## Audio stream played when the required Data folder is unavailable at startup.
@export var missing_data_music: AudioStream
## Fade-in duration for main menu music.
@export var main_menu_music_fade_in: float = 0.75
## Fade-out duration used when replacing existing music.
@export var main_menu_music_fade_out: float = 0.5
@export_group("")

const LOADING_SCREEN_SCENE: PackedScene = preload("res://LS5Framework/Scenes/UI/LoadingScreen.tscn")
const CHARACTER_SETTINGS_MENU_SCENE: PackedScene = preload("res://LS5Framework/Scenes/UI/CharacterSettingsMenu.tscn")
const CHARACTER_SETTINGS_ICON: Texture2D = preload("res://LS5Framework/Images/UI/Settings_Cogwheel.png")
const LOADING_MIN_VISIBLE_TIME: float = 0.2
## Delay after the loading transition settles before starting the threaded load.
const LOADING_PRELOAD_DELAY: float = 0.12
const MENU_TRANSITION_DURATION: float = 0.12
const MENU_TRANSITION_OFFSET: float = 44.0
const MISSING_DATA_ROW_COUNT: int = 5
const MISSING_DATA_TEXT: String = "NO WAY!  NO WAY!  NO WAY?  "
const MISSING_DATA_SCROLL_VIEWPORTS_PER_SECOND: float = 0.16
const MISSING_DATA_PULSE_CYCLE_DURATION: float = 2.0
const MISSING_DATA_FONT: Font = preload("res://LS5Framework/Resources/Fonts/Orbitron900.tres")

## UI nodes that stay visible and active while the level loading screen is shown.
@export var loading_exposed_nodes: Array[Node] = []

## Main menu frame and its contents, animated together during navigation.
@onready var panel_main: Control = $Overlay/MenuContainer
@onready var panel_character: Control   = $Overlay/CharacterSelectPanel
@onready var panel_level: Control       = $Overlay/LevelSelectPanel
@onready var panel_online: Control      = $Overlay/OnlinePanel
@onready var panel_options: Control     = $Overlay/OptionsPanel
@onready var panel_credits: Control     = $Overlay/CreditsPanel
## Starts the configured test level from the main menu.
@onready var button_start_test_level: Button = $Overlay/MenuContainer/VBoxMain/ButtonStart
## Opens character selection when packaged game data is available.
@onready var button_character_select: Button = $Overlay/MenuContainer/VBoxMain/ButtonCharacterSelect
## Opens level selection when packaged game data is available.
@onready var button_level_select: Button = $Overlay/MenuContainer/VBoxMain/ButtonLevelSelect
## Replaces the standard title backdrop when the required Data folder is unavailable.
@onready var missing_data_background: ColorRect = $MissingDataBackground
## Blocks the main menu while the required Data folder warning is visible.
@onready var missing_data_warning: Control = $Overlay/MissingDataWarning
## Exits immediately from the blocking missing-Data warning.
@onready var button_dismiss_missing_data: Button = $Overlay/MissingDataWarning/WarningFrame/Margin/Content/ButtonDismiss

@onready var character_list: VBoxContainer = $Overlay/CharacterSelectPanel/Panel/VBoxCharacters/ScrollContainer/CharacterList
@onready var level_list: VBoxContainer  = $Overlay/LevelSelectPanel/Panel/VBoxLevels/ScrollContainer/LevelList

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

@onready var chk_vsync: CheckBox      = $Overlay/OptionsPanel/Panel/VBoxOptions/TabsOptions/TabGraphics/ScrollGraphics/GraphicsContent/HBoxVsync/CheckVsync
@onready var chk_fullscreen: CheckBox = $Overlay/OptionsPanel/Panel/VBoxOptions/TabsOptions/TabGraphics/ScrollGraphics/GraphicsContent/HBoxFullscreen/CheckFullscreen

@onready var chk_ssr: CheckBox     = $Overlay/OptionsPanel/Panel/VBoxOptions/TabsOptions/TabGraphics/ScrollGraphics/GraphicsContent/GridGraphics/CheckSSR
@onready var chk_ssao: CheckBox    = $Overlay/OptionsPanel/Panel/VBoxOptions/TabsOptions/TabGraphics/ScrollGraphics/GraphicsContent/GridGraphics/CheckSSAO
@onready var chk_ssil: CheckBox    = $Overlay/OptionsPanel/Panel/VBoxOptions/TabsOptions/TabGraphics/ScrollGraphics/GraphicsContent/GridGraphics/CheckSSIL
@onready var chk_sdfgi: CheckBox   = $Overlay/OptionsPanel/Panel/VBoxOptions/TabsOptions/TabGraphics/ScrollGraphics/GraphicsContent/GridGraphics/CheckSDFGI
@onready var chk_shadows: CheckBox = $Overlay/OptionsPanel/Panel/VBoxOptions/TabsOptions/TabGraphics/ScrollGraphics/GraphicsContent/GridGraphics/CheckShadows
@onready var chk_glow: CheckBox    = $Overlay/OptionsPanel/Panel/VBoxOptions/TabsOptions/TabGraphics/ScrollGraphics/GraphicsContent/GridGraphics/CheckGlow
## Controls the depth-of-field graphics setting.
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
## Controls the UI audio bus volume from the main menu.
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
@onready var slider_reticle_vertical_offset: HSlider = $Overlay/OptionsPanel/Panel/VBoxOptions/TabsOptions/TabGameplay/ScrollGameplay/GameplayContent/HBoxReticleVerticalOffset/SliderReticleVerticalOffset
## Controls whether the emote wheel remembers its last used page.
@onready var chk_remember_emote_page: CheckBox = $Overlay/OptionsPanel/Panel/VBoxOptions/TabsOptions/TabGameplay/ScrollGameplay/GameplayContent/HBoxRememberEmotePage/CheckRememberEmotePage
@onready var chk_combo_system: CheckBox = $Overlay/OptionsPanel/Panel/VBoxOptions/TabsOptions/TabGameplay/ScrollGameplay/GameplayContent/HBoxComboSystem/CheckComboSystem
## Controls whether eligible single-player race runs are captured in memory for optional saving.
@onready var chk_record_race_ghosts: CheckBox = $Overlay/OptionsPanel/Panel/VBoxOptions/TabsOptions/TabGameplay/ScrollGameplay/GameplayContent/HBoxRecordRaceGhosts/CheckRecordRaceGhosts
## Selects the sampling rate used for new race ghost recordings.
@onready var opt_ghost_recording_rate: OptionButton = $Overlay/OptionsPanel/Panel/VBoxOptions/TabsOptions/TabGameplay/ScrollGameplay/GameplayContent/HBoxGhostRecordingRate/OptionGhostRecordingRate
## Caps how frequently ghost playback poses are applied.
@onready var opt_ghost_playback_rate: OptionButton = $Overlay/OptionsPanel/Panel/VBoxOptions/TabsOptions/TabGameplay/ScrollGameplay/GameplayContent/HBoxGhostPlaybackRate/OptionGhostPlaybackRate
## Describes the active race ghost recording policy and quality level.
@onready var label_ghost_recording_hint: Label = $Overlay/OptionsPanel/Panel/VBoxOptions/TabsOptions/TabGameplay/ScrollGameplay/GameplayContent/GhostRecordingHint
@onready var chk_use_character_colors_offline: CheckBox = $Overlay/OptionsPanel/Panel/VBoxOptions/TabsOptions/TabGameplay/ScrollGameplay/GameplayContent/HBoxUseCharacterColorsOffline/CheckUseCharacterColorsOffline
@onready var color_offline_primary: ColorPickerButton = $Overlay/OptionsPanel/Panel/VBoxOptions/TabsOptions/TabGameplay/ScrollGameplay/GameplayContent/HBoxOfflinePrimaryColor/ColorOfflinePrimary
@onready var color_offline_secondary: ColorPickerButton = $Overlay/OptionsPanel/Panel/VBoxOptions/TabsOptions/TabGameplay/ScrollGameplay/GameplayContent/HBoxOfflineSecondaryColor/ColorOfflineSecondary
@onready var color_offline_trail: ColorPickerButton = $Overlay/OptionsPanel/Panel/VBoxOptions/TabsOptions/TabGameplay/ScrollGameplay/GameplayContent/HBoxOfflineTrailColor/ColorOfflineTrail

@onready var edit_address: LineEdit = $Overlay/OnlinePanel/Panel/VBoxOnline/HBoxAddress/LineEditAddress
@onready var label_address: Label = $Overlay/OnlinePanel/Panel/VBoxOnline/HBoxAddress/LabelAddress
@onready var opt_connection_method: OptionButton = $Overlay/OnlinePanel/Panel/VBoxOnline/HBoxConnectionMethod/OptionConnectionMethod
@onready var row_port: HBoxContainer = $Overlay/OnlinePanel/Panel/VBoxOnline/HBoxPort
@onready var label_connection_hint: Label = $Overlay/OnlinePanel/Panel/VBoxOnline/LabelConnectionHint
@onready var edit_port: LineEdit = $Overlay/OnlinePanel/Panel/VBoxOnline/HBoxPort/LineEditPort
@onready var edit_name: LineEdit = $Overlay/OnlinePanel/Panel/VBoxOnline/HBoxName/LineEditName
@onready var color_name: ColorPickerButton = $Overlay/OnlinePanel/Panel/VBoxOnline/HBoxName/ColorName
@onready var chk_use_character_colors: CheckBox = $Overlay/OnlinePanel/Panel/VBoxOnline/HBoxUseCharacterColors/CheckUseCharacterColors
@onready var color_primary: ColorPickerButton = $Overlay/OnlinePanel/Panel/VBoxOnline/HBoxCharColors/ColorPrimary
@onready var color_secondary: ColorPickerButton = $Overlay/OnlinePanel/Panel/VBoxOnline/HBoxSecondaryColors/ColorSecondary
@onready var color_trail: ColorPickerButton = $Overlay/OnlinePanel/Panel/VBoxOnline/HBoxTrailColors/ColorTrail
@onready var spin_max_players: SpinBox = $Overlay/OnlinePanel/Panel/VBoxOnline/HBoxMaxPlayers/SpinMaxPlayers
@onready var label_online_status: Label = $Overlay/OnlinePanel/Panel/VBoxOnline/LabelOnlineStatus
@onready var button_host: Button = $Overlay/OnlinePanel/Panel/VBoxOnline/HBoxButtons/ButtonHost
@onready var button_join: Button = $Overlay/OnlinePanel/Panel/VBoxOnline/HBoxButtons/ButtonJoin

@onready var sfx_hover: AudioStreamPlayer = $Overlay/SfxHover
@onready var sfx_press: AudioStreamPlayer = $Overlay/SfxPress
@onready var sfx_click: AudioStreamPlayer = $Overlay/SfxClick
## Plays the warning cue when a blocking warning or confirmation opens.
@onready var sfx_warning: AudioStreamPlayer = $Overlay/SfxWarning
## Plays UI voice lines belonging to the currently selected character.
@onready var character_ui_voice_player: CharacterUIVoicePlayer = $CharacterUIVoicePlayer
## Displays current music information without intercepting menu input.
@onready var music_track_display: HUDMusicTrackDisplay = $MusicTrackDisplay

## Time window (seconds) to suppress hover SFX after a confirm press.
@export var hover_suppress_after_press_time: float = 0.15
## Stops the active button-down sound when the button-release sound begins.
@export var release_cancels_press_sound: bool = true

var _level_entries: Array = []
var _character_entries: Array = []
var _level_list_waiting_for_packs: bool = false
var _pack_wait_attempts: int = 0
var _hover_suppress_until_ms: int = 0
var _menu_music_controller: MusicController = null
var _loading_started: bool = false
var _online_connection_mode: int = ONLINE_CONNECTION_INTERNET
var _menu_panels: Array[Control] = []
var _menu_panel_positions: Dictionary = {}
var _active_panel: Control = null
var _menu_transition: Tween = null
var _menu_transition_active: bool = false
var _character_settings_menu: CharacterSettingsMenu = null
var _missing_data_rows: Array[Dictionary] = []
var _missing_data_animation_time: float = 0.0
var _data_folder_missing: bool = true
var _graphics_previous_snapshot: Dictionary = {}
var _graphics_confirmation_remaining: float = 0.0
var _last_options_tab: int = 0
var _pending_options_tab: int = -1
var _pending_options_exit: bool = false
var _changing_options_tab: bool = false
const GRAPHICS_CONFIRMATION_DURATION: float = 15.0

var slider_auto_follow_deadzone: HSlider
var slider_auto_follow_max_deviation: HSlider
var chk_auto_follow_vertical_enabled: CheckBox
var slider_auto_follow_vertical_max_tilt: HSlider
var slider_auto_follow_level_pitch: HSlider

var _deadzone_visual: Control


## Animated skyline, title artwork, and title prompt.
@onready var title_backdrop: Control = $TitleBackdrop
## Root containing the interactive menu frames.
@onready var menu_overlay: Control = $Overlay
## Controller-accessible exit confirmation.
@onready var _exit_dialog: Control = $ExitDialog
## Confirms exiting the game and receives initial dialog focus.
@onready var _button_exit: Button = $ExitDialog/WarningFrame/Margin/Content/Buttons/ButtonExit
## Cancels exiting and restores the previous menu focus.
@onready var _button_exit_cancel: Button = $ExitDialog/WarningFrame/Margin/Content/Buttons/ButtonCancel
var _title_active: bool = true
var _title_departing: bool = false
## Plays the logo entrance sound through the UI bus.
@onready var sfx_title_swoopin: AudioStreamPlayer = $SfxTitleSwoopin
## Plays the title confirmation sound through the UI bus.
@onready var sfx_title_start: AudioStreamPlayer = $SfxTitleStart
static var _startup_title_shown: bool = false
var _startup_data_check_complete: bool = false
var _test_level_skip_requested: bool = false

func _ready() -> void:
	menu_overlay.hide()
	title_backdrop.entrance_music_requested.connect(_play_title_music)
	title_backdrop.departure_finished.connect(_finish_title_departure)
	_button_exit.pressed.connect(func() -> void: get_tree().quit())
	_button_exit_cancel.pressed.connect(_cancel_exit)
	_ensure_content_pack_manager()
	_set_data_dependent_actions_enabled(false)
	set_process_input(true)
	set_process(true)
	set_process_unhandled_input(true)
	# Ensure we're not still connected if we came back from gameplay.
	var net = get_node_or_null("/root/NetworkManager")
	if net != null:
		net.call("leave")
	_restore_menu_mouse_cursor()
	call_deferred("_restore_menu_mouse_cursor")

	# Clean up any persistent race UI elements that may have been added to the viewport.
	if get_tree() != null:
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

	# Panels
	_register_menu_panels()
	_ensure_camera_tab()
	_ensure_data_tab()
	_ensure_player_tracking_setting()
	_build_auto_follow_tuning_ui()
	_organize_gameplay_sections()
	_ensure_displays_tab()
	_organize_options_tabs()
	_configure_graphics_apply_button()
	_configure_options_tab_focus()
	_show_main_menu(true)
	_apply_tab_titles()
	if tabs_options != null and not tabs_options.tab_changed.is_connected(_on_options_tab_changed):
		tabs_options.tab_changed.connect(_on_options_tab_changed)
	call_deferred("_focus_visible_panel")

	# Populate resolution list
	_populate_resolution_list()
	_populate_render_scaling_options()
	_populate_graphics_quality_options()
	_populate_lod_distance_options()
	_populate_homing_target_mode()
	_populate_lightspeed_dash_target_mode()
	_populate_ghost_recording_rates()
	_populate_ghost_playback_rates()
	_populate_online_connection_methods()

	# Sync UI to current settings
	_sync_options_from_settings()
	_last_options_tab = tabs_options.current_tab
	_update_music_track_display_colors()

	# Online defaults from settings
	edit_port.text = str(SettingsManager.online_port)
	edit_name.text = SettingsManager.online_player_name
	if color_name != null:
		color_name.color = SettingsManager.online_name_color
	if chk_use_character_colors != null:
		chk_use_character_colors.button_pressed = SettingsManager.use_character_colors
	if color_primary != null:
		color_primary.color = SettingsManager.character_primary_color
	if color_secondary != null:
		color_secondary.color = SettingsManager.character_secondary_color
	if color_trail != null:
		color_trail.color = SettingsManager.character_trail_color
	if spin_max_players != null:
		spin_max_players.value = SettingsManager.online_max_players
	_online_connection_mode = clampi(SettingsManager.online_connection_mode, ONLINE_CONNECTION_INTERNET, ONLINE_CONNECTION_DIRECT)
	_apply_online_connection_mode()
	#var net = get_node_or_null("/root/NetworkManager")
	if net != null:
		net.set("player_name", SettingsManager.online_player_name)
		net.set("player_color", SettingsManager.online_name_color)
		net.set("player_primary_color", SettingsManager.character_primary_color)
		net.set("player_secondary_color", SettingsManager.character_secondary_color)
		net.set("player_trail_color", SettingsManager.character_trail_color)
		_store_online_destination()
		SettingsManager.online_port = int(edit_port.text)
		SettingsManager.online_max_players = int(spin_max_players.value)
		SettingsManager.save_now()
	# Build level select list after pack mounts finish.
	call_deferred("_build_level_list_after_packs")

	# Connect button sounds for all buttons in the "MenuButtons" group
	for node in get_tree().get_nodes_in_group("MenuButtons"):
		if node is BaseButton:
			node.mouse_entered.connect(_on_any_button_mouse_entered)
			node.focus_entered.connect(_on_any_button_focus_entered)
			node.button_down.connect(_on_any_button_button_down)
			node.pressed.connect(_on_any_button_pressed)

	# Online menu buttons
	var btn_online = get_node_or_null("Overlay/MenuContainer/VBoxMain/ButtonOnline")
	if btn_online != null:
		btn_online.pressed.connect(_on_ButtonOnline_pressed)
	get_node("Overlay/OnlinePanel/Panel/VBoxOnline/ButtonOnlineBack").pressed.connect(_on_ButtonOnlineBack_pressed)
	get_node("Overlay/OnlinePanel/Panel/VBoxOnline/HBoxButtons/ButtonHost").pressed.connect(_on_ButtonHost_pressed)
	get_node("Overlay/OnlinePanel/Panel/VBoxOnline/HBoxButtons/ButtonJoin").pressed.connect(_on_ButtonJoin_pressed)
	opt_connection_method.item_selected.connect(_on_ConnectionMethod_item_selected)

	if net != null:
		if not net.status_changed.is_connected(_on_network_status_changed):
			net.status_changed.connect(_on_network_status_changed)
		if not net.connection_state_changed.is_connected(_on_network_connection_state_changed):
			net.connection_state_changed.connect(_on_network_connection_state_changed)
	_on_network_status_changed("")
	call_deferred("_initialize_startup_music_and_data_warning")


func _restore_menu_mouse_cursor() -> void:
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	Input.set_default_cursor_shape(Input.CURSOR_ARROW)


# =========================================
# MAIN BUTTON HANDLERS (hook via editor)
# =========================================
func _on_ButtonStart_pressed() -> void:
	if _loading_started or _data_folder_missing:
		return
	_start_test_level_from_menu()

func _on_ButtonOnline_pressed() -> void:
	if _loading_started:
		return
	_play_click()
	_play_character_ui_voice(&"online")
	_show_online()

func _on_ButtonCharacterSelect_pressed() -> void:
	if _loading_started or _data_folder_missing:
		return
	_play_click()
	_play_character_ui_voice(&"character")
	_show_character_select()

func _on_ButtonLevelSelect_pressed() -> void:
	if _loading_started or _data_folder_missing:
		return
	_play_click()
	_play_character_ui_voice(&"level")
	_show_level_select()

func _on_ButtonOptions_pressed() -> void:
	if _loading_started:
		return
	_play_click()
	_play_character_ui_voice(&"settings")
	_show_options()

func _on_ButtonCredits_pressed() -> void:
	if _loading_started:
		return
	_play_click()
	_show_credits()

func _on_ButtonQuit_pressed() -> void:
	if _loading_started:
		return
	_play_click()
	_show_exit_confirmation()


func _initialize_startup_music_and_data_warning() -> void:
	if OS.has_feature("editor"):
		_data_folder_missing = false
		_startup_data_check_complete = true
		_set_data_dependent_actions_enabled(true)
		call_deferred("_focus_visible_panel")
		if _test_level_skip_requested:
			_start_requested_test_level_skip()
		else:
			show_title_screen(not _startup_title_shown)
		return
	var pack_manager: Node = _get_content_pack_manager()
	if pack_manager == null:
		call_deferred("_initialize_startup_music_and_data_warning")
		return
	if not pack_manager.has_method("get_data_directory"):
		_data_folder_missing = false
		_startup_data_check_complete = true
		_set_data_dependent_actions_enabled(true)
		call_deferred("_focus_visible_panel")
		if _test_level_skip_requested:
			_start_requested_test_level_skip()
		else:
			show_title_screen(not _startup_title_shown)
		return
	var data_directory: String = String(pack_manager.call("get_data_directory"))
	if data_directory != "":
		_data_folder_missing = false
		_startup_data_check_complete = true
		_set_data_dependent_actions_enabled(true)
		call_deferred("_focus_visible_panel")
		if _test_level_skip_requested:
			_start_requested_test_level_skip()
		else:
			show_title_screen(not _startup_title_shown)
		return
	_activate_missing_data_lockout()


func _activate_missing_data_lockout() -> void:
	_startup_data_check_complete = true
	_test_level_skip_requested = false
	_title_active = false
	_title_departing = false
	menu_overlay.show()
	title_backdrop.hide()
	_data_folder_missing = true
	_set_data_dependent_actions_enabled(false)
	_show_main_menu(true)
	for menu_panel: Control in _menu_panels:
		menu_panel.hide()
	play_main_menu_music(missing_data_music)
	_activate_missing_data_background()
	missing_data_warning.visible = true
	missing_data_warning.mouse_filter = Control.MOUSE_FILTER_STOP
	button_dismiss_missing_data.visible = true
	button_dismiss_missing_data.disabled = false
	button_dismiss_missing_data.focus_mode = Control.FOCUS_ALL
	_play_warning()
	button_dismiss_missing_data.grab_focus()


func _on_dismiss_missing_data_pressed() -> void:
	if not _data_folder_missing:
		return
	get_tree().quit()


func _set_data_dependent_actions_enabled(enabled: bool) -> void:
	var buttons: Array[Button] = [
		button_start_test_level,
		button_character_select,
		button_level_select,
	]
	for button: Button in buttons:
		button.disabled = not enabled
		button.focus_mode = Control.FOCUS_ALL if enabled else Control.FOCUS_NONE
		button.tooltip_text = "" if enabled else "Unavailable because the required Data folder was not found."
	var online_buttons: Array[Button] = [button_host, button_join]
	for online_button: Button in online_buttons:
		online_button.disabled = not enabled
		online_button.focus_mode = Control.FOCUS_ALL if enabled else Control.FOCUS_NONE
		online_button.tooltip_text = "" if enabled else "Unavailable because the required Data folder was not found."


func _activate_missing_data_background() -> void:
	missing_data_background.visible = true
	if _missing_data_rows.is_empty():
		_create_missing_data_rows()
		if not missing_data_background.resized.is_connected(_configure_missing_data_rows):
			missing_data_background.resized.connect(_configure_missing_data_rows)
	_configure_missing_data_rows()


func _create_missing_data_rows() -> void:
	for row_index: int in range(MISSING_DATA_ROW_COUNT):
		var row_control: Control = Control.new()
		row_control.name = "TextRow%d" % (row_index + 1)
		row_control.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row_control.clip_contents = true
		missing_data_background.add_child(row_control)

		var row_labels: Array[Label] = []
		for label_index: int in range(2):
			var label: Label = Label.new()
			label.name = "ScrollingText%d" % (label_index + 1)
			label.mouse_filter = Control.MOUSE_FILTER_IGNORE
			label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
			label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
			label.add_theme_font_override(&"font", MISSING_DATA_FONT)
			label.add_theme_color_override(&"font_color", Color.WHITE)
			row_control.add_child(label)
			row_labels.append(label)

		_missing_data_rows.append({
			"container": row_control,
			"labels": row_labels,
			"direction": -1.0 if row_index % 2 == 0 else 1.0,
			"offset": 0.0,
			"segment_width": 1.0,
		})


func _configure_missing_data_rows() -> void:
	var viewport_size: Vector2 = missing_data_background.size
	if viewport_size.x <= 0.0 or viewport_size.y <= 0.0:
		return
	var row_height: float = viewport_size.y / float(MISSING_DATA_ROW_COUNT)
	var font_size: int = maxi(24, int(row_height * 0.72))
	for row_index: int in range(_missing_data_rows.size()):
		var row_data: Dictionary = _missing_data_rows[row_index]
		var row_control: Control = row_data.get("container") as Control
		var row_labels: Array = row_data.get("labels", [])
		if row_control == null or row_labels.size() != 2:
			continue
		row_control.position = Vector2(0.0, row_height * float(row_index))
		row_control.size = Vector2(viewport_size.x, row_height)

		var segment_text: String = MISSING_DATA_TEXT
		var segment_width: float = MISSING_DATA_FONT.get_string_size(segment_text, HORIZONTAL_ALIGNMENT_LEFT, -1.0, font_size).x
		while segment_width < viewport_size.x * 1.15:
			segment_text += MISSING_DATA_TEXT
			segment_width = MISSING_DATA_FONT.get_string_size(segment_text, HORIZONTAL_ALIGNMENT_LEFT, -1.0, font_size).x
		segment_width = maxf(segment_width, 1.0)

		for label_value: Variant in row_labels:
			var label: Label = label_value as Label
			if label == null:
				continue
			label.text = segment_text
			label.add_theme_font_size_override(&"font_size", font_size)
			label.size = Vector2(segment_width, row_height)

		var direction: float = float(row_data.get("direction", -1.0))
		var offset: float = 0.0 if direction < 0.0 else -segment_width
		row_data["offset"] = offset
		row_data["segment_width"] = segment_width
		_position_missing_data_row(row_data)


func _update_missing_data_background(delta: float) -> void:
	_missing_data_animation_time += maxf(delta, 0.0)
	var scroll_speed: float = missing_data_background.size.x * MISSING_DATA_SCROLL_VIEWPORTS_PER_SECOND
	for row_index: int in range(_missing_data_rows.size()):
		var row_data: Dictionary = _missing_data_rows[row_index]
		var direction: float = float(row_data.get("direction", -1.0))
		var segment_width: float = maxf(float(row_data.get("segment_width", 1.0)), 1.0)
		var offset: float = float(row_data.get("offset", 0.0)) + direction * scroll_speed * delta
		if direction < 0.0 and offset <= -segment_width:
			offset += segment_width
		elif direction > 0.0 and offset >= 0.0:
			offset -= segment_width
		row_data["offset"] = offset

		var pulse_phase: float = (_missing_data_animation_time / MISSING_DATA_PULSE_CYCLE_DURATION) * TAU
		var pulse: float = sin(pulse_phase + float(row_index) * 0.72)
		var opacity: float = lerpf(0.38, 1.0, pulse * 0.5 + 0.5)
		var row_labels: Array = row_data.get("labels", [])
		for label_value: Variant in row_labels:
			var label: Label = label_value as Label
			if label != null:
				label.modulate = Color(1.0, 1.0, 1.0, opacity)
		_position_missing_data_row(row_data)


func _position_missing_data_row(row_data: Dictionary) -> void:
	var row_labels: Array = row_data.get("labels", [])
	if row_labels.size() != 2:
		return
	var first_label: Label = row_labels[0] as Label
	var second_label: Label = row_labels[1] as Label
	if first_label == null or second_label == null:
		return
	var offset: float = float(row_data.get("offset", 0.0))
	var segment_width: float = float(row_data.get("segment_width", 1.0))
	first_label.position = Vector2(offset, 0.0)
	second_label.position = Vector2(offset + segment_width, 0.0)


# --- Level Select panel buttons (hook via editor) ---
func _on_ButtonCharacterBack_pressed() -> void:
	if _loading_started:
		return
	_play_click()
	_show_main_menu()


func _on_ButtonLevelBack_pressed() -> void:
	if _loading_started:
		return
	_play_click()
	_show_main_menu()

# Called for each dynamically-created level button
func _on_level_button_pressed(level_name: String, scene_path: String, level_scene_path: String = "") -> void:
	if _loading_started or _data_folder_missing:
		return
	_play_click()
	if level_scene_path.strip_edges() != "":
		_set_pending_level_scene(level_scene_path)
	_change_scene_with_loading(scene_path, level_name, level_scene_path)


func _on_character_button_pressed(entry: Dictionary) -> void:
	if _loading_started:
		return
	_play_click()
	var character_id: String = String(entry.get("id", "")).strip_edges()
	if character_id == "":
		return
	SettingsManager.set_chosen_character_id(character_id)
	SettingsManager.save_now()
	_build_character_list()
	_play_character_ui_voice(&"character")


func _on_character_button_right_pressed(entry: Dictionary) -> void:
	if _loading_started:
		return
	_play_click()
	var character_id: String = String(entry.get("id", "")).strip_edges()
	if character_id == "":
		return
	var current_buddy_id: String = SettingsManager.chosen_buddy_character_id
	if SettingsManager.buddy_active and current_buddy_id.nocasecmp_to(character_id) == 0:
		SettingsManager.set_buddy_active(false)
	else:
		SettingsManager.set_chosen_buddy_character_id(character_id)
		SettingsManager.set_buddy_active(true)
	SettingsManager.save_now()
	_build_character_list()


func _on_character_settings_pressed(entry: Dictionary) -> void:
	if _loading_started:
		return
	_play_click()
	if _character_settings_menu != null and is_instance_valid(_character_settings_menu):
		_character_settings_menu.queue_free()
	_character_settings_menu = CHARACTER_SETTINGS_MENU_SCENE.instantiate() as CharacterSettingsMenu
	if _character_settings_menu == null:
		return
	$Overlay.add_child(_character_settings_menu)
	_character_settings_menu.closed.connect(_on_character_settings_closed)
	_character_settings_menu.open_for_character(entry)


func _on_character_settings_closed() -> void:
	_character_settings_menu = null
	call_deferred("_focus_visible_panel")


# --- Options panel buttons (hook via editor) ---
func _on_ButtonResetDefaults_pressed() -> void:
	if _loading_started:
		return
	_play_click()
	reset_defaults_dialog.visible = true
	_play_warning()
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
		push_warning("MainMenu: failed to reset settings: %s" % error_string(err))
		return
	_populate_resolution_list()
	_sync_options_from_settings()
	if tab_controls.has_method("refresh_from_settings"):
		tab_controls.call("refresh_from_settings")
	if tab_bindings.has_method("refresh_from_settings"):
		tab_bindings.call("refresh_from_settings")
	button_reset_defaults.grab_focus()


func _on_ButtonOptionsBack_pressed() -> void:
	if _loading_started:
		return
	if _has_unsaved_graphics_changes():
		_pending_options_exit = true
		_pending_options_tab = -1
		_show_unsaved_graphics_dialog()
		return
	_leave_options_menu()


func _leave_options_menu() -> void:
	_play_click()
	SettingsManager.save_now()
	_show_main_menu()

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
	_play_warning()
	button_confirm_graphics.grab_focus()


func _on_graphics_settings_confirmed() -> void:
	if not graphics_confirm_dialog.visible:
		return
	SettingsManager.save_now()
	_play_character_ui_voice(&"confirm")
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
	_play_warning()
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


# --- Credits panel buttons (hook via editor) ---
func _on_ButtonCreditsBack_pressed() -> void:
	if _loading_started:
		return
	_play_click()
	_show_main_menu()


# =========================================
# PANEL SWITCHING
# =========================================
func _show_main_menu(immediate: bool = false) -> void:
	_transition_to_panel(panel_main, -1, immediate)

func _show_character_select() -> void:
	if _data_folder_missing:
		return
	_build_character_list()
	_transition_to_panel(panel_character)

func _show_level_select() -> void:
	if _data_folder_missing:
		return
	_build_level_list()
	_transition_to_panel(panel_level)

func _show_online() -> void:
	_transition_to_panel(panel_online)

func _show_options() -> void:
	_transition_to_panel(panel_options)

func _show_credits() -> void:
	_transition_to_panel(panel_credits)


func _register_menu_panels() -> void:
	_menu_panels = [panel_main, panel_character, panel_level, panel_online, panel_options, panel_credits]
	_menu_panel_positions.clear()
	for panel in _menu_panels:
		if panel != null:
			_menu_panel_positions[panel.get_instance_id()] = panel.position


func _transition_to_panel(target: Control, direction: int = 1, immediate: bool = false) -> void:
	if target == null or _menu_transition_active:
		return
	var target_position: Vector2 = _get_menu_panel_position(target)
	if immediate:
		for panel in _menu_panels:
			if panel != null:
				panel.visible = panel == target
				panel.position = _get_menu_panel_position(panel)
				panel.modulate = Color.WHITE
		_active_panel = target
		call_deferred("_focus_visible_panel")
		return
	if _active_panel == target and target.visible:
		call_deferred("_focus_visible_panel")
		return
	_menu_transition_active = true
	var previous: Control = _active_panel
	if previous and not previous.visible:
		previous = null
	var travel: float = MENU_TRANSITION_OFFSET * float(direction)
	target.visible = true
	target.position = target_position + Vector2(travel, 0.0)
	target.modulate = Color(1.0, 1.0, 1.0, 0.0)
	_menu_transition = create_tween()
	_menu_transition.set_parallel(true)
	_menu_transition.set_trans(Tween.TRANS_QUAD)
	_menu_transition.set_ease(Tween.EASE_OUT)
	if previous:
		_menu_transition.tween_property(previous, "position", _get_menu_panel_position(previous) - Vector2(travel * 0.45, 0.0), MENU_TRANSITION_DURATION)
		_menu_transition.tween_property(previous, "modulate:a", 0.0, MENU_TRANSITION_DURATION)
	_menu_transition.tween_property(target, "position", target_position, MENU_TRANSITION_DURATION)
	_menu_transition.tween_property(target, "modulate:a", 1.0, MENU_TRANSITION_DURATION)
	_menu_transition.finished.connect(_finish_menu_transition.bind(previous, target))


func _finish_menu_transition(previous: Control, target: Control) -> void:
	if previous != null and is_instance_valid(previous):
		previous.visible = false
		previous.position = _get_menu_panel_position(previous)
		previous.modulate = Color.WHITE
	if target != null and is_instance_valid(target):
		target.visible = true
		target.position = _get_menu_panel_position(target)
		target.modulate = Color.WHITE
	_active_panel = target
	_menu_transition_active = false
	_menu_transition = null
	call_deferred("_focus_visible_panel")


func _get_menu_panel_position(panel: Control) -> Vector2:
	if panel == null:
		return Vector2.ZERO
	var stored_position: Variant = _menu_panel_positions.get(panel.get_instance_id(), panel.position)
	if stored_position is Vector2:
		return stored_position
	return panel.position


# =========================================
# ONLINE
# =========================================
func _on_network_status_changed(message: String) -> void:
	if label_online_status == null:
		return
	label_online_status.text = message


func _on_network_connection_state_changed(_state: int) -> void:
	var net: Node = get_node_or_null("/root/NetworkManager")
	var busy: bool = net != null and net.has_method("is_connecting") and bool(net.call("is_connecting"))
	if button_host != null:
		button_host.disabled = busy or _data_folder_missing
	if button_join != null:
		button_join.disabled = busy or _data_folder_missing

func _on_ButtonOnlineBack_pressed() -> void:
	if _loading_started:
		return
	var net: Node = get_node_or_null("/root/NetworkManager")
	if net != null and net.has_method("is_connecting") and bool(net.call("is_connecting")):
		net.call("leave")
	_play_click()
	_show_main_menu()

func _on_ButtonHost_pressed() -> void:
	if _loading_started or _data_folder_missing:
		return
	_play_click()
	_sync_online_character_settings_from_ui()
	var test_entry: Dictionary = _get_test_level_entry()
	var scene_path: String = test_level_scene
	var level_scene_path: String = ""
	if not test_entry.is_empty():
		scene_path = String(test_entry.get("scene", scene_path))
		level_scene_path = String(test_entry.get("level_scene", ""))
	if scene_path.strip_edges() == "":
		_on_network_status_changed("No test_level_scene set.")
		return
	if level_scene_path.strip_edges() != "":
		_set_pending_level_scene(level_scene_path)
	var port: int = int(edit_port.text)
	var max_players: int = 16
	if spin_max_players != null:
		max_players = int(spin_max_players.value)
	var net: Node = get_node_or_null("/root/NetworkManager")
	if net != null:
		_play_character_ui_voice(&"confirm")
		_apply_online_profile_to_manager(net)
		_store_online_destination()
		SettingsManager.online_connection_mode = _online_connection_mode
		SettingsManager.online_port = port
		SettingsManager.online_max_players = max_players
		SettingsManager.save_now()
		if _online_connection_mode == ONLINE_CONNECTION_INTERNET:
			net.call("host_internet", scene_path, max_players)
		else:
			net.call("host", scene_path, port, max_players)
	else:
		_on_network_status_changed("NetworkManager autoload not found.")

func _on_ButtonJoin_pressed() -> void:
	if _loading_started or _data_folder_missing:
		return
	_play_click()
	_sync_online_character_settings_from_ui()
	var address: String = edit_address.text.strip_edges()
	var port: int = int(edit_port.text)
	if address.is_empty() and _online_connection_mode == ONLINE_CONNECTION_INTERNET:
		_on_network_status_changed("Enter the host's invite code.")
		return
	if address.is_empty():
		address = "127.0.0.1"
	var net: Node = get_node_or_null("/root/NetworkManager")
	if net != null:
		_play_character_ui_voice(&"confirm")
		_apply_online_profile_to_manager(net)
		_store_online_destination()
		SettingsManager.online_connection_mode = _online_connection_mode
		SettingsManager.online_port = port
		SettingsManager.save_now()
		if _online_connection_mode == ONLINE_CONNECTION_INTERNET:
			net.call("join_with_code", address)
		else:
			net.call("join", address, port)
	else:
		_on_network_status_changed("NetworkManager autoload not found.")


func _populate_online_connection_methods() -> void:
	if opt_connection_method == null:
		return
	opt_connection_method.clear()
	opt_connection_method.add_item("Internet (Invite Code)", ONLINE_CONNECTION_INTERNET)
	opt_connection_method.add_item("Direct IP / LAN", ONLINE_CONNECTION_DIRECT)


func _on_ConnectionMethod_item_selected(index: int) -> void:
	_store_online_destination()
	_online_connection_mode = opt_connection_method.get_item_id(index)
	SettingsManager.online_connection_mode = _online_connection_mode
	_apply_online_connection_mode()
	SettingsManager.save_now()


func _apply_online_connection_mode() -> void:
	if opt_connection_method != null:
		var selected_index: int = opt_connection_method.get_item_index(_online_connection_mode)
		if selected_index >= 0:
			opt_connection_method.select(selected_index)
	var internet: bool = _online_connection_mode == ONLINE_CONNECTION_INTERNET
	if label_address != null:
		label_address.text = "Invite Code" if internet else "Address"
	if edit_address != null:
		edit_address.text = SettingsManager.online_invite_code if internet else SettingsManager.online_address
		edit_address.placeholder_text = "Enter the host's invite code" if internet else "127.0.0.1"
		edit_address.tooltip_text = "Invite code shown to the internet host." if internet else "IPv4 address or hostname for the direct host."
	if row_port != null:
		row_port.visible = not internet
	if label_connection_hint != null:
		label_connection_hint.text = (
			"Internet sessions try NAT punch-through first and fall back to a relay automatically."
			if internet
			else "Direct IP is intended for LAN play and development; internet hosts must forward the UDP port."
		)
	if button_host != null:
		button_host.text = "Host Online" if internet else "Host Direct"
	if button_join != null:
		button_join.text = "Join by Code" if internet else "Join Direct"


func _store_online_destination() -> void:
	if edit_address == null:
		return
	if _online_connection_mode == ONLINE_CONNECTION_INTERNET:
		SettingsManager.online_invite_code = edit_address.text.strip_edges()
	else:
		SettingsManager.online_address = edit_address.text.strip_edges()


func _apply_online_profile_to_manager(net: Node) -> void:
	var name_value: String = edit_name.text.strip_edges()
	if not name_value.is_empty():
		net.set("player_name", name_value)
		SettingsManager.online_player_name = name_value
	var name_color: Color = Color(1, 1, 1, 1)
	if color_name != null:
		name_color = color_name.color
	net.set("player_color", name_color)
	SettingsManager.online_name_color = name_color
	net.set("player_primary_color", SettingsManager.character_primary_color)
	net.set("player_secondary_color", SettingsManager.character_secondary_color)
	net.set("player_trail_color", SettingsManager.character_trail_color)


func _on_CheckUseCharacterColors_toggled(pressed: bool) -> void:
	SettingsManager.set_use_character_colors(pressed)
	SettingsManager.save_now()
	_refresh_character_colors_now()


func _on_ColorPrimary_color_changed(color: Color) -> void:
	SettingsManager.set_character_primary_color(color)
	SettingsManager.save_now()
	_refresh_character_colors_now()


func _on_ColorSecondary_color_changed(color: Color) -> void:
	SettingsManager.set_character_secondary_color(color)
	SettingsManager.save_now()
	_refresh_character_colors_now()


func _on_ColorTrail_color_changed(color: Color) -> void:
	SettingsManager.set_character_trail_color(color)
	SettingsManager.save_now()
	_refresh_character_colors_now()


func _on_ColorName_color_changed(color: Color) -> void:
	SettingsManager.online_name_color = color
	SettingsManager.save_now()
	_refresh_character_colors_now()


func _sync_online_character_settings_from_ui() -> void:
	if color_name != null:
		SettingsManager.online_name_color = color_name.color
	if chk_use_character_colors != null:
		SettingsManager.set_use_character_colors(chk_use_character_colors.button_pressed)
	if color_primary != null:
		SettingsManager.set_character_primary_color(color_primary.color)
	if color_secondary != null:
		SettingsManager.set_character_secondary_color(color_secondary.color)
	if color_trail != null:
		SettingsManager.set_character_trail_color(color_trail.color)


func _refresh_character_colors_now() -> void:
	_update_music_track_display_colors()
	if get_tree() == null:
		return
	var ns_nodes = get_tree().get_nodes_in_group(&"NetworkSession")
	if ns_nodes.is_empty():
		return
	var ns = ns_nodes[0]
	if ns == null:
		return
	if ns.has_method("refresh_local_character_colors"):
		ns.call("refresh_local_character_colors")
	elif ns.has_method("refresh_local_colors_if_offline"):
		ns.call("refresh_local_colors_if_offline")


func _update_music_track_display_colors() -> void:
	if music_track_display == null:
		return
	music_track_display.set_character_colors(
		SettingsManager.character_primary_color,
		SettingsManager.character_secondary_color
	)


func _change_scene_ref(scene_ref: String) -> void:
	if _data_folder_missing:
		return
	# Supports both `res://...` paths and `uid://...` scene references.
	var packed = load(scene_ref)
	if packed is PackedScene:
		get_tree().change_scene_to_packed(packed)
	else:
		get_tree().change_scene_to_file(scene_ref)


# =========================================
# LEVEL SELECT
# =========================================
func _build_level_list_after_packs() -> void:
	var pack_manager: Node = _get_content_pack_manager()
	if pack_manager == null:
		_pack_wait_attempts += 1
		if _pack_wait_attempts >= 300:
			print("MainMenu: ContentPackManager missing, building list anyway.")
			_build_character_list()
			_build_level_list()
			return
		if _pack_wait_attempts == 1 or _pack_wait_attempts == 60 or _pack_wait_attempts == 120 or _pack_wait_attempts == 240:
			print("MainMenu: waiting for ContentPackManager (%d)" % _pack_wait_attempts)
		call_deferred("_build_level_list_after_packs")
		return
	if pack_manager.has_method("are_packs_loaded"):
		var loaded = pack_manager.call("are_packs_loaded")
		if loaded is bool and bool(loaded):
			print("MainMenu: packs_loaded=true, building list.")
			_build_character_list()
			_build_level_list()
			return
	if not _level_list_waiting_for_packs:
		_level_list_waiting_for_packs = true
		if pack_manager.has_signal("packs_loaded"):
			if not pack_manager.packs_loaded.is_connected(_on_packs_loaded):
				pack_manager.packs_loaded.connect(_on_packs_loaded)
		else:
			_pack_wait_attempts += 1
			if _pack_wait_attempts >= 300:
				print("MainMenu: packs_loaded signal missing, building list anyway.")
				_build_character_list()
				_build_level_list()
				return
			if _pack_wait_attempts == 1 or _pack_wait_attempts == 60 or _pack_wait_attempts == 120 or _pack_wait_attempts == 240:
				print("MainMenu: waiting for packs_loaded signal (%d)" % _pack_wait_attempts)
			call_deferred("_build_level_list_after_packs")


func _on_packs_loaded() -> void:
	_level_list_waiting_for_packs = false
	print("MainMenu: packs_loaded signal received, building list.")
	_build_character_list()
	_build_level_list()


func _build_character_list() -> void:
	if character_list == null:
		return
	_character_entries = CharacterCatalog.load_character_entries(character_data_dir)
	print("MainMenu: character_entries=%d" % _character_entries.size())
	if _character_entries.is_empty():
		print("MainMenu: no character entries found.")
	var buddy_marker_id: String = SettingsManager.chosen_buddy_character_id if SettingsManager.buddy_active else ""
	MenuSelectList.populate(
		character_list,
		_character_entries,
		SettingsManager.chosen_character_id,
		Callable(self, "_on_character_button_pressed"),
		&"MenuButtons",
		Callable(self, "_on_character_button_right_pressed"),
		buddy_marker_id,
		"Buddy",
		Callable(self, "_on_character_settings_pressed"),
		CHARACTER_SETTINGS_ICON
	)
	call_deferred("_focus_visible_panel")


func _play_character_ui_voice(voice_class: StringName) -> bool:
	if character_ui_voice_player == null:
		return false
	var character_id: String = SettingsManager.chosen_character_id.strip_edges()
	var entry: Dictionary = CharacterCatalog.get_selected_or_default_entry(character_data_dir, character_id)
	var profile: CharacterUIVoiceProfile = entry.get("ui_voice_profile") as CharacterUIVoiceProfile
	if profile == null:
		return false
	var resolved_character_id: String = String(entry.get("id", character_id))
	return character_ui_voice_player.play_voice_class(profile, resolved_character_id, voice_class)


func _build_level_list() -> void:
	_level_entries = LevelCatalog.load_level_entries(level_data_dir)
	print("MainMenu: level_entries=%d" % _level_entries.size())
	if _level_entries.is_empty():
		print("MainMenu: no level entries found.")
	MenuSelectList.populate(level_list, _level_entries, "", Callable(self, "_on_level_entry_pressed"))
	call_deferred("_focus_visible_panel")


func _on_level_entry_pressed(entry: Dictionary) -> void:
	if not entry.has("name") or not entry.has("scene"):
		return
	var name: String = str(entry["name"])
	var scene_path: String = str(entry["scene"])
	var level_scene_path: String = ""
	if entry.has("level_scene"):
		level_scene_path = str(entry["level_scene"])
	_on_level_button_pressed(name, scene_path, level_scene_path)


func _clear_level_list() -> void:
	MenuSelectList.clear(level_list)


func _get_test_level_entry() -> Dictionary:
	if _level_entries.is_empty():
		_level_entries = LevelCatalog.load_level_entries(level_data_dir)
	for entry in _level_entries:
		if entry is Dictionary:
			if entry.has("is_test") and bool(entry["is_test"]):
				return entry
	return {}


func _start_test_level_from_menu() -> void:
	if _loading_started or _data_folder_missing:
		return
	var test_entry: Dictionary = _get_test_level_entry()
	var scene_path: String = test_level_scene
	var level_scene_path: String = ""
	var level_name: String = "Test Level"
	if not test_entry.is_empty():
		scene_path = String(test_entry.get("scene", scene_path))
		level_scene_path = String(test_entry.get("level_scene", ""))
		level_name = String(test_entry.get("name", level_name))
	if scene_path.strip_edges() == "":
		push_warning("Test level scene not set on MainMenu.")
		return
	_play_click()
	if level_scene_path.strip_edges() != "":
		_set_pending_level_scene(level_scene_path)
	var net = get_node_or_null("/root/NetworkManager")
	if net != null:
		net.call("leave")
	_change_scene_with_loading(scene_path, level_name, level_scene_path)


func _request_test_level_skip() -> void:
	if _loading_started:
		return
	_test_level_skip_requested = true
	_start_requested_test_level_skip()


func _start_requested_test_level_skip() -> void:
	if not _test_level_skip_requested or not _startup_data_check_complete:
		return
	if _data_folder_missing:
		_test_level_skip_requested = false
		return
	_test_level_skip_requested = false
	_title_active = false
	_title_departing = false
	title_backdrop.cancel_title()
	menu_overlay.hide()
	if sfx_title_swoopin.playing:
		sfx_title_swoopin.stop()
	if sfx_title_start.playing:
		sfx_title_start.stop()
	_start_test_level_from_menu()


func _show_loading_screen(level_name: String) -> LoadingScreen:
	if LOADING_SCREEN_SCENE == null:
		return null
	var screen: LoadingScreen = LOADING_SCREEN_SCENE.instantiate() as LoadingScreen
	if screen == null:
		return null
	if get_tree() != null:
		get_tree().root.add_child(screen)
	screen.set_level_name(level_name)
	return screen


func _change_scene_with_loading(scene_ref: String, level_name: String, level_scene_ref: String = "") -> void:
	if _data_folder_missing:
		return
	if scene_ref.strip_edges() == "":
		return
	if _loading_started:
		return
	_loading_started = true
	_play_character_ui_voice(&"loading")
	var screen: LoadingScreen = _show_loading_screen(level_name)
	if screen != null:
		screen.intro_finished.connect(_clear_menu_for_loading, CONNECT_ONE_SHOT)
		var audio_manifest: AudioPreparationManifest = null
		if LevelPreparationManager.is_cache_enabled():
			audio_manifest = _build_audio_preparation_manifest(level_scene_ref)
		screen.start_loading(
			scene_ref,
			LOADING_MIN_VISIBLE_TIME,
			LOADING_PRELOAD_DELAY,
			level_scene_ref,
			audio_manifest
		)
	else:
		_change_scene_ref(scene_ref)


func _build_audio_preparation_manifest(level_scene_ref: String) -> AudioPreparationManifest:
	var manifest: AudioPreparationManifest = AudioPreparationManifest.new()
	_append_character_audio_root(manifest, SettingsManager.chosen_character_id)
	if SettingsManager.buddy_active:
		_append_character_audio_root(manifest, SettingsManager.chosen_buddy_character_id)
	var normalized_level_ref: String = level_scene_ref.strip_edges()
	if normalized_level_ref != "":
		manifest.level_roots.append(normalized_level_ref)
	return manifest


func _append_character_audio_root(manifest: AudioPreparationManifest, character_id: String) -> void:
	var entries: Array = _character_entries
	if entries.is_empty():
		entries = CharacterCatalog.load_character_entries(character_data_dir)
	var selected_entry: Dictionary = {}
	for entry_value: Variant in entries:
		if not (entry_value is Dictionary):
			continue
		var entry: Dictionary = entry_value
		if String(entry.get("id", "")).nocasecmp_to(character_id) == 0:
			selected_entry = entry
			break
	if selected_entry.is_empty() and not entries.is_empty():
		var first_entry_value: Variant = entries[0]
		if first_entry_value is Dictionary:
			selected_entry = first_entry_value
	var character_scene_ref: String = String(selected_entry.get("scene", "")).strip_edges()
	if character_scene_ref != "" and not manifest.character_roots.has(character_scene_ref):
		manifest.character_roots.append(character_scene_ref)


func play_main_menu_music(stream_override: AudioStream = null) -> void:
	var music_stream: AudioStream = stream_override if stream_override != null else main_menu_music
	if music_stream == null:
		return
	if _menu_music_controller == null or not is_instance_valid(_menu_music_controller):
		_menu_music_controller = MusicController.new()
		_menu_music_controller.name = "MainMenuMusicController"
		_menu_music_controller.autoplay = false
		add_child(_menu_music_controller)
	_menu_music_controller.play_music_override(music_stream, main_menu_music_fade_in, main_menu_music_fade_out, false)


func _clear_menu_for_loading() -> void:
	set_process(false)
	set_process_input(false)
	set_process_unhandled_input(false)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var focus_owner: Control = get_viewport().gui_get_focus_owner()
	if focus_owner != null:
		focus_owner.release_focus()
	for child in get_children():
		if child == _menu_music_controller:
			continue
		if child == character_ui_voice_player:
			continue
		if _is_loading_exposed_node(child):
			continue
		child.queue_free()


func _is_loading_exposed_node(candidate: Node) -> bool:
	if candidate == null or not is_instance_valid(candidate):
		return false
	for exposed in loading_exposed_nodes:
		if exposed == null or not is_instance_valid(exposed):
			continue
		if exposed == candidate:
			return true
		if candidate.is_ancestor_of(exposed):
			return true
	return false


func _unhandled_input(event: InputEvent) -> void:
	if _title_active or (_exit_dialog and _exit_dialog.visible):
		return
	if _loading_started:
		return
	if _startup_data_check_complete and _data_folder_missing:
		get_viewport().set_input_as_handled()
		return
	if graphics_confirm_dialog.visible:
		if event.is_action_pressed("ui_cancel"):
			_on_graphics_settings_reverted()
			get_viewport().set_input_as_handled()
		return
	if unsaved_graphics_dialog.visible:
		if event.is_action_pressed("ui_cancel"):
			_on_unsaved_graphics_go_back_pressed()
			get_viewport().set_input_as_handled()
		return
	if reset_defaults_dialog.visible:
		if event.is_action_pressed("ui_cancel"):
			_on_reset_defaults_canceled()
			get_viewport().set_input_as_handled()
		return
	if _character_settings_menu != null and is_instance_valid(_character_settings_menu):
		return
	if _is_input_binding_active():
		return
	if event.is_action_pressed("ui_cancel"):
		if panel_options.visible:
			_on_ButtonOptionsBack_pressed()
		elif panel_character.visible:
			_on_ButtonCharacterBack_pressed()
		elif panel_level.visible:
			_on_ButtonLevelBack_pressed()
		elif panel_online.visible:
			_on_ButtonOnlineBack_pressed()
		elif panel_credits.visible:
			_on_ButtonCreditsBack_pressed()
		elif panel_main.visible and not _data_folder_missing:
			show_title_screen()
		else:
			return
		get_viewport().set_input_as_handled()
		return
	if event.is_action_pressed("respawn"):
		if _is_main_menu_screen():
			_start_test_level_from_menu()
			get_viewport().set_input_as_handled()


func _process(delta: float) -> void:
	if _title_active or (_exit_dialog and _exit_dialog.visible):
		return
	if missing_data_background.visible:
		_update_missing_data_background(delta)
	if graphics_confirm_dialog.visible:
		_update_graphics_confirmation(delta)
		return
	if unsaved_graphics_dialog.visible:
		return
	if _loading_started:
		return
	if reset_defaults_dialog.visible:
		return
	if _character_settings_menu != null and is_instance_valid(_character_settings_menu):
		return
	if _is_input_binding_active():
		return
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


func _input(event: InputEvent) -> void:
	if event is InputEventKey:
		var debug_key_event: InputEventKey = event as InputEventKey
		if debug_key_event.pressed and not debug_key_event.echo \
				and (debug_key_event.keycode == Key.KEY_KP_PERIOD or debug_key_event.physical_keycode == Key.KEY_KP_PERIOD):
			_activate_missing_data_lockout()
			get_viewport().set_input_as_handled()
			return
	if _startup_data_check_complete and _data_folder_missing:
		if event is InputEventKey:
			var blocked_key_event: InputEventKey = event as InputEventKey
			if blocked_key_event.pressed and not blocked_key_event.echo \
					and (blocked_key_event.keycode == KEY_F1 or blocked_key_event.physical_keycode == KEY_F1):
				get_viewport().set_input_as_handled()
		return
	if event is InputEventKey:
		var key_event: InputEventKey = event as InputEventKey
		if key_event.pressed and not key_event.echo \
				and (key_event.keycode == KEY_F1 or key_event.physical_keycode == KEY_F1):
			_request_test_level_skip()
			get_viewport().set_input_as_handled()
			return
	if _title_departing:
		get_viewport().set_input_as_handled()
		return
	if _exit_dialog and _exit_dialog.visible:
		if event.is_action_pressed("ui_cancel"):
			_cancel_exit()
			get_viewport().set_input_as_handled()
		return
	if _title_active:
		if event.is_pressed() and not event.is_echo():
			if event.is_action_pressed("ui_cancel"):
				_show_exit_confirmation()
			elif allow_title_sequence_skip and not title_backdrop.ready_for_input:
				title_backdrop.skip_entrance()
			elif title_backdrop.ready_for_input and (event is InputEventKey or event is InputEventJoypadButton or event is InputEventMouseButton or event is InputEventScreenTouch):
				_enter_main_menu()
		get_viewport().set_input_as_handled()
		return
	if _loading_started:
		get_viewport().set_input_as_handled()
		return
	if graphics_confirm_dialog.visible:
		return
	if unsaved_graphics_dialog.visible:
		return
	if reset_defaults_dialog.visible:
		return
	if _character_settings_menu != null and is_instance_valid(_character_settings_menu):
		return
	if _is_input_binding_active():
		return
	if _menu_transition_active:
		if event is InputEventKey or event is InputEventJoypadButton or event is InputEventMouseButton:
			get_viewport().set_input_as_handled()
		return
	if _handle_options_tab_input(event):
		get_viewport().set_input_as_handled()
		return
	if _is_confirm_press_event(event):
		_suppress_hover_after_press()


func _is_confirm_press_event(event: InputEvent) -> bool:
	# SUMMARY: Identify confirm presses that should suppress hover SFX.
	if event is InputEventMouseButton:
		var mouse_event: InputEventMouseButton = event
		if mouse_event.pressed and mouse_event.button_index == MouseButton.MOUSE_BUTTON_LEFT:
			return true
	if event is InputEventKey:
		var key_event: InputEventKey = event
		if key_event.pressed and not key_event.echo:
			if key_event.is_action_pressed("ui_accept") or key_event.is_action_pressed("ui_select"):
				return true
	if event is InputEventJoypadButton:
		var joy_event: InputEventJoypadButton = event
		if joy_event.pressed:
			if joy_event.is_action_pressed("ui_accept") or joy_event.is_action_pressed("ui_select"):
				return true
	return false


func _is_input_binding_active() -> bool:
	var tree: SceneTree = get_tree()
	if tree == null:
		return false
	return bool(tree.get_meta("input_binding_active", false))


func _get_active_scroll_container() -> ScrollContainer:
	var root: Node = null
	if panel_options.visible:
		if tabs_options != null and tabs_options.current_tab >= 0:
			root = tabs_options.get_tab_control(tabs_options.current_tab)
		if root == null:
			root = panel_options
	elif panel_character.visible:
		root = panel_character
	elif panel_level.visible:
		root = panel_level
	elif panel_online.visible:
		root = panel_online
	elif panel_credits.visible:
		root = panel_credits
	else:
		root = panel_main
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


func _is_main_menu_screen() -> bool:
	if not panel_main.visible:
		return false
	if panel_character.visible or panel_level.visible or panel_online.visible or panel_options.visible or panel_credits.visible:
		return false
	return true


func _set_pending_level_scene(scene_path: String) -> void:
	if get_tree() == null:
		return
	if scene_path.strip_edges() == "":
		return
	get_tree().set_meta("pending_level_scene", scene_path)


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


func _focus_visible_panel() -> void:
	if _title_active or (_exit_dialog and _exit_dialog.visible):
		return
	if graphics_confirm_dialog.visible:
		button_confirm_graphics.grab_focus()
		return
	if unsaved_graphics_dialog.visible:
		button_save_unsaved_graphics.grab_focus()
		return
	if missing_data_warning.visible:
		button_dismiss_missing_data.grab_focus()
		return
	if panel_main.visible:
		_focus_first_focusable_control(panel_main)
		return
	if panel_character.visible:
		if not _focus_first_focusable_control(character_list):
			_focus_first_focusable_control(panel_character)
		return
	if panel_level.visible:
		if not _focus_first_focusable_control(level_list):
			_focus_first_focusable_control(panel_level)
		return
	if panel_online.visible:
		var online_root: Node = get_node_or_null("Overlay/OnlinePanel/Panel/VBoxOnline/HBoxButtons")
		if not _focus_first_focusable_control(online_root):
			_focus_first_focusable_control(panel_online)
		return
	if panel_options.visible:
		var current_tab: Control = null
		if tabs_options != null and tabs_options.current_tab >= 0:
			current_tab = tabs_options.get_tab_control(tabs_options.current_tab)
		if current_tab != null and _focus_first_focusable_control(current_tab):
			return
		_focus_first_focusable_control(panel_options)
		return
	if panel_credits.visible:
		_focus_first_focusable_control(panel_credits)


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


func _is_text_input_focused() -> bool:
	var vp = get_viewport()
	if vp == null:
		return false
	var focus = vp.gui_get_focus_owner()
	return focus is LineEdit or focus is TextEdit


# =========================================
# OPTIONS UI ↔ SETTINGS
# =========================================
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
	# Display
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

	# Graphics
	chk_ssr.button_pressed     = SettingsManager.ssr
	chk_ssao.button_pressed    = SettingsManager.ssao
	chk_ssil.button_pressed    = SettingsManager.ssil
	chk_sdfgi.button_pressed   = SettingsManager.sdfgi
	chk_shadows.button_pressed = SettingsManager.shadows
	chk_glow.button_pressed    = SettingsManager.glow
	chk_depth_of_field.button_pressed = SettingsManager.depth_of_field_enabled
	chk_water_displacement.button_pressed = SettingsManager.water_displacement_enabled
	chk_water_refraction.button_pressed = SettingsManager.water_refraction_enabled
	chk_water_normals.button_pressed = SettingsManager.water_normal_maps_enabled
	chk_water_depth_fx.button_pressed = SettingsManager.water_depth_effects_enabled
	var lod_index: int = opt_lod_distance.get_item_index(SettingsManager.lod_distance_quality)
	if lod_index >= 0:
		opt_lod_distance.selected = lod_index

	# Audio sliders (percent)
	slider_master.value = SettingsManager.get_master_volume_percent()
	slider_music.value  = SettingsManager.get_music_volume_percent()
	slider_sfx.value    = SettingsManager.get_sfx_volume_percent()
	slider_ui.value     = SettingsManager.get_ui_volume_percent()
	slider_voice.value  = SettingsManager.get_voice_volume_percent()
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


# --- Toggle callbacks (hook via editor) ---
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

# --- Audio slider callbacks (hook via editor) ---
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
	_add_row.call("Auto Follow Max Deviation", slider_auto_follow_max_deviation, "HBoxAutoFollowMaxDeviation")

	chk_auto_follow_vertical_enabled = CheckBox.new()
	chk_auto_follow_vertical_enabled.button_pressed = SettingsManager.camera_auto_follow_vertical_enabled
	chk_auto_follow_vertical_enabled.toggled.connect(_on_CheckAutoFollowVerticalEnabled_toggled)
	_add_row.call("Auto Follow Vertical", chk_auto_follow_vertical_enabled, "HBoxAutoFollowVerticalEnabled")

	slider_auto_follow_vertical_max_tilt = HSlider.new()
	slider_auto_follow_vertical_max_tilt.min_value = 0.0
	slider_auto_follow_vertical_max_tilt.max_value = 45.0
	slider_auto_follow_vertical_max_tilt.step = 1.0
	slider_auto_follow_vertical_max_tilt.value = SettingsManager.camera_auto_follow_vertical_max_tilt
	slider_auto_follow_vertical_max_tilt.value_changed.connect(_on_SliderAutoFollowVerticalMaxTilt_value_changed)
	_add_row.call("Auto Follow Vertical Strength", slider_auto_follow_vertical_max_tilt, "HBoxAutoFollowVerticalMaxTilt")

	slider_auto_follow_level_pitch = HSlider.new()
	slider_auto_follow_level_pitch.min_value = -45.0
	slider_auto_follow_level_pitch.max_value = 45.0
	slider_auto_follow_level_pitch.step = 1.0
	slider_auto_follow_level_pitch.value = SettingsManager.camera_auto_follow_level_pitch_deg
	slider_auto_follow_level_pitch.value_changed.connect(_on_SliderAutoFollowLevelPitch_value_changed)
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
	if _deadzone_visual != null:
		_deadzone_visual.visible = true
		_deadzone_visual.set_deadzone(slider_auto_follow_deadzone.value)
		_deadzone_visual.set_max_deviation(slider_auto_follow_max_deviation.value)


func _on_DeadzoneSlider_focus_exited() -> void:
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
	_refresh_character_colors_now()


# =========================================
# BUTTON SFX
# =========================================
func _on_any_button_mouse_entered() -> void:
	_play_hover()

func _on_any_button_focus_entered() -> void:
	_play_hover()

func _on_any_button_button_down() -> void:
	_suppress_hover_after_press()
	_play_press()

func _on_any_button_pressed() -> void:
	_suppress_hover_after_press()
	_play_click()

func _play_hover() -> void:
	if _is_confirm_input_active():
		return
	if _is_hover_suppressed():
		return
	if sfx_hover == null or not sfx_hover.stream:
		return
	if not sfx_hover.is_inside_tree():
		return
	sfx_hover.play()

func _play_click() -> void:
	if sfx_click == null or not sfx_click.stream:
		return
	if not sfx_click.is_inside_tree():
		return
	if release_cancels_press_sound and sfx_press != null and sfx_press.playing:
		sfx_press.stop()
	sfx_click.play()

func _play_warning() -> void:
	if sfx_warning == null or not sfx_warning.stream:
		return
	if not sfx_warning.is_inside_tree():
		return
	sfx_warning.play()

func _play_press() -> void:
	# SUMMARY: Play the UI press sound (button down).
	if sfx_press == null or not sfx_press.stream:
		return
	if not sfx_press.is_inside_tree():
		return
	sfx_press.play()


func _suppress_hover_after_press() -> void:
	# SUMMARY: Prevent hover SFX from replaying on the same confirm action.
	var window_s: float = max(hover_suppress_after_press_time, 0.0)
	if window_s <= 0.0:
		return
	var now_ms: int = Time.get_ticks_msec()
	_hover_suppress_until_ms = now_ms + int(window_s * 1000.0)


func _is_hover_suppressed() -> bool:
	if _hover_suppress_until_ms <= 0:
		return false
	return Time.get_ticks_msec() <= _hover_suppress_until_ms


func _is_confirm_input_active() -> bool:
	# SUMMARY: Skip hover while a confirm/press input is held.
	if Input.is_mouse_button_pressed(MouseButton.MOUSE_BUTTON_LEFT):
		return true
	if Input.is_mouse_button_pressed(MouseButton.MOUSE_BUTTON_RIGHT):
		return true
	if Input.is_mouse_button_pressed(MouseButton.MOUSE_BUTTON_MIDDLE):
		return true
	if Input.is_action_pressed("ui_accept"):
		return true
	if Input.is_action_pressed("ui_select"):
		return true
	return false


func _ensure_content_pack_manager() -> void:
	if get_tree() == null:
		return
	var existing = get_tree().get_nodes_in_group("ContentPackManager")
	if existing != null and existing.size() > 0:
		return
	var mgr := ContentPackManager.new()
	mgr.name = "ContentPackManager"
	get_tree().root.call_deferred("add_child", mgr)
	mgr.call_deferred("load_all_packs")


func _get_content_pack_manager() -> Node:
	if get_tree() == null:
		return null
	var list = get_tree().get_nodes_in_group("ContentPackManager")
	if list != null and list.size() > 0:
		return list[0]
	return get_tree().root.find_child("ContentPackManager", true, false)


## Returns to title; explicit transitions can request a black fade.
func show_title_screen(fade_from_black: bool = false) -> void:
	_title_departing = false
	_title_active = true
	_startup_title_shown = true
	menu_overlay.hide()
	var focus_owner: Control = get_viewport().gui_get_focus_owner()
	if focus_owner:
		focus_owner.release_focus()
	title_backdrop.show()
	title_backdrop.show_title(fade_from_black)

func _play_title_music() -> void:
	sfx_title_swoopin.play()
	play_main_menu_music(title_music)
	if _menu_music_controller:
		title_backdrop.playback_position = Callable(_menu_music_controller, "get_current_playback_position")
		title_backdrop.music_bpm = float(_menu_music_controller.get_current_track_information().get("bpm", 0.0))

func _enter_main_menu() -> void:
	if _title_departing or not title_backdrop.ready_for_input:
		return
	_title_departing = true
	sfx_title_start.play()
	title_backdrop.dismiss_title()

func _finish_title_departure() -> void:
	_title_departing = false
	_title_active = false
	for panel in _menu_panels:
		panel.hide()
	_active_panel = null
	menu_overlay.show()
	_show_main_menu()
	if main_menu_music:
		play_main_menu_music()
		title_backdrop.music_bpm = float(_menu_music_controller.get_current_track_information().get("bpm", 0.0))

func _show_exit_confirmation() -> void:
	_exit_dialog.show()
	_play_warning()
	_play_character_ui_voice(&"confirm_exit")
	_button_exit.grab_focus()

func _cancel_exit() -> void:
	_exit_dialog.hide()
	var focus_owner: Control = get_viewport().gui_get_focus_owner()
	if focus_owner:
		focus_owner.release_focus()
	if not _title_active:
		call_deferred("_focus_visible_panel")


func _on_CheckRememberEmotePage_toggled(pressed: bool) -> void:
	SettingsManager.set_remember_emote_page(pressed)
	SettingsManager.save_now()
