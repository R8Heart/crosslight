shader_type spatial;
// Volumetric raymarched fire.
//
// Adapted from "Spatial Fire Raymarched v2.0" by Dari0us (CC0 / MIT),
// https://godotshaders.com/shader/spatial-fire-raymarched/ -- see
// docs/credits.md. Rewritten here only for integration (world tint, zone
// dimming, tidier structure) plus one upstream fix noted at the march
// loop; the actual fire algorithm is theirs and is left intact.
//
// Three things this does that a hand-rolled version easily gets wrong,
// and that every earlier attempt in this project got wrong:
//   * Alpha compositing with real absorption, not additive accumulation.
//     Summing emission blows out to flat white wherever the volume is
//     dense, which is what made previous versions look washed out.
//   * A shape defined by a signed distance field that noise *perturbs*,
//     rather than a smooth radial falloff that noise multiplies. Only the
//     former gives torn, tapering edges.
//   * High-frequency, high-contrast, domain-warped noise. Smooth low
//     octave noise cannot produce flame tongues at any settings.
//
// The mesh is only a proxy screen: it billboards so it always covers the
// fire, while the fire volume itself is anchored in world space around
// the node's origin. So the flame never turns to face the camera -- only
// the invisible surface being marched through does.
render_mode unshaded, cull_disabled, blend_mix, depth_draw_opaque;

group_uniforms quality;
uniform int raymarch_steps : hint_range(2, 24) = 6;
uniform bool sample_jitter = true;
// Diagnostic: paints the proxy quad flat green and skips the raymarch
// entirely. If the fire is invisible, this separates "the surface isn't
// being drawn at all" (nothing appears) from "it draws but the volume
// comes out empty" (a green rectangle appears).
uniform bool debug_show_proxy = false;

group_uniforms shape;
uniform sampler3D sample_noise;
uniform sampler2D depth_texture : hint_depth_texture;
uniform bool billboard = true;
uniform float billboard_z_offset = 0.675;
uniform float proximity_fade_distance = 0.375;
uniform float time_scale = 0.027;
uniform float noise_scale = 0.45;
uniform float noise_threshold = 0.43;
uniform float fire_height = 2.45;
uniform float fire_width = 2.25;
uniform float taper_factor = 0.425;
uniform float wobble_strength = 2.0;
uniform float wobble_speed = 6.0;
uniform float wobble_noise_frequency : hint_range(0.1, 10.0) = 0.125;
uniform float sharpness_cutoff : hint_range(0.0, 20.0) = 4.5;

group_uniforms look;
uniform float emission_strength = 12.5;
uniform float core_glow_multiplier : hint_range(0.0, 20.0) = 16.0;
uniform vec3 color_core : source_color = vec3(1.0, 0.9, 0.5);
uniform vec3 color_mid : source_color = vec3(1.0, 0.625, 0.0);
uniform vec3 color_outer : source_color = vec3(0.8, 0.01, 0.0);
// Deliberately negative: this is subtracted into the mix to darken the
// cooling tips into smoke rather than adding grey on top of them.
uniform vec3 color_smoke = vec3(-0.067, -0.067, -0.067);

varying vec3 world_position;
varying vec3 world_camera;

// Height the upstream shader was authored at. Several of its constants
// are in world units -- how far noise displaces the surface, how far the
// wobble pushes a sample, the proximity fade distance -- so they only
// behave as intended at roughly that size. A hearth fire is about a
// quarter of it, at which the 0.3m surface displacement alone exceeds the
// whole flame and pushes the distance field positive everywhere, so
// nothing ever registers as burning. Everything in world units is scaled
// by this instead.
const float AUTHORED_HEIGHT = 2.45;

float size_ref() {
	return max(fire_height, 0.001) / AUTHORED_HEIGHT;
}

vec3 get_box_center(vec3 node_world) {
	// The node sits at the base of the fire, so the volume is centred half
	// a flame-height above it.
	return node_world + vec3(0.0, fire_height * 0.5, 0.0);
}

float get_animated_time() {
	return -TIME * time_scale;
}

// Position is divided by the size reference before scaling, so a small
// fire gets proportionally the same noise features as a large one rather
// than a few metres-wide blobs spanning the whole flame.
float get_noise_value(vec3 p_coord, float scale_factor, float time_offset_y) {
	vec3 tex_coords = p_coord / size_ref() * scale_factor + vec3(0.0, time_offset_y, 0.0);
	return texture(sample_noise, fract(tex_coords)).r;
}

