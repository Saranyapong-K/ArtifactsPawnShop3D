extends Node3D
## Plug final models into the exported scenes; markers control world locations.
const TargetScript = preload("res://scripts/cleaning_target.gd")
const PlaceholderScript = preload("res://scripts/cleaning_placeholder.gd")
const HUDScene = preload("res://ui/cleaning_hud.tscn")
const RobotScript = preload("res://scripts/roomba.gd")
@export var roomba_model: PackedScene
@export var rubbish_models: Array[PackedScene] = []
@export var spill_model: PackedScene
@export var dust_model: PackedScene
@export var broom_model: PackedScene
@export var mop_model: PackedScene
@export var mop_used_model: PackedScene
@export var mop_dirty_model: PackedScene
@export var feather_duster_model: PackedScene
@export var trash_bag_models: Array[PackedScene] = []
@export var dumpster_model: PackedScene
@export_range(10, 300) var min_mess_minutes := 80
@export_range(10, 300) var max_mess_minutes := 140
@export_range(1, 4, 0.1) var cleaning_reach := 2.2
var player: Node3D
var placement: Node3D
var game_ui: CanvasLayer
var day_manager: Node
var held_tool := ""
var held_visual: Node3D
var targets: Dictionary = {}
var tool_targets: Dictionary = {}
var floor_spots: Array[Dictionary] = []
var surfaces: Dictionary = {}
var prompt: Label
var holding_label: Label
var hud: CanvasLayer
var bag_target: Area3D
var dumpster_target: Area3D
var _active_target: Area3D
var _cleaning_pivot: Node3D
var wash_target: Area3D
var dumpster_arrow_point := Vector3.ZERO
var held_base_position := Vector3.ZERO
var held_base_rotation := Vector3.ZERO
var walk_bob := 0.0
var robot: Node3D

func _ready() -> void:
	add_to_group("cleaning_manager")
	_collect_floor_spots()
	_discover_surfaces()
	_build_tools()
	_build_hud()
	var state: CleaningState = GameState.cleaning
	if not state.initialized:
		for index in mini(5, floor_spots.size()):
			var spot := floor_spots[index]
			var kind: String = "spill" if index >= 3 else "rubbish"
			if not spot.kind.is_empty(): kind = spot.kind
			state.add_mess(kind, spot.id, spot.position, index % 3)
		if not surfaces.is_empty():
			var key: String = surfaces.keys()[0]
			state.add_mess("dust", key, surfaces[key])
		state.initialized = true
	if GameState.day > 1: state.broom_available = true
	_day_schedule()
	_refresh_targets()
	GameState.changed.connect(_refresh_targets)
	GameState.time_changed.connect(_on_time_changed)
	GameState.day_started.connect(_on_day_started)
	GameState.changed.emit()

func _collect_floor_spots() -> void:
	# User markers take precedence over the temporary floor layout.
	var main := get_parent()
	for node in main.find_children("*", "Marker3D", true, false):
		var kind := ""
		if node.is_in_group("rubbish_spots") or String(node.name).begins_with("RubbishSpot") or String(node.name).begins_with("TrashSpot"): kind = "rubbish"
		if node.is_in_group("spill_spots") or String(node.name).begins_with("SpillSpot") or String(node.name).begins_with("TrashDrink"): kind = "spill"
		if not kind.is_empty():
			floor_spots.append({"id": String(main.get_path_to(node)), "position": node.global_position, "kind": kind})
	if floor_spots.is_empty():
		for node: Marker3D in $FloorSpots.get_children():
			floor_spots.append({"id": String(get_path_to(node)), "position": node.global_position, "kind": ""})

func _discover_surfaces() -> void:
	surfaces.clear()
	for node: Marker3D in $DustSurfaces.get_children(): surfaces[String(get_path_to(node))] = node.global_position
	for node in get_tree().get_nodes_in_group("cleaning_surfaces"):
		if node is Node3D and get_parent().is_ancestor_of(node):
			surfaces["surface:" + String(get_parent().get_path_to(node))] = node.global_position
	if placement:
		for item in placement.items.values():
			if not is_instance_valid(item) or not item.get_meta("is_furniture", false): continue
			var bounds: AABB = item.global_transform * ArtifactVisual.local_bounds(item.visual)
			if bounds.size.y > 0.01:
				surfaces["furniture:" + item.artifact.id] = Vector3(bounds.get_center().x, bounds.end.y + 0.015, bounds.get_center().z)
	for key in surfaces:
		if not GameState.cleaning.dusted_days.has(key): GameState.cleaning.dusted_days[key] = GameState.day

