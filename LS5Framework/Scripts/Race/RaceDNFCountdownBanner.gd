extends CanvasLayer

## Displays the legacy results countdown when no notification stack is available.
@onready var label: Label = get_node_or_null("Root/Label") as Label


func _ready() -> void:
	layer = 45
	visible = false
	if label != null:
		label.text = ""


func set_remaining(active: bool, remaining: float) -> void:
	if not active:
		if label != null:
			label.text = ""
		visible = false
		HUDMusicTrackDisplay.dismiss_posted_notification(get_tree(), &"race_results_countdown")
		return
	var remaining_text: String = "Finalizing in %0.0fs" % max(remaining, 0.0)
	if HUDMusicTrackDisplay.post_notification(
		get_tree(),
		"Race Results",
		remaining_text,
		null,
		max(remaining + 0.5, 1.0),
		&"race_results_countdown"
	):
		visible = false
		return
	if label == null:
		return
	visible = true
	label.text = "Race results in %0.0fs" % max(remaining, 0.0)


func _exit_tree() -> void:
	HUDMusicTrackDisplay.dismiss_posted_notification(get_tree(), &"race_results_countdown")
