class_name ArtifactVisual
extends RefCounted

const CELL_SIZE: float = 0.4
const OUTLINE_SHADER = preload("res://shaders/artifact_rarity_outline.gdshader")
const OUTLINE_MASK_SHADER = preload("res://shaders/artifact_outline_mask.gdshader")
const OUTLINE_WIDTH_PIXELS: float = 3.0
const RARITY_OUTLINE_COLORS := {
	"Common": Color("f1f3f5"), "Uncommon": Color("70c340"),
	"Rare": Color("238de8"), "SR": Color("ffc632"), "SSR": Color.WHITE,
}
static var _outline_mesh_cache: Dictionary = {}
const LEGACY_MODEL_REPLACEMENTS := {"res://assets/Relics/Expanded/long_longsword.glb":"res://assets/Relics/Sword.glb", "res://assets/Relics/Expanded/std_lute.glb":"res://assets/Relics/Guitar.glb"}

static func create(artifact: ArtifactData, height_limit: float = 0.8, footprint_margin: float = 0.84, rarity_outline: bool = true) -> Node3D:
	var visual := Node3D.new()
	visual.name = "ArtifactVisual"
	var model: Node3D
	var model_path: String=artifact.model_path
	if not ResourceLoader.exists(model_path): model_path=LEGACY_MODEL_REPLACEMENTS.get(model_path,model_path)
	var packed: PackedScene = load(model_path) as PackedScene if ResourceLoader.exists(model_path) else null
	if packed:
		model = packed.instantiate() as Node3D
		if model and model.has_method("build"): model.build()
	if model == null:
		var mesh := MeshInstance3D.new()
		mesh.mesh = BoxMesh.new()
		model = mesh
	var normalized := Node3D.new()
	visual.add_child(normalized)
	normalized.add_child(model)
	_strip_physics(model)
	var bounds: AABB = local_bounds(model)
	var extent: Vector3 = bounds.size.max(Vector3.ONE * 0.001)
	var maximum := Vector3(float(artifact.grid_size.x) * CELL_SIZE * footprint_margin, height_limit, float(artifact.grid_size.y) * CELL_SIZE * footprint_margin)
	var fixed_scale: float = minf(maximum.x / extent.x, minf(maximum.y / extent.y, maximum.z / extent.z))
	normalized.scale = Vector3.ONE * fixed_scale
	normalized.position = -Vector3(bounds.position.x + bounds.size.x * 0.5, bounds.position.y, bounds.position.z + bounds.size.z * 0.5) * fixed_scale
	visual.set_meta("height", maxf(0.08, extent.y * fixed_scale))
	if rarity_outline:
		_apply_outline(model, Transform3D.IDENTITY, artifact.rarity, bounds)
	return visual

static func _apply_outline(node: Node, transform: Transform3D, rarity: String, bounds: AABB) -> void:
	var local := transform
	if node is Node3D:
		local *= (node as Node3D).transform
	# Visit imported children before adding our outline mesh.
	for child in node.get_children():
		_apply_outline(child, local, rarity, bounds)
	if node is MeshInstance3D and (node as MeshInstance3D).mesh:
		var mesh := node as MeshInstance3D
		var outline := ShaderMaterial.new()
		outline.shader = OUTLINE_SHADER
		outline.render_priority = 1
		outline.set_shader_parameter("outline_color", RARITY_OUTLINE_COLORS.get(rarity, RARITY_OUTLINE_COLORS.Common))
		outline.set_shader_parameter("outline_width_pixels", OUTLINE_WIDTH_PIXELS)
		outline.set_shader_parameter("rainbow", rarity == "SSR")
		outline.set_shader_parameter("artifact_from_mesh", local)
		# Use the model's longest axis so lying swords and upright artifacts both
		# show the full rainbow, consistently across all their separate meshes.
		var rainbow_axis := Vector3.UP
		if bounds.size.x > maxf(bounds.size.y, bounds.size.z) * 1.05:
			rainbow_axis = Vector3.RIGHT
		elif bounds.size.z > maxf(bounds.size.x, bounds.size.y) * 1.05:
			rainbow_axis = Vector3.BACK
		outline.set_shader_parameter("rainbow_axis", rainbow_axis)
		outline.set_shader_parameter("rainbow_offset", bounds.position.dot(rainbow_axis))
		outline.set_shader_parameter("rainbow_length", maxf(bounds.size.dot(rainbow_axis), 0.001))
		var mask := ShaderMaterial.new()
		mask.shader = OUTLINE_MASK_SHADER
		mask.render_priority = -128
		# Mask the original silhouette before the outer shell. This prevents
		# internal outlines and colour filling transparent/glass artifacts.
		# Imported materials, textures, meshes, and collisions remain unchanged.
		mesh.material_overlay = mask
		mesh.extra_cull_margin = maxf(mesh.extra_cull_margin, 0.05)
		var hull := MeshInstance3D.new()
		hull.name = "RarityOutline"
		hull.set_meta("rarity_outline_hull", true)
		hull.mesh = _smooth_outline_mesh(mesh.mesh)
		hull.material_override = outline
		hull.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		hull.layers = mesh.layers
		hull.extra_cull_margin = 0.05
		mesh.add_child(hull)
		if mesh.skin:
			hull.skin = mesh.skin
			hull.skeleton = mesh.skeleton if mesh.skeleton.is_absolute() else NodePath("../" + String(mesh.skeleton))

