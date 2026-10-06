extends Node3D
## Holder for the relic on the counter.
## Hold left mouse and drag to rotate it. When you let go it keeps coasting
## with the speed you gave it, then slowly settles back to the normal auto-spin.

@export var auto_spin_speed := 0.8     # radians per second (the normal slow spin)
@export var drag_sensitivity := 0.01
@export var friction := 2.5            # higher = the coast ends sooner
@export var max_speed := 12.0          # cap so a violent flick can't go crazy

var _dragging := false
var _vel := Vector2(0.8, 0.0)   # x = yaw speed, y = pitch speed (rad/s)
var _motion := Vector2.ZERO     # mouse movement collected since last frame


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		_dragging = event.pressed
		_motion = Vector2.ZERO
	elif event is InputEventMouseMotion and _dragging:
		_motion += event.relative


func _process(delta: float) -> void:
	# if the button was released over a UI element we never saw the release
	if _dragging and not Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
		_dragging = false

	if _dragging:
		# follow the mouse exactly, and remember how fast it was moving
		var move := _motion * drag_sensitivity
		_motion = Vector2.ZERO
		rotation.y += move.x
		rotation.x = clampf(rotation.x + move.y, -1.2, 1.2)
		var speed := move / maxf(delta, 0.001)
		_vel = _vel.lerp(speed, 0.5).limit_length(max_speed)   # smoothed, so one jittery frame can't spike it
	else:
		# coast: yaw eases toward the normal auto-spin, pitch eases to a stop
		var k := 1.0 - exp(-friction * delta)
		_vel.x = lerpf(_vel.x, auto_spin_speed, k)
		_vel.y = lerpf(_vel.y, 0.0, k)
		rotation.y += _vel.x * delta
		rotation.x = clampf(rotation.x + _vel.y * delta, -1.2, 1.2)
