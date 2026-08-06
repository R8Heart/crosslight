// Full night sky: twinkling stars of varied size/colour, a real textured moon
// disc drawn wherever the scene's directional light points from (so the light
// and the visible moon can never drift apart), and animated puffy clouds that
// scroll across, occlude the moon, catch a silver lining near it, and can carry
// lightning from the inside.
//
// All of it is analytic — there is no photographic HDRI anywhere, which is the
// whole point: a real night photo always carries atmospheric glow near the
// horizon that cannot be removed, and that glow is exactly what we did not want.
shader_type sky;

group_uniforms stars;
// Multiplier on the per-layer base densities below. Those are deliberately tiny
// (a few thousandths): the star grid has millions of cells, so anything higher
// turns the sky into solid white noise rather than a starfield.
uniform float star_density : hint_range(0.0, 3.0) = 1.0;
uniform float star_brightness : hint_range(0.0, 4.0) = 1.5;
uniform float twinkle_speed : hint_range(0.0, 8.0) = 2.0;
uniform vec3 sky_color : source_color = vec3(0.004, 0.006, 0.013);

group_uniforms moon;
uniform sampler2D moon_tex : source_color, filter_linear_mipmap;
uniform float moon_angular_radius : hint_range(0.005, 0.3) = 0.06;
uniform float moon_brightness : hint_range(0.0, 8.0) = 2.6;
uniform vec3 moon_tint : source_color = vec3(0.82, 0.88, 1.0);
uniform float moon_halo : hint_range(0.0, 4.0) = 0.9;
uniform float moon_halo_falloff : hint_range(1.0, 200.0) = 40.0;

group_uniforms clouds;
uniform float cloud_coverage : hint_range(0.0, 1.0) = 0.5;
uniform float cloud_softness : hint_range(0.01, 1.0) = 0.32;
uniform float cloud_scale : hint_range(0.1, 10.0) = 1.4;
uniform vec2 cloud_wind = vec2(0.03, 0.01);
uniform float cloud_warp : hint_range(0.0, 4.0) = 1.5;
uniform vec3 cloud_dark : source_color = vec3(0.028, 0.034, 0.052);
uniform vec3 cloud_lit : source_color = vec3(0.55, 0.62, 0.8);
uniform float cloud_silver : hint_range(0.0, 6.0) = 2.0;
// Even the thickest, densest cloud never fully erases what is behind it — a
// real overcast sky dims the moon to a hazy glow, it does not cut it out to
// a flat silhouette. This is the ceiling on how much of the cloud colour can
// replace the sky/moon/stars behind it, however dense the noise gets.
uniform float cloud_opacity : hint_range(0.0, 1.0) = 0.8;

group_uniforms storm;
uniform float lightning_flash : hint_range(0.0, 1.0) = 0.0;
uniform vec2 lightning_pos = vec2(0.0, 0.0);
uniform vec3 lightning_color : source_color = vec3(0.45, 1.0, 0.55);
uniform float lightning_reach : hint_range(0.1, 8.0) = 2.0;

group_uniforms world;
// Tinted by the world-state controller so the whole sky shifts with the orb.
uniform vec3 world_tint : source_color = vec3(1.0, 1.0, 1.0);

vec3 hash33(vec3 p) {
	p = vec3(dot(p, vec3(127.1, 311.7, 74.7)),
			 dot(p, vec3(269.5, 183.3, 246.1)),
			 dot(p, vec3(113.5, 271.9, 124.6)));
	return fract(sin(p) * 43758.5453123);
}

float hash21(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	float a = hash21(i);
	float b = hash21(i + vec2(1.0, 0.0));
	float c = hash21(i + vec2(0.0, 1.0));
	float d = hash21(i + vec2(1.0, 1.0));
	return mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
}

float fbm(vec2 p, int octaves) {
	float total = 0.0;
	float amp = 0.5;
	for (int i = 0; i < octaves; i++) {
		total += vnoise(p) * amp;
		p *= 2.03;
		amp *= 0.5;
	}
	return total;
}

// One layer of stars. Each cell of the direction-space grid may hold a single
// star; its jitter, size, brightness, colour and twinkle phase all come out of
// the same hash so no two stars behave alike.
vec3 star_layer(vec3 dir, float scale, float density, float size, float time) {
	vec3 cell = floor(dir * scale);
	vec3 h = hash33(cell);
	if (h.x > density) {
		return vec3(0.0);
	}
	vec3 star_dir = normalize((cell + vec3(0.15) + h * 0.7) / scale);
	float d = distance(dir, star_dir) * scale;

	float phase = h.z * 6.2831853;
	float rate = 0.4 + h.y * 2.2;
	float twinkle = 0.45 + 0.55 * sin(time * twinkle_speed * rate + phase);
	// A slower second beat keeps a few stars steady while others flicker hard.
	twinkle *= 0.7 + 0.3 * sin(time * twinkle_speed * 0.21 + phase * 2.1);

	float mag = (0.25 + h.y * 0.75) * max(twinkle, 0.0);

	// Screen-derivative antialiasing: without it a disc this small in angular
	// terms only ever covers a handful of pixels, and a hard smoothstep edge
	// evaluated at just those few pixel centres aliases into a blocky diamond
	// instead of a soft dot — this is what was actually reading as "cartoon
	// squares", not glow (confirmed by rendering with glow off).
	float aa = max(fwidth(d), 0.0008);
	float shape = 1.0 - smoothstep(size - aa, size + aa, d);
	// Faint cross-flare on the brightest few, the way a real bright star reads.
	float flare_edge = size * 4.0;
	float flare = (1.0 - smoothstep(flare_edge - aa, flare_edge + aa, d))
		* smoothstep(0.75, 1.0, h.y) * 0.35;

	vec3 tint = mix(vec3(0.62, 0.75, 1.0), vec3(1.0, 0.82, 0.66), h.z);
	tint = mix(vec3(1.0), tint, 0.75);
	return tint * (shape + flare) * mag;
}

