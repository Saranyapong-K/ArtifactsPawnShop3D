extends Node3D
## Uses the shop's real horizontal collision surfaces, with multi-cell occupancy.

signal notice(text: String)
const CELL: float = ArtifactVisual.CELL_SIZE
const RelicItemScript = preload("res://scripts/relic_item.gd")
const FurnitureItemScript = preload("res://scripts/furniture_item.gd")
var player: Node3D
var items: Dictionary = {}
var held: Node3D
var ghost: Node3D
var footprint_mesh: MeshInstance3D
var _previous: Dictionary = {}
var _rotation: int = 0
var _candidate: Vector3
var _valid: bool = false
var _surface: String = ""
var _height_cache: Dictionary = {}

func _ready() -> void:
	add_to_group("artifact_placement")
	GameState.changed.connect(sync_inventory)

func sync_inventory() -> void:
	for id in items.keys():
		var item: Node3D = items[id]
		var missing: bool = GameState.get_furniture(String(id)).is_empty() if item.get_meta("is_furniture", false) else GameState.get_artifact(String(id)) == null
		if missing:
			if held == items[id]:
				_clear_ghost()
				held = null
			(items[id] as Node).queue_free()
			items.erase(id)

func spawn_artifact(artifact: ArtifactData, default_position: Vector3) -> Node3D:
	if items.has(artifact.id):
		return items[artifact.id] as Node3D
	var item: Node3D = RelicItemScript.new()
	add_child(item)
	item.setup_artifact(artifact)
	items[artifact.id] = item
	if artifact.placement.has("position"):
		var position_data: Array = artifact.placement["position"]
		item.global_position = Vector3(float(position_data[0]), float(position_data[1]), float(position_data[2]))
		item.rotation.y = int(artifact.placement.get("rotation", 0)) * PI * 0.5
	else:
		item.global_position = _find_free_spot(default_position, artifact, artifact.id)
		_record(item, 0, "counter")
	return item

func restore_stock(default_position: Vector3) -> void:
	for artifact: ArtifactData in GameState.inventory:
		spawn_artifact(artifact, default_position)

func spawn_furniture(record: Dictionary, default_position: Vector3) -> Node3D:
	var id: String = String(record.get("id", ""))
	if items.has(id):
		return items[id] as Node3D
	var item: Node3D = FurnitureItemScript.new()
	add_child(item)
	item.setup_furniture(record)
	items[id] = item
	if item.artifact.placement.has("position"):
		var position_data: Array = item.artifact.placement["position"]
		item.global_position = Vector3(float(position_data[0]), float(position_data[1]), float(position_data[2]))
		item.rotation.y = int(item.artifact.placement.get("rotation", 0)) * PI * 0.5
	else:
		item.global_position = _find_free_spot(default_position, item.artifact, id)
		_record(item, 0, "floor")
	item.adapt_legacy_contents(GameState.inventory, items)
	return item

func restore_furniture(default_position: Vector3 = Vector3(1.6, 0.1, 1.6)) -> void:
	for record: Dictionary in GameState.furniture:
		spawn_furniture(record, default_position)

func pick_up(item: Node3D) -> void:
	var cleaning: Node = get_tree().get_first_node_in_group("cleaning_manager")
	if cleaning and not cleaning.held_tool.is_empty():
		notice.emit("Put your cleaning tool away with Q first.")
		return
	if held or Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		return
	if item.get_meta("is_furniture", false) and _has_displayed_artifacts(item):
		notice.emit("Move the artifacts off this furniture first.")
		return
	held = item
	_previous = item.artifact.placement.duplicate(true)
	_rotation = int(_previous.get("rotation", 0))
	item.visible = false
	_set_collision(item, false)
	item.artifact.placement["placed"] = false
	item.artifact.placement["held"] = true
	_sync_record(item)
	var furniture: bool = item.get_meta("is_furniture", false)
	ghost = FurnitureItemScript.create_visual(item.artifact) if furniture else ArtifactVisual.create(item.artifact, 0.8, 0.84, false)
	add_child(ghost)
	footprint_mesh = MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = Vector3(item.artifact.grid_size.x * CELL, 0.012, item.artifact.grid_size.y * CELL)
	footprint_mesh.mesh = mesh
	ghost.add_child(footprint_mesh)
	notice.emit("%s: place  •  %s: rotate  •  Q: cancel" % [GameSettings.key_name("interact"), GameSettings.key_name("rotate_item")])

