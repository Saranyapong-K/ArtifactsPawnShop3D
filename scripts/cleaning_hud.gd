extends CanvasLayer
## Viewport waypoint has no world depth test, so walls never hide it.
@onready var prompt: Label = %Prompt
@onready var holding_label: Label = %HoldingLabel
@onready var progress_panel: Control = %CleaningProgress
@onready var progress_bar: ProgressBar = %ProgressBar
@onready var progress_label: Label = %ProgressLabel
@onready var indicator: Control = %DumpsterIndicator
@onready var arrow: Polygon2D = %DumpsterArrow
@onready var arrow_outline: Polygon2D = $Screen/DumpsterIndicator/ArrowOutline
@onready var distance_label: Label = %DumpsterDistance
@onready var wash_indicator: Control = %WashIndicator
@onready var wash_arrow: Polygon2D = %WashArrow
@onready var wash_outline: Polygon2D = $Screen/WashIndicator/ArrowOutline
@onready var feedback: Label = %Feedback
var feedback_left := 0.0
var bob_seconds := 0.0

func show_progress(title: String, seconds: float) -> void:
	progress_panel.show()
	progress_bar.value = clampf(seconds / CleaningState.CLEAN_SECONDS * 100.0, 0.0, 100.0)
	progress_label.text = ""
	progress_label.hide()

func hide_progress() -> void:
	progress_panel.hide()

func update_dumpster(camera: Camera3D, point: Vector3, visible: bool) -> void:
	_waypoint(camera,point,visible,indicator,arrow,arrow_outline)
	distance_label.hide()

func update_wash(camera: Camera3D,point: Vector3,visible: bool) -> void:
	_waypoint(camera,point,visible,wash_indicator,wash_arrow,wash_outline)

func _waypoint(camera: Camera3D, point: Vector3, visible: bool, control: Control, icon: Polygon2D, outline: Polygon2D) -> void:
	control.visible = visible and camera != null
	if not control.visible: return
	var screen := get_viewport().get_visible_rect().size
	var center := screen * 0.5
	var projected := camera.unproject_position(point+Vector3.UP*sin(bob_seconds*4.0)*0.10)
	var behind := camera.is_position_behind(point)
	if behind:
		var local := camera.to_local(point)
		var direction := Vector2(local.x, -local.y)
		if direction.length_squared() < 0.0001: direction = Vector2.DOWN
		projected = center + direction.normalized() * screen.length()
	var margin := Vector2(85, 95)
	var position_on_screen := projected.clamp(margin, (screen - margin).max(margin))
	var offscreen := behind or not position_on_screen.is_equal_approx(projected)
	control.position = position_on_screen
	icon.rotation = (projected - center).angle() + PI * 0.5 if offscreen else PI
	outline.rotation = icon.rotation

func flash(text: String) -> void:
	feedback.text = text
	feedback_left = 2.0
	feedback.show()

func _process(delta: float) -> void:
	bob_seconds += delta
	feedback_left = maxf(0,feedback_left-delta)
	feedback.visible = feedback_left>0
