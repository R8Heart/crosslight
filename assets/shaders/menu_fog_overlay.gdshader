// Drifting, billowing fog for 2D UI overlays -- see assets/shaders/
// fog_field.gdshader for the 3D version tied to the player's world position;
// this one is a plain canvas_item shader for a flat screen-space backdrop
// layer (ColorRect), not for hiding specific 3D geometry -- see
// assets/shaders/menu_fog_volume.gdshader for that.
//
// Density follows a straight left-right gradient (not a radial falloff --
// a circular fade reads as a lens/vignette, not fog) so it can sit dense on
// whichever side the subject is on and fade to fully clear on the side that
// needs to stay readable (e.g. a menu list).
shader_type canvas_item;

uniform vec4 fog_color : source_color = vec4(0.06, 0.13, 0.08, 1.0);
uniform vec4 fog_color_bright : source_color = vec4(0.18, 0.34, 0.20, 1.0);
uniform float density : hint_range(0.0, 3.0) = 1.8;
uniform float noise_scale : hint_range(0.3, 10.0) = 1.6;
uniform float contrast : hint_range(1.0, 6.0) = 2.8;
uniform vec2 drift_a = vec2(0.05, -0.015);
uniform vec2 drift_b = vec2(-0.035, 0.02);
uniform float warp_strength : hint_range(0.0, 2.5) = 1.1;
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

	vec2 warp_uv = uv * noise_scale * 0.4 + drift_a * TIME * 0.4;
	vec2 warp = vec2(fbm2(warp_uv), fbm2(warp_uv + vec2(5.2, 1.3))) - 0.5;

	vec2 p1 = uv * noise_scale + warp * warp_strength + drift_a * TIME;
	vec2 p2 = uv * noise_scale * 2.4 + warp * warp_strength * 0.65 + drift_b * TIME;
	float n = fbm2(p1) * 0.65 + fbm2(p2) * 0.35;
	n = pow(clamp(n, 0.0, 1.0), contrast);

	float alpha = clamp(n * density, 0.0, 1.0) * gradient;
	vec3 col = mix(fog_color.rgb, fog_color_bright.rgb, clamp(n * 1.6, 0.0, 1.0));
	COLOR = vec4(col, alpha);
}