func _unhandled_input(event: InputEvent) -> void:
	if not held or Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		return
	if event.is_action_pressed("rotate_item"):
		_rotation = (_rotation + 1) % 4
		get_viewport().set_input_as_handled()
	elif event is InputEventKey and event.pressed and event.physical_keycode == KEY_Q:
		cancel_placement()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("interact"):
		get_viewport().set_input_as_handled()
		if _valid:
			held.global_position = _candidate
			held.rotation.y = _rotation * PI * 0.5
			_record(held, _rotation, _surface)
			held.visible = true
			_set_collision(held, true)
			held = null
			_clear_ghost()
			GameState.changed.emit()
			notice.emit("Placed.")
		else:
			notice.emit("That footprint needs a clear, supported surface.")

func _physics_process(_delta: float) -> void:
	if not held or not is_instance_valid(held) or not ghost:
		return
	var camera: Camera3D = get_viewport().get_camera_3d()
	if camera == null:
		return
	var query := PhysicsRayQueryParameters3D.create(camera.global_position, camera.global_position - camera.global_basis.z * 4.0)
	query.exclude = _excluded_rids(held.artifact.id)
	var hit: Dictionary = get_world_3d().direct_space_state.intersect_ray(query)
	ghost.visible = not hit.is_empty()
	_valid = false
	if hit.is_empty():
		return
	var hit_position: Vector3 = hit["position"]
	var candidate := resolve_candidate(held.artifact,hit_position,_rotation,held.artifact.id,hit["collider"])
	_candidate = candidate.position
	_surface = String((hit["collider"] as Node).get_path())
	_valid = (hit["normal"] as Vector3).dot(Vector3.UP) > 0.85 and candidate.valid
	ghost.global_position = _candidate
	ghost.rotation.y = _rotation * PI * 0.5
	ArtifactVisual.tint_hologram(ghost, _valid)
	var base_material := StandardMaterial3D.new()
	base_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	base_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	base_material.albedo_color = Color(0.15, 1, 0.35, 0.6) if _valid else Color(1, 0.15, 0.1, 0.6)
	footprint_mesh.material_override = base_material

func resolve_candidate(artifact: ArtifactData,hit: Vector3,rotation: int,excluded_id: String="",collider: Node=null) -> Dictionary:
	var size: Vector2i=artifact.grid_size if rotation%2==0 else Vector2i(artifact.grid_size.y,artifact.grid_size.x)
	var anchor := Vector2.ZERO
	var patch := Rect2()
	var node := collider
	var surfaces: Array = []
	while node:
		if node.has_method("get_placement_patches"):
			surfaces = node.get_placement_patches()
			break
		elif node.has_meta("placement_patches"):
			surfaces = node.get_meta("placement_patches")
			break
		node=node.get_parent()
	for surface: Dictionary in surfaces:
		var rect: Rect2=surface.rect
		if absf(float(surface.y)-hit.y)<0.04 and rect.grow(0.015).has_point(Vector2(hit.x,hit.z)) and (patch.size==Vector2.ZERO or rect.get_area()>patch.get_area()): patch=rect
	if patch.size!=Vector2.ZERO:
		# Centre complete cells on the usable board, rather than against one edge.
		var cells := ((patch.size + Vector2.ONE * 0.07) / CELL).floor().max(Vector2(size))
		anchor=patch.get_center()-cells*CELL*0.5+Vector2(size)*CELL*0.5
	var point:=Vector2(hit.x,hit.z)
	var snapped:=anchor+((point-anchor)/CELL).round()*CELL
	var candidates: Array[Vector3]=[]
	for x in range(-1,2):
		for z in range(-1,2):
			var p:=snapped+Vector2(x,z)*CELL
			if patch.size!=Vector2.ZERO:
				var half:=Vector2(size)*CELL*0.5
				if patch.size.x<half.x*2-0.07 or patch.size.y<half.y*2-0.07: continue
				p=p.clamp(patch.position+half-Vector2.ONE*0.025,patch.end-half+Vector2.ONE*0.025)
			if p.distance_to(point)<=CELL*1.15: candidates.append(Vector3(p.x,hit.y+0.012,p.y))
	candidates.sort_custom(func(a: Vector3,b: Vector3):return a.distance_squared_to(hit)<b.distance_squared_to(hit))
	for p in candidates:
		if can_place(artifact,p,rotation,excluded_id): return {"position":p,"valid":true}
	return {"position":Vector3(snapped.x,hit.y+0.012,snapped.y),"valid":false}

