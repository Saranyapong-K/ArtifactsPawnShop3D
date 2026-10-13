extends Node3D
## Small walkability grid sampled from real physics, including purchased furniture.
const CELL := 0.5
var grid: AStarGrid2D
var origin := Vector2(-9, -7)
var floor_y := -0.02
var dirty := true
var revision := 0
var _graph := AStar3D.new()
var _checked_edges: Dictionary = {}

func _ready() -> void:
	add_to_group("shop_navigation")
	GameState.changed.connect(func(): dirty = true)
	await get_tree().physics_frame
	rebuild()

func rebuild() -> void:
	var main := get_parent()
	var floor_mesh := main.find_child("Floor", true, false) as MeshInstance3D
	var dimensions := Vector2i(40, 36)
	if floor_mesh:
		var b: AABB = floor_mesh.global_transform * floor_mesh.get_aabb()
		origin = Vector2(b.position.x-0.25,b.position.z-0.25)
		floor_y = b.end.y
		dimensions = Vector2i(ceili((b.size.x+0.5)/CELL),ceili((b.size.z+3.5)/CELL))
	grid = AStarGrid2D.new()
	grid.region = Rect2i(Vector2i.ZERO,dimensions)
	grid.cell_size = Vector2(CELL,CELL)
	grid.offset = origin
	grid.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_ONLY_IF_NO_OBSTACLES
	grid.default_compute_heuristic=AStarGrid2D.HEURISTIC_OCTILE
	grid.default_estimate_heuristic=AStarGrid2D.HEURISTIC_OCTILE
	grid.update()
	var excluded: Array[RID] = []
	for actor in get_tree().get_nodes_in_group("shop_visitors")+get_tree().get_nodes_in_group("shop_player"):
		if actor is CollisionObject3D: excluded.append(actor.get_rid())
		for body in actor.find_children("*","CollisionObject3D",true,false): excluded.append(body.get_rid())
	for controller in get_tree().get_nodes_in_group("automatic_doors"):
		for body in controller.door.find_children("*","CollisionObject3D",true,false): excluded.append(body.get_rid())
	var capsule := CapsuleShape3D.new()
	capsule.radius = 0.28
	capsule.height = 1.65
	var space := get_world_3d().direct_space_state
	var walkable: Array[Vector2i] = []
	for x in dimensions.x:
		for z in dimensions.y:
			var point := Vector3(origin.x+x*CELL,floor_y+0.04,origin.y+z*CELL)
			var ray := PhysicsRayQueryParameters3D.create(point+Vector3.UP*0.12,point-Vector3.UP*0.22)
			ray.exclude = excluded
			var hit := space.intersect_ray(ray)
			var blocked := hit.is_empty() or (hit.get("normal",Vector3.ZERO) as Vector3).dot(Vector3.UP)<0.9
			if not blocked:
				var query := PhysicsShapeQueryParameters3D.new()
				query.shape = capsule
				query.transform = Transform3D(Basis.IDENTITY,point+Vector3.UP*0.825)
				query.exclude = excluded
				query.margin = 0.0
				blocked = not space.intersect_shape(query,1).is_empty()
			grid.set_point_solid(Vector2i(x,z),blocked)
			if not blocked: walkable.append(Vector2i(x,z))
	# Grid occupancy alone cannot catch a thin wall between two free points.
	# Keep explicit links so a swept collision can reject just that connection.
	_graph.clear()
	_checked_edges.clear()
	for cell: Vector2i in walkable:
		_graph.add_point(_point_id(cell), Vector3(origin.x + cell.x * CELL, floor_y + 0.015, origin.y + cell.y * CELL))
	for cell: Vector2i in walkable:
		for offset in [Vector2i(1,0), Vector2i(0,1), Vector2i(1,1), Vector2i(-1,1)]:
			var next: Vector2i = cell + offset
			if not grid.is_in_boundsv(next) or grid.is_point_solid(next): continue
			if offset.x != 0 and offset.y != 0:
				if grid.is_point_solid(cell + Vector2i(offset.x,0)) or grid.is_point_solid(cell + Vector2i(0,offset.y)): continue
			_graph.connect_points(_point_id(cell), _point_id(next))
	dirty = false
	revision += 1

func _point_id(cell: Vector2i) -> int:
	return cell.y * grid.region.size.x + cell.x

