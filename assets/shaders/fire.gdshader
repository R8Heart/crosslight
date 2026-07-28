// Volumetric torch flame: the fragment shader ray-marches a density field
// inside a box, so the fire is genuinely three-dimensional — it reads
// differently from every angle instead of looking like a flat card.
//
// The flame's root sits at the node's own origin (local y = 0) and grows
// upward, so moving, rotating or scaling the node behaves intuitively and the
// root never drifts off the torch. The volume bounds are driven from torch.gd
// and always leave clearance around the flame, so the shape is never clipped
// into hard square edges — do not hand-edit them.
shader_type spatial;
render_mode unshaded, cull_front, blend_mix, depth_draw_never, depth_test_disabled, shadows_disabled;

uniform sampler3D noise_tex : repeat_enable, filter_linear;

group_uniforms shape;
uniform float flame_height : hint_range(0.02, 1.5) = 0.3;
uniform float flame_radius : hint_range(0.01, 0.6) = 0.085;
uniform float taper_power : hint_range(0.2, 3.0) = 0.75;
// How tightly the flame's root grips the torch head before it widens.
uniform float root_grip : hint_range(0.1, 1.0) = 0.72;

group_uniforms motion;
uniform float rise_speed : hint_range(0.0, 4.0) = 1.0;
uniform float turbulence : hint_range(0.0, 3.0) = 1.0;
uniform float noise_scale : hint_range(0.5, 40.0) = 9.0;
uniform float warp_strength : hint_range(0.0, 2.0) = 0.55;
// Object-space lean, driven by the torch's own motion (see torch.gd).
uniform vec3 drag = vec3(0.0);
uniform float sway : hint_range(0.0, 0.1) = 0.014;

group_uniforms smoke;
uniform float smoke_amount : hint_range(0.0, 2.0) = 0.45;
uniform float smoke_extent : hint_range(0.1, 4.0) = 1.6;
uniform vec3 smoke_color : source_color = vec3(0.05, 0.045, 0.04);

group_uniforms look;
uniform vec3 color_core : source_color = vec3(1.0, 0.94, 0.68);
uniform vec3 color_mid : source_color = vec3(1.0, 0.45, 0.07);
uniform vec3 color_edge : source_color = vec3(0.55, 0.07, 0.005);
uniform float intensity : hint_range(0.0, 20.0) = 5.5;
uniform float absorption : hint_range(1.0, 200.0) = 55.0;
uniform int steps : hint_range(4, 64) = 28;

group_uniforms volume_driven_from_script;
uniform vec3 volume_min = vec3(-0.2, -0.02, -0.2);
uniform vec3 volume_max = vec3(0.2, 0.63, 0.2);

varying vec3 v_ray_origin;
varying vec3 v_local_pos;

void vertex() {
	v_local_pos = VERTEX;
	v_ray_origin = (inverse(MODEL_MATRIX) * INV_VIEW_MATRIX[3]).xyz;
}

float hash13(vec3 p) {
	p = fract(p * 0.1031);
	p += dot(p, p.zyx + 31.32);
	return fract((p.x + p.y) * p.z);
}

// Radius profile: grips the head at the root, swells just above it, then
// tapers to a tip — the silhouette of a real flame rather than a cylinder.
float profile(float h) {
	float grow = smoothstep(0.0, 0.22, h);
	float shrink = pow(max(1.0 - h, 0.0), taper_power);
	return mix(root_grip, 1.0, grow) * shrink;
}

// Higher parts of the flame lag further behind the torch's movement.
vec2 lean_at(float h, float t) {
	float lag = pow(clamp(h, 0.0, 1.0), 1.6);
	vec2 l = drag.xz * lag;
	l += vec2(sin(t * 2.1 + h * 5.0), cos(t * 1.6 + h * 4.2)) * sway * lag;
	return l;
}