float sdf_box(vec3 p, vec3 b) {
	vec3 q = abs(p) - b;
	return length(max(vec3(0.0), q)) + min(0.0, max(q.x, max(q.y, q.z)));
}

// Three independent noise lookups, one per axis, at different time rates:
// this is what curls the flame instead of letting it rise as a straight
// column.
vec3 get_per_sample_wobble(vec3 p, float strength, float noise_freq, float speed) {
	float t = get_animated_time();
	float wx = get_noise_value(p + vec3(100.0, 0.0, 0.0), noise_freq, t * speed);
	float wy = get_noise_value(p + vec3(0.0, 200.0, 0.0), noise_freq, t * speed * 1.2);
	float wz = get_noise_value(p + vec3(0.0, 0.0, 300.0), noise_freq, t * speed * 0.8);
	return vec3(wx - 0.5, wy - 0.5, wz - 0.5) * strength;
}

// Distance to the flame body: a tapering box, with noise added straight
// onto the distance so the surface is eaten into tongues.
float fire_sdf(vec3 p, vec3 node_world) {
	vec3 local_p = p - get_box_center(node_world);
	vec3 box_size = vec3(fire_width, fire_height, fire_width);

	float normalized_height = (local_p.y + box_size.y * 0.5) / box_size.y;
	float current_taper = max(0.01, 1.0 - normalized_height * taper_factor);
	vec3 tapered = local_p;
	tapered.xz /= current_taper;

	vec3 wobble = get_per_sample_wobble(local_p, wobble_strength * size_ref(), wobble_noise_frequency, wobble_speed);
	float dist = sdf_box(tapered, box_size * 0.5);
	// Displacement in world units, hence scaled: this is what tears the
	// box's flat sides into tongues, and it has to stay a fraction of the
	// flame rather than a fixed 0.3m.
	dist += get_noise_value(local_p + wobble, noise_scale * 0.5, get_animated_time() * 20.0) * 0.3 * size_ref();
	return dist;
}

float hash(vec3 p) {
	p = fract(p * 0.3183099 + vec3(0.1, 0.3, 0.7));
	p = p * dot(p, p.yzx + 19.19);
	return fract((p.x + p.y) * p.z);
}

void vertex() {
	if (billboard) {
		mat3 cam_rotation = mat3(
			MAIN_CAM_INV_VIEW_MATRIX[0].xyz,
			MAIN_CAM_INV_VIEW_MATRIX[1].xyz,
			MAIN_CAM_INV_VIEW_MATRIX[2].xyz);
		VERTEX = cam_rotation * VERTEX;
		NORMAL = cam_rotation * NORMAL;
		// Pushed along the camera's own Z so the proxy plane stays in
		// front of the volume when looking down at the fire.
		VERTEX += MAIN_CAM_INV_VIEW_MATRIX[2].xyz
				* (CAMERA_DIRECTION_WORLD.y + billboard_z_offset) * size_ref();
	}
	world_position = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	world_camera = INV_VIEW_MATRIX[3].xyz;
}

