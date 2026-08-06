// One puff of ground mist. fog_field.gd owns a pool of these — each is its own
// FogVolume (Ellipsoid shape) with its own copy of this material, repositioned
// and resized every frame rather than sharing one big volume driven by an
// array uniform (that path turned out not to reach the GPU reliably here;
// per-instance simple uniforms do).
//
// The ellipsoid's own bounding box gives the puff's centre and radius for
// free via UVW, so this shader only needs to know how strong *this* puff
// currently is (fading in/out, breaking apart) and where the player is.
shader_type fog;

global uniform vec3 player_position;
global uniform vec3 world_fog_tint;

group_uniforms body;
/// Current strength of this puff — fade-in/out and break-up all fold into
/// this one number, set by fog_field.gd every frame.
uniform float alpha : hint_range(0.0, 1.0) = 1.0;
uniform float density_scale : hint_range(0.0, 8.0) = 3.0;
uniform vec3 fog_albedo : source_color = vec3(0.17, 0.19, 0.24);
/// Fraction of the radius that stays at full strength before falling off.
uniform float core_fraction : hint_range(0.0, 0.9) = 0.15;

group_uniforms detail;
uniform float noise_scale : hint_range(0.02, 2.0) = 0.32;
uniform vec3 drift = vec3(0.03, 0.008, 0.017);
/// How hard the noise eats into the puff. 0 = smooth ball, 1 = shredded.
uniform float wisp_strength : hint_range(0.0, 1.0) = 0.6;

group_uniforms dispersal;
uniform float clear_radius : hint_range(0.5, 8.0) = 2.6;
uniform float clear_strength : hint_range(0.0, 1.0) = 0.85;
/// How far the noise lookup is dragged outward near the player — this is what
/// makes the mist look pushed aside rather than simply thinning out.
uniform float swirl : hint_range(0.0, 8.0) = 3.0;

float hash13(vec3 p) {
	p = fract(p * 0.1031);
	p += dot(p, p.zyx + 31.32);
	return fract((p.x + p.y) * p.z);
}

float vnoise3(vec3 p) {
	vec3 i = floor(p);
	vec3 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);

	float n000 = hash13(i);
	float n100 = hash13(i + vec3(1.0, 0.0, 0.0));
	float n010 = hash13(i + vec3(0.0, 1.0, 0.0));
	float n110 = hash13(i + vec3(1.0, 1.0, 0.0));
	float n001 = hash13(i + vec3(0.0, 0.0, 1.0));
	float n101 = hash13(i + vec3(1.0, 0.0, 1.0));
	float n011 = hash13(i + vec3(0.0, 1.0, 1.0));
	float n111 = hash13(i + vec3(1.0, 1.0, 1.0));

	return mix(
		mix(mix(n000, n100, f.x), mix(n010, n110, f.x), f.y),
		mix(mix(n001, n101, f.x), mix(n011, n111, f.x), f.y),
		f.z);
}

float fbm3(vec3 p) {
	float total = 0.0;
	float amp = 0.5;
	for (int i = 0; i < 3; i++) {
		total += vnoise3(p) * amp;
		p *= 2.11;
		amp *= 0.5;
	}
	return total;
}

void fog() {
	// UVW spans 0..1 across the volume's own bounding box, so this is simply
	// "how far from the ellipsoid's centre, in its own squashed space" — the
	// vertical flattening is already baked in via the node's Size.y, nothing
	// extra to do here.
	vec3 c = (UVW - vec3(0.5)) * 2.0;
	float d = length(c);
	float core = 1.0 - smoothstep(core_fraction, 1.0, d);

	vec3 wp = WORLD_POSITION;
	vec3 to_player = wp - player_position;
	to_player.y *= 0.35;
	float dp = length(to_player);
	float push = 1.0 - smoothstep(0.0, clear_radius, dp);
	vec3 away = dp > 0.001 ? to_player / dp : vec3(0.0, 1.0, 0.0);

	vec3 np = wp * noise_scale + drift * TIME + away * push * swirl;
	float n = fbm3(np);

	float total = core * alpha;
	total *= mix(1.0 - wisp_strength, 1.0 + wisp_strength * 0.35, n);
	total *= 1.0 - push * clear_strength;

	DENSITY = max(total * density_scale, 0.0);
	ALBEDO = fog_albedo * world_fog_tint;
}
