class_name PlayerCharacterVisualProfile
extends Resource

@export_group("HUD Palette")
## Primary HUD color used when custom character colors are disabled.
@export var default_primary_color: Color = Color(0.18, 0.52, 1.0, 1.0)
## Secondary HUD color used when custom character colors are disabled.
@export var default_secondary_color: Color = Color(1.0, 1.0, 1.0, 1.0)

@export_group("Trick Presentation")
@export_subgroup("Authored Trick Names")
## Optional Backflip display name. Empty uses the TrickSystem default.
@export var trick_name_backflip: String = ""
## Optional Frontflip display name. Empty uses the TrickSystem default.
@export var trick_name_frontflip: String = ""
## Optional left spin display name. Empty uses the TrickSystem default.
@export var trick_name_left_spin: String = ""
## Optional right spin display name. Empty uses the TrickSystem default.
@export var trick_name_right_spin: String = ""
## Optional front-left diagonal trick display name. Empty uses the TrickSystem default.
@export var trick_name_frontflip_left_spin: String = ""
## Optional back-left diagonal trick display name. Empty uses the TrickSystem default.
@export var trick_name_backflip_left_spin: String = ""
## Optional back-right diagonal trick display name. Empty uses the TrickSystem default.
@export var trick_name_backflip_right_spin: String = ""
## Optional front-right diagonal trick display name. Empty uses the TrickSystem default.
@export var trick_name_frontflip_right_spin: String = ""
## Optional forward rail trick display name. Empty uses the TrickSystem default.
@export var trick_name_rail_forward: String = ""
## Optional backward rail trick display name. Empty uses the TrickSystem default.
@export var trick_name_rail_backward: String = ""
## Optional crouched forward rail trick display name. Empty uses the TrickSystem default.
@export var trick_name_rail_forward_crouch: String = ""
## Optional crouched backward rail trick display name. Empty uses the TrickSystem default.
@export var trick_name_rail_backward_crouch: String = ""
## Optional fast crouched forward rail trick display name. Empty uses the TrickSystem default.
@export var trick_name_rail_forward_crouch_fast: String = ""
## Optional fast crouched backward rail trick display name. Empty uses the TrickSystem default.
@export var trick_name_rail_backward_crouch_fast: String = ""
## Optional pogo trick display name. Empty uses the TrickSystem default.
@export var trick_name_bounce_pogo: String = ""
## Optional stomp trick display name. Empty uses the TrickSystem default.
@export var trick_name_stomp_darehog: String = ""

@export_subgroup("Feat Names")
## Optional Spring Launch display name. Empty uses the feat default.
@export var feat_name_spring_launch: String = ""
## Optional Bumper Bounce display name. Empty uses the feat default.
@export var feat_name_bumper_bounce: String = ""
## Optional Dash Panel display name. Empty uses the feat default.
@export var feat_name_dash_panel: String = ""
## Optional Badnik Defeated display name. Empty uses the feat default.
@export var feat_name_badnik_defeat: String = ""
## Optional Drift display name. Empty uses the feat default.
@export var feat_name_drift: String = ""
## Optional Ledge Mantle display name. Empty uses the feat default.
@export var feat_name_ledge_mantle: String = ""
## Optional Landing Roll display name. Empty uses the feat default.
@export var feat_name_landing_roll: String = ""
## Optional Rejected Landing Roll display name. Empty uses the feat default.
@export var feat_name_rejected_landing_roll: String = ""
## Optional Rough Landing display name. Empty uses the feat default.
@export var feat_name_rough_landing: String = ""
## Optional Wall Carve display name. Empty uses the feat default.
@export var feat_name_wall_carve: String = ""
## Optional Wall Cling display name. Empty uses the feat default.
@export var feat_name_wall_cling: String = ""
## Optional Wall Run Kick display name. Empty uses the feat default.
@export var feat_name_wall_run_kick: String = ""
## Optional Wall Kick display name. Empty uses the feat default.
@export var feat_name_wall_kick: String = ""
## Optional Object Pickup display name. Empty uses the feat default.
@export var feat_name_object_pickup: String = ""
## Optional Object Placed display name. Empty uses the feat default.
@export var feat_name_object_placed: String = ""
## Optional Object Throw display name. Empty uses the feat default.
@export var feat_name_object_throw: String = ""
## Optional Vault Bar display name. Empty uses the feat default.
@export var feat_name_vault_bar: String = ""
## Optional Rail Grind display name. Empty uses the feat default.
@export var feat_name_rail_grind: String = ""
## Optional Skydive display name. Empty uses the feat default.
@export var feat_name_skydive: String = ""

@export_group("Combo Ratings")
## Minimum combo scores for each rating tier, ordered from lowest to highest.
@export var combo_rating_score_thresholds: PackedFloat32Array = PackedFloat32Array([
	1.0, 400.0, 800.0, 1600.0, 2400.0, 4000.0, 8000.0, 12000.0, 25000.0, 50000.0
])
## Rating text corresponding to each score threshold.
@export var combo_rating_flavour_texts: PackedStringArray = PackedStringArray([
	"Good!", "Great!", "Nice!", "Jammin'!", "Cool!", "Radical!", "Tight!", "Awesome!", "Extreme!", "Perfect!"
])
## Rating colors corresponding to each score threshold. Scores blend between adjacent colors.
@export var combo_rating_colors: PackedColorArray = PackedColorArray([
	Color(0.08, 0.66, 1.0, 1.0),
	Color(0.0, 0.9, 0.86, 1.0),
	Color(0.2, 1.0, 0.38, 1.0),
	Color(0.94, 1.0, 0.2, 1.0),
	Color(1.0, 0.78, 0.08, 1.0),
	Color(1.0, 0.48, 0.08, 1.0),
	Color(1.0, 0.25, 0.08, 1.0),
	Color(1.0, 0.12, 0.42, 1.0),
	Color(1.0, 0.08, 0.9, 1.0),
	Color(1.0, 0.08, 0.9, 1.0)
])

