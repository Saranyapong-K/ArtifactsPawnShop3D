class_name NightEventActor
extends StaticBody3D
## Night intruders follow a visible route. Walking up and interacting stops them.

signal caught(actor: Node3D)
signal escaped(actor: Node3D)

var kind: String = "thief"
var resolved: bool = false
var walk_speed: float = 1.15
var _route: Array[Vector3] = []
var _route_index: int = 0
var _wait_seconds: float = 0.0
var _wait_remaining: float = 0.0
var _waiting: bool = false
var _visual: Node3D
var _prompt: Label3D
var _animation: AnimationPlayer
var _state: Node
var _height := 1.75
var _leg_path := PackedVector3Array()
var _leg_point := 0
var _leg_index := -1
var _navigation_revision := -1
var _retry_seconds := 0.0


func setup(p_kind: String, route: Array[Vector3], source_scene: PackedScene = null, wait_seconds: float = 20.0) -> void:
	kind = p_kind
	if kind == "thief":
		var player := get_tree().get_first_node_in_group("shop_player")
		var player_speed: Variant = player.get("sprint_speed") if player else null
		walk_speed = float(player_speed) * 1.08 if player_speed is float or player_speed is int else 7.02
	_height = 0.9 if kind in ["demon", "police"] else 1.75
	_route = route.duplicate()
	_wait_seconds = wait_seconds
	_state = get_node_or_null("/root/GameState")
	collision_layer = 1
	collision_mask = 0
	add_to_group("night_intruders")
	var capsule := CapsuleShape3D.new()
	capsule.radius = 0.20 if _height < 1.0 else 0.32
	capsule.height = _height
	var shape := CollisionShape3D.new()
	shape.shape = capsule
	shape.position.y = _height * 0.5
	add_child(shape)
	if source_scene != null:
		_visual = source_scene.instantiate() as Node3D
		_visual.set_script(null)
		add_child(_visual)
		_remove_model_collisions(_visual)
		# Preserve authored materials on replacements; darken the reused customer only.
		if kind == "thief" and source_scene.resource_path == "res://npcs_1.tscn":
			_recolour_clothes(_visual)
		_fit_visual(_visual)
		_animation = _visual.find_child("AnimationPlayer", true, false) as AnimationPlayer
	else:
		_visual = _shadow_demon()
		add_child(_visual)
	_prompt = Label3D.new()
	_prompt.text = _prompt_text()
	_prompt.font_size = 34
	_prompt.pixel_size = 0.004
	_prompt.outline_size = 8
	_prompt.position.y = _height + 0.25
	_prompt.visible = kind != "police"
	_prompt.modulate = Color("ffd475")
	_prompt.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	add_child(_prompt)
	_play_animation("walk")
	if not _route.is_empty():
		global_position = _route[0]
		_route_index = 1


func interact(player: Node) -> void:
	if resolved or kind == "police" or not player is Node3D:
		return
	if global_position.distance_to((player as Node3D).global_position) > 3.5:
		return
	resolved = true
	collision_layer = 0
	caught.emit(self)
	queue_free()


func _process(delta: float) -> void:
	if _prompt: _prompt.text = _prompt_text()
	if resolved or _route.is_empty():
		return
	if _state != null and (_state.get("failed") or not _state.get("clock_running")):
		return
	if _state != null and _state.has_method("is_time_paused") and _state.call("is_time_paused"):
		return
	if _waiting:
		_wait_remaining -= delta
		if _wait_remaining <= 0.0:
			_waiting = false
			_play_animation("walk")
		return
	if _route_index >= _route.size():
		resolved = true
		collision_layer = 0
		escaped.emit(self)
		queue_free()
		return
	var destination := _route[_route_index]
	var navigation := get_tree().get_first_node_in_group("shop_navigation")
	if navigation:
		_retry_seconds = maxf(0.0, _retry_seconds - delta)
		if _leg_index != _route_index or navigation.dirty or _navigation_revision != navigation.revision:
			if _retry_seconds > 0: return
			_leg_path = navigation.approach_route(global_position, destination, self)
			_leg_point = 0; _leg_index = _route_index; _navigation_revision = navigation.revision
			if _leg_path.is_empty(): _leg_index = -1; _retry_seconds = 0.5; _play_animation("idle"); return
			_play_animation("walk")
		destination = _leg_path[_leg_point]
	var direction := destination - global_position
	direction.y = 0.0
	if direction.length() > 0.03:
		rotation.y = lerp_angle(rotation.y, atan2(direction.x, direction.z), 1.0 - exp(-delta * 5.0))
	var next := global_position.move_toward(destination, walk_speed * delta)
	if navigation and not navigation.motion_clear(global_position, next, self, _height, 0.18 if _height < 1.0 else 0.28):
		navigation.dirty = true; _leg_index = -1; _retry_seconds = 0.3; return
	global_position = next
	if global_position.distance_to(destination) <= 0.04:
		if navigation:
			_leg_point += 1
			if _leg_point < _leg_path.size(): return
		_route_index += 1
		# The middle waypoint is the artifact shelf. Leave time to catch the intruder.
		if _route_index == 3:
			_waiting = true
			_wait_remaining = _wait_seconds
			_play_animation("idle")


