// Volumetric energy orb: the interior is an actual ray-marched density field
// (same core technique proven on the torch flame earlier), not a thin
// transparent shell — that's what was reading as "empty air with a rim"
// before. Churning 3D noise inside gives real internal motion. The surface
// itself is textured with a real CC0 brushed-metal normal/roughness map
// (ambientCG Metal009) instead of procedural noise — actual scratch/streak
// detail broke up the fresnel/highlights far more convincingly than random
// jitter did.
shader_type spatial;
render_mode blend_mix, depth_draw_never, cull_back, unshaded, shadows_disabled;

uniform sampler2D screen_tex : hint_screen_texture, repeat_disable, filter_linear;
uniform sampler3D noise_tex : repeat_enable, filter_linear;
// Real brushed-metal PBR maps (CC0, ambientCG) drive the surface roughness
// instead of procedural hash noise — the streaky, scratched detail reads as
// far more convincing "rough glass/metal" than a uniform random jitter did.
uniform sampler2D normal_tex : hint_normal, repeat_enable, filter_linear;
uniform sampler2D roughness_tex : hint_default_white, repeat_enable, filter_linear;
uniform float normal_tiling : hint_range(0.5, 8.0) = 2.0;
uniform float normal_strength : hint_range(0.0, 2.0) = 1.0;

group_uniforms shape;
// Must match the SphereMesh's own radius (see orb.gd) — the volume is
// bounded by an actual analytic sphere intersection, not a box.
uniform float sphere_radius : hint_range(0.01, 1.0) = 0.045;

group_uniforms look;
uniform vec3 color_core : source_color = vec3(1.0, 0.85, 0.5);
uniform vec3 color_mid : source_color = vec3(1.0, 0.55, 0.15);
uniform vec3 color_rim : source_color = vec3(1.0, 0.4, 0.05);
uniform float glow_intensity : hint_range(0.0, 8.0) = 3.0;
// Baseline fill so the interior never reads as mostly-empty with sparse
// wisps — real "not holding air" solidity.
uniform float density_base : hint_range(0.0, 2.0) = 1.1;
uniform float absorption : hint_range(1.0, 60.0) = 26.0;
uniform int steps : hint_range(4, 24) = 12;

group_uniforms motion;
uniform float swirl_speed : hint_range(0.0, 3.0) = 0.6;
uniform float noise_scale : hint_range(0.5, 8.0) = 2.4;
uniform float warp_strength : hint_range(0.0, 2.0) = 0.8;

group_uniforms glass;
uniform float refraction_strength : hint_range(0.0, 0.2) = 0.03;
uniform float fresnel_power : hint_range(0.5, 8.0) = 3.0;
// Overall strength of the metal normal map's effect on the rim/highlights —
// 0 is a perfectly smooth machined ball, 1 is the full scratched texture.
uniform float surface_roughness : hint_range(0.0, 1.0) = 0.6;

group_uniforms highlight;
uniform vec3 highlight_dir = vec3(-0.4, 0.6, 0.7);
uniform float highlight_soft_size : hint_range(1.0, 64.0) = 8.0;
uniform float highlight_sharp_size : hint_range(1.0, 256.0) = 90.0;

group_uniforms transition;
// Driven by orb.gd during a world switch: a shell of light sweeps from the core
// outward (`wave` is its radius) while `energy` fades it in and back out, so the
// colour change arrives as a pulse through the orb instead of a hard cut.
uniform float transition_wave : hint_range(0.0, 2.0) = 0.0;
uniform float transition_energy : hint_range(0.0, 1.0) = 0.0;

varying vec3 v_ray_origin;
varying vec3 v_local_pos;
varying vec3 v_view_normal;
varying vec3 v_view_tangent;
varying vec3 v_view_binormal;
varying vec3 v_view_dir;
varying vec2 v_uv;

void vertex() {
	v_local_pos = VERTEX;
	v_uv = UV;
	v_ray_origin = (inverse(MODEL_MATRIX) * INV_VIEW_MATRIX[3]).xyz;
	v_view_normal = normalize((MODELVIEW_MATRIX * vec4(NORMAL, 0.0)).xyz);
	v_view_tangent = normalize((MODELVIEW_MATRIX * vec4(TANGENT, 0.0)).xyz);
	v_view_binormal = normalize((MODELVIEW_MATRIX * vec4(BINORMAL, 0.0)).xyz);
	v_view_dir = normalize(-(MODELVIEW_MATRIX * vec4(VERTEX, 1.0)).xyz);
}

float hash13(vec3 p) {
	p = fract(p * 0.1031);
	p += dot(p, p.zyx + 31.32);
	return fract((p.x + p.y) * p.z);
}