@export_group("Tint")
## Enables visual tinting for this character.
@export var tint_enabled: bool = true
## Per-material character colour assignments.
@export var color_materials: Array[CharacterColorMaterialEntry] = []
## Hue used when the selected colour has too little saturation.
@export var hue_fallback_color: Color = Color(0.18, 0.52, 1.0, 1.0)
## Multiplier applied to the hue overlay intensity.
@export_range(0.0, 1.0, 0.01) var hue_overlay_strength: float = 1.0
## Minimum saturation required before hue shifting begins.
@export_range(0.0, 1.0, 0.01) var hue_saturation_threshold: float = 0.2
## Width of the saturation ramp for hue shifting.
@export_range(0.0, 1.0, 0.01) var hue_saturation_softness: float = 0.25
## Power applied to the saturation ramp mask.
@export_range(0.01, 8.0, 0.01) var hue_saturation_exponent: float = 1.0
## Fallback jump-ball colour used when custom colours are disabled.
@export var jump_ball_default_color: Color = Color(0.2, 0.8, 1.0, 0.72)

func get_trick_display_name(trick_id: StringName, fallback_name: String) -> String:
	var override_name: String = ""
	match trick_id:
		&"backflip": override_name = trick_name_backflip
		&"frontflip": override_name = trick_name_frontflip
		&"left_spin": override_name = trick_name_left_spin
		&"right_spin": override_name = trick_name_right_spin
		&"frontflip_left_spin": override_name = trick_name_frontflip_left_spin
		&"backflip_left_spin": override_name = trick_name_backflip_left_spin
		&"backflip_right_spin": override_name = trick_name_backflip_right_spin
		&"frontflip_right_spin": override_name = trick_name_frontflip_right_spin
		&"rail_forward": override_name = trick_name_rail_forward
		&"rail_backward": override_name = trick_name_rail_backward
		&"rail_forward_crouch": override_name = trick_name_rail_forward_crouch
		&"rail_backward_crouch": override_name = trick_name_rail_backward_crouch
		&"rail_forward_crouch_fast": override_name = trick_name_rail_forward_crouch_fast
		&"rail_backward_crouch_fast": override_name = trick_name_rail_backward_crouch_fast
		&"bounce_pogo": override_name = trick_name_bounce_pogo
		&"stomp_darehog": override_name = trick_name_stomp_darehog
	return override_name if not override_name.is_empty() else fallback_name

func get_feat_display_name(feat_id: StringName, fallback_name: String) -> String:
	var override_name: String = ""
	match feat_id:
		&"spring_launch": override_name = feat_name_spring_launch
		&"bumper_bounce": override_name = feat_name_bumper_bounce
		&"dash_panel": override_name = feat_name_dash_panel
		&"badnik_defeat": override_name = feat_name_badnik_defeat
		&"drift": override_name = feat_name_drift
		&"ledge_mantle": override_name = feat_name_ledge_mantle
		&"landing_roll": override_name = feat_name_landing_roll
		&"rejected_landing_roll": override_name = feat_name_rejected_landing_roll
		&"rough_landing": override_name = feat_name_rough_landing
		&"wall_carve": override_name = feat_name_wall_carve
		&"wall_cling": override_name = feat_name_wall_cling
		&"wall_run_kick": override_name = feat_name_wall_run_kick
		&"wall_kick": override_name = feat_name_wall_kick
		&"object_pickup": override_name = feat_name_object_pickup
		&"object_placed": override_name = feat_name_object_placed
		&"object_throw": override_name = feat_name_object_throw
		&"vault_bar": override_name = feat_name_vault_bar
		&"rail_grind": override_name = feat_name_rail_grind
		&"skydive": override_name = feat_name_skydive
	return override_name if not override_name.is_empty() else fallback_name

func get_combo_rating(score: float) -> Dictionary:
	var tier_count: int = mini(combo_rating_score_thresholds.size(), combo_rating_flavour_texts.size())
	if tier_count <= 0:
		return {"text": "", "tier": 0, "tier_count": 0}
	var selected_tier: int = 0
	for tier_index: int in range(tier_count):
		if score < combo_rating_score_thresholds[tier_index]:
			break
		selected_tier = tier_index
	return {
		"text": combo_rating_flavour_texts[selected_tier],
		"tier": selected_tier,
		"tier_count": tier_count
	}

func get_combo_rating_color(score: float) -> Color:
	var tier_count: int = mini(combo_rating_score_thresholds.size(), combo_rating_colors.size())
	if tier_count <= 0:
		return Color.WHITE
	if tier_count == 1 or score <= combo_rating_score_thresholds[0]:
		return combo_rating_colors[0]
	for tier_index: int in range(tier_count - 1):
		var lower_score: float = combo_rating_score_thresholds[tier_index]
		var upper_score: float = combo_rating_score_thresholds[tier_index + 1]
		if score < upper_score:
			var blend: float = inverse_lerp(lower_score, upper_score, score) if upper_score > lower_score else 0.0
			return combo_rating_colors[tier_index].lerp(combo_rating_colors[tier_index + 1], blend)
	return combo_rating_colors[tier_count - 1]
