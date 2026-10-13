extends Node3D
## Temporary geometry, replaced through CleaningManager's exported models.
@export_enum("broom", "mop", "feather_duster", "rubbish", "spill", "dust", "trash_bag", "dumpster") var kind := "broom"
@export_range(0, 2) var variant := 0
var dirt_level := 0
var bag_load := 1

func _init() -> void:
	pass

func _ready() -> void:
	build()

func build() -> void:
	if get_child_count() > 0: return
	if kind in ["broom", "mop", "feather_duster"]:
		part(Vector3(0.025, 0.75, 0.025), Vector3(0, 0.42, 0), Color("986a3e"))
		var size := Vector3(0.28, 0.10, 0.10)
		var color := Color("d6b35a")
		if kind == "mop":
			size = Vector3(0.20, 0.12, 0.20)
			color = Color("242624") if dirt_level >= 4 else (Color("888266") if dirt_level >= 2 else Color("d5d8c0"))
		if kind == "feather_duster": size = Vector3(0.15, 0.22, 0.15); color = Color("c38a6b")
		part(size, Vector3(0, 0.09, 0), color)
		if kind=="mop": (get_child(get_child_count()-1) as MeshInstance3D).material_override.resource_name="mop"
	elif kind == "trash_bag":
		var bag := MeshInstance3D.new()
		var sphere := SphereMesh.new()
		sphere.radius = 0.11 + bag_load * 0.028
		sphere.height = 0.20 + bag_load * 0.085
		bag.mesh = sphere
		bag.position.y = sphere.height * 0.5
		var material := StandardMaterial3D.new()
		material.albedo_color = Color("28282b")
		material.roughness = 0.75
		bag.material_override = material
		add_child(bag)
		part(Vector3(0.08, 0.07, 0.08), Vector3(0, sphere.height, 0), Color("353539"))
	elif kind == "dumpster":
		part(Vector3(0.95, 0.75, 0.65), Vector3(0, 0.375, 0), Color("456148"))
		part(Vector3(1.02, 0.08, 0.70), Vector3(0, 0.79, 0), Color("283328"))
	else:
		var size := Vector3(0.5, 0.008, 0.4)
		var color := Color("a89678")
		if kind == "spill": color = Color("8c5d39")
		if kind == "rubbish":
			size = Vector3(0.14 + variant * 0.03, 0.09, 0.19)
			color = [Color("d4ba8c"), Color("81926e"), Color("a8754a")][variant]
		part(size, Vector3(0, size.y * 0.5, 0), color)

func part(size: Vector3, point: Vector3, color: Color) -> void:
	var mesh := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = size
	mesh.mesh = box
	mesh.position = point
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = 0.95
	mesh.material_override = material
	add_child(mesh)