func _marker(name: String) -> Vector3:
	var aliases: Array = {"DumpsterSpot":["DumpsterSpot","Dumbster spot"],"MopWashSpot":["MopWashSpot","MopCleanerSpot2","MopCleanerSpot"]}.get(name,[name])
	var user_marker: Marker3D
	for alias in aliases:
		user_marker = _user_marker(alias)
		if user_marker: break
	return user_marker.global_position if user_marker else ($ToolSpots.get_node(name) as Marker3D).global_position

func _user_marker(name: String) -> Marker3D:
	for marker in get_parent().find_children(name,"Marker3D",true,false):
		if not is_ancestor_of(marker): return marker
	return null

func _snap_home(point: Vector3) -> Vector3:
	var query:=PhysicsRayQueryParameters3D.create(point+Vector3.UP*0.35,point-Vector3.UP*0.6)
	if player is CollisionObject3D: query.exclude=[player.get_rid()]
	var hit:=get_world_3d().direct_space_state.intersect_ray(query)
	if not hit.is_empty() and (hit.normal as Vector3).dot(Vector3.UP)>0.9: point.y=hit.position.y+0.012
	return point

func _build_tools() -> void:
	for tool in ["broom", "mop", "feather_duster"]:
		var marker_name: String = {"broom": "BroomSpot", "mop": "MopSpot", "feather_duster": "DusterSpot"}[tool]
		var target := _target("tool", _snap_home(_marker(marker_name)), _visual(tool))
		target.tool_id = tool
		if tool=="mop": target.set_meta("uses",GameState.cleaning.mop_uses)
		tool_targets[tool] = target
	wash_target = _target("wash", _marker("MopWashSpot"), null)
	bag_target = _target("trash_bag", _marker("TrashBagSpot"), _visual("trash_bag"))
	bag_target.set_meta("load",GameState.cleaning.bag_load)
	if not _user_marker("TrashBagSpot"): bag_target.global_position = _snap_home(_marker("BroomSpot")+Vector3(-0.65,0,0))
	dumpster_arrow_point = _marker("DumpsterSpot")+Vector3.UP*1.3
	var real_dumpster := get_parent().find_child("Dumpster",true,false) as MeshInstance3D
	dumpster_target = _target("dumpster",_marker("DumpsterSpot"),null if real_dumpster else _visual("dumpster"))
	if real_dumpster:
		var b: AABB = real_dumpster.global_transform * real_dumpster.get_aabb()
		dumpster_target.global_position = Vector3(b.get_center().x,b.position.y,b.get_center().z)
		var collision := dumpster_target.get_node("InteractionCollision") as CollisionShape3D
		(collision.shape as BoxShape3D).size = b.size+Vector3.ONE*0.05
		collision.position.y = b.size.y*0.5

func _visual(kind: String, variant: int = 0) -> Node3D:
	var model: PackedScene
	match kind:
		"rubbish":
			if not rubbish_models.is_empty(): model = rubbish_models[variant % rubbish_models.size()]
		"spill": model = spill_model
		"dust": model = dust_model
		"broom": model = broom_model
		"mop":
			model = mop_dirty_model if GameState.cleaning.mop_uses >= 4 and mop_dirty_model else (mop_used_model if GameState.cleaning.mop_uses >= 2 and mop_used_model else mop_model)
		"feather_duster": model = feather_duster_model
		"trash_bag":
			if not trash_bag_models.is_empty(): model = trash_bag_models[clampi(GameState.cleaning.bag_load - 1, 0, trash_bag_models.size() - 1)]
		"dumpster": model = dumpster_model
	if model:
		var node := model.instantiate() as Node3D
		if node:
			return CleaningVisual.prepare(node,kind,variant,GameState.cleaning.mop_uses,GameState.cleaning.bag_load)
	var placeholder: Node3D = PlaceholderScript.new()
	placeholder.kind = kind
	placeholder.variant = variant
	placeholder.dirt_level = GameState.cleaning.mop_uses
	placeholder.bag_load = maxi(1, GameState.cleaning.bag_load)
	placeholder.build()
	return placeholder

