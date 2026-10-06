extends CanvasLayer

## Displays the score name and value in the top-left HUD stack.
@onready var stat_score: HUDStatContainer = get_node_or_null("HUDRoot/TopLeftPanel/StatsVBox/ScoreStat") as HUDStatContainer
## Displays the elapsed time name and value in the top-left HUD stack.
@onready var stat_time: HUDStatContainer = get_node_or_null("HUDRoot/TopLeftPanel/StatsVBox/TimeStat") as HUDStatContainer
## Displays the ring count name and value in the top-left HUD stack.
@onready var stat_rings: HUDStatContainer = get_node_or_null("HUDRoot/TopLeftPanel/StatsVBox/RingsStat") as HUDStatContainer
## Displays the selected character portrait in the bottom-left HUD stack.
@onready var texture_icon: TextureRect = get_node_or_null("HUDRoot/BottomLeftSafeArea/CharacterIcon")
## Displays and animates the active camera orientation mode beside the stat stack.
@onready var camera_orientation_indicator: Control = get_node_or_null("HUDRoot/CameraOrientationIndicator")
## Displays character-specific ability values at the bottom center of the HUD.
@onready var ability_meter: HUDAbilityMeter = get_node_or_null("HUDRoot/AbilityMeter") as HUDAbilityMeter
## Displays coyote jump availability below the camera orientation mode.
@onready var coyote_indicator: TextureRect = get_node_or_null("HUDRoot/CoyoteJumpIndicator") as TextureRect
## Draws speed and Barrier Blast progress in the bottom-right HUD.
@onready var speedometer: Control = get_node_or_null("HUDRoot/Speedometer")
## Displays transient item notifications and the timed power-up queue.
@onready var item_notifier: HUDItemNotifier = get_node_or_null("HUDRoot/ItemNotifier") as HUDItemNotifier
## Displays current music information in the top-right corner.
@onready var music_track_display: HUDMusicTrackDisplay = get_node_or_null("HUDRoot/MusicTrackDisplay") as HUDMusicTrackDisplay
## Colors scanlines on framed HUD backgrounds.
@onready var crt_background_effect: CRTUIBackgroundEffect = get_node_or_null("CRTUIBackgroundEffect") as CRTUIBackgroundEffect
## Displays input glyphs and gestures for the local player's available actions.
@onready var action_prompts: HUDActionPrompts = get_node_or_null("HUDRoot/ActionPrompts") as HUDActionPrompts
## Displays urgent ability glyphs above the speedometer.
@onready var contextual_prompts: HUDContextualPrompts = get_node_or_null("HUDRoot/ContextualPrompts") as HUDContextualPrompts

var elapsed_time: float = 0.0
var running: bool = true

func _ready() -> void:
	visible = SettingsManager.hud_visible


func _ensure_nodes() -> void:
	if stat_score == null:
		stat_score = get_node_or_null("HUDRoot/TopLeftPanel/StatsVBox/ScoreStat") as HUDStatContainer
	if stat_time == null:
		stat_time = get_node_or_null("HUDRoot/TopLeftPanel/StatsVBox/TimeStat") as HUDStatContainer
	if stat_rings == null:
		stat_rings = get_node_or_null("HUDRoot/TopLeftPanel/StatsVBox/RingsStat") as HUDStatContainer
	if texture_icon == null:
		texture_icon = get_node_or_null("HUDRoot/BottomLeftSafeArea/CharacterIcon")
	if camera_orientation_indicator == null:
		camera_orientation_indicator = get_node_or_null("HUDRoot/CameraOrientationIndicator")
	if ability_meter == null:
		ability_meter = get_node_or_null("HUDRoot/AbilityMeter") as HUDAbilityMeter
	if coyote_indicator == null:
		coyote_indicator = get_node_or_null("HUDRoot/CoyoteJumpIndicator") as TextureRect
	if speedometer == null:
		speedometer = get_node_or_null("HUDRoot/Speedometer")
	if item_notifier == null:
		item_notifier = get_node_or_null("HUDRoot/ItemNotifier") as HUDItemNotifier
	if music_track_display == null:
		music_track_display = get_node_or_null("HUDRoot/MusicTrackDisplay") as HUDMusicTrackDisplay
	if crt_background_effect == null:
		crt_background_effect = get_node_or_null("CRTUIBackgroundEffect") as CRTUIBackgroundEffect

func _process(delta: float) -> void:
	if not SettingsManager.hud_visible and visible:
		visible = false
	if running:
		elapsed_time += delta
		_update_time_label()

func set_rings(value: int) -> void:
	if stat_rings == null:
		if not is_node_ready():
			call_deferred("set_rings", value)
			return
		_ensure_nodes()
		if stat_rings == null:
			push_warning("HUD: RingsStat container not found.")
			return
	stat_rings.set_value_text("%03d" % value)
	stat_rings.set_warning_active(value <= 0)

func set_score(value: int) -> void:
	if stat_score == null:
		if not is_node_ready():
			call_deferred("set_score", value)
			return
		_ensure_nodes()
		if stat_score == null:
			push_warning("HUD: ScoreStat container not found.")
			return
	stat_score.set_value_text("%06d" % value)

func set_elapsed_time(seconds: float) -> void:
	elapsed_time = max(seconds, 0.0)
	_update_time_label()

