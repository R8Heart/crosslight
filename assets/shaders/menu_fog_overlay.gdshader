// Drifting, billowing fog for 2D UI overlays -- see assets/shaders/
// fog_field.gdshader for the 3D version tied to the player's world position;
// this one is a plain canvas_item shader for a flat screen-space backdrop
// layer (ColorRect), not for hiding specific 3D geometry -- see
// assets/shaders/menu_fog_volume.gdshader for that.
//
// Shape is a two-level domain-warped FBM (fractal Brownian motion) --
// sample a noise field, use its own output to distort the coordinates fed
// into a second noise sample, twice over. This is the standard real-time
// smoke/mist recipe (see Inigo Quilez's "Fractal Brownian Motion" writeup,
// or any Shadertoy "clouds"/"smoke" demo built the same way): it produces
// continuous, amorphous, curling shapes with no repeating structure and no
// hard cell boundaries anywhere.
//
// An earlier version of this shader used Worley/cellular noise for the
// base shape instead. That is the right tool for thick volumetric cloud
// *tops* viewed close up (Horizon Zero Dawn-style cauliflower puffs), but
// for a flat ground-hugging mist layer it reads as exactly what it is: a
// tiling pattern of separate round blobs, made worse by a glint pass that
// traced a bright ring around every single blob's edge -- a spotted/
// cellular look, not fog. Warped FBM has no such cell identity to outline,
// so it doesn't have that failure mode.
shader_type canvas_item;

uniform vec4 fog_color : source_color = vec4(0.05, 0.11, 0.07, 1.0);
uniform vec4 fog_color_bright : source_color = vec4(0.17, 0.32, 0.19, 1.0);
uniform vec4 glint_color : source_color = vec4(0.72, 0.9, 0.6, 1.0);
/// Subtle internal brightness shimmer inside dense mist, standing in for
/// light catching drifting haze -- NOT an edge/outline effect, so it never
/// traces a ring around a "blob" the way a boundary-detection pass would.
uniform float glint_strength : hint_range(0.0, 3.0) = 0.5;
uniform float density : hint_range(0.0, 3.0) = 1.7;
uniform float noise_scale : hint_range(0.2, 6.0) = 1.1;
/// Higher = a narrower, punchier transition between "clear" and "dense".
/// Lower = a slow, soft gradient -- real mist has no sharp edges, so keep
/// this modest (1.0-2.0) unless deliberately going for a stylized look.
uniform float contrast : hint_range(0.3, 6.0) = 1.4;
uniform vec2 drift_a = vec2(0.035, -0.012);
uniform vec2 drift_b = vec2(-0.02, 0.017);
/// How far the domain warp displaces samples, in noise-space units. Unlike
/// a cellular-noise warp, there is no cell boundary here to tear across --
/// large values just mean more aggressive swirling, not artifacts.
uniform float warp_strength : hint_range(0.0, 4.0) = 1.6;
/// Fully clear at the gradient_start side, ramps to full density by
/// gradient_end. Direction is left-to-right unless gradient_reverse flips
/// it to right-to-left -- needed because the same UV.x=0..1 span means the
/// opposite screen side depending on where a given ColorRect is anchored.
uniform float gradient_start : hint_range(0.0, 1.0) = 0.15;
uniform float gradient_end : hint_range(0.0, 1.0) = 0.7;
uniform bool gradient_reverse = false;
/// Fades the top/bottom edges of the rect to nothing instead of a hard
/// cutoff. 0 = off (full-screen backdrops don't need this since their
/// edges are the screen edge); raise it for a smaller, localized patch
/// where the rect's own top/bottom would otherwise show as a hard line.
uniform float vertical_softness : hint_range(0.0, 1.0) = 0.0;

float hash12(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

float vnoise2(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	float n00 = hash12(i);
	float n10 = hash12(i + vec2(1.0, 0.0));
	float n01 = hash12(i + vec2(0.0, 1.0));
	float n11 = hash12(i + vec2(1.0, 1.0));
	return mix(mix(n00, n10, f.x), mix(n01, n11, f.x), f.y);
}

/// 5-octave value-noise FBM, range roughly 0..1.06. Used both as the field
/// being warped and as the warp field itself -- see fragment() below.
float fbm2(vec2 p) {
	float total = 0.0;
	float amp = 0.5;
	for (int i = 0; i < 5; i++) {
		total += vnoise2(p) * amp;
		p *= 2.08;
		amp *= 0.55;
	}
	return total;
}

void fragment() {
	vec2 uv = UV;
	float x = gradient_reverse ? 1.0 - uv.x : uv.x;
	float gradient = smoothstep(gradient_start, gradient_end, x);

	if (vertical_softness > 0.0) {
		float v_centered = abs(uv.y * 2.0 - 1.0);
		gradient *= 1.0 - smoothstep(1.0 - vertical_softness, 1.0, v_centered);
	}

	vec2 p = uv * noise_scale;

	// First warp pass: distort p by an independent noise field before
	// sampling anything visible -- this is what makes the result curl and
	// billow instead of just sliding sideways with drift.
	vec2 warp1 = vec2(fbm2(p + drift_a * TIME), fbm2(p + vec2(5.2, 1.3) + drift_a * TIME)) - 0.5;
	vec2 q = p + warp1 * warp_strength;

	// Second warp pass, at a different frequency/phase, applied on top of
	// the first -- two nested warps read as genuinely turbulent, rolling
	// motion rather than a single wobble.
	vec2 warp2 = vec2(fbm2(q * 1.8 + vec2(1.7, 9.2) + drift_b * TIME * 1.4), fbm2(q * 1.8 + vec2(8.3, 2.8) + drift_b * TIME * 1.4)) - 0.5;
	vec2 r = q + warp2 * warp_strength * 0.6;

	float base = fbm2(r * 1.15 + drift_a * TIME * 0.6);

	// A finer, faster-drifting layer sampled in mostly-unwarped space --
	// adds fine mist texture on top of the big billowing shapes without
	// introducing any isolated blob silhouettes of its own.
	float fine = fbm2(uv * noise_scale * 3.4 + drift_b * TIME * 1.9);

	float raw = clamp(base * 0.75 + fine * 0.3, 0.0, 1.0);

	// Soft S-curve centered on the noise's own midpoint -- narrows for a
	// punchier look as contrast rises, but never produces a hard edge the
	// way pow() with a steep exponent does.
	float half_width = 0.5 / max(contrast, 0.05);
	float n = smoothstep(0.5 - half_width, 0.5 + half_width, raw);

	// Sub-LSB screen-space dither so the smooth low-variance parts of the
	// gradient don't quantize into visible stepped bands.
	float dither = (hash12(FRAGCOORD.xy) - 0.5) * (1.0 / 80.0);

	float alpha = clamp(n * density + dither, 0.0, 1.0) * gradient;

	vec3 col = mix(fog_color.rgb, fog_color_bright.rgb, clamp(n * 1.3, 0.0, 1.0));

	// Subtle internal shimmer: brighten in step with the fine-detail layer,
	// gated by how dense the mist already is there. No edge-detection, so
	// it never traces an outline around anything -- just a soft inner glow
	// that drifts with the fine noise, standing in for light scattering
	// through moving haze.
	col += glint_color.rgb * fine * n * glint_strength * gradient;

	COLOR = vec4(col, alpha);
}