func _tint_mop(node: Node3D) -> void:
	if GameState.cleaning.mop_uses < 2: return
	var head := node.find_child("MopHead", true, false)
	var part: Node = head if head else node
	var meshes: Array[Node] = part.find_children("*", "MeshInstance3D", true, false)
	if part is MeshInstance3D: meshes.append(part)
	var tint := Color("242624") if GameState.cleaning.mop_uses >= 4 else Color("888266")
	for mesh: MeshInstance3D in meshes:
		if not mesh.mesh: continue
		for surface in mesh.mesh.get_surface_count():
			var original := mesh.get_active_material(surface)
			if original is StandardMaterial3D:
				var material := original.duplicate() as StandardMaterial3D
				material.albedo_color *= tint
				mesh.set_surface_override_material(surface, material)

func _target(kind: String, point: Vector3, visual: Node3D) -> Area3D:
	var target: Area3D = TargetScript.new()
	target.kind = kind
	target.manager = self
	target.collision_layer = 1
	target.collision_mask = 0
	add_child(target)
	target.global_position = point
	var collision := CollisionShape3D.new()
	collision.name="InteractionCollision"
	var box := BoxShape3D.new()
	box.size = Vector3(0.45, 0.18, 0.45) if kind in ["rubbish", "spill", "dust"] else Vector3(0.3, 0.85, 0.3)
	if kind == "dumpster": box.size = Vector3(0.95, 0.85, 0.65)
	if kind == "trash_bag": box.size = Vector3(0.45, 0.6, 0.45)
	if kind == "wash": box.size = Vector3(0.95,1.05,0.7)
	if visual and visual.has_meta("bounds"):
		var bounds: AABB = visual.get_meta("bounds")
		box.size = bounds.size.max(Vector3(0.22,0.16,0.22))+Vector3.ONE*0.04
	collision.shape = box
	collision.position.y = box.size.y * 0.5
	target.add_child(collision)
	if visual:
		target.add_child(visual)
		target.set_meta("visual", visual)
	return target

func _replace_visual(target: Area3D, kind: String) -> void:
	var previous: Node = target.get_meta("visual", null)
	if previous and is_instance_valid(previous):
		_retire_visual(previous)
	var visual := _visual(kind)
	target.add_child(visual)
	target.set_meta("visual", visual)

func _retire_visual(visual: Node3D) -> void:
	# Let the renderer finish material updates before releasing imported meshes.
	visual.hide()
	await get_tree().process_frame
	if is_instance_valid(visual): visual.queue_free()

func _refresh_targets() -> void:
	_sync_robot.call_deferred()
	_discover_surfaces()
	var records: Array[Dictionary] = GameState.cleaning.mess
	var live := {}
	for record in records:
		live[record.id] = true
		var point := Vector3(float(record.position[0]), float(record.position[1]), float(record.position[2]))
		if record.kind == "dust" and surfaces.has(record.spot): point = surfaces[record.spot]
		for spot in floor_spots:
			if spot.id == record.spot: point = spot.position; break
		record.position = [point.x, point.y, point.z]
		if not targets.has(record.id):
			var target := _target(record.kind, point, _visual(record.kind, int(record.variant)))
			target.rotation.y = float(record.get("rotation",0.0))
			target.record_id = record.id
			targets[record.id] = target
		else: targets[record.id].global_position = point
	for id in targets.keys():
		if not live.has(id):
			targets[id].collision_layer = 0
			targets[id].queue_free()
			targets.erase(id)
	for tool in tool_targets:
		var available: bool = GameState.owned_items.get(tool, false) or (tool == "broom" and GameState.cleaning.broom_available)
		tool_targets[tool].visible = available and held_tool != tool
		tool_targets[tool].collision_layer = 1 if tool_targets[tool].visible else 0
	var mop: Area3D = tool_targets.get("mop")
	if mop and int(mop.get_meta("uses", -1)) != GameState.cleaning.mop_uses:
		if mop_used_model or mop_dirty_model: _replace_visual(mop,"mop")
		else: CleaningVisual.set_mop_dirt(mop.get_meta("visual"),GameState.cleaning.mop_uses)
		mop.set_meta("uses", GameState.cleaning.mop_uses)
	if bag_target:
		bag_target.visible = GameState.cleaning.bag_load > 0 and held_tool != "trash_bag"
		bag_target.collision_layer = 1 if bag_target.visible else 0
		if int(bag_target.get_meta("load", -1)) != GameState.cleaning.bag_load:
			if trash_bag_models.size()>1: _replace_visual(bag_target,"trash_bag")
			else:
				var visual: Node3D=bag_target.get_meta("visual")
				CleaningVisual.set_bag_fill(visual,GameState.cleaning.bag_load)
				var bounds:=ArtifactVisual.local_bounds(visual)
				var collision:=bag_target.get_node("InteractionCollision") as CollisionShape3D
				(collision.shape as BoxShape3D).size=bounds.size+Vector3.ONE*0.04
				collision.position.y=bounds.size.y*0.5
			bag_target.set_meta("load", GameState.cleaning.bag_load)
	_update_held_appearance()