func set_special_gauge(fraction: float) -> void:
	if speedometer == null:
		if not is_node_ready():
			call_deferred("set_special_gauge", fraction)
			return
		_ensure_nodes()
		if speedometer == null:
			push_warning("HUD: Speedometer node not found for Barrier Blast gauge.")
			return
	if speedometer.has_method("set_barrier_blast_fraction"):
		speedometer.call("set_barrier_blast_fraction", fraction)


func set_ability_meter(ability_name: String, current: float, max_value: float, available: bool = true) -> void:
	if ability_meter == null:
		if not is_node_ready():
			call_deferred("set_ability_meter", ability_name, current, max_value, available)
			return
		_ensure_nodes()
		if ability_meter == null:
			if available:
				push_warning("HUD: AbilityMeter node not found.")
			return
	ability_meter.set_meter(ability_name, current, max_value, available)


func set_hud_character_colors(primary_color: Color, secondary_color: Color) -> void:
	if not is_node_ready():
		call_deferred("set_hud_character_colors", primary_color, secondary_color)
		return
	_ensure_nodes()
	if action_prompts:
		action_prompts.set_frame_color(primary_color)
	if stat_score != null:
		stat_score.set_frame_color(primary_color)
	if stat_time != null:
		stat_time.set_frame_color(primary_color)
	if stat_rings != null:
		stat_rings.set_frame_color(primary_color)
	if camera_orientation_indicator != null and camera_orientation_indicator.has_method("set_icon_color"):
		camera_orientation_indicator.call("set_icon_color", primary_color)
	if coyote_indicator != null:
		coyote_indicator.modulate = primary_color
	if ability_meter != null:
		ability_meter.set_frame_color(primary_color)
		ability_meter.set_meter_color(secondary_color)
	if speedometer != null and speedometer.has_method("set_hud_colors"):
		speedometer.call("set_hud_colors", primary_color, secondary_color)
	if item_notifier != null:
		item_notifier.set_hud_colors(primary_color, secondary_color)
	if music_track_display != null:
		music_track_display.set_character_colors(primary_color, secondary_color)
	if crt_background_effect != null:
		crt_background_effect.set_scanline_color(primary_color.lightened(0.2))
	if contextual_prompts:
		contextual_prompts.set_frame_color(primary_color)

func set_action_prompts(prompts: Array[Dictionary], source: Node) -> void:
	if action_prompts:
		action_prompts.set_prompts(prompts, source)
	if contextual_prompts:
		contextual_prompts.set_prompts(prompts, source)


func set_character_icon(texture: Texture2D) -> void:
	if texture_icon == null:
		if not is_node_ready():
			call_deferred("set_character_icon", texture)
			return
		_ensure_nodes()
		if texture_icon == null:
			push_warning("HUD: Icon node not found.")
			return
	texture_icon.texture = texture
	texture_icon.visible = texture != null


func show_item_notification(
	item_id: StringName,
	amount: float = 1.0,
	effect_duration: float = -1.0
	) -> bool:
	if item_notifier == null:
		if not is_node_ready():
			call_deferred("show_item_notification", item_id, amount, effect_duration)
			return true
		_ensure_nodes()
		if item_notifier == null:
			return false
	return item_notifier.enqueue_item(item_id, amount, effect_duration)


func clear_item_notifications() -> void:
	_ensure_nodes()
	if item_notifier != null:
		item_notifier.clear_all_notifications()


func set_camera_orientation_mode(player_up_enabled: bool, animate: bool = true) -> void:
	if camera_orientation_indicator == null:
		if not is_node_ready():
			call_deferred("set_camera_orientation_mode", player_up_enabled, animate)
			return
		_ensure_nodes()
		if camera_orientation_indicator == null:
			push_warning("HUD: CameraOrientationIndicator node not found.")
			return
	if camera_orientation_indicator.has_method("set_player_up_enabled"):
		camera_orientation_indicator.call("set_player_up_enabled", player_up_enabled, animate)

func set_timer_running(value: bool) -> void:
	running = value

func set_coyote_available(available: bool) -> void:
	if coyote_indicator == null:
		if not is_node_ready():
			call_deferred("set_coyote_available", available)
			return
		_ensure_nodes()
		if coyote_indicator == null:
			push_warning("HUD: CoyoteJumpIndicator node not found.")
			return
	coyote_indicator.visible = available

func set_speedometer_value(speed: float, max_speed_value: float, top_speed_value: float, delta: float = 0.0) -> void:
	if speedometer == null:
		if not is_node_ready():
			call_deferred("set_speedometer_value", speed, max_speed_value, top_speed_value, delta)
			return
		_ensure_nodes()
		if speedometer == null:
			push_warning("HUD: Speedometer node not found.")
			return
	if speedometer.has_method("set_speed"):
		speedometer.call("set_speed", speed, max_speed_value, top_speed_value, delta)


func play_landing_roll_speedometer_effect(
	result: StringName,
	strength: float
) -> void:
	if speedometer == null:
		_ensure_nodes()
	if speedometer != null and speedometer.has_method("play_landing_roll_effect"):
		speedometer.call(
			"play_landing_roll_effect",
			result,
			clamp(strength, 0.0, 1.0)
		)

func _update_time_label() -> void:
	if stat_time == null:
		_ensure_nodes()
		if stat_time == null:
			return
	var total_seconds: int = int(elapsed_time)
	var minutes: int = int(total_seconds / 60)
	var seconds: int = total_seconds % 60
	var hundredths: int = int((elapsed_time - total_seconds) * 100.0) % 100
	stat_time.set_value_text("%02d:%02d:%02d" % [minutes, seconds, hundredths])
