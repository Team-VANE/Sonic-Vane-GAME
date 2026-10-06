extends CanvasLayer

## Displays the legacy race queue message when no notification stack is available.
@onready var label: Label = get_node_or_null("Root/Label") as Label


func _ready() -> void:
	layer = 45
	visible = false
	if label != null:
		label.text = ""


func set_state(active: bool, remaining: float, gathering: bool = false) -> void:
	if not active:
		if label != null:
			label.text = ""
		visible = false
		HUDMusicTrackDisplay.dismiss_posted_notification(get_tree(), &"race_queue")
		return
	var remaining_text: String = "Join from the pause menu - %0.0fs remaining" % max(remaining, 0.0)
	if gathering:
		remaining_text = "Gathering players - waiting for everyone to load and prepare"
	if HUDMusicTrackDisplay.post_notification(
		get_tree(),
		"Gathering Players" if gathering else "Race Queue Open",
		remaining_text,
		null,
		2.0 if gathering else max(remaining + 0.5, 1.0),
		&"race_queue"
	):
		visible = false
		return
	if label == null:
		return
	visible = true
	if gathering:
		label.text = remaining_text
		return
	label.text = "A player has started a race!  Enter the pause menu to join!  (%0.0fs)" % max(remaining, 0.0)


func _exit_tree() -> void:
	HUDMusicTrackDisplay.dismiss_posted_notification(get_tree(), &"race_queue")