func _day_schedule() -> void:
	var state: CleaningState = GameState.cleaning
	if state.schedule_day != GameState.day:
		state.schedule_day = GameState.day
		state.next_mess_minute = GameState.time_minutes + randi_range(min_mess_minutes, maxi(min_mess_minutes, max_mess_minutes))
	_discover_surfaces()
	for key in surfaces:
		if GameState.day - int(state.dusted_days[key]) >= CleaningState.DUST_DAYS:
			state.add_mess("dust", key, surfaces[key])

func _on_day_started(_day: int) -> void:
	put_tool_away()
	_day_schedule()
	_refresh_targets()
	GameState.changed.emit()

func _on_time_changed(hour: int, minute: int) -> void:
	var now := hour * 60 + minute
	var state: CleaningState = GameState.cleaning
	if now >= 1230 or GameState.failed or now < state.next_mess_minute: return
	if state.schedule_day != GameState.day: _day_schedule()
	var free: Array[Dictionary] = []
	for spot in floor_spots:
		if not state.occupied(spot.id): free.append(spot)
	if not free.is_empty():
		var spot: Dictionary = free.pick_random()
		var kind: String = spot.kind if not spot.kind.is_empty() else ("rubbish" if randf() < 0.65 else "spill")
		state.add_mess(kind, spot.id, spot.position, randi_range(0, 2))
	state.next_mess_minute = now + randi_range(min_mess_minutes, maxi(min_mess_minutes, max_mess_minutes))
	GameState.changed.emit()

func interact_target(target: Area3D, actor: Node) -> void:
	if actor != player or not player or not bool(player.get("controls_enabled")) or GameState.failed: return
	# Player's normal ray limits reach; retain a guard for direct calls/signals.
	if player.global_position.distance_to(target.global_position) > 3.5: return
	match target.kind:
		"tool":
			if target.tool_id == "broom" and not GameState.owned_items.get("broom", false):
				if not GameState.cleaning.broom_available: return
				if GameState.purchase(DayQueue.broom_offer().artifact, 20):
					hud.flash("20 G")
				else: game_ui.show_notice("You need 20 G to buy the broom.")
				return
			hold_tool(target.tool_id)
		"wash":
			if held_tool != "mop": hud.flash("Use mop")
			else: start_cleaning(target)
		"trash_bag":
			hold_tool("trash_bag")
		"dumpster":
			if held_tool != "trash_bag": hud.flash("Bring bag")
			elif GameState.cleaning.empty_bag():
				put_tool_away()
				GameState.changed.emit()
		_:
			start_cleaning(target)

func is_cleaning() -> bool:
	return _active_target != null and is_instance_valid(_active_target)

func start_cleaning(target: Area3D) -> bool:
	if not player or player.global_position.distance_to(target.global_position)>cleaning_reach: return false
	var allowed: Dictionary = {"ok": held_tool == "mop", "message": "Hold the mop to wash it."} if target.kind == "wash" else GameState.cleaning.can_clean(target.record_id, held_tool)
	if not allowed.ok:
		if held_tool=="mop" and GameState.cleaning.mop_uses>=4 and target.kind!="wash":
			hud.flash("Too dirty! Wash the mop inside the toilet")
			if player.has_method("shake_camera"): player.shake_camera()
		elif held_tool=="broom" and GameState.cleaning.bag_load>=4: hud.flash("Take the trash out first")
		else: hud.flash("Wrong tool")
		return false
	if not held_visual: return false
	stop_cleaning()
	_active_target = target
	if not _cleaning_pivot:
		_cleaning_pivot = Node3D.new()
		_cleaning_pivot.name = "ActiveCleaningTool"
		add_child(_cleaning_pivot)
	_cleaning_pivot.transform = Transform3D.IDENTITY
	_cleaning_pivot.global_position = target.global_position
	_cleaning_pivot.show()
	held_visual.reparent(_cleaning_pivot, false)
	held_visual.transform = Transform3D.IDENTITY
	CleaningVisual.held_depth(held_visual,false)
	_animate_cleaning(_progress_seconds())
	return true

