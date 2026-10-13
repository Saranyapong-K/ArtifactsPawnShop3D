shader_type canvas_item;
render_mode unshaded;
uniform sampler2D screen_texture : hint_screen_texture, filter_linear_mipmap;
uniform float blur_amount : hint_range(0.0, 6.0) = 3.5;
uniform float brightness : hint_range(0.0, 1.0) = 0.8;
void fragment() {
	vec3 backdrop = textureLod(screen_texture, SCREEN_UV, blur_amount).rgb;
	COLOR = vec4(backdrop * brightness, 1.0);
}
