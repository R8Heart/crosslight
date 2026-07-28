// Embers: soft round glowing points that pulse as they tumble and cool from
// yellow-white through orange to deep red before dying out.
shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, depth_test_disabled, cull_disabled, shadows_disabled;

uniform vec3 color_hot : source_color = vec3(1.0, 0.86, 0.48);
uniform vec3 color_cool : source_color = vec3(0.9, 0.16, 0.02);
uniform float intensity : hint_range(0.0, 20.0) = 6.0;
uniform float twinkle_speed : hint_range(0.0, 60.0) = 22.0;
uniform float softness : hint_range(0.5, 6.0) = 2.2;

varying float v_age;
varying float v_seed;

void vertex() {
	v_age = clamp(INSTANCE_CUSTOM.y, 0.0, 1.0);
	v_seed = fract(float(INSTANCE_ID) * 0.6180339887);

	// Billboard towards the camera, preserving each particle's own scale.
	mat4 bb = mat4(INV_VIEW_MATRIX[0], INV_VIEW_MATRIX[1], INV_VIEW_MATRIX[2], MODEL_MATRIX[3]);
	bb = bb * mat4(
		vec4(length(MODEL_MATRIX[0].xyz), 0.0, 0.0, 0.0),
		vec4(0.0, length(MODEL_MATRIX[1].xyz), 0.0, 0.0),
		vec4(0.0, 0.0, length(MODEL_MATRIX[2].xyz), 0.0),
		vec4(0.0, 0.0, 0.0, 1.0));
	MODELVIEW_MATRIX = VIEW_MATRIX * bb;
}

void fragment() {
	float d = length(UV - vec2(0.5)) * 2.0;
	float dot_mask = pow(clamp(1.0 - d, 0.0, 1.0), softness);
	if (dot_mask <= 0.001) {
		discard;
	}

	// Each ember flickers on its own phase as it spins through the air.
	float twinkle = 0.55 + 0.45 * sin(TIME * twinkle_speed + v_seed * 63.0);
	vec3 c = mix(color_hot, color_cool, smoothstep(0.1, 0.85, v_age));
	float life = smoothstep(0.0, 0.06, v_age) * (1.0 - smoothstep(0.5, 1.0, v_age));

	ALBEDO = c * dot_mask * twinkle * life * intensity;
	ALPHA = 1.0;
}
