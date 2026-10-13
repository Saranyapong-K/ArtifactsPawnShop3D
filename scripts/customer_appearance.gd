extends RefCounted
## Clothing variants reuse the imported rigs, meshes and animations.

const CLOTHING_COLORS := [
	Color("a7542e"), Color("74815a"), Color("b9863d"),
	Color("647a86"), Color("8f617e"), Color("b1644b"),
]
const HAIR_COLORS := [Color("503528"),Color("8e4936"),Color("d4aa65"),Color("c6bcb4"),Color("302a28"),Color("e2cda9")]
static var _palette_shader: Shader
static var _masked_meshes: Dictionary={}

const PALETTE_SHADER := """
shader_type spatial;
render_mode cull_back;
uniform sampler2D garment_texture : source_color, filter_nearest, repeat_disable;
uniform vec4 garment_source : source_color;
uniform vec4 garment_secondary : source_color;
uniform vec4 shirt_color : source_color;
uniform float garment_roughness = 0.8;
uniform bool recolor_secondary = false;
uniform bool recolor_hair = false;
uniform vec4 hair_source : source_color;
uniform vec4 hair_color : source_color;
void fragment() {
	vec4 texel = texture(garment_texture, UV);
	float clothing_mask = 1.0 - smoothstep(0.07, 0.14, distance(texel.rgb, garment_source.rgb));
	float secondary_mask = recolor_secondary ? 1.0 - smoothstep(0.025, 0.06, distance(texel.rgb, garment_secondary.rgb)) : 0.0;
	float upper_body = COLOR.r;
	vec3 garment = mix(texel.rgb, shirt_color.rgb * 0.85, clothing_mask * upper_body);
	ALBEDO = mix(garment, min(vec3(1.0), shirt_color.rgb * 1.2), secondary_mask * upper_body);
	float hair_mask = recolor_hair ? 1.0 - smoothstep(0.035, 0.08, distance(texel.rgb, hair_source.rgb)) : 0.0;
	ALBEDO=mix(ALBEDO,hair_color.rgb*clamp(dot(texel.rgb,vec3(0.333))/max(dot(hair_source.rgb,vec3(0.333)),0.01),0.85,1.15),hair_mask);
	ROUGHNESS = garment_roughness;
	METALLIC = 0.0;
}
"""

static func apply_to(customer: Node, variant_index: int, hair_index: int=-1) -> void:
	var color: Color = CLOTHING_COLORS[posmod(variant_index, CLOTHING_COLORS.size())]
	var hair: Color=HAIR_COLORS[posmod(hair_index,HAIR_COLORS.size())] if hair_index>=0 else HAIR_COLORS.pick_random()
	customer.set_meta("clothing_color",color)
	customer.set_meta("hair_color",hair)
	var bodies := customer.find_children("*", "MeshInstance3D", true, false)
	for node in bodies:
		var body := node as MeshInstance3D
		if not body or not body.mesh:
			continue
		var is_body:=String(body.name).begins_with("Body")
		var is_hair:=String(body.name).begins_with("Head") or String(body.name).begins_with("Tail")
		if not is_body and not is_hair and body.name!="Cape": continue
		var has_palette := false
		for surface in body.mesh.get_surface_count():
			var material := body.get_active_material(surface) as StandardMaterial3D
			if material and material.albedo_texture:
				has_palette = true
		if has_palette and is_body:
			body.mesh = _clothing_mask_mesh(body.mesh)
		for surface in body.mesh.get_surface_count():
			var original := body.get_active_material(surface) as StandardMaterial3D
			if not original:
				continue
			if original.albedo_texture:
				# Palette matching preserves skin; the height mask keeps footwear
				# unchanged even when it shares the shirt's palette swatch.
				var palette := original.albedo_texture.get_image()
				if not palette or palette.is_empty():
					continue
				if palette.is_compressed():
					palette.decompress()
				var source := palette.get_pixel(0, 0)
				if not _palette_shader:
					_palette_shader=Shader.new()
					_palette_shader.code=PALETTE_SHADER
				var material := ShaderMaterial.new()
				material.shader = _palette_shader
				material.set_shader_parameter("garment_texture", original.albedo_texture)
				material.set_shader_parameter("garment_source", source)
				material.set_shader_parameter("shirt_color", color)
				material.set_shader_parameter("garment_roughness", original.roughness)
				material.set_shader_parameter("recolor_hair",is_hair)
				material.set_shader_parameter("hair_source",Color("ffca81") if original.resource_name=="Lumin_colour" else Color("473f47"))
				material.set_shader_parameter("hair_color",hair)
				if original.resource_name == "Lumin_colour":
					material.set_shader_parameter("recolor_secondary", true)
					material.set_shader_parameter("garment_secondary", Color.WHITE)
				body.set_surface_override_material(surface, material)
			elif original.resource_name.to_lower() in ["body","cape","hair"]:
				# NPC1 separates shirt and skin into independent surfaces.
				var material := original.duplicate() as StandardMaterial3D
				material.albedo_color = hair if original.resource_name.to_lower()=="hair" else color
				body.set_surface_override_material(surface, material)


static func _clothing_mask_mesh(source: Mesh) -> ArrayMesh:
	if _masked_meshes.has(source.get_instance_id()): return _masked_meshes[source.get_instance_id()]
	# A per-vertex mask stays attached to the rig during every animation.
	# It distinguishes the shirt from shoes that use the same palette color.
	var result := ArrayMesh.new()
	for blend_index in source.get_blend_shape_count():
		result.add_blend_shape(source.get_blend_shape_name(blend_index))
	var bounds := source.get_aabb()
	var cutoff := bounds.position.y + bounds.size.y * 0.48
	for surface in source.get_surface_count():
		var arrays := source.surface_get_arrays(surface)
		var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var mask := PackedColorArray()
		mask.resize(vertices.size())
		for index in vertices.size():
			mask[index] = Color(1.0 if vertices[index].y >= cutoff else 0.0, 0.0, 0.0, 1.0)
		arrays[Mesh.ARRAY_COLOR] = mask
		var flags: int = int(source.surface_get_format(surface)) & Mesh.ARRAY_FLAG_USE_8_BONE_WEIGHTS
		result.add_surface_from_arrays(source.surface_get_primitive_type(surface), arrays, source.surface_get_blend_shape_arrays(surface), {}, flags)
		result.surface_set_material(surface, source.surface_get_material(surface))
	_masked_meshes[source.get_instance_id()]=result
	return result
