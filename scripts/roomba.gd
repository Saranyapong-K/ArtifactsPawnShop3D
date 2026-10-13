extends Node3D
## Autonomous shop cleaner. Uses the shared navigation and saved mess progress.
var manager: Node3D
var model_scene: PackedScene
@export var speed := 0.7
var target_id := ""
var path := PackedVector3Array()
var path_index := 0
var _search_delay := 0.0
var _destination := Vector3.ZERO
var _revision := -1
var _cleaning := false
var _animation: AnimationPlayer

func _ready() -> void:
	add_to_group("shop_robots")
	var data := ArtifactData.create(model_scene.resource_path, "Roomba", "Common", "normal", Vector2i.ONE)
	var visual := ArtifactVisual.create(data, 0.23, 1.0, false)
	add_child(visual)
	_animation = visual.find_child("AnimationPlayer", true, false) as AnimationPlayer
	if _animation:
		for clip in _animation.get_animation_list():
			if String(clip).to_lower().begins_with("roomba"):
				_animation.get_animation(clip).loop_mode = Animation.LOOP_LINEAR
				_animation.play(clip)

func _process(delta: float) -> void:
	if GameState.is_time_paused():
		if _animation: _animation.speed_scale = 0.0
		return
	if _animation: _animation.speed_scale = 1.0
	var nav := get_tree().get_first_node_in_group("shop_navigation")
	if nav == null: return
	if nav.dirty and not nav.motion_clear(global_position, global_position, self, 0.30, 0.18):
		# Recover if new furniture was placed over the appliance or its saved home.
		var safe: PackedVector3Array = nav.approach_route(global_position, global_position, self)
		if not safe.is_empty(): global_position = safe[0]
		_clear_target()
	_search_delay = maxf(0.0, _search_delay - delta)
	var record: Dictionary = GameState.cleaning.get_mess(target_id)
	if not target_id.is_empty() and record.is_empty(): _clear_target()
	if _search_delay == 0.0 and path_index >= path.size() and not _cleaning:
		_find_work(nav)
		_search_delay = 2.0
	if path_index < path.size():
		if nav.dirty or _revision != nav.revision:
			path = nav.route(global_position, _destination, self)
			path_index = 0
			_revision = nav.revision
			if path.is_empty(): _clear_target(); return
		var point := path[path_index]
		var next := global_position.move_toward(point, speed * delta)
		if not nav.motion_clear(global_position, next, self, 0.30, 0.18):
			nav.dirty = true
			_clear_target()
			return
		var direction := point - global_position
		if Vector2(direction.x, direction.z).length() > 0.01:
			rotation.y = lerp_angle(rotation.y, atan2(direction.x, direction.z), 1.0 - exp(-delta * 5.0))
		global_position = next
		if global_position.distance_to(point) < 0.025: path_index += 1
		if path_index >= path.size() and not target_id.is_empty(): _cleaning = true
	elif _cleaning:
		rotation.y += delta * 0.4
		# Manual work takes priority if the player starts cleaning this spot.
		if manager.is_cleaning() and manager._active_target.record_id == target_id: return
		var result: Dictionary = GameState.cleaning.advance_robot(target_id, delta, GameState.day)
		if not result.get("ok", false) or result.get("completed", false):
			if result.get("completed", false):
				var sfx := get_node_or_null("/root/Sfx")
				if sfx: sfx.play("clean", 0.9)
				GameState.changed.emit()
			_clear_target()

func _find_work(nav: Node) -> void:
	var records: Array = GameState.cleaning.mess.duplicate()
	records.sort_custom(func(a: Dictionary, b: Dictionary): return global_position.distance_squared_to(_point(a)) < global_position.distance_squared_to(_point(b)))
	for record: Dictionary in records:
		if manager.is_cleaning() and manager._active_target.record_id == record.id: continue
		var point := _point(record)
		# Dust sits above furniture: clean alongside its base rather than crossing it.
		var candidates: Array[Vector3] = [point]
		if record.kind == "dust":
			for offset in [Vector3(0,0,0.8),Vector3(0,0,-0.8),Vector3(0.8,0,0),Vector3(-0.8,0,0),Vector3(0,0,1.25),Vector3(1.25,0,0)]: candidates.append(point + offset)
		for candidate in candidates:
			var route: PackedVector3Array = nav.route(global_position, candidate, self)
			if route.is_empty(): continue
			target_id = record.id
			_destination = candidate
			path = route; path_index = 0; _revision = nav.revision
			return
	# Patrol the existing floor spots when the shop is clean.
	if not manager.floor_spots.is_empty():
		_destination = manager.floor_spots.pick_random().position
		path = nav.route(global_position, _destination, self)
		path_index = 0; _revision = nav.revision

func _point(record: Dictionary) -> Vector3:
	var p: Array = record.position
	return Vector3(p[0], global_position.y, p[2])

func _clear_target() -> void:
	target_id = ""; path.clear(); path_index = 0; _cleaning = false