func _play_animation(prefix: String) -> void:
	if _animation == null:
		return
	for animation_name in _animation.get_animation_list():
		var name_lower := String(animation_name).get_file().to_lower()
		if name_lower.begins_with(prefix) or (prefix == "walk" and name_lower in ["running", "running_loop"]):
			_animation.get_animation(animation_name).loop_mode = Animation.LOOP_LINEAR
			_animation.play(animation_name)
			return
	_animation.stop()

func _prompt_text() -> String:
	var settings := get_node_or_null("/root/GameSettings")
	var key: String = settings.key_name("interact") if settings else "E"
	return key + (" / Catch" if kind == "thief" else " / Repel")


func _remove_model_collisions(root: Node) -> void:
	if root is CollisionObject3D:
		root.collision_layer = 0
		root.collision_mask = 0
	for child in root.get_children():
		_remove_model_collisions(child)


func _recolour_clothes(root: Node3D) -> void:
	for mesh in root.find_children("*", "MeshInstance3D", true, false):
		var instance := mesh as MeshInstance3D
		for surface in range(instance.mesh.get_surface_count()):
			var material := instance.get_active_material(surface) as StandardMaterial3D
			if material == null or not material.resource_name.to_lower() in ["body", "cape"]:
				continue
			var dark := material.duplicate() as StandardMaterial3D
			dark.albedo_texture = null
			dark.albedo_color = Color("302b38")
			instance.set_surface_override_material(surface, dark)


func _fit_visual(root: Node3D) -> void:
	var bounds := AABB()
	var first := true
	var inverse := root.global_transform.affine_inverse()
	var meshes := root.find_children("*", "MeshInstance3D", true, false)
	if root is MeshInstance3D:
		meshes.append(root)
	for child in meshes:
		var instance := child as MeshInstance3D
		var box: AABB = (inverse * instance.global_transform) * ArtifactVisual.mesh_bounds(instance)
		bounds = box if first else bounds.merge(box)
		first = false
	if first or bounds.size.y <= 0.001:
		return
	var factor := _height / bounds.size.y
	root.scale = Vector3.ONE * factor
	root.position.y = -bounds.position.y * root.scale.y


func _shadow_demon() -> Node3D:
	var visual := Node3D.new()
	var shadow := _material(Color("281c32"))
	var horn := _material(Color("ab6141"))
	var eyes := _material(Color("ffba52"), true)
	var body := CapsuleMesh.new()
	body.radius = 0.35
	body.height = 1.25
	body.radial_segments = 6
	body.rings = 3
	_add_mesh(visual, body, shadow, Vector3(0, 0.8, 0))
	var head := SphereMesh.new()
	head.radius = 0.3
	head.height = 0.5
	head.radial_segments = 6
	head.rings = 3
	_add_mesh(visual, head, shadow, Vector3(0, 1.53, 0))
	for side in [-1.0, 1.0]:
		var cone := CylinderMesh.new()
		cone.top_radius = 0.0
		cone.bottom_radius = 0.11
		cone.height = 0.4
		cone.radial_segments = 5
		var spike := _add_mesh(visual, cone, horn, Vector3(side * 0.22, 1.86, 0))
		spike.rotation.z = -side * 0.35
		var eye := BoxMesh.new()
		eye.size = Vector3(0.09, 0.055, 0.025)
		_add_mesh(visual, eye, eyes, Vector3(side * 0.12, 1.56, 0.28))
	return visual


func _material(colour: Color, glowing: bool = false) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = colour
	material.roughness = 1.0
	if glowing:
		material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	return material


func _add_mesh(parent: Node3D, mesh: Mesh, material: Material, at: Vector3) -> MeshInstance3D:
	var instance := MeshInstance3D.new()
	instance.mesh = mesh
	instance.material_override = material
	instance.position = at
	parent.add_child(instance)
	return instance
