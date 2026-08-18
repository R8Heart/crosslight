// One CSGBox3D, two materials -- CSG primitives only expose a single
// material slot for the whole shape, so the two faces are told apart in
// the shader itself by which way their normal points, rather than by
// splitting the wall into two separate boxes.
shader_type spatial;

group_uniforms side_a;
uniform sampler2D albedo_a : source_color;
uniform sampler2D normal_a : hint_normal;
uniform sampler2D roughness_a : hint_default_white;
uniform float uv_scale_a : hint_range(0.05, 20.0) = 1.0;

group_uniforms side_b;
uniform sampler2D albedo_b : source_color;
uniform sampler2D normal_b : hint_normal;
uniform sampler2D roughness_b : hint_default_white;
uniform float uv_scale_b : hint_range(0.05, 20.0) = 1.0;

// The box's own local-space direction that points out of the "B" face --
// e.g. (0, 0, 1) if the wallpaper side faces the box's local +Z. Whichever
// face's normal is closest to this direction gets material B; every other
// face (the opposite side, and the four thin edge faces) gets material A.
// Read this off the box's own Transform in the editor, not world space --
// it has to survive the box being rotated.
uniform vec3 face_b_direction = vec3(0.0, 0.0, 1.0);

varying vec3 v_obj_normal;

void vertex() {
	// Captured before Godot's own transform touches NORMAL, so this stays
	// in the box's own local space regardless of how the node is rotated
	// in the world -- the comparison below only makes sense against a
	// direction that doesn't move when the wall does.
	v_obj_normal = NORMAL;
}

void fragment() {
	bool is_b = dot(normalize(v_obj_normal), normalize(face_b_direction)) > 0.5;

	vec2 uv = UV;
	if (is_b) {
		ALBEDO = texture(albedo_b, uv * uv_scale_b).rgb;
		NORMAL_MAP = texture(normal_b, uv * uv_scale_b).rgb;
		ROUGHNESS = texture(roughness_b, uv * uv_scale_b).r;
	} else {
		ALBEDO = texture(albedo_a, uv * uv_scale_a).rgb;
		NORMAL_MAP = texture(normal_a, uv * uv_scale_a).rgb;
		ROUGHNESS = texture(roughness_a, uv * uv_scale_a).r;
	}
}