func _checked_path(a: Vector2i, b: Vector2i, actor: Node3D) -> PackedVector3Array:
	# Validate only links that a route actually needs, then cache until geometry
	# changes. This avoids thousands of physics sweeps every time gold changes.
	for attempt in 256:
		var ids := _graph.get_id_path(_point_id(a), _point_id(b))
		if ids.is_empty(): break
		var valid := true
		for index in range(1, ids.size()):
			var edge := Vector2i(mini(ids[index-1],ids[index]), maxi(ids[index-1],ids[index]))
			if not _checked_edges.has(edge):
				_checked_edges[edge] = motion_clear(_graph.get_point_position(ids[index-1]), _graph.get_point_position(ids[index]), actor)
			if not _checked_edges[edge]:
				_graph.disconnect_points(ids[index-1], ids[index])
				valid = false
				break
		if valid: return _graph.get_point_path(_point_id(a), _point_id(b))
	return PackedVector3Array()

func _motion_exclusions(actor: Node3D = null) -> Array[RID]:
	var excluded: Array[RID] = []
	for node in get_tree().get_nodes_in_group("shop_visitors") + get_tree().get_nodes_in_group("shop_player") + get_tree().get_nodes_in_group("night_intruders"):
		if node is CollisionObject3D: excluded.append(node.get_rid())
		for body in node.find_children("*", "CollisionObject3D", true, false): excluded.append(body.get_rid())
	for controller in get_tree().get_nodes_in_group("automatic_doors"):
		for body in controller.door.find_children("*", "CollisionObject3D", true, false): excluded.append(body.get_rid())
	if actor is CollisionObject3D: excluded.append(actor.get_rid())
	return excluded

func motion_clear(from: Vector3, to: Vector3, actor: Node3D = null, height: float = 1.65, radius: float = 0.28) -> bool:
	var shape := CapsuleShape3D.new()
	shape.radius = radius
	shape.height = height
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = shape
	query.transform = Transform3D(Basis.IDENTITY, from + Vector3.UP * (height * 0.5 + 0.04))
	query.motion = to - from
	query.exclude = _motion_exclusions(actor)
	query.margin = 0.001
	var space := get_world_3d().direct_space_state
	if not space.intersect_shape(query, 1).is_empty(): return false
	var fractions := space.cast_motion(query)
	return fractions.size() > 0 and fractions[0] >= 0.999

func _nearest(point: Vector3) -> Vector2i:
	var cell := Vector2i(roundi((point.x-origin.x)/CELL),roundi((point.z-origin.y)/CELL))
	var best := Vector2i(-999,-999)
	var distance := INF
	for radius in range(5):
		for x in range(-radius,radius+1):
			for z in range(-radius,radius+1):
				var candidate := cell+Vector2i(x,z)
				if not grid.is_in_boundsv(candidate) or grid.is_point_solid(candidate): continue
				var cost := Vector2(candidate-cell).length_squared()
				if cost<distance: distance=cost; best=candidate
		if best.x!=-999: return best
	return best

func route(from: Vector3,to: Vector3,exclude_actor: Node3D=null) -> PackedVector3Array:
	if dirty or grid==null: rebuild()
	var temporarily_blocked: Array[Vector2i] = []
	for actor in get_tree().get_nodes_in_group("shop_visitors"):
		if actor==exclude_actor or actor.get_meta("visit_phase","")!="queued": continue
		var cell := Vector2i(roundi((actor.global_position.x-origin.x)/CELL),roundi((actor.global_position.z-origin.y)/CELL))
		for x in range(-1,2):
			for z in range(-1,2):
				var p := cell+Vector2i(x,z)
				if grid.is_in_boundsv(p) and not grid.is_point_solid(p):
					grid.set_point_solid(p,true)
					_graph.set_point_disabled(_point_id(p),true)
					temporarily_blocked.append(p)
	var a := _nearest(from)
	var b := _nearest(to)
	var result := PackedVector3Array()
	if a.x!=-999 and b.x!=-999:
		var end_point := Vector3(origin.x + b.x * CELL, floor_y + 0.015, origin.y + b.y * CELL)
		if Vector2(end_point.x - to.x, end_point.z - to.z).length() <= 0.45:
			result = _checked_path(a,b,exclude_actor)
	for p in temporarily_blocked:
		grid.set_point_solid(p,false)
		_graph.set_point_disabled(_point_id(p),false)
	return result

func approach_route(from: Vector3, to: Vector3, actor: Node3D = null) -> PackedVector3Array:
	# Intruders/cleaners can stand beside a shelf instead of inside its footprint.
	var direct := route(from, to, actor)
	if not direct.is_empty(): return direct
	for radius in [0.5, 1.0, 1.5]:
		var candidates: Array[Vector3] = []
		for x in [-1, 0, 1]:
			for z in [-1, 0, 1]:
				if x != 0 or z != 0: candidates.append(to + Vector3(x * radius, 0, z * radius))
		candidates.sort_custom(func(a: Vector3, b: Vector3): return from.distance_squared_to(a) < from.distance_squared_to(b))
		for point in candidates:
			var result := route(from, point, actor)
			if not result.is_empty(): return result
	return PackedVector3Array()
