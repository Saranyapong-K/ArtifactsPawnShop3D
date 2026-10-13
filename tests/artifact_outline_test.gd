extends SceneTree
## Check real imported models and the visual/placement boundary, not shader text.

var checks := 0
var failures := 0

func _init() -> void:
	_run.call_deferred()

func _check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error(message)

func _run() -> void:
	var catalog: Array = JSON.parse_string(FileAccess.get_file_as_string("res://scripts/data/artifact_catalog.json"))
	var tiers := ["Common", "Uncommon", "Rare", "SR", "SSR"]
	for entry: Dictionary in catalog:
		for tier: String in tiers:
			var artifact := ArtifactData.create(entry.model_path, entry.name, tier, "curse", Vector2i(entry.grid_size[0], entry.grid_size[1]))
			var visual := ArtifactVisual.create(artifact)
			var plain := ArtifactVisual.create(artifact, 0.8, 0.84, false)
			var bounds := ArtifactVisual.local_bounds(visual)
			var plain_bounds := ArtifactVisual.local_bounds(plain)
			_check(bounds.position.is_equal_approx(plain_bounds.position) and bounds.size.is_equal_approx(plain_bounds.size) and is_equal_approx(visual.get_meta("height"), plain.get_meta("height")), "%s/%s: outlining preserves model size and placement height" % [entry.id, tier])
			var meshes := visual.find_children("*", "MeshInstance3D", true, false).filter(func(mesh: Node): return not mesh.get_meta("rarity_outline_hull", false))
			var plain_meshes := plain.find_children("*", "MeshInstance3D", true, false)
			_check(not meshes.is_empty() and meshes.size() == plain_meshes.size() and visual.find_children("*", "CollisionShape3D", true, false).size() == plain.find_children("*", "CollisionShape3D", true, false).size(), "%s/%s: outline adds no collision geometry" % [entry.id, tier])
			for i in range(meshes.size()):
				var mesh := meshes[i] as MeshInstance3D
				var original := plain_meshes[i] as MeshInstance3D
				var mask := mesh.material_overlay as ShaderMaterial
				var outline := mesh.get_node("RarityOutline").material_override as ShaderMaterial
				_check(mask != null and outline != null and outline.get_shader_parameter("rainbow") == (tier == "SSR") and outline.get_shader_parameter("outline_color") == ArtifactVisual.RARITY_OUTLINE_COLORS[tier], "%s/%s: every mesh gets the correct rarity and SSR mode" % [entry.id, tier])
				_check(mesh.mesh == original.mesh and mesh.material_override == original.material_override and original.material_overlay == null, "%s/%s: original shared mesh, textures, and materials are retained" % [entry.id, tier])
			visual.free()
			plain.free()
	var artifact := ArtifactData.create("res://assets/Relics/Guitar.glb", "Saved guitar", "SSR", "broken", Vector2i(1, 2))
	var restored := ArtifactData.from_dict(artifact.to_dict())
	var loaded_visual := ArtifactVisual.create(restored)
	var meshes := loaded_visual.find_children("*", "MeshInstance3D", true, false).filter(func(mesh: Node): return not mesh.get_meta("rarity_outline_hull", false))
	_check((meshes[0].get_node("RarityOutline").material_override as ShaderMaterial).get_shader_parameter("rainbow"), "Loading an existing saved SSR artifact recreates its rainbow outline")
	ArtifactVisual.tint_hologram(loaded_visual, false)
	for mesh: MeshInstance3D in meshes:
		_check(mesh.material_overlay == null and not mesh.get_node("RarityOutline").visible and (mesh.material_override as StandardMaterial3D).albedo_color.r > 0.9, "Invalid placement uses its red hologram without a competing rarity outline")
	loaded_visual.free()
	var furniture: Node3D = load("res://scripts/furniture_item.gd").new()
	root.add_child(furniture)
	furniture.setup_furniture({"id":"outline-test-shelf", "name":"Shelf", "model_path":"res://assets/Relics/Expanded/Furniture/furn_shelf.glb", "grid_size":[3, 1]})
	for mesh: MeshInstance3D in furniture.visual.find_children("*", "MeshInstance3D", true, false):
		_check(mesh.material_overlay == null, "Furniture keeps its original appearance without artifact rarity outlines")
	furniture.free()
	print("ARTIFACT OUTLINE TEST: %d checks, %d failures; %d catalog models x 5 rarities" % [checks, failures, catalog.size()])
	quit(0 if failures == 0 else 1)
