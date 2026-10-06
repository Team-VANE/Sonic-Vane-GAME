extends RefCounted
class_name UIExcitementEffects


static func set_center_pivot(control: Control) -> void:
	if control == null:
		return
	control.pivot_offset = control.size * 0.5


static func pulse_in(
		control: Control,
		duration: float = 0.32,
		start_scale: float = 0.68,
		overshoot_scale: float = 1.08
	) -> Tween:
	if control == null:
		return null
	set_center_pivot(control)
	control.scale = Vector2.ONE * max(start_scale, 0.0)
	control.modulate.a = 0.0
	var tween: Tween = control.create_tween()
	var first_duration: float = max(duration, 0.01) * 0.62
	var settle_duration: float = max(duration, 0.01) - first_duration
	tween.set_parallel(true)
	tween.tween_property(control, "modulate:a", 1.0, first_duration * 0.7)
	tween.tween_property(
		control,
		"scale",
		Vector2.ONE * max(overshoot_scale, 1.0),
		first_duration
	).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tween.chain().tween_property(control, "scale", Vector2.ONE, settle_duration).set_trans(
		Tween.TRANS_QUAD
	).set_ease(Tween.EASE_OUT)
	return tween


static func sweep_in(
		control: Control,
		start_offset: Vector2,
		duration: float = 0.45,
		start_scale: float = 0.94
	) -> Tween:
	if control == null:
		return null
	set_center_pivot(control)
	var target_position: Vector2 = control.position
	control.position = target_position + start_offset
	control.scale = Vector2.ONE * max(start_scale, 0.0)
	control.modulate.a = 0.0
	var tween: Tween = control.create_tween()
	tween.set_parallel(true)
	tween.tween_property(control, "position", target_position, max(duration, 0.01)).set_trans(
		Tween.TRANS_QUINT
	).set_ease(Tween.EASE_OUT)
	tween.tween_property(control, "scale", Vector2.ONE, max(duration, 0.01)).set_trans(
		Tween.TRANS_BACK
	).set_ease(Tween.EASE_OUT)
	tween.tween_property(control, "modulate:a", 1.0, max(duration, 0.01) * 0.7)
	tween.set_parallel(false)
	return tween


static func sweep_out(
		control: Control,
		target_offset: Vector2,
		duration: float = 0.4,
		end_scale: float = 0.94
	) -> Tween:
	if control == null:
		return null
	var target_position: Vector2 = control.position + target_offset
	var tween: Tween = control.create_tween()
	tween.set_parallel(true)
	tween.tween_property(control, "position", target_position, max(duration, 0.01)).set_trans(
		Tween.TRANS_QUINT
	).set_ease(Tween.EASE_IN)
	tween.tween_property(
		control,
		"scale",
		Vector2.ONE * max(end_scale, 0.0),
		max(duration, 0.01)
	).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tween.tween_property(control, "modulate:a", 0.0, max(duration, 0.01) * 0.8)
	tween.set_parallel(false)
	return tween


static func reveal_text(label: RichTextLabel, duration: float = 0.65) -> Tween:
	if label == null:
		return null
	label.visible_ratio = 0.0
	var tween: Tween = label.create_tween()
	tween.tween_property(label, "visible_ratio", 1.0, max(duration, 0.01)).set_trans(
		Tween.TRANS_QUAD
	).set_ease(Tween.EASE_OUT)
	return tween


static func create_tracking_font(label: Label) -> FontVariation:
	if label == null:
		return null
	var source_font: Font = label.get_theme_font("font")
	var tracking_font: FontVariation = FontVariation.new()
	tracking_font.base_font = source_font
	tracking_font.spacing_glyph = 0
	label.add_theme_font_override("font", tracking_font)
	return tracking_font


static func animate_tracking(
		owner: Node,
		tracking_font: FontVariation,
		spacing: int,
		duration: float
	) -> Tween:
	if owner == null or tracking_font == null:
		return null
	tracking_font.spacing_glyph = 0
	var tween: Tween = owner.create_tween()
	tween.tween_property(
		tracking_font,
		"spacing_glyph",
		max(spacing, 0),
		max(duration, 0.01)
	).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	return tween


static func accelerate_tweens(tweens: Array[Tween], speed_scale: float) -> void:
	for tween: Tween in tweens:
		if tween != null and tween.is_valid() and tween.is_running():
			tween.set_speed_scale(max(speed_scale, 1.0))
