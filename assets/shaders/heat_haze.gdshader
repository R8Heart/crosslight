// Heat shimmer around and above the flame: samples the screen behind this
// volume with a noise-driven UV offset, so whatever is seen through the rising
// hot air wobbles like it does over a real fire.
//
// Renders before the flame itself (render_priority -1) so it distorts the
// scene, not the fire drawn on top of it.
shader_type spatial;
render_mode unshaded, cull_front, blend_mix, depth_draw_never, depth_test_disabled, shadows_disabled;

uniform sampler2D screen_tex : hint_screen_texture, filter_linear_mipmap;
uniform sampler3D noise_tex : repeat_enable, filter_linear;

uniform float strength : hint_range(0.0, 0.06) = 0.011;
uniform float rise_speed : hint_range(0.0, 4.0) = 1.5;
uniform float noise_scale : hint_range(0.5, 30.0) = 6.0;
uniform float plume_radius : hint_range(0.02, 0.8) = 0.14;
uniform float plume_extent : hint_range(0.5, 6.0) = 2.6;
uniform float opacity : hint_range(0.0, 1.0) = 0.9;
uniform int steps : hint_range(2, 16) = 6;
uniform vec3 drag = vec3(0.0);

group_uniforms volume_driven_from_script;
uniform vec3 volume_min = vec3(-0.25, -0.02, -0.25);
uniform vec3 volume_max = vec3(0.25, 0.78, 0.25);
uniform float flame_height = 0.3;

varying vec3 v_ray_origin;
varying vec3 v_local_pos;

void vertex() {
	v_local_pos = VERTEX;
	v_ray_origin = (inverse(MODEL_MATRIX) * INV_VIEW_MATRIX[3]).xyz;
}

void fragment() {
	vec3 ro = v_ray_origin;
	vec3 rd = normalize(v_local_pos - v_ray_origin);

	vec3 inv_rd = 1.0 / rd;
	vec3 t0 = (volume_min - ro) * inv_rd;
	vec3 t1 = (volume_max - ro) * inv_rd;
	vec3 t_small = min(t0, t1);
	vec3 t_big = max(t0, t1);
	float t_enter = max(max(t_small.x, t_small.y), max(t_small.z, 0.0));
	float t_exit = min(min(t_big.x, t_big.y), t_big.z);

	if (t_enter >= t_exit) {
		discard;
	}

	float step_size = (t_exit - t_enter) / float(steps);
	float t = t_enter + step_size * 0.5;

	float heat = 0.0;
	vec2 wobble = vec2(0.0);

	for (int i = 0; i < steps; i++) {
		vec3 p = ro + rd * t;
		// Hot air keeps rising and spreading well past the visible flame.
		float h = p.y / max(flame_height * plume_extent, 0.0001);

		if (h > 0.0 && h < 1.0) {
			vec2 lean = drag.xz * pow(h, 1.5);
			float rad = plume_radius * (0.45 + 1.4 * h);
			float r = length(p.xz - lean);
			float shape = 1.0 - smoothstep(rad * 0.15, rad, r);
			shape *= smoothstep(0.0, 0.1, h) * (1.0 - smoothstep(0.4, 1.0, h));

			if (shape > 0.0) {
				vec3 q = p * noise_scale + vec3(0.0, -TIME * rise_speed, 0.0);
				float nx = texture(noise_tex, q).r - 0.5;
				float ny = texture(noise_tex, q + vec3(4.3, 2.1, 7.7)).r - 0.5;
				wobble += vec2(nx, ny) * shape;
				heat += shape;
			}
		}

		t += step_size;
		if (t >= t_exit) {
			break;
		}
	}

	heat = clamp(heat / float(steps) * 3.0, 0.0, 1.0);
	if (heat < 0.004) {
		discard;
	}
	wobble /= float(steps);

	vec2 uv = clamp(SCREEN_UV + wobble * strength, vec2(0.0), vec2(1.0));
	ALBEDO = texture(screen_tex, uv).rgb;
	ALPHA = heat * opacity;
}