// Domain-warped noise: the first octave displaces the sample position of the
// second, which is what turns smooth blobs into curling, tearing flame edges.
float fire_noise(vec3 p, float t) {
	vec3 q = p * noise_scale + vec3(0.0, -t * rise_speed, 0.0);
	float n1 = texture(noise_tex, q * 0.5).r;
	float n2 = texture(noise_tex, q + vec3(n1 * warp_strength)).r;
	return n1 * 0.45 + n2 * 0.55;
}

void densities(vec3 p, float t, out float fire, out float smoke) {
	fire = 0.0;
	smoke = 0.0;

	// The flame's root is the node's origin, so height is simply local y.
	float h = p.y / max(flame_height, 0.0001);
	vec2 lean = lean_at(h, t);

	if (h > -0.05 && h < 1.15) {
		float rad = flame_radius * profile(h);
		if (rad > 0.0001) {
			float r = length(p.xz - lean);
			float core = 1.0 - smoothstep(rad * 0.2, rad, r);
			if (core > 0.0) {
				float n = fire_noise(p, t);
				// Holds together low down, shreds into tongues towards the tip.
				float threshold = mix(0.10, 0.68, clamp(h, 0.0, 1.0)) * turbulence;
				float d = core * smoothstep(threshold, threshold + 0.24, n);
				d *= smoothstep(-0.02, 0.06, h) * (1.0 - smoothstep(0.68, 1.08, h));
				fire = clamp(d, 0.0, 1.0);
			}
		}
	}

	// Smoke picks up where the flame burns out: wider, slower, cooler.
	if (smoke_amount > 0.0) {
		float sh = (h - 0.5) / smoke_extent;
		if (sh > 0.0 && sh < 1.0) {
			float srad = flame_radius * (0.8 + 1.7 * sh);
			float sr = length(p.xz - lean * 1.4);
			float score = 1.0 - smoothstep(srad * 0.1, srad, sr);
			if (score > 0.0) {
				vec3 sq = p * noise_scale * 0.45 + vec3(0.0, -t * rise_speed * 0.55, 0.0);
				float sn = texture(noise_tex, sq).r;
				float sd = score * smoothstep(0.42, 0.72, sn);
				sd *= 1.0 - smoothstep(0.3, 1.0, sh);
				smoke = clamp(sd * smoke_amount, 0.0, 1.0);
			}
		}
	}

	// Never let density touch the volume wall, or the box shows as a hard edge.
	vec3 span = max(volume_max - volume_min, vec3(0.0001));
	vec3 rel = min(p - volume_min, volume_max - p) / span;
	float bounds = smoothstep(0.0, 0.07, min(rel.x, min(rel.y, rel.z)));
	fire *= bounds;
	smoke *= bounds;
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
	// Jitter each ray's start, otherwise low step counts band into visible slices.
	float t = t_enter + hash13(vec3(SCREEN_UV * 1024.0, TIME)) * step_size;

	vec3 accum = vec3(0.0);
	float alpha = 0.0;

	for (int i = 0; i < steps; i++) {
		vec3 p = ro + rd * t;

		float fd;
		float sd;
		densities(p, TIME, fd, sd);
		float total = fd + sd;

		if (total > 0.002) {
			float h = clamp(p.y / max(flame_height, 0.0001), 0.0, 1.0);
			// Hottest where the flame is densest and lowest.
			float heat = clamp(fd * (1.4 - h * 1.2), 0.0, 1.0);
			vec3 c = mix(color_edge, color_mid, smoothstep(0.04, 0.32, heat));
			c = mix(c, color_core, smoothstep(0.4, 0.85, heat));
			vec3 col = mix(smoke_color, c * intensity, fd / total);

			float a = 1.0 - exp(-total * step_size * absorption);
			accum += col * a * (1.0 - alpha);
			alpha += a * (1.0 - alpha);
			if (alpha > 0.995) {
				break;
			}
		}

		t += step_size;
		if (t >= t_exit) {
			break;
		}
	}

	if (alpha < 0.002) {
		discard;
	}

	ALBEDO = accum / alpha;
	ALPHA = alpha;
}