func _progress_seconds() -> float:
	if not is_cleaning(): return 0.0
	if _active_target.kind == "wash": return GameState.cleaning.mop_wash_progress
	return float(GameState.cleaning.get_mess(_active_target.record_id).get("progress", 0.0))

func _animate_cleaning(seconds: float) -> void:
	if not is_cleaning() or not _cleaning_pivot: return
	_cleaning_pivot.global_position = _active_target.global_position + Vector3.UP * 0.01
	var sweep := sin(seconds * TAU * 0.9)
	_cleaning_pivot.rotation = Vector3(0, sweep * 0.6, sweep * 0.12)
	if held_tool == "feather_duster":
		_cleaning_pivot.rotation = Vector3(0, 0, sweep * 0.65)
		_cleaning_pivot.position.x += sweep * 0.10
	hud.show_progress("Wash mop" if _active_target.kind == "wash" else _active_target.kind.capitalize(), seconds)

func advance_cleaning(seconds: float, require_focus: bool = true) -> void:
	if not is_cleaning(): return
	if not player or not bool(player.get("controls_enabled")) or GameState.failed or get_tree().paused or player.global_position.distance_to(_active_target.global_position) > cleaning_reach:
		stop_cleaning(); return
	if GameState.clock_running and GameState.is_time_paused(): stop_cleaning(); return
	if require_focus:
		# Once started, aim is free; only holding E and staying nearby matter.
		if not Input.is_action_pressed("interact") or Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
			stop_cleaning(); return
	var result: Dictionary = GameState.cleaning.advance_wash(seconds) if _active_target.kind == "wash" else GameState.cleaning.advance(_active_target.record_id, held_tool, seconds, GameState.day)
	if not result.ok:
		stop_cleaning()
		if result.message=="Too dirty": hud.flash("Too dirty! Wash the mop inside the toilet")
		return
	if result.completed:
		stop_cleaning()
		var sfx := get_node_or_null("/root/Sfx")
		if sfx: sfx.play("clean")
		GameState.changed.emit()
	else: _animate_cleaning(float(result.progress) * CleaningState.CLEAN_SECONDS)

func stop_cleaning() -> void:
	_active_target = null
	if hud: hud.hide_progress()
	if _cleaning_pivot: _cleaning_pivot.hide()
	if held_visual and is_instance_valid(held_visual) and player and is_instance_valid(player) and player.get("camera"):
		var camera: Camera3D = player.get("camera")
		if held_visual.get_parent() != camera:
			held_visual.reparent(camera, false)
			CleaningVisual.held_depth(held_visual,true)
		_set_held_pose()

func _set_held_pose() -> void:
	if not held_visual: return
	held_base_position = Vector3(0.34,-0.65,-0.95)
	held_base_rotation = Vector3(-0.20,-0.15,-0.22)
	if held_tool=="feather_duster": held_base_position=Vector3(0.30,-0.38,-0.65)
	if held_tool=="trash_bag": held_base_position=Vector3(0.34,-0.52,-0.90)
	held_visual.position=held_base_position
	held_visual.rotation=held_base_rotation

func _update_held_appearance() -> void:
	if not held_visual or not is_instance_valid(held_visual): return
	var appearance: int = GameState.cleaning.mop_uses if held_tool == "mop" else GameState.cleaning.bag_load
	if held_tool not in ["mop", "trash_bag"] or int(held_visual.get_meta("appearance", -1)) == appearance: return
	if held_tool=="mop" and not mop_used_model and not mop_dirty_model:
		CleaningVisual.set_mop_dirt(held_visual,appearance)
		held_visual.set_meta("appearance",appearance)
		return
	if held_tool=="trash_bag" and trash_bag_models.size()<=1:
		CleaningVisual.set_bag_fill(held_visual,appearance)
		held_visual.set_meta("appearance",appearance)
		return
	var parent := held_visual.get_parent()
	var pose := held_visual.transform
	_retire_visual(held_visual)
	held_visual = _visual(held_tool)
	parent.add_child(held_visual)
	held_visual.transform = pose
	held_visual.set_meta("appearance", appearance)
	CleaningVisual.held_depth(held_visual,not is_cleaning())

