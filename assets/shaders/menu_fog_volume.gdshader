// A billowing, alpha-blended wisp of fog for hiding a specific bit of 3D
// geometry -- e.g. draping across an arm right where its mesh cuts off, so
// the raw edge disappears into mist instead of ending abruptly.
//
// Unlike assets/shaders/menu_fog_overlay.gdshader (a flat screen-space
// backdrop), this is a real object sitting in the 3D scene at whatever
// depth you place it: put a MeshInstance3D with a QuadMesh where the arm
// should start fading out, apply this material, and scale/rotate it to
// cover that spot. No billboarding -- the hand rig only sways a little, so
// a fixed angle (set once by eye) holds up fine without it, and a custom
// spatial shader has no built-in billboard render mode (that's a
// StandardMaterial3D-only feature) -- faking it means overriding
// MODELVIEW_MATRIX in vertex(), not worth the complexity here.
//
// Shape is a two-level domain-warped FBM (fractal Brownian motion), same
// recipe and same reasoning as menu_fog_overlay.gdshader -- see that
// file's header. An earlier version of both shaders used Worley/cellular
// noise for the base shape, which reads as a tiling pattern of separate
// round blobs rather than continuous mist, especially up close where these
// quads typically sit (well under 1 world unit from the camera, so only a
// couple of "cells" were ever visible at once). Warped FBM has no cell
// identity to read as a blob, so it doesn't have that failure mode. Kept
// as a near-identical copy of the overlay shader rather than shared code
// because Godot shaders can't #include another shader file's functions.
shader_type spatial;
render_mode unshaded, blend_mix, cull_disabled, depth_draw_never, shadows_disabled, fog_disabled;

uniform vec4 fog_color : source_color = vec4(0.05, 0.11, 0.07, 1.0);
uniform vec4 fog_color_bright : source_color = vec4(0.19, 0.34, 0.2, 1.0);
uniform vec4 glint_color : source_color = vec4(0.72, 0.9, 0.6, 1.0);
/// Subtle internal brightness shimmer inside dense mist, standing in for
/// light catching drifting haze -- NOT an edge/outline effect.
uniform float glint_strength : hint_range(0.0, 3.0) = 0.5;
uniform float density : hint_range(0.0, 4.0) = 2.4;
uniform float noise_scale : hint_range(0.2, 6.0) = 1.3;
/// Higher = a narrower, punchier transition between "clear" and "dense".
/// Lower = a slow, soft gradient -- real mist has no sharp edges, so keep
/// this modest (1.0-2.0) unless deliberately going for a stylized look.
uniform float contrast : hint_range(0.3, 6.0) = 1.3;
uniform vec2 drift = vec2(0.05, 0.025);
/// How far the domain warp displaces samples, in noise-space units. No
/// cell boundary to tear across here -- large values just mean more
/// aggressive swirling, not artifacts.
uniform float warp_strength : hint_range(0.0, 4.0) = 1.6;
/// Fades out toward the top/bottom (V) edges of the quad.
uniform float edge_softness : hint_range(0.0, 1.0) = 0.85;
/// Fades out toward the left/right (U) edges of the quad, on top of the
/// gradient below. These quads often sit close enough to the camera that
/// their own polygon boundary can end up inside the visible frame -- without
/// this, that boundary is a hard, dead-straight cutoff line where the mesh
/// simply stops. Keep it well above 0 whenever a quad might not be safely
/// outside the camera frustum.
uniform float side_softness : hint_range(0.0, 1.0) = 0.35;
/// A quad that's uniformly dense in its centre just hides whatever's behind
/// it -- the thing itself still vanishes at a hard edge, only now behind a
/// wall of fog instead of in the open. Rotate/place the quad so its local
/// U axis runs along whatever needs to dissolve (fist -> cut-off point),
/// and this ramps density along that axis instead: clear at gradient_start,
/// fully opaque by gradient_end, so the object fades out gradually rather
/// than disappearing behind an opaque patch.
uniform float gradient_start : hint_range(0.0, 1.0) = 0.15;
uniform float gradient_end : hint_range(0.0, 1.0) = 0.85;

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
	float v_centered = abs(uv.y * 2.0 - 1.0);
	float edge_fade = 1.0 - smoothstep(1.0 - edge_softness, 1.0, v_centered);
	float gradient = smoothstep(gradient_start, gradient_end, uv.x);

	if (side_softness > 0.0) {
		float u_centered = abs(uv.x * 2.0 - 1.0);
		edge_fade *= 1.0 - smoothstep(1.0 - side_softness, 1.0, u_centered);
	}

	vec2 p = uv * noise_scale;

	// First warp pass: distort p by an independent noise field before
	// sampling anything visible -- this is what makes the result curl and
	// billow instead of just sliding sideways with drift.
	vec2 warp1 = vec2(fbm2(p + drift * TIME), fbm2(p + vec2(5.2, 1.3) + drift * TIME)) - 0.5;
	vec2 q = p + warp1 * warp_strength;

	// Second warp pass, at a different frequency/phase, applied on top of
	// the first -- two nested warps read as genuinely turbulent, rolling
	// motion rather than a single wobble.
	vec2 warp2 = vec2(fbm2(q * 1.8 + vec2(1.7, 9.2) + drift * TIME * 1.4), fbm2(q * 1.8 + vec2(8.3, 2.8) + drift * TIME * 1.4)) - 0.5;
	vec2 r = q + warp2 * warp_strength * 0.6;

	float base = fbm2(r * 1.15 + drift * TIME * 0.6);

	// A finer, faster-drifting layer sampled in mostly-unwarped space --
	// adds fine mist texture on top of the big billowing shapes without
	// introducing any isolated blob silhouettes of its own.
	float fine = fbm2(uv * noise_scale * 3.4 + drift * TIME * 1.9 * 1.4);

	float raw = clamp(base * 0.75 + fine * 0.3, 0.0, 1.0);

	// Soft S-curve centered on the noise's own midpoint -- narrows for a
	// punchier look as contrast rises, but never produces a hard edge the
	// way pow() with a steep exponent does.
	float half_width = 0.5 / max(contrast, 0.05);
	float n = smoothstep(0.5 - half_width, 0.5 + half_width, raw);

	ALBEDO = mix(fog_color.rgb, fog_color_bright.rgb, clamp(n * 1.3, 0.0, 1.0));

	// Subtle internal shimmer: brighten in step with the fine-detail layer,
	// gated by how dense the mist already is there. No edge-detection, so
	// it never traces an outline around anything -- just a soft inner glow
	// that drifts with the fine noise, standing in for light scattering
	// through moving haze.
	ALBEDO += glint_color.rgb * fine * n * glint_strength * edge_fade * gradient;

	// Sub-LSB screen-space dither so the smooth low-variance parts of the
	// gradient don't quantize into visible stepped bands.
	float dither = (hash12(FRAGCOORD.xy) - 0.5) * (1.0 / 80.0);

	ALPHA = clamp(n * density + dither, 0.0, 1.0) * edge_fade * gradient;
}