func can_place(artifact: ArtifactData, position: Vector3, rotation: int, excluded_id: String = "") -> bool:
	var furniture: bool = items.has(excluded_id) and items[excluded_id].get_meta("is_furniture", false)
	if furniture and position.y > 0.35:
		return false
	var size: Vector2i = artifact.grid_size if rotation % 2 == 0 else Vector2i(artifact.grid_size.y, artifact.grid_size.x)
	var proposed := Rect2(Vector2(position.x, position.z) - Vector2(size) * CELL * 0.5, Vector2(size) * CELL * 0.98)
	for id in items:
		if String(id) == excluded_id:
			continue
		var other: Node3D = items[id]
		if not is_instance_valid(other) or not other.artifact.placement.get("placed", true):
			continue
		# The cabinet reserves floor cells; its actual boards support artifacts.
		if not furniture and other.get_meta("is_furniture", false) and position.y > other.global_position.y + 0.04:
			continue
		if absf(other.global_position.y - position.y) > 0.35:
			continue
		var other_size: Vector2i = other.artifact.grid_size
		if int(other.artifact.placement.get("rotation", 0)) % 2:
			other_size = Vector2i(other_size.y, other_size.x)
		var occupied := Rect2(Vector2(other.global_position.x, other.global_position.z) - Vector2(other_size) * CELL * 0.5, Vector2(other_size) * CELL * 0.98)
		if proposed.intersects(occupied):
			return false
	# Every occupied cell and the perimeter need support at one level.
	var samples: Array[Vector2] = [Vector2.ZERO]
	for x in range(size.x):
		for z in range(size.y):
			samples.append(Vector2((x - (size.x - 1) * 0.5) * CELL, (z - (size.y - 1) * 0.5) * CELL))
	for x_sign in [-1.0, 1.0]:
		for z_sign in [-1.0, 1.0]:
			samples.append(Vector2(x_sign * (size.x * CELL * 0.5 - 0.035), z_sign * (size.y * CELL * 0.5 - 0.035)))
	for sample: Vector2 in samples:
		var point := position + Vector3(sample.x, 0, sample.y)
		var query := PhysicsRayQueryParameters3D.create(point + Vector3.UP * 0.12, point - Vector3.UP * 0.18)
		query.exclude = _excluded_rids(excluded_id)
		var support: Dictionary = get_world_3d().direct_space_state.intersect_ray(query)
		if support.is_empty() or (support["normal"] as Vector3).dot(Vector3.UP) < 0.85:
			return false
		if absf((support["position"] as Vector3).y - (position.y - 0.012)) > 0.035:
			return false
		if furniture and _is_furniture_surface(support["collider"] as Node):
			return false
	# Check the visible item's height against shelf uprights and boards above it.
	var height := _item_height(artifact,excluded_id)
	var box := BoxShape3D.new()
	box.size=Vector3(size.x*CELL*0.82,maxf(0.035,height-0.035),size.y*CELL*0.82)
	var clearance := PhysicsShapeQueryParameters3D.new()
	clearance.shape=box
	clearance.transform=Transform3D(Basis.IDENTITY,position+Vector3.UP*(box.size.y*0.5+0.025))
	clearance.exclude=_excluded_rids(excluded_id,false)
	clearance.margin=0.0
	return get_world_3d().direct_space_state.intersect_shape(clearance,1).is_empty()

func _item_height(artifact: ArtifactData,id: String) -> float:
	if items.has(id) and items[id].visual: return float(items[id].visual.get_meta("height",0.25))
	var key:=artifact.model_path+str(artifact.grid_size)
	if not _height_cache.has(key):
		var visual:=ArtifactVisual.create(artifact,0.8,0.84,false)
		_height_cache[key]=float(visual.get_meta("height",0.25))
		visual.free()
	return _height_cache[key]

