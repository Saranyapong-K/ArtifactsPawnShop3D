extends CharacterBody3D
## First-person player: WASD + mouse look + E to interact.
## Needs these child nodes: Head (Node3D) > Camera3D, plus a CollisionShape3D.
## Input Map actions needed: move_forward, move_back, move_left, move_right, interact

signal interacted(target: Node)

@export var speed := 4.0
@export var mouse_sensitivity := 0.0025
@export var reach := 3.0
@export var hide_model_in_first_person := true

@onready var head: Node3D = $Head
@onready var camera: Camera3D = $Head/Camera3D
@onready var model: Node3D = get_node_or_null("TwinkElf")

var controls_enabled := true
var ray: RayCast3D
var _gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity")
#var _spawn_pos := Vector3.ZERO

func _ready() -> void:
	#_spawn_pos = global_position
	ray = RayCast3D.new()
	ray.target_position = Vector3(0, 0, -reach)
	ray.collide_with_areas = true
	camera.add_child(ray)
	ray.add_exception(self)

	camera.current = true
	if model and hide_model_in_first_person:
		model.visible = false
	set_controls_enabled(true)


## Call with false when the bargain UI / another camera takes over.
func set_controls_enabled(enabled: bool) -> void:
	controls_enabled = enabled
	if enabled:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	else:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and controls_enabled and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		rotate_y(-event.relative.x * mouse_sensitivity)
		head.rotation.x = clampf(
			head.rotation.x - event.relative.y * mouse_sensitivity,
			deg_to_rad(-85.0), deg_to_rad(85.0))
	elif event.is_action_pressed("interact") and controls_enabled:
		_try_interact()
	elif event.is_action_pressed("ui_cancel"):
		# ESC frees the mouse 
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	elif event is InputEventMouseButton and event.pressed and controls_enabled \
			and Input.mouse_mode == Input.MOUSE_MODE_VISIBLE:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED   # click to re-capture


func _physics_process(delta: float) -> void:
	#if global_position.y < -20.0:
		#global_position = _spawn_pos
		#velocity = Vector3.ZERO
		
	if not is_on_floor():
		velocity.y -= _gravity * delta

	var input_dir := Vector2.ZERO
	if controls_enabled:
		input_dir = Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	var move := (transform.basis * Vector3(input_dir.x, 0.0, input_dir.y)).normalized()
	velocity.x = move.x * speed
	velocity.z = move.z * speed
	move_and_slide()


func _try_interact() -> void:
	ray.force_raycast_update()
	if not ray.is_colliding():
		return
	# Find the first node (collider or its parents) that has an interact() function
	var target := ray.get_collider() as Node
	while target and not target.has_method("interact"):
		target = target.get_parent()
	if target:
		target.interact(self)
		interacted.emit(target)
