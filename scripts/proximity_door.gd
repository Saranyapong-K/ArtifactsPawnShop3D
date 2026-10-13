extends Node3D
## Each door has its own animation player, so front/back can open together.
var door: MeshInstance3D
var animation: Animation
var front := false
var trigger_center := Vector3.ZERO
var opened := false
var requests: Dictionary = {}
var close_delay := 0.0
var animator: AnimationPlayer
var _collision_bodies: Array[CollisionObject3D] = []
var _collision_layers: Array[int] = []

func _ready() -> void:
	add_to_group("automatic_doors")
	trigger_center = (door.global_transform * door.get_aabb()).get_center()
	animator = AnimationPlayer.new()
	animator.callback_mode_process=AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_PHYSICS
	door.add_child(animator)
	animator.root_node = NodePath("..")
	var clip: Animation = animation.duplicate(true)
	var base := door.rotation
	var original: Vector3 = clip.track_get_key_value(0, 0)
	clip.track_set_path(0, NodePath(":rotation"))
	for key in clip.track_get_key_count(0):
		clip.track_set_key_value(0, key, base + Vector3(0, (clip.track_get_key_value(0, key) as Vector3).y - original.y, 0))
	var library := AnimationLibrary.new()
	library.add_animation("open", clip)
	animator.add_animation_library("", library)
	for body in door.find_children("*", "CollisionObject3D", true, false):
		_collision_bodies.append(body)
		_collision_layers.append(body.collision_layer)
	animator.animation_finished.connect(_finish_motion)
	set_meta("front", front)

func request_open(owner: String) -> void:
	requests[owner] = true
	_set_open(true)

func release(owner: String) -> void:
	requests.erase(owner)

func _near(point: Vector3) -> bool:
	return Vector2(point.x - trigger_center.x, point.z - trigger_center.z).length() < 1.65 and absf(point.y - trigger_center.y) < 2.5

func _physics_process(delta: float) -> void:
	var nearby := not requests.is_empty()
	var player := get_tree().get_first_node_in_group("shop_player") as Node3D
	if player: nearby = nearby or _near(player.global_position)
	for group in ["shop_visitors", "night_intruders"]:
		for actor in get_tree().get_nodes_in_group(group):
			if actor is Node3D and _near(actor.global_position): nearby = true
	if nearby:
		close_delay = 0.8
		_set_open(true)
	else:
		close_delay = maxf(0, close_delay - delta)
		if close_delay == 0: _set_open(false)

func _set_open(value: bool) -> void:
	if opened == value: return
	opened = value
	# A moving leaf must not shove a capsule into the wall. Restore its solid
	# collision only after it reaches the closed pose; wall geometry stays solid.
	_set_leaf_collision(false)
	if value:
		animator.play("open")
		var sfx := get_node_or_null("/root/Sfx")
		if sfx: sfx.play("door")
	else: animator.play_backwards("open")

func _set_leaf_collision(solid: bool) -> void:
	for i in _collision_bodies.size():
		if is_instance_valid(_collision_bodies[i]):
			_collision_bodies[i].collision_layer = _collision_layers[i] if solid else 0

func _finish_motion(_clip: StringName) -> void:
	if not opened: _set_leaf_collision(true)