void fragment() {
	// Godot's shader language forbids `return` inside the fragment
	// entry point, so the diagnostic path has to be a branch rather
	// than an early exit.
	if (debug_show_proxy) {
		ALBEDO = vec3(0.0, 1.0, 0.0);
		EMISSION = vec3(0.0, 1.0, 0.0);
		ALPHA = 0.4;
	} else {
		vec3 ray_origin = world_camera;
		vec3 ray_direction = normalize(world_position - world_camera);

		vec3 fire_world_center = get_box_center(NODE_POSITION_WORLD);
		vec3 box_size = vec3(fire_width, fire_height, fire_width);
		float max_dim = max(box_size.x, max(box_size.y, box_size.z));
		vec3 half_extents = vec3(max_dim);

		vec3 box_min = fire_world_center - half_extents * 0.5;
		vec3 box_max = fire_world_center + half_extents * 0.5;

		vec3 inv_dir = 1.0 / ray_direction;
		vec3 t0 = (box_min - ray_origin) * inv_dir;
		vec3 t1 = (box_max - ray_origin) * inv_dir;
		vec3 t_smaller = min(t0, t1);
		vec3 t_larger = max(t0, t1);

		float t_enter = max(0.0, max(t_smaller.x, max(t_smaller.y, t_smaller.z)));
		float t_exit = min(t_larger.x, min(t_larger.y, t_larger.z));
		if (t_enter >= t_exit) {
			discard;
		}

		float march_range = t_exit - t_enter;
		if (march_range <= 0.0001) {
			discard;
		}

		// Looking along the flame's axis means far less of it per pixel, so
		// spend more steps at grazing angles than head-on.
		float angle_factor = clamp(1.0 - abs(dot(ray_direction, vec3(0.0, 1.0, 0.0))), 0.0, 1.0);
		int adjusted_steps = clamp(int(float(raymarch_steps) * mix(1.0, 2.5, angle_factor)), raymarch_steps, 24);
		// Upstream divides the range by raymarch_steps here even when it has
		// just computed adjusted_steps, because its own reassignment lands in
		// an inner scope and is discarded -- so the extra grazing-angle steps
		// overshoot the volume. Divided by the count actually used.
		float step_size = march_range / float(adjusted_steps);

		float total_distance = t_enter;
		vec3 final_color = vec3(0.0);
		float current_alpha = 0.0;

		for (int i = 0; i < 48; i++) {
			if (i >= adjusted_steps || total_distance >= t_exit) {
				break;
			}

			vec3 sample_position = ray_origin + ray_direction * total_distance;
			if (sample_jitter) {
				// Randomising each sample's position along the ray trades
				// banding for noise, which the eye forgives far more readily.
				vec3 hash_input = sample_position * 1.25 + ray_direction * 33.333 + vec3(TIME * 33.333);
				sample_position += ray_direction * (hash(hash_input) - 0.5) * step_size;
			}

			float sdf_dist = fire_sdf(sample_position, NODE_POSITION_WORLD);
			vec3 wobble = get_per_sample_wobble(sample_position, wobble_strength * 0.7 * size_ref(),
					wobble_noise_frequency * 1.1, wobble_speed * 0.9);
			float noise_val = get_noise_value(sample_position + wobble, noise_scale * 0.7,
					get_animated_time() * 30.0);

			float density = 0.0;
			if (sdf_dist < 0.0) {
				float noise_shaping = 1.0 - smoothstep(noise_threshold * 0.8, noise_threshold * 1.2, noise_val);
				density = clamp(smoothstep(0.0, sharpness_cutoff, -sdf_dist * 0.5 + noise_shaping), 0.0, 1.0);

				vec3 local_pos = sample_position - fire_world_center;
				// Thin out toward the tips, and toward the outside of the
				// column, so the fire has a dense heart and frayed edges.
				float height_alpha = pow(smoothstep(0.5, 1.0, (local_pos.y + box_size.y * 0.5) / box_size.y), 0.333);
				density *= 1.0 - height_alpha;
				density *= smoothstep(0.7, 0.0, length(local_pos.xz) / (box_size.x * 0.5));
			}

			// Beer-Lambert absorption over the step, then front-to-back
			// compositing. This is the part that keeps a thick flame reading
			// as fire instead of saturating to white the way plain additive
			// accumulation does.
			float alpha_step = 1.0 - exp(-density * step_size * 25.0);

			vec3 col = mix(color_outer, color_mid, noise_val);
			col = mix(col, color_core, smoothstep(0.7, 1.0, density * core_glow_multiplier));
			float height_factor = (sample_position.y - fire_world_center.y + box_size.y * 0.5) / box_size.y;
			col = mix(col, color_smoke, smoothstep(0.6, 1.0, height_factor * (1.0 - density)));

			final_color += col * alpha_step * (1.0 - current_alpha);
			current_alpha += alpha_step * (1.0 - current_alpha);
			if (current_alpha > 0.99) {
				break;
			}
			total_distance += step_size;
		}

		ALPHA = clamp(current_alpha, 0.0, 1.0);

		// Soften where the volume meets solid geometry, so the flame doesn't
		// cut a hard line against the logs it sits between.
		float scene_depth = textureLod(depth_texture, SCREEN_UV, 0.0).r;
		vec4 scene_view = INV_PROJECTION_MATRIX * vec4(SCREEN_UV * 2.0 - 1.0, scene_depth, 1.0);
		scene_view.xyz /= scene_view.w;
		// Also in world units: at a fixed 0.375m this fades out an entire
		// hearth-sized flame, since every part of it is within that distance
		// of the logs it stands in.
		float fade = proximity_fade_distance * size_ref();
		ALPHA *= clamp(1.0 - smoothstep(scene_view.z + fade, scene_view.z, VERTEX.z), 0.0, 1.0);

		ALBEDO = final_color * emission_strength;
		EMISSION = ALBEDO;
	}
}
