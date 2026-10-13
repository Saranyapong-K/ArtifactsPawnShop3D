class_name CleaningVisual
extends RefCounted
static var _material_cache: Dictionary = {}

static func _material(source: StandardMaterial3D,kind: String,variant: int,uses: int,held: bool) -> StandardMaterial3D:
	var original: StandardMaterial3D=source.get_meta("cleaning_source",source)
	var key: String="%d:%s:%d:%d:%s"%[original.get_instance_id(),kind,variant,uses,held]
	if _material_cache.has(key): return _material_cache[key]
	var material:=source.duplicate() as StandardMaterial3D
	material.no_depth_test=held
	material.set_meta("cleaning_source",original)
	material.set_meta("cleaning_kind",kind)
	material.set_meta("cleaning_variant",variant)
	material.set_meta("cleaning_uses",uses)
	_material_cache[key]=material
	return material
## Wrap offset GLB/FBX origins and duplicate only the materials being changed.
static func prepare(model: Node3D, kind: String, variant: int, mop_uses: int, bag_load: int) -> Node3D:
	ArtifactVisual._strip_physics(model)
	var bounds := ArtifactVisual.local_bounds(model)
	var scale_factor := 1.0
	if kind == "trash_bag": scale_factor = minf(0.65 / maxf(bounds.size.y,0.001),0.52 / maxf(maxf(bounds.size.x,bounds.size.z),0.001)) * (0.65 + bag_load*0.0875)
	elif kind in ["rubbish","spill"]: scale_factor = minf(1.0,0.75 / maxf(maxf(bounds.size.x,bounds.size.z),0.001))
	elif kind == "dust": scale_factor = minf(1.0, minf(0.48 / maxf(maxf(bounds.size.x,bounds.size.z),0.001), 0.17 / maxf(bounds.size.y,0.001)))
	elif kind in ["broom","mop","feather_duster"]: scale_factor = minf(1.0,1.2/maxf(bounds.size.y,0.001))
	var wrapper := Node3D.new()
	wrapper.add_child(model)
	model.scale *= scale_factor
	model.position -= Vector3(bounds.get_center().x,bounds.position.y,bounds.get_center().z)*scale_factor
	for mesh: MeshInstance3D in wrapper.find_children("*","MeshInstance3D",true,false):
		mesh.set_meta("cleaning_materials_owned",true)
		for surface in mesh.mesh.get_surface_count():
			var original: Material = mesh.get_active_material(surface)
			if not original is StandardMaterial3D: continue
			var owned:=_material(original,kind,variant,mop_uses if kind=="mop" else 0,false)
			mesh.set_surface_override_material(surface,owned)
			var name := original.resource_name.to_lower()
			if kind == "mop" and (name == "mop" or "mophead" in name):
				var material := owned
				material.albedo_color = Color("393a2c") if mop_uses>=4 else (Color("958057") if mop_uses>=2 else Color("e1e0d3"))
				mesh.set_surface_override_material(surface,material)
			if kind == "spill" and "spilleddrink" in name:
				var material := owned
				material.albedo_color = [Color(0.50,0.78,0.9,0.72),Color("4b2514"),Color("dd8d24")][variant%3]
				material.roughness = 0.16
				material.metallic = 0.0
				if variant%3==0: material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
				mesh.set_surface_override_material(surface,material)
			if kind == "trash_bag":
				var material := owned
				material.albedo_color = Color("252627")
				material.roughness = 0.68
				mesh.set_surface_override_material(surface,material)
	wrapper.set_meta("bounds",ArtifactVisual.local_bounds(wrapper))
	if kind=="trash_bag": wrapper.set_meta("bag_fill",bag_load)
	return wrapper

static func set_mop_dirt(node: Node3D, uses: int) -> void:
	for mesh: MeshInstance3D in node.find_children("*","MeshInstance3D",true,false):
		for i in mesh.mesh.get_surface_count():
			var material: Material=mesh.get_active_material(i)
			if material is StandardMaterial3D and material.resource_name.to_lower()=="mop":
				material=_material(material,"mop",0,uses,material.no_depth_test)
				material.albedo_color=Color("393a2c") if uses>=4 else (Color("958057") if uses>=2 else Color("e1e0d3"))
				mesh.set_surface_override_material(i,material)

static func set_bag_fill(node: Node3D,fill: int) -> void:
	var old:=int(node.get_meta("bag_fill",fill))
	node.scale*=(0.65+fill*0.0875)/(0.65+old*0.0875)
	node.set_meta("bag_fill",fill)

static func held_depth(node: Node3D, held: bool) -> void:
	for mesh: MeshInstance3D in node.find_children("*","MeshInstance3D",true,false):
		for surface in mesh.mesh.get_surface_count():
			var source: Material = mesh.get_active_material(surface)
			if source is StandardMaterial3D:
				var material:=_material(source,source.get_meta("cleaning_kind",""),int(source.get_meta("cleaning_variant",0)),int(source.get_meta("cleaning_uses",0)),held)
				if mesh.material_override: mesh.material_override=material
				else: mesh.set_surface_override_material(surface,material)
		mesh.set_meta("cleaning_materials_owned",true)
