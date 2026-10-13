extends Node3D
## Rebuild physical surfaces from the current shop meshes; keep imported art intact.
const DoorScript = preload("res://scripts/proximity_door.gd")

func _ready() -> void:
	for title in ["Floor", "Wall", "Celing", "Window", "ATFCounter", "SmallTable", "Mattress", "Toilet", "Dumpster", "Chair", "Door", "Door_001"]:
		var mesh := find_child(title, true, false) as MeshInstance3D
		if not mesh or not mesh.mesh: continue
		if mesh.find_children("*", "CollisionShape3D", true, false).is_empty():
			var body: PhysicsBody3D = AnimatableBody3D.new() if title.begins_with("Door") else StaticBody3D.new()
			if body is AnimatableBody3D: body.sync_to_physics=false
			body.name = "RuntimeCollision"
			mesh.add_child(body)
			var shape := CollisionShape3D.new()
			shape.shape = mesh.mesh.create_trimesh_shape()
			body.add_child(shape)
		if title in ["Floor", "ATFCounter", "SmallTable"]:
			mesh.set_meta("placement_patches", horizontal_patches(mesh))
	_setup_doors()
	# Ground beyond the front threshold lets visitors enter/leave the new floor mesh.
	var floor_mesh := find_child("Floor", true, false) as MeshInstance3D
	if floor_mesh:
		var b: AABB = floor_mesh.global_transform * floor_mesh.get_aabb()
		var ground := StaticBody3D.new()
		ground.name = "EntranceGround"
		add_child(ground)
		ground.global_position = Vector3(b.get_center().x, b.end.y - 0.1, b.end.z + 1.5)
		var shape := CollisionShape3D.new()
		var box := BoxShape3D.new()
		box.size = Vector3(b.size.x, 0.2, 3.2)
		shape.shape = box
		ground.add_child(shape)

func _setup_doors() -> void:
	var old: Node = load("res://assets/Scene/shop.tscn").instantiate()
	var original := old.find_child("AnimationPlayer", true, false) as AnimationPlayer
	for title in ["Door", "Door_001"]:
		var mesh := find_child(title, true, false) as MeshInstance3D
		if not mesh: continue
		var name_of_clip := "DoorFront_Open" if title == "Door_001" else "DoorBack_Open"
		var clip: Animation = original.get_animation(name_of_clip) if original and original.has_animation(name_of_clip) else null
		if clip == null:
			clip = Animation.new()
			clip.length = 0.5
			clip.add_track(Animation.TYPE_VALUE)
			clip.track_set_path(0, NodePath(":rotation"))
			clip.track_insert_key(0, 0, Vector3.ZERO)
			clip.track_insert_key(0, 0.5, Vector3(0, 2.0, 0))
		var controller := DoorScript.new()
		controller.name = name_of_clip + "Controller"
		controller.door = mesh
		controller.animation = clip
		controller.front = title == "Door_001"
		add_child(controller)
	old.free()

static func horizontal_patches(mesh: MeshInstance3D) -> Array[Dictionary]:
	var patches: Array[Dictionary] = []
	for surface in mesh.mesh.get_surface_count():
		var arrays: Array = mesh.mesh.surface_get_arrays(surface)
		if arrays.is_empty(): continue
		var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
		var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
		if indices.is_empty():
			for i in vertices.size(): indices.append(i)
		for i in range(0, indices.size() - 2, 3):
			var a := mesh.global_transform * vertices[indices[i]]
			var b := mesh.global_transform * vertices[indices[i + 1]]
			var c := mesh.global_transform * vertices[indices[i + 2]]
			var normal: Vector3 = (mesh.global_basis.inverse().transposed()*normals[indices[i]]).normalized() if not normals.is_empty() else -(b-a).cross(c-a).normalized()
			if normal.dot(Vector3.UP) < 0.95: continue
			var lo := a.min(b).min(c)
			var hi := a.max(b).max(c)
			if hi.x-lo.x < 0.05 or hi.z-lo.z < 0.05: continue
			patches.append({"rect":Rect2(Vector2(lo.x,lo.z),Vector2(hi.x-lo.x,hi.z-lo.z)), "y":(a.y+b.y+c.y)/3.0})
	var merged := true
	while merged:
		merged = false
		for i in patches.size():
			if merged: break
			for j in range(i+1, patches.size()):
				var a: Rect2 = patches[i].rect
				var b: Rect2 = patches[j].rect
				if absf(patches[i].y-patches[j].y)>0.018 or not a.grow(0.002).intersects(b): continue
				var combined := a.merge(b)
				var overlap := a.intersection(b).get_area()
				if combined.get_area() > (a.get_area()+b.get_area()-overlap)*1.03: continue
				patches[i].rect = combined
				patches.remove_at(j)
				merged = true
				break
	return patches
