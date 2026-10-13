extends StaticBody3D

var artifact: ArtifactData
var record: Dictionary
var is_furniture: bool = true
var visual: Node3D

func setup_furniture(data: Dictionary) -> void:
	record = data
	artifact = ArtifactData.from_dict(data)
	var grid: Array = data.get("grid_size", [1, 1])
	artifact.grid_size = Vector2i(int(grid[0]), int(grid[1]))
	set_meta("is_furniture", true)
	name = "Furniture_" + artifact.id
	visual = ArtifactVisual.create(artifact, 2.0, 1.0, false)
	add_child(visual)
	# Physical geometry preserves the horizontal surfaces inside shelves/cabinets.
	for node in visual.find_children("*", "MeshInstance3D", true, false):
		var mesh: MeshInstance3D = node as MeshInstance3D
		if mesh.mesh:
			var shape := CollisionShape3D.new()
			shape.shape = mesh.mesh.create_trimesh_shape()
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

func interact(_player: Node) -> void:
	var placement: Node = get_tree().get_first_node_in_group("artifact_placement")
	if placement:
		placement.pick_up(self)

func set_highlighted(_value: bool) -> void:
	pass
