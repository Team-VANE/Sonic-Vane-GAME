extends CanvasLayer

## Time the legacy finish banner remains visible when no notification stack is available.
@export_range(0.0, 30.0, 0.1, "or_greater", "suffix:s") var display_time: float = 3.0

## Displays the legacy finish message when no notification stack is available.
@onready var label: Label = get_node_or_null("Root/Label") as Label

var _timer: float = 0.0


func _ready() -> void:
	layer = 46
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_process(true)
	visible = false


func _process(delta: float) -> void:
	if not visible:
		return
	_timer = max(_timer - max(delta, 0.0), 0.0)
	if _timer <= 0.0:
		visible = false


func show_message(text_value: String, duration: float = -1.0) -> void:
	var resolved_duration: float = duration
	if resolved_duration < 0.0:
		resolved_duration = display_time
	if HUDMusicTrackDisplay.post_notification(
		get_tree(),
		"Finish Line",
		text_value,
		null,
		resolved_duration
	):
		visible = false
		return
	if label != null:
		label.text = text_value
	visible = true
	_timer = max(resolved_duration, 0.0)