func _excluded_rids(excluded_id: String = "",ignore_visitors: bool=true) -> Array[RID]:
	var excluded: Array[RID] = []
	if player is CollisionObject3D:
		excluded.append((player as CollisionObject3D).get_rid())
	for item: Node3D in items.values():
		if is_instance_valid(item) and (not item.get_meta("is_furniture", false) or item == held or item.artifact.id == excluded_id):
			excluded.append((item as CollisionObject3D).get_rid())
	for actor in get_tree().get_nodes_in_group("night_intruders"):
		if actor is CollisionObject3D:
			excluded.append(actor.get_rid())
	if ignore_visitors:
		for actor in get_tree().get_nodes_in_group("shop_visitors"):
			for body in actor.find_children("*","CollisionObject3D",true,false): excluded.append(body.get_rid())
	return excluded

func _find_free_spot(seed: Vector3, artifact: ArtifactData, excluded_id: String) -> Vector3:
	for row in range(8):
		for column in range(8):
			var point := Vector3(roundf(seed.x / CELL) * CELL + column * CELL, seed.y, roundf(seed.z / CELL) * CELL - row * CELL)
			var query := PhysicsRayQueryParameters3D.create(point + Vector3.UP * 2, point - Vector3.UP * 3)
			query.exclude = _excluded_rids(excluded_id)
			var hit: Dictionary = get_world_3d().direct_space_state.intersect_ray(query)
			if not hit.is_empty():
				point.y = (hit["position"] as Vector3).y + 0.012
				if can_place(artifact, point, 0, excluded_id):
					return point
	return seed + Vector3(float(items.size() % 6) * CELL, 0, floorf(items.size() / 6.0) * CELL)

func cancel_placement() -> void:
	if not held:
		return
	held.artifact.placement = _previous.duplicate(true)
	_sync_record(held)
	held.visible = true
	_set_collision(held, true)
	held = null
	_clear_ghost()
	GameState.changed.emit()

func finish_holding_before_sleep() -> void:
	cancel_placement()

func highlight(id: String, enabled: bool) -> void:
	if items.has(id):
		items[id].set_highlighted(enabled)

func _record(item: Node3D, rotation: int, surface: String) -> void:
	var position: Vector3 = item.global_position
	item.artifact.placement = {"position": [position.x, position.y, position.z], "rotation": rotation, "surface": surface, "placed": true, "held": false}
	_sync_record(item)

func _sync_record(item: Node3D) -> void:
	if item.get_meta("is_furniture", false):
		item.record["placement"] = item.artifact.placement

func _set_collision(item: Node3D, enabled: bool) -> void:
	item.collision_layer = 1 if enabled else 0
	var area: Area3D = item.get_node_or_null("InteractionArea")
	if area:
		area.collision_layer = 1 if enabled else 0

func _is_furniture_surface(node: Node) -> bool:
	while node:
		if node.get_meta("is_furniture", false):
			return true
		node = node.get_parent()
	return false

func _has_displayed_artifacts(furniture: Node3D) -> bool:
	var size: Vector2i = furniture.artifact.grid_size
	if int(furniture.artifact.placement.get("rotation", 0)) % 2:
		size = Vector2i(size.y, size.x)
	var floor_rect := Rect2(Vector2(furniture.global_position.x, furniture.global_position.z) - Vector2(size) * CELL * 0.5, Vector2(size) * CELL)
	var top: float = furniture.global_position.y + float(furniture.visual.get_meta("height", 2.0))
	for item: Node3D in items.values():
		if item.get_meta("is_furniture", false) or not item.artifact.placement.get("placed", true):
			continue
		if item.global_position.y > furniture.global_position.y + 0.04 and item.global_position.y < top + 0.05 and floor_rect.has_point(Vector2(item.global_position.x, item.global_position.z)):
			return true
	return false

func _clear_ghost() -> void:
	if ghost and is_instance_valid(ghost):
		ghost.queue_free()
	ghost = null
	footprint_mesh = null
