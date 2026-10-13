shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never, shadows_disabled;
stencil_mode write, compare_always, 1;

// Reserve only the original visible silhouette, including glass artifacts.
// No colour or depth is written; imported materials keep their appearance.
void fragment() {
	ALPHA = 0.0;
}
