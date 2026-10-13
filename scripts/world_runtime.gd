extends Node3D
## Physical fences/terrain; perimeter follows the fences, leaving the road open.
@export var boundary_height := 3.0
@export var opposite_verge := 2.0
var _road: MeshInstance3D
var _fence_bounds: AABB
var _road_bounds: AABB
static var _shapes: Dictionary = {}

func _ready() -> void:
	for title in ["Earth", "Freace", "Plane"]:
		var mesh := find_child(title, true, false) as MeshInstance3D
		if not mesh or not mesh.mesh: continue
		var body := StaticBody3D.new()
		body.name = title + "Collision"
		body.set_meta("world_surface", "road" if title == "Plane" else title.to_lower())
		mesh.add_child(body)
		var shape := CollisionShape3D.new()
		var key := mesh.mesh.get_instance_id()
		if not _shapes.has(key): _shapes[key] = mesh.mesh.create_trimesh_shape()
		shape.shape = _shapes[key]
		body.add_child(shape)
		if title == "Freace": _fence_bounds = mesh.global_transform * mesh.get_aabb()
		if title == "Plane":
			_road = mesh
			_road_bounds = mesh.global_transform * mesh.get_aabb()
	if _fence_bounds.size.x > 0 and _road:
		var rear := _fence_bounds.position.z
		var far := _road_bounds.end.z + opposite_verge
		var left := _fence_bounds.position.x
		var right := _fence_bounds.end.x
		_boundary("LeftFenceAndRoadEdge", Vector3(left, 1, (rear+far)*0.5), Vector3(0.32,boundary_height,far-rear))
		_boundary("RightFenceAndRoadEdge", Vector3(right, 1, (rear+far)*0.5), Vector3(0.32,boundary_height,far-rear))
		_boundary("RearFence", Vector3((left+right)*0.5,1,rear), Vector3(right-left,boundary_height,0.32))
		_boundary("OppositeRoadVerge", Vector3((left+right)*0.5,1,far), Vector3(right-left,boundary_height,0.32))
	await get_tree().physics_frame
	await get_tree().physics_frame
	if is_inside_tree() and _road:
		_road_curbs()
		_shop_apron()

func _boundary(title: String, at: Vector3, size: Vector3) -> void:
	var body := StaticBody3D.new(); body.name = title; add_child(body)
	body.global_position = at
	var collider := CollisionShape3D.new()
	var box := BoxShape3D.new(); box.size = size
	collider.shape = box; body.add_child(collider)

func _ground(at: Vector3) -> Dictionary:
	var query := PhysicsRayQueryParameters3D.create(at + Vector3.UP*3, at - Vector3.UP*2)
	return get_world_3d().direct_space_state.intersect_ray(query)

func _road_curbs() -> void:
	# Invisible shallow ramps bridge the authored raised road curbs for walking.
	# The road itself and the grass still use their exact imported mesh collision.
	var x := _fence_bounds.get_center().x
	var near_edge := INF; var far_edge := -INF
	var z := _road_bounds.position.z
	while z <= _road_bounds.end.z:
		var hit := _ground(Vector3(x,0,z))
		if not hit.is_empty() and hit.collider.get_meta("world_surface", "") == "road":
			near_edge = minf(near_edge, z); far_edge = maxf(far_edge,z)
		z += 0.1
	if not is_finite(near_edge): return
	for edge in [near_edge,far_edge]:
		var direction := -1.0 if edge == near_edge else 1.0
		var points: Array[Vector3] = []
		for sx in [_fence_bounds.position.x+0.2,_fence_bounds.end.x-0.2]:
			var road_hit := _ground(Vector3(sx,0,edge-direction*0.8))
			var grass_hit := _ground(Vector3(sx,0,edge+direction*2.0))
			var road_y: float = float(road_hit.position.y) + 0.025 if not road_hit.is_empty() else 0.2
			var grass_y: float = float(grass_hit.position.y) + 0.018 if not grass_hit.is_empty() else -0.2
			points.append(Vector3(sx,road_y,edge-direction*0.45))
			points.append(Vector3(sx,road_y,edge+direction*0.5))
			points.append(Vector3(sx,grass_y,edge+direction*2.0))
		var body := StaticBody3D.new(); body.name="RoadCurbRamp"; add_child(body)
		var collider := CollisionShape3D.new()
		var shape := ConcavePolygonShape3D.new(); shape.backface_collision=true
		var faces := PackedVector3Array([points[0],points[1],points[3],points[3],points[1],points[4],points[1],points[2],points[4],points[4],points[2],points[5]])
		for i in range(0,faces.size(),3):
			if (faces[i+1]-faces[i]).cross(faces[i+2]-faces[i]).y > 0:
				var swap := faces[i+1]; faces[i+1]=faces[i+2]; faces[i+2]=swap
		shape.set_faces(faces)
		collider.shape=shape; body.add_child(collider)

func _shop_apron() -> void:
	var entrance := get_parent().find_child("EntranceGround",true,false) as StaticBody3D
	if not entrance: return
	var collider := entrance.get_child(0) as CollisionShape3D
	if not collider or not collider.shape is BoxShape3D: return
	var size: Vector3=collider.shape.size
	var center:=entrance.global_position
	var edge:=center.z+size.z*0.5
	var top:=center.y+size.y*0.5+0.02
	var points: Array[Vector3]=[]
	for x in [center.x-size.x*0.5+0.04,center.x+size.x*0.5-0.04]:
		var grass:=_ground(Vector3(x,0,edge+1.8))
		var grass_y: float=grass.position.y+0.02 if not grass.is_empty() else -0.2
		points.append(Vector3(x,top,edge-0.45))
		points.append(Vector3(x,top,edge+0.5))
		points.append(Vector3(x,grass_y,edge+1.8))
	var faces:=PackedVector3Array([points[0],points[1],points[3],points[3],points[1],points[4],points[1],points[2],points[4],points[4],points[2],points[5]])
	for i in range(0,faces.size(),3):
		if (faces[i+1]-faces[i]).cross(faces[i+2]-faces[i]).y>0:
			var swap:=faces[i+1]; faces[i+1]=faces[i+2]; faces[i+2]=swap
	var body:=StaticBody3D.new(); body.name="ShopApproachRamp"; add_child(body)
	var shape:=ConcavePolygonShape3D.new(); shape.backface_collision=true; shape.set_faces(faces)
	var ramp:=CollisionShape3D.new(); ramp.shape=shape; body.add_child(ramp)