void fragment() {
	vec3 ro = v_ray_origin;
	vec3 rd = normalize(v_local_pos - v_ray_origin);

	// Analytic ray/sphere intersection — simpler than a box slab test since
	// the volume genuinely is a sphere centred on this node's own origin.
	float b = dot(ro, rd);
	float c = dot(ro, ro) - sphere_radius * sphere_radius;
	float disc = b * b - c;
	if (disc < 0.0) {
		discard;
	}
	float sq = sqrt(disc);
	float t_enter = max(-b - sq, 0.0);
	float t_exit = -b + sq;
	if (t_exit <= t_enter) {
		discard;
	}

	float step_size = (t_exit - t_enter) / float(steps);
	float t = t_enter + hash13(vec3(SCREEN_UV * 1024.0, TIME)) * step_size;

	vec3 accum = vec3(0.0);
	float alpha = 0.0;

	for (int i = 0; i < steps; i++) {
		vec3 p = ro + rd * t;
		float r = length(p) / sphere_radius;

		vec3 q = p * noise_scale * (1.0 / sphere_radius);
		q.y -= TIME * swirl_speed;
		float ang = TIME * swirl_speed * 0.35;
		float s = sin(ang);
		float cc = cos(ang);
		q.xz = mat2(vec2(cc, -s), vec2(s, cc)) * q.xz;

		float n1 = texture(noise_tex, q * 0.12).r;
		float n2 = texture(noise_tex, q * 0.12 + vec3(n1 * warp_strength)).r;
		float n = mix(n1, n2, 0.5);

		// Never drops all the way to zero — mix(0.55, 1.0, n) keeps a solid
		// baseline fill; n only modulates brightness/energy on top of that,
		// which is what reads as "moving light inside a solid", not holes.
		float radial = 1.0 - smoothstep(0.55, 1.0, r);
		float d = clamp(density_base * radial * mix(0.55, 1.0, n), 0.0, 1.0);

		// Expanding shell during a world switch — brightest exactly where the
		// wavefront currently sits, so it reads as energy travelling outward
		// rather than the whole volume just changing colour at once.
		float shell = exp(-abs(r - transition_wave) * 7.0) * transition_energy;
		d = clamp(d + shell * 0.6, 0.0, 1.0);

		if (d > 0.01) {
			float heat = clamp(n * radial * 1.3 + shell, 0.0, 1.0);
			vec3 col = mix(color_rim, color_mid, smoothstep(0.15, 0.5, heat));
			col = mix(col, color_core, smoothstep(0.5, 0.9, heat));

			float a = 1.0 - exp(-d * step_size * absorption);
			accum += col * glow_intensity * a * (1.0 - alpha);
			alpha += a * (1.0 - alpha);
			if (alpha > 0.99) {
				break;
			}
		}

		t += step_size;
		if (t >= t_exit) {
			break;
		}
	}

	// Thin glass layer on top of the volumetric interior: a real brushed-metal
	// normal map drives the fresnel rim and highlights instead of random
	// noise — the scratches/streaks read as actual surface detail, and the
	// roughness map softens the highlight where the "metal" is rougher. This
	// is what makes it look like a solid, imperfect object instead of a
	// perfectly smooth procedural bubble.
	vec3 tex_n = texture(normal_tex, v_uv * normal_tiling).rgb * 2.0 - 1.0;
	tex_n.xy *= normal_strength * surface_roughness;
	mat3 tbn = mat3(normalize(v_view_tangent), normalize(v_view_binormal), normalize(v_view_normal));
	vec3 n_surf = normalize(tbn * tex_n);

	float rough = texture(roughness_tex, v_uv * normal_tiling).r;

	vec3 v = normalize(v_view_dir);
	float fresnel = pow(1.0 - clamp(dot(n_surf, v), 0.0, 1.0), fresnel_power);

	vec2 refr_offset = n_surf.xy * refraction_strength;
	vec3 refracted = textureLod(screen_tex, SCREEN_UV + refr_offset, 0.0).rgb;

	vec3 rim = color_rim * fresnel * glow_intensity * 0.5;

	vec3 hdir = normalize(highlight_dir);
	vec3 r_vec = reflect(-v, n_surf);
	// Rougher patches (higher `rough`) widen and dim the sharp highlight,
	// smoother patches keep it tight and hot — same logic as a real
	// roughness map driving specular response.
	float soft = pow(max(dot(r_vec, hdir), 0.0), highlight_soft_size) * 0.6;
	float sharp = pow(max(dot(r_vec, hdir), 0.0), mix(highlight_sharp_size, highlight_soft_size * 1.5, rough)) * mix(1.4, 0.7, rough);
	vec3 highlight = vec3(1.0) * (soft + sharp);

	vec3 glassLayer = refracted * 0.08 * (1.0 - alpha) + rim + highlight;

	ALBEDO = accum + glassLayer;
	ALPHA = clamp(alpha + fresnel * 0.55 + soft + sharp, 0.2, 1.0);
}
