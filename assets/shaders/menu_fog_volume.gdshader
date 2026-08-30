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
shader_type spatial;
render_mode unshaded, blend_mix, cull_disabled, depth_draw_never, shadows_disabled, fog_disabled;

uniform vec4 fog_color : source_color = vec4(0.06, 0.13, 0.08, 1.0);
uniform vec4 fog_color_bright : source_color = vec4(0.2, 0.38, 0.22, 1.0);
uniform float density : hint_range(0.0, 4.0) = 2.6;
uniform float noise_scale : hint_range(0.3, 10.0) = 3.0;
uniform float contrast : hint_range(1.0, 6.0) = 1.2;
uniform vec2 drift = vec2(0.06, 0.03);
uniform float warp_strength : hint_range(0.0, 2.5) = 1.0;
/// Fades out toward the top/bottom (V) edges of the quad, same idea as
/// before -- just no longer the only thing controlling density, see below.
uniform float edge_softness : hint_range(0.0, 1.0) = 0.85;
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
	// Only the V (top/bottom) edges get the soft radial-style fade now --
	// the U axis is what gradient_start/end drives, see the uniform above.
	float v_centered = abs(uv.y * 2.0 - 1.0);
	float edge_fade = 1.0 - smoothstep(1.0 - edge_softness, 1.0, v_centered);
	float gradient = smoothstep(gradient_start, gradient_end, uv.x);

	vec2 warp_uv = uv * noise_scale * 0.4 + drift * TIME * 0.4;
	vec2 warp = vec2(fbm2(warp_uv), fbm2(warp_uv + vec2(5.2, 1.3))) - 0.5;

	vec2 p1 = uv * noise_scale + warp * warp_strength + drift * TIME;
	vec2 p2 = uv * noise_scale * 2.2 - warp * warp_strength * 0.6 + drift * TIME * 1.4;
	float n = fbm2(p1) * 0.6 + fbm2(p2) * 0.4;
	n = pow(clamp(n, 0.0, 1.0), contrast);

	ALBEDO = mix(fog_color.rgb, fog_color_bright.rgb, clamp(n * 1.5, 0.0, 1.0));
	ALPHA = clamp(n * density, 0.0, 1.0) * edge_fade * gradient;
}
