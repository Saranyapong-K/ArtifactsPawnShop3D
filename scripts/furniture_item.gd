extends StaticBody3D

const SurfaceGeometry = preload("res://scripts/shop_runtime.gd")
const SIZING_VERSION := 1
const PROFILES := {
	"furn_shelf": {"grid":Vector2i(4, 2), "height":1.8},
	"cab_open_shelf": {"grid":Vector2i(4, 2), "height":1.85},
	"cab_counter_glass": {"grid":Vector2i(3, 2), "height":1.05},
	"cab_weapon_rack": {"grid":Vector2i(4, 2), "height":1.8},
	"furn_glass_cabinet": {"grid":Vector2i(3, 2), "height":1.65},
	"cab_tall_vitrine": {"grid":Vector2i(3, 2), "height":1.85},
	"cab_combo": {"grid":Vector2i(4, 2), "height":1.8},
	"cab_pedestal_dome": {"grid":Vector2i(2, 2), "height":2.0},
}
var artifact: ArtifactData
var record: Dictionary
var is_furniture: bool = true
var visual: Node3D
var _local_patches: Array[Dictionary] = []
var _legacy_patches: Array[Dictionary] = []
var _legacy_height := 0.0

static func create_visual(item: ArtifactData) -> Node3D:
	var profile: Dictionary = PROFILES.get(item.model_path.get_file().get_basename(), {})
	return ArtifactVisual.create(item, float(profile.get("height", 2.0)), 1.0, false)

func setup_furniture(data: Dictionary) -> void:
	record = data
	artifact = ArtifactData.from_dict(data)
	var grid: Array = data.get("grid_size", [1, 1])
	artifact.grid_size = Vector2i(int(grid[0]), int(grid[1]))
	if int(data.get("display_sizing_version", 0)) < SIZING_VERSION and data.get("placement", {}).has("position"):
		var old_visual := ArtifactVisual.create(artifact, 2.0, 1.0, false)
		add_child(old_visual)
		_legacy_height = float(old_visual.get_meta("height", 0.0))
		for mesh in old_visual.find_children("*", "MeshInstance3D", true, false):
			for patch: Dictionary in SurfaceGeometry.horizontal_patches(mesh):
				_legacy_patches.append(_transform_patch(patch, global_transform.affine_inverse()))
		old_visual.free()
	var profile: Dictionary = PROFILES.get(artifact.model_path.get_file().get_basename(), {})
	if not profile.is_empty(): artifact.grid_size = profile.grid
	record["grid_size"] = [artifact.grid_size.x, artifact.grid_size.y]
	set_meta("is_furniture", true)
	name = "Furniture_" + artifact.id
	visual = create_visual(artifact)
	add_child(visual)
	# Physical geometry preserves the horizontal surfaces inside shelves/cabinets.
	for node in visual.find_children("*", "MeshInstance3D", true, false):
		var mesh: MeshInstance3D = node as MeshInstance3D
		if mesh.mesh:
			for patch: Dictionary in SurfaceGeometry.horizontal_patches(mesh):
				_local_patches.append(_transform_patch(patch, global_transform.affine_inverse()))
			var shape := CollisionShape3D.new()
			shape.shape = _display_collision(mesh)
			shape.transform = global_transform.affine_inverse() * mesh.global_transform
			add_child(shape)
	var area := Area3D.new()
	area.name = "InteractionArea"
	area.collision_layer = 1
	area.collision_mask = 0
	var shape := CollisionShape3D.new()
	var bounds := BoxShape3D.new()
	bounds.size = Vector3(artifact.grid_size.x * ArtifactVisual.CELL_SIZE, float(visual.get_meta("height", 1.0)), artifact.grid_size.y * ArtifactVisual.CELL_SIZE)
	shape.shape = bounds
	shape.position.y = bounds.size.y * 0.5
	area.add_child(shape)
	add_child(area)

func adapt_legacy_contents(inventory: Array[ArtifactData], placed_items: Dictionary) -> void:
	if _legacy_height > 0.0:
		var ratio := float(visual.get_meta("height", _legacy_height)) / _legacy_height
		for item: ArtifactData in inventory:
			if not item.placement.has("position") or item.placement.get("held", false): continue
			var position_data: Array = item.placement.position
			var local := to_local(Vector3(position_data[0], position_data[1], position_data[2]))
			for patch: Dictionary in _legacy_patches:
				if absf(local.y-patch.y-0.012) > 0.04 or not (patch.rect as Rect2).grow(0.02).has_point(Vector2(local.x,local.z)): continue
				var moved := to_global(Vector3(local.x*ratio,(local.y-0.012)*ratio+0.012,local.z*ratio))
				item.placement.position = [moved.x,moved.y,moved.z]
				if placed_items.has(item.id): placed_items[item.id].global_position = moved
				break
	record["display_sizing_version"] = SIZING_VERSION
	_legacy_patches.clear()
	_legacy_height = 0.0

func _display_collision(mesh: MeshInstance3D) -> ConcavePolygonShape3D:
	var faces := PackedVector3Array()
	for surface in mesh.mesh.get_surface_count():
		var material := mesh.get_active_material(surface)
		var glass: bool = material is BaseMaterial3D and material.transparency != BaseMaterial3D.TRANSPARENCY_DISABLED and material.albedo_color.a < 0.9
		var arrays := mesh.mesh.surface_get_arrays(surface)
		var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
		var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
		if indices.is_empty():
			for i in vertices.size(): indices.append(i)
		for i in range(0, indices.size()-2, 3):
			# Reach display contents through glass panels; glass shelves still support them.
			if glass:
				var normal: Vector3 = normals[indices[i]] if not normals.is_empty() else -(vertices[indices[i+1]]-vertices[indices[i]]).cross(vertices[indices[i+2]]-vertices[indices[i]]).normalized()
				if absf((mesh.global_basis.inverse().transposed()*normal).normalized().y) < 0.95: continue
			for j in 3: faces.append(vertices[indices[i+j]])
	var shape := ConcavePolygonShape3D.new()
	shape.set_faces(faces)
	return shape

func get_placement_patches() -> Array[Dictionary]:
	# Keep the grid attached to the furniture through moving, turning and reloads.
	var patches: Array[Dictionary] = []
	for patch: Dictionary in _local_patches:
		patches.append(_transform_patch(patch, global_transform))
	return patches

func _transform_patch(patch: Dictionary, transform: Transform3D) -> Dictionary:
	var rect: Rect2 = patch.rect
	var points: Array[Vector3] = []
	for x in [rect.position.x, rect.end.x]:
		for z in [rect.position.y, rect.end.y]:
			points.append(transform * Vector3(x, patch.y, z))
	var result := Rect2(Vector2(points[0].x, points[0].z), Vector2.ZERO)
	for point: Vector3 in points:
		result = result.expand(Vector2(point.x, point.z))
	return {"rect":result, "y":points[0].y}

func interact(_player: Node) -> void:
	var placement: Node = get_tree().get_first_node_in_group("artifact_placement")
	if placement:
		placement.pick_up(self)

func set_highlighted(_value: bool) -> void:
	pass
