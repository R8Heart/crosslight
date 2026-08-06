// The world-switch: space itself is twisted and dragged into the orb, held
// in darkness for a beat, then flung back out in the new colour. All of the
// timing comes from WorldState (see world_state.gd) -- this only draws it.
//
// The swirl is deliberately stronger the closer a pixel is to the orb,
// which is what gives the stretched, spaghettified look of something being
// pulled past an event horizon rather than a uniform screen spin.
//
// Runs as `spatial` rather than `canvas_item` because canvas_item shaders
// in this Godot build cannot read hint_depth_texture at all -- this is
// drawn on a 2x2 QuadMesh parented to the camera whose vertex shader skips
// the normal MVP transform entirely, the standard "full-screen pass"
// trick, so it always exactly fills the view regardless of FOV.
shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never, depth_test_disabled, cull_disabled, fog_disabled, shadows_disabled, skip_vertex_transform;

uniform sampler2D screen_tex : hint_screen_texture, repeat_disable, filter_linear;

// Where the orb is on screen, in UV. Everything warps around this point.
uniform vec2 orb_uv = vec2(0.5, 0.5);
uniform float aspect = 1.777;

// Signed: >0 drags space inward (inhale), <0 throws it outward (exhale).
uniform float swirl = 0.0;
// 0 = untouched world, 1 = fully black.
uniform float darkness = 0.0;
// Short white-hot spike at the moment of release.
uniform float burst = 0.0;

uniform vec3 tint : source_color = vec3(1.0, 0.6, 0.25);
uniform float pull_amount : hint_range(0.0, 2.0) = 0.85;
uniform float smear_strength : hint_range(0.0, 0.05) = 0.02;
uniform float ca_strength : hint_range(0.0, 0.06) = 0.02;

void vertex() {
	// Bypass MODEL/VIEW/PROJECTION entirely -- the quad's own local XY
	// (authored as a 2x2 QuadMesh, so it already spans -1..1) becomes clip
	// space directly, so this always covers exactly the full screen no
	// matter the camera's FOV or this node's own transform.
	POSITION = vec4(VERTEX.xy, 0.999, 1.0);
}

// Warps a UV straight toward (or away from) the orb -- purely radial, no
// rotation, so space is dragged directly into the light rather than spun
// around it.
vec2 warp(vec2 uv, float strength) {
	vec2 d = uv - orb_uv;
	d.x *= aspect;
	float r = length(d);

	// 1/(r+k) so the pull tightens sharply near the orb and fades to
	// nothing at the screen edges.
	float falloff = 1.0 / (r + 0.22);
	float new_r = r * (1.0 - strength * pull_amount * falloff * 0.16);
	new_r = max(new_r, 0.0);

	vec2 dir = r > 0.0001 ? d / r : vec2(1.0, 0.0);
	vec2 nd = dir * new_r;
	nd.x /= aspect;
	return orb_uv + nd;
}

void fragment() {
	float s = swirl;
	float mag = abs(s);

	vec2 uv = warp(SCREEN_UV, s);

	// Radial smear toward/away from the orb: several taps along the warp
	// path, which is what turns a clean twist into actual motion-streaked
	// stretching of whatever the light was touching.
	vec2 to_orb = normalize((orb_uv - uv) * vec2(aspect, 1.0) + 0.0001) * vec2(1.0 / aspect, 1.0);
	vec3 col = vec3(0.0);
	const int TAPS = 5;
	for (int i = 0; i < TAPS; i++) {
		float f = float(i) / float(TAPS - 1) - 0.5;
		vec2 offs = to_orb * f * smear_strength * mag * sign(s);
		vec2 suv = uv + offs;
		// Split the channels along the same axis so the stretch fringes
		// with colour, the way strong lensing does.
		float rr = texture(screen_tex, suv + to_orb * ca_strength * mag).r;
		float gg = texture(screen_tex, suv).g;
		float bb = texture(screen_tex, suv - to_orb * ca_strength * mag).b;
		col += vec3(rr, gg, bb);
	}
	col /= float(TAPS);

	// Everything that is left gets pulled toward the orb's own colour as it
	// is swallowed -- the world doesn't just dim, it goes *into* the light.
	col = mix(col, col * tint * 1.6, clamp(mag * 0.55, 0.0, 1.0));
	col *= (1.0 - darkness);

	// The release: a hard flash centred on the orb, falling off outward.
	if (burst > 0.001) {
		vec2 bd = (SCREEN_UV - orb_uv) * vec2(aspect, 1.0);
		float br = length(bd);
		float core = exp(-br * 5.0);
		float halo = exp(-br * 1.6) * 0.4;
		col += tint * burst * (core * 3.0 + halo);
	}

	ALBEDO = col;
	// hint_screen_texture is a snapshot taken before transparent geometry
	// draws (the lamp glass among it), so this quad's own screen_tex sample
	// is always missing anything transparent underneath. Blending in fully
	// when nothing is happening would silently erase every other
	// transparent effect in the scene every frame -- so when the transition
	// is idle this stays completely out of the way.
	ALPHA = clamp(max(max(mag, darkness), burst), 0.0, 1.0);
}
