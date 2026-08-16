shader_type spatial;
render_mode unshaded, blend_add, cull_disabled, depth_draw_never, billboard;

// Cheap procedural flame for a small billboard quad -- meant to sit on top
// of an existing Light3D (candle, sconce, lantern), not to BE the light
// itself. No textures, no raymarching: a vertical noise-wobbled taper with
// a base-to-tip color gradient, additive-blended so overlapping flames
// never look like flat cutout sprites.

uniform vec4 color_base : source_color = vec4(1.0, 0.85, 0.35, 1.0);
uniform vec4 color_tip : source_color = vec4(1.0, 0.32, 0.04, 1.0);
uniform float intensity : hint_range(0.0, 5.0) = 1.5;
uniform float flame_height = 0.22;
uniform float flicker_speed : hint_range(0.1, 5.0) = 1.8;
uniform float wobble_amount : hint_range(0.0, 0.5) = 0.15;
// Randomized per instance so a row of candles doesn't flicker in lockstep.
uniform float time_offset = 0.0;

varying vec2 flame_uv;

void vertex() {
	// QuadMesh is authored centered on (0,0), spanning -0.5..0.5 -- lift it
	// so the BASE sits at the node's own origin (the wick/flame point),
	// with the tip extending upward in local Y.
	flame_uv = UV;
	VERTEX.y += flame_height * 0.5;
}

float hash(float n) {
	return fract(sin(n) * 43758.5453123);
}

float noise1(float x) {
	float i = floor(x);
	float f = fract(x);
	return mix(hash(i), hash(i + 1.0), smoothstep(0.0, 1.0, f));
}

void fragment() {
	float t = TIME * flicker_speed + time_offset;
	float h = flame_uv.y; // 0 at base, 1 at tip

	// The tip wanders side to side; the base stays anchored to the wick.
	float wob = (noise1(t * 2.3 + h * 4.0) - 0.5) * wobble_amount * h * h;
	float x = flame_uv.x - 0.5 + wob;

	float width = mix(0.5, 0.05, h);
	float d = abs(x) / max(width, 0.001);

	float shape = 1.0 - smoothstep(0.55, 1.0, d);
	shape *= 1.0 - smoothstep(0.7, 1.0, h);
	shape *= smoothstep(0.0, 0.08, h); // soft, not a hard-edged base

	float flick = 0.7 + 0.3 * noise1(t * 3.1);

	vec3 col = mix(color_tip.rgb, color_base.rgb, smoothstep(0.0, 0.6, 1.0 - h));
	float alpha = clamp(shape * flick, 0.0, 1.0);

	ALBEDO = col;
	ALPHA = alpha;
	EMISSION = col * intensity * alpha;
}