func hold_tool(tool: String) -> bool:
	var owned: bool = GameState.cleaning.bag_load > 0 if tool == "trash_bag" else GameState.owned_items.get(tool, false)
	if not owned or not held_tool.is_empty():
		if hud: hud.flash("Hands full")
		return false
	if placement and placement.held:
		if hud: hud.flash("Hands full")
		return false
	if not player or not player.get("camera"): return false
	held_tool = tool
	held_visual = _visual(tool)
	if tool in ["mop","trash_bag"]: held_visual.set_meta("appearance",GameState.cleaning.mop_uses if tool=="mop" else GameState.cleaning.bag_load)
	(player.get("camera") as Camera3D).add_child(held_visual)
	_set_held_pose()
	CleaningVisual.held_depth(held_visual,true)
	_refresh_targets()
	return true

func put_tool_away() -> void:
	stop_cleaning()
	if held_visual and is_instance_valid(held_visual): held_visual.queue_free()
	held_visual = null
	held_tool = ""
	_refresh_targets()

func _unhandled_input(event: InputEvent) -> void:
	if not held_tool.is_empty() and event is InputEventKey and event.pressed and not event.echo and event.physical_keycode == KEY_Q:
		if is_cleaning(): stop_cleaning()
		else: put_tool_away()
		get_viewport().set_input_as_handled()

func _build_hud() -> void:
	hud = HUDScene.instantiate()
	add_child(hud)
	prompt = hud.prompt
	holding_label = hud.holding_label

func _process(delta: float) -> void:
	advance_cleaning(delta)
	var active: bool = player and bool(player.get("controls_enabled")) and not GameState.failed
	if held_visual: held_visual.visible = active
	if not holding_label: return
	holding_label.text = "Press Q to drop"
	holding_label.visible = active and not held_tool.is_empty()
	if held_visual and active and not is_cleaning():
		var velocity: Variant = player.get("velocity")
		var walking: float = clampf(Vector2(velocity.x,velocity.z).length()/4.0,0,1) if velocity is Vector3 else 0.0
		var motion: Variant = player.get("view_motion")
		var mouse: Vector2 = motion if motion is Vector2 else Vector2.ZERO
		walk_bob += delta*8.0*walking
		var sway := Vector3(sin(walk_bob)*0.018*walking,-absf(cos(walk_bob))*0.015*walking,0)
		sway += Vector3(-mouse.x*0.0006,mouse.y*0.0005,0)
		held_visual.position = held_visual.position.lerp(held_base_position+sway,1-exp(-delta*12))
		held_visual.rotation = held_visual.rotation.lerp(held_base_rotation+Vector3(-mouse.y*0.001,-mouse.x*0.001,sin(walk_bob)*0.025*walking),1-exp(-delta*12))
	var camera := get_viewport().get_camera_3d()
	hud.update_dumpster(camera,dumpster_arrow_point,active and (held_tool=="trash_bag" or GameState.cleaning.bag_load>=4))
	hud.update_wash(camera,wash_target.global_position+Vector3.UP*1.25,active and GameState.cleaning.mop_uses>=4)
	prompt.text = ""
	for item in tool_targets.values()+targets.values()+[bag_target,wash_target,dumpster_target]:
		if is_instance_valid(item): item.show_prompt(false)
	if not active or not player.get("ray") or Input.mouse_mode != Input.MOUSE_MODE_CAPTURED: return
	var target: Node = player.get_interaction_target()
	if target == null or target.get_script() != TargetScript: return
	if is_cleaning(): return
	target.show_prompt(true)

func _sync_robot() -> void:
	if not is_inside_tree(): return
	if not GameState.owned_items.get("roomba", false):
		if is_instance_valid(robot): robot.queue_free()
		robot = null
		return
	if is_instance_valid(robot) or roomba_model == null: return
	robot = RobotScript.new()
	robot.name = "Roomba"
	robot.manager = self
	robot.model_scene = roomba_model
	add_child(robot)
	var home := _marker("RoombaSpot")
	robot.global_position = home
	var nav := get_tree().get_first_node_in_group("shop_navigation")
	if nav:
		var path: PackedVector3Array = nav.approach_route(home, home, robot)
		if not path.is_empty(): robot.global_position = path[0]
