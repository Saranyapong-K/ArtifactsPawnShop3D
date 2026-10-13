shader_type spatial;
render_mode unshaded, cull_front, depth_draw_never, shadows_disabled;
stencil_mode read, compare_not_equal, 1;

uniform vec4 outline_color : source_color = vec4(0.94, 0.95, 0.96, 1.0);
uniform float outline_width_pixels : hint_range(0.0, 8.0, 0.25) = 3.0;
uniform bool rainbow = false;
uniform float rainbow_speed : hint_range(0.0, 0.2, 0.005) = 0.04;
uniform mat4 artifact_from_mesh;
uniform vec3 rainbow_axis = vec3(0.0, 1.0, 0.0);
uniform float rainbow_offset = 0.0;
uniform float rainbow_length = 1.0;

varying float rainbow_coordinate;

vec3 rainbow_rgb(float hue) {
	vec3 bands = abs(fract(vec3(hue) + vec3(0.0, 2.0 / 3.0, 1.0 / 3.0)) * 6.0 - 3.0);
	return mix(vec3(1.0), clamp(bands - 1.0, 0.0, 1.0), 0.85);
}

void vertex() {
	vec4 clip = PROJECTION_MATRIX * MODELVIEW_MATRIX * vec4(VERTEX, 1.0);
	vec3 view_normal = normalize(MODELVIEW_NORMAL_MATRIX * NORMAL);
	vec2 pixel_direction = (PROJECTION_MATRIX * vec4(view_normal, 0.0)).xy * VIEWPORT_SIZE;
	float direction_length = length(pixel_direction);
	if (direction_length > 0.0001) {
		clip.xy += pixel_direction / direction_length * (2.0 * outline_width_pixels / VIEWPORT_SIZE) * clip.w;
	}
	POSITION = clip;
	float along_axis = dot((artifact_from_mesh * vec4(VERTEX, 1.0)).xyz, rainbow_axis);
	rainbow_coordinate = (along_axis - rainbow_offset) / max(rainbow_length, 0.001);
}

void fragment() {
	ALBEDO = rainbow ? rainbow_rgb(fract(rainbow_coordinate + TIME * rainbow_speed)) : outline_color.rgb;
	ALPHA = 1.0;
}