static func _smooth_outline_mesh(source: Mesh) -> ArrayMesh:
	var key := source.get_instance_id()
	if _outline_mesh_cache.has(key):
		return _outline_mesh_cache[key].hull
	var surfaces: Array[Array] = []
	var summed_normals: Dictionary = {}
	var epsilon := maxf(source.get_aabb().size.length() * 0.000001, 0.000001)
	for surface in range(source.get_surface_count()):
		var arrays := source.surface_get_arrays(surface)
		surfaces.append(arrays)
		var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
		for index in range(vertices.size()):
			var point := vertices[index].snapped(Vector3.ONE * epsilon)
			var normal := normals[index] if normals.size() == vertices.size() else (vertices[index] - source.get_aabb().get_center()).normalized()
			summed_normals[point] = summed_normals.get(point, Vector3.ZERO) + normal
	var hull := ArrayMesh.new()
	if source is ArrayMesh:
		for index in range(source.get_blend_shape_count()): hull.add_blend_shape(source.get_blend_shape_name(index))
		hull.blend_shape_mode = source.blend_shape_mode
	for surface in range(surfaces.size()):
		var arrays: Array = surfaces[surface]
		var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var normals := PackedVector3Array()
		normals.resize(vertices.size())
		for index in range(vertices.size()):
			var normal: Vector3 = summed_normals[vertices[index].snapped(Vector3.ONE * epsilon)]
			normals[index] = normal.normalized() if normal.length_squared() > 0.000001 else Vector3.UP
		arrays[Mesh.ARRAY_NORMAL] = normals
		var primitive: int = source.surface_get_primitive_type(surface) if source is ArrayMesh else Mesh.PRIMITIVE_TRIANGLES
		hull.add_surface_from_arrays(primitive, arrays, source.surface_get_blend_shape_arrays(surface))
	# Only the invisible shell uses smoothed normals. Original flat shading,
	# UVs and materials stay intact, and instances share the cached shell mesh.
	_outline_mesh_cache[key] = {"source": source, "hull": hull}
	return hull

static func local_bounds(model: Node3D) -> AABB:
	var boxes: Array[AABB] = []
	_collect(model, Transform3D.IDENTITY, boxes)
	if boxes.is_empty():
		return AABB(Vector3(-0.1, 0, -0.1), Vector3(0.2, 0.2, 0.2))
	var result: AABB = boxes[0]
	for index in range(1, boxes.size()):
		result = result.merge(boxes[index])
	return result

static func _collect(node: Node, transform: Transform3D, boxes: Array[AABB]) -> void:
	var local: Transform3D = transform
	if node is Node3D:
		local *= (node as Node3D).transform
	if node is MeshInstance3D:
		boxes.append(local * mesh_bounds(node as MeshInstance3D))
	for child in node.get_children():
		_collect(child, local, boxes)

static func mesh_bounds(mesh: MeshInstance3D) -> AABB:
	if mesh.skin == null or mesh.mesh == null: return mesh.get_aabb()
	var skeleton := mesh.get_node_or_null(mesh.skeleton) as Skeleton3D
	if skeleton == null: return mesh.get_aabb()
	var transforms: Array[Transform3D] = []
	for bind in mesh.skin.get_bind_count():
		var bone: int = mesh.skin.get_bind_bone(bind)
		if bone < 0: bone = skeleton.find_bone(mesh.skin.get_bind_name(bind))
		transforms.append(skeleton.get_bone_global_pose(bone) * mesh.skin.get_bind_pose(bind) if bone >= 0 else Transform3D.IDENTITY)
	# glTF skinned vertices may retain Blender world coordinates. Their inverse
	# binds move them into the rig; raw mesh AABBs would apply the export offset
	# twice and normalize the model around a point where it is not rendered.
	var mesh_to_skeleton := Transform3D.IDENTITY
	var cursor: Node3D = mesh
	while cursor and cursor != skeleton:
		mesh_to_skeleton = cursor.transform * mesh_to_skeleton
		cursor = cursor.get_parent() as Node3D
	if cursor != skeleton: return mesh.get_aabb()
	var skeleton_to_mesh := mesh_to_skeleton.affine_inverse()
	var result := AABB()
	var first := true
	for surface in mesh.mesh.get_surface_count():
		var arrays: Array = mesh.mesh.surface_get_arrays(surface)
		var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var bones: PackedInt32Array = arrays[Mesh.ARRAY_BONES] if arrays[Mesh.ARRAY_BONES] != null else PackedInt32Array()
		var weights: PackedFloat32Array = arrays[Mesh.ARRAY_WEIGHTS] if arrays[Mesh.ARRAY_WEIGHTS] != null else PackedFloat32Array()
		if vertices.is_empty() or bones.is_empty() or weights.size() != bones.size(): return mesh.get_aabb()
		var influences: int = bones.size() / vertices.size()
		for i in vertices.size():
			var point := Vector3.ZERO
			for j in influences:
				var index := i * influences + j
				if weights[index] > 0 and bones[index] < transforms.size(): point += (transforms[bones[index]] * vertices[i]) * weights[index]
			point = skeleton_to_mesh * point
			if first: result = AABB(point, Vector3.ZERO); first = false
			else: result = result.expand(point)
	return mesh.get_aabb() if first else result

static func _strip_physics(node: Node) -> void:
	if node is CollisionObject3D:
		(node as CollisionObject3D).collision_layer = 0
		(node as CollisionObject3D).collision_mask = 0
	for child in node.get_children():
		_strip_physics(child)

static func tint_hologram(visual: Node3D, valid: bool) -> void:
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.albedo_color = Color(0.2, 0.7, 1.0, 0.38) if valid else Color(1.0, 0.15, 0.1, 0.38)
	material.no_depth_test = false
	for node in visual.find_children("*", "MeshInstance3D", true, false):
		if node.get_meta("rarity_outline_hull", false):
			(node as MeshInstance3D).hide()
			continue
		# Placement colour communicates validity; the owned artifact keeps its
		# rarity outline when placement completes or is cancelled.
		(node as MeshInstance3D).material_overlay = null
		(node as MeshInstance3D).material_override = material
