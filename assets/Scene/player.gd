extends CharacterBody3D
## First-person player: WASD + mouse look + E to interact.
## Needs these child nodes: Head (Node3D) > Camera3D, plus a CollisionShape3D.
## Input Map actions needed: move_forward, move_back, move_left, move_right, interact

signal interacted(target: Node)

@export var speed := 4.0
@export var sprint_speed := 6.5
@export var crouch_speed := 1.8
@export var crouch_height := 1.1
@export var mouse_sensitivity := 0.0025
@export var reach := 3.0
@export var hide_model_in_first_person := true

@onready var head: Node3D = $Head
@onready var camera: Camera3D = $Head/Camera3D
@onready var model: Node3D = get_node_or_null("TwinkElf")

var controls_enabled := true
var ray: RayCast3D
var _gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity")
var _collision: CollisionShape3D
var _capsule: CapsuleShape3D
var _standing_height := 2.0
var _standing_collision_position := Vector3.ZERO
var _standing_head_position := Vector3.ZERO
var _crouched := false
var _spawn_position := Vector3.ZERO
var view_motion := Vector2.ZERO
var _shake_left := 0.0
var _shake_time := 0.0
var _interaction_frame := -1
var _interaction_target: Node
var _step_seconds := 0.0

func _ready() -> void:
	add_to_group("shop_player")
	_spawn_position = global_position
	_standing_head_position = head.position
	_collision = get_node_or_null("CollisionShape3D") as CollisionShape3D
	if _collision and _collision.shape is CapsuleShape3D:
		_capsule = _collision.shape.duplicate() as CapsuleShape3D
		_collision.shape = _capsule
		_standing_height = _capsule.height
		_standing_collision_position = _collision.position
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
		# Browsers require a fresh click event to grant pointer lock.
		if not OS.has_feature("web"):
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	else:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT and controls_enabled and Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
		get_viewport().set_input_as_handled()
	elif event is InputEventMouseMotion and controls_enabled and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		view_motion = event.relative.limit_length(50)
		rotate_y(-event.relative.x * mouse_sensitivity)
		head.rotation.x = clampf(
			head.rotation.x - event.relative.y * mouse_sensitivity,
			deg_to_rad(-85.0), deg_to_rad(85.0))
	elif event.is_action_pressed("interact") and not event.is_echo() and controls_enabled and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		_try_interact()


func shake_camera() -> void:
	_shake_left = 0.2
	_shake_time = 0.0

func _process(delta: float) -> void:
	view_motion = view_motion.lerp(Vector2.ZERO,1-exp(-delta*14))
	_shake_time += delta
	_shake_left = maxf(0,_shake_left-delta)
	camera.h_offset = sin(_shake_time*72)*0.014*(_shake_left/0.2)
	camera.v_offset = cos(_shake_time*53)*0.008*(_shake_left/0.2)

func _physics_process(delta: float) -> void:
	if global_position.y < -20.0:
		global_position = _spawn_position
		velocity = Vector3.ZERO
	var settings := get_node_or_null("/root/GameSettings")
	if settings:
		mouse_sensitivity = float(settings.mouse_sensitivity)
	if not is_on_floor():
		velocity.y -= _gravity * delta
	else:
		velocity.y = 0.0
	_update_crouch()

	var input_dir := Vector2.ZERO
	if controls_enabled:
		input_dir = Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	var move := (transform.basis * Vector3(input_dir.x, 0.0, input_dir.y)).normalized()
	var move_speed := speed
	if _crouched:
		move_speed = crouch_speed
	elif controls_enabled and InputMap.has_action("sprint") and Input.is_action_pressed("sprint"):
		move_speed = sprint_speed
	velocity.x = move.x * move_speed
	velocity.z = move.z * move_speed
	move_and_slide()
	if controls_enabled and is_on_floor() and Vector2(velocity.x, velocity.z).length() > 0.3:
		_step_seconds += delta
		if _step_seconds >= (0.30 if move_speed > speed else 0.46):
			_step_seconds = 0.0
			var sfx := get_node_or_null("/root/Sfx")
			if sfx: sfx.play("footstep", randf_range(0.9, 1.1))
	else: _step_seconds = 0.0


func _update_crouch() -> void:
	if not _capsule:
		return
	var wants_crouch := controls_enabled and InputMap.has_action("crouch") and Input.is_action_pressed("crouch")
	if wants_crouch and not _crouched:
		_crouched = true
	elif not wants_crouch and _crouched and _can_stand():
		_crouched = false
	var height := clampf(crouch_height, _capsule.radius * 2.0, _standing_height) if _crouched else _standing_height
	var reduction := _standing_height - height
	_capsule.height = height
	_collision.position = _standing_collision_position - Vector3(0.0, reduction * 0.5, 0.0)
	head.position = _standing_head_position - Vector3(0.0, reduction, 0.0)


func _can_stand() -> bool:
	var standing_shape := CapsuleShape3D.new()
	standing_shape.radius = _capsule.radius
	standing_shape.height = _standing_height
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = standing_shape
	query.transform = global_transform * Transform3D(_collision.transform.basis, _standing_collision_position)
	query.collision_mask = collision_mask
	query.exclude = [get_rid()]
	query.margin = 0.0
	return get_world_3d().direct_space_state.intersect_shape(query, 1).is_empty()


func _try_interact() -> void:
	var target: Node = get_interaction_target(true)
	if target:
		target.interact(self)
		interacted.emit(target)

func get_interaction_target(force: bool = false) -> Node:
	# Prompts and the actual interaction share one ray, including cleaning areas.
	if not force and _interaction_frame == Engine.get_process_frames():
		return _interaction_target if is_instance_valid(_interaction_target) else null
	_interaction_frame = Engine.get_process_frames()
	ray.force_raycast_update()
	if not ray.is_colliding():
		_interaction_target = null
		return null
	# Find the first node (collider or its parents) that has an interact() function
	var target := ray.get_collider() as Node
	# Dust areas sit over display surfaces. Without the duster, prefer a book or
	# artifact directly underneath; the same resolved target drives its prompt.
	if target and target is Area3D and target.get_script() and target.get_script().resource_path == "res://scripts/cleaning_target.gd" and target.kind == "dust":
		var cleaner := get_tree().get_first_node_in_group("cleaning_manager")
		if cleaner and cleaner.held_tool != "feather_duster":
			var query := PhysicsRayQueryParameters3D.create(camera.global_position, camera.global_position - camera.global_basis.z * reach)
			query.collide_with_areas = true
			query.exclude = [get_rid(), target.get_rid()]
			var hit := get_world_3d().direct_space_state.intersect_ray(query)
			var behind: Node = hit.get("collider")
			while behind and not behind.has_method("interact"): behind = behind.get_parent()
			if behind: target = behind
	while target and not target.has_method("interact"):
		target = target.get_parent()
	_interaction_target = target
	return target
