extends RigidBody3D
## A bought relic lying in the shop.
## Look at it -> "E / Pick up" appears. E picks it up, E again drops it.
## While held it shows its TRUE value.
##
## While you hold it, only the relic's MODEL is attached to your camera (so it follows
## your view smoothly). The physics body waits on the counter and takes over again on drop.

var true_value := 0
var size := Vector3(0.3, 0.3, 0.3)   # real size after scaling
var held := false

var _model: Node3D
var _model_scale := 1.0
var _label: Label3D          # "Worth 453", shown only while held
var _label_height := 0.5
var _prompt: Node3D          # "E / Pick up", shown when you look at it
var _prompt_height := 0.6
var _bob := 0.0
var _picked_ms := 0
var _spawn_pos := Vector3.ZERO


## Call after the item is in the scene tree and `model` is its child.
func setup(model: Node3D, model_scale: float, value: int) -> void:
	true_value = value
	_model = model
	_model_scale = model_scale
	_spawn_pos = global_position
	collision_layer = 1
	collision_mask = 1
	continuous_cd = true

	# collision box fitted to the model, same size the player saw while haggling
	var box := _local_aabb(model)
	if box.size == Vector3.ZERO:
		box = AABB(Vector3(-0.15, -0.15, -0.15), Vector3(0.3, 0.3, 0.3))
	model.scale = Vector3.ONE * model_scale
	size = box.size * model_scale
	var top := (box.position.y + box.size.y) * model_scale

	var shape := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = size
	shape.shape = bs
	shape.position = (box.position + box.size * 0.5) * model_scale
	add_child(shape)

	# "Worth ..." label (goes to the camera while held)
	_label_height = top + 0.2
	_label = _make_label("Worth %d" % value, 64, 0.0025, 14, Color("f5c542"))
	_label.visible = false
	add_child(_label)

	# "E / Pick up" prompt: top_level so it ignores the relic tumbling around
	_prompt_height = top + 0.3
	_prompt = Node3D.new()
	_prompt.top_level = true
	_prompt.visible = false
	add_child(_prompt)
	_prompt.add_child(_make_label("E", 80, 0.003, 10, Color.WHITE))
	var pick := _make_label("Pick up", 40, 0.003, 8, Color.WHITE)
	pick.position = Vector3(0.0, -0.2, 0.0)
	_prompt.add_child(pick)


## Called by player.gd when E is pressed while looking at this relic.
func interact(player: Node) -> void:
	if held:
		return
	# small cooldown after a drop, and only one relic in hand
	if Time.get_ticks_msec() - int(Engine.get_meta("relic_drop_ms", -1000)) < 300:
		return
	if not get_tree().get_nodes_in_group("held_relic").is_empty():
		return
	var cam = player.get("camera")
	if cam == null:
		return

	var hold := cam.get_node_or_null("HoldPoint") as Node3D
	if hold == null:
		hold = Node3D.new()
		hold.name = "HoldPoint"
		cam.add_child(hold)
	# lower-right of the view, further away for bigger relics
	var ext := maxf(size.x, maxf(size.y, size.z))
	hold.position = Vector3(0.25 + ext * 0.12, -0.25 - ext * 0.1, -(0.6 + ext * 0.9))

	held = true
	_picked_ms = Time.get_ticks_msec()
	add_to_group("held_relic")
	freeze_mode = RigidBody3D.FREEZE_MODE_KINEMATIC
	freeze = true
	collision_layer = 0
	collision_mask = 0
	_prompt.visible = false

	# only the visual moves to the camera
	_model.reparent(hold, false)
	_model.transform = Transform3D(Basis.from_scale(Vector3.ONE * _model_scale), Vector3.ZERO)
	_label.reparent(hold, false)
	_label.position = Vector3(0.0, _label_height, 0.0)
	_label.visible = true


func _unhandled_input(event: InputEvent) -> void:
	if not held:
		return
	if Time.get_ticks_msec() - _picked_ms < 300:
		return   # ignore the same E press that picked it up
	if Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		return   # dialogue / bargain is open, E belongs to the UI
	if event.is_action_pressed("interact"):
		get_viewport().set_input_as_handled()
		_drop()


func _drop() -> void:
	var cam := get_viewport().get_camera_3d()
	var forward := -cam.global_transform.basis.z
	var pos := _model.global_position
	var yaw := cam.global_rotation.y

	# model and label come back to the physics body
	_model.reparent(self, false)
	_model.transform = Transform3D(Basis.from_scale(Vector3.ONE * _model_scale), Vector3.ZERO)
	_label.reparent(self, false)
	_label.visible = false

	global_position = pos
	global_rotation = Vector3(0.0, yaw, 0.0)
	held = false
	remove_from_group("held_relic")
	Engine.set_meta("relic_drop_ms", Time.get_ticks_msec())
	collision_layer = 1
	collision_mask = 1
	freeze = false
	linear_velocity = forward * 1.5
	angular_velocity = Vector3.ZERO


func _process(delta: float) -> void:
	if _prompt == null:
		return
	var can_show := false
	if not held and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED \
			and get_tree().get_nodes_in_group("held_relic").is_empty():
		var cam := get_viewport().get_camera_3d()
		if cam:
			var to := global_position - cam.global_position
			var fwd := -cam.global_transform.basis.z
			if to.length() < 4.5 and to.normalized().dot(fwd) > 0.5:
				can_show = _is_looking_at(cam, fwd)
	_prompt.visible = can_show
	if can_show:
		_bob += delta * 4.0
		_prompt.global_position = global_position + Vector3(0.0, _prompt_height + sin(_bob) * 0.04, 0.0)


func _physics_process(_delta: float) -> void:
	# safety net: if it ever falls out of the world, put it back
	if not held and global_position.y < -10.0:
		linear_velocity = Vector3.ZERO
		global_position = _spawn_pos


## Same reach as the player's interaction ray (3 m), so the prompt only shows when E works.
func _is_looking_at(cam: Camera3D, fwd: Vector3) -> bool:
	var from := cam.global_position
	var query := PhysicsRayQueryParameters3D.create(from, from + fwd * 3.0)
	query.collision_mask = 1
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	return not hit.is_empty() and hit["collider"] == self


func _make_label(text: String, font_size: int, pixel_size: float, outline: int, color: Color) -> Label3D:
	var l := Label3D.new()
	l.text = text
	l.font_size = font_size
	l.pixel_size = pixel_size
	l.outline_size = outline
	l.modulate = color
	l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	l.no_depth_test = true
	return l


func _local_aabb(root: Node3D) -> AABB:
	var meshes: Array = root.find_children("*", "MeshInstance3D", true, false)
	if root is MeshInstance3D:
		meshes.append(root)
	var out := AABB()
	var first := true
	var inv := root.global_transform.affine_inverse()
	for m in meshes:
		var mi := m as MeshInstance3D
		var box: AABB = (inv * mi.global_transform) * mi.get_aabb()
		if first:
			out = box
			first = false
		else:
			out = out.merge(box)
	return out