vec2 cloud_uv(vec3 dir) {
	// Projected onto a dome overhead so the layer recedes toward the horizon.
	// The constant in the denominator caps how far it can stretch — dividing by
	// dir.y alone smears everything near the horizon into long streaks, which
	// reads as thin cirrus instead of the heaped clouds we want.
	float y = max(dir.y, 0.0) + 0.45;
	return (dir.xz / y) * cloud_scale + cloud_wind * TIME;
}

void sky() {
	vec3 dir = EYEDIR;
	float t = TIME;

	// ------------------------------------------------------------ stars
	// Three layers: a few big bright ones, more mid ones, and fine dust. The
	// densities look absurdly small because they are per grid cell, and the grid
	// has ~4*PI*scale^2 cells over the sphere.
	vec3 stars = vec3(0.0);
	stars += star_layer(dir, 120.0, 0.012 * star_density, 0.09, t);
	stars += star_layer(dir, 300.0, 0.0030 * star_density, 0.08, t + 31.0);
	stars += star_layer(dir, 620.0, 0.0009 * star_density, 0.09, t + 77.0);
	stars *= star_brightness;
	// No stars below the horizon line.
	stars *= smoothstep(-0.05, 0.06, dir.y);

	// ------------------------------------------------------------ moon
	// LIGHT0_DIRECTION points *toward* the light (same convention the built-in
	// procedural sky uses to place its sun), so the disc goes straight there.
	// Drawing it from the light itself is what keeps the visible moon and the
	// direction of the moonlight locked together no matter how the light moves.
	vec3 moon_dir = normalize(LIGHT0_DIRECTION);
	float cos_a = dot(dir, moon_dir);
	float ang = acos(clamp(cos_a, -1.0, 1.0));

	vec3 ref = abs(moon_dir.y) > 0.98 ? vec3(1.0, 0.0, 0.0) : vec3(0.0, 1.0, 0.0);
	vec3 m_right = normalize(cross(ref, moon_dir));
	vec3 m_up = cross(moon_dir, m_right);

	vec3 perp = dir - moon_dir * cos_a;
	float dx = dot(perp, m_right) / moon_angular_radius;
	float dy = dot(perp, m_up) / moon_angular_radius;
	float r = sqrt(dx * dx + dy * dy);

	vec3 moon_col = vec3(0.0);
	if (r < 1.02 && cos_a > 0.0) {
		// Proper spherical projection: the texture wraps around a real sphere so
		// craters compress toward the limb instead of looking like a flat sticker.
		float rc = min(r, 0.999);
		float z = sqrt(max(1.0 - rc * rc, 0.0));
		float lat = asin(clamp(dy, -1.0, 1.0));
		float lon = atan(dx, max(z, 0.0001));
		vec2 uv = vec2(0.5 + lon / 6.2831853, 0.5 - lat / 3.14159265);
		vec3 surface = texture(moon_tex, uv).rgb;
		float disc = smoothstep(1.0, 0.985, r);
		moon_col = surface * moon_tint * moon_brightness * disc;
	}

	// Soft halo bleeding out from the disc into the surrounding sky.
	float halo = exp(-ang * moon_halo_falloff) * moon_halo;
	vec3 halo_col = moon_tint * halo;

	// ------------------------------------------------------------ clouds
	vec2 cuv = cloud_uv(dir);
	// Warping the lookup by another noise field is what turns smooth blobs into
	// billowing, clumped masses instead of soft grey stains.
	float warp = fbm(cuv * 0.45, 3);
	float base = fbm(cuv + vec2(warp) * cloud_warp, 5);
	// Eroding the base with higher-frequency noise tears the edges open, giving
	// the ragged, porous rim a real cloud has.
	float detail = fbm(cuv * 3.1 - vec2(warp) * 0.6, 3);
	float shape = base - (1.0 - base) * detail * 0.45;

	float density = smoothstep(1.0 - cloud_coverage, 1.0 - cloud_coverage + cloud_softness, shape);
	density *= smoothstep(0.0, 0.16, dir.y);

	// Two-part moonlight on the cloud: a wide wash over the whole moonward half
	// of the sky, plus a hot silver rim right around the disc, strongest where
	// the cloud is thin enough for light to come through.
	float broad = pow(max(cos_a, 0.0), 2.0);
	float tight = pow(max(cos_a, 0.0), 40.0);
	float thin = 1.0 - density;
	vec3 cloud_col = cloud_dark;
	cloud_col += cloud_lit * broad * 0.20;
	cloud_col += cloud_lit * tight * (0.3 + 0.7 * thin) * cloud_silver;

	// ------------------------------------------------------------ lightning
	if (lightning_flash > 0.001) {
		float ld = length(cuv - lightning_pos);
		float core = exp(-ld * lightning_reach);
		float bloom = exp(-ld * lightning_reach * 0.28) * 0.35;
		// Lights the cloud from within, so it reads as discharge inside the mass
		// rather than a lamp stuck in front of it.
		cloud_col += lightning_color * (core * (0.35 + density * 1.6) + bloom * density) * lightning_flash * 3.0;
	}

	vec3 background = sky_color + stars + moon_col + halo_col;
	vec3 col = mix(background, cloud_col, density * cloud_opacity);

	// Whole-sky wash during a strike, dimmer than the cloud itself.
	col += lightning_color * lightning_flash * 0.03;

	COLOR = col * world_tint;
}
