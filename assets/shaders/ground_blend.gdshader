// Blends four CC0 ground materials (ambientCG) into one continuous surface.
//
// Two things keep it from looking like tiled wallpaper. First, the four sets are
// mixed by low-frequency noise so patches of grass, leaf litter and stone drift
// into each other in organic shapes instead of on hard boundaries. Second, UVs
// come from world position rather than the mesh, so the pattern does not stretch
// or restart wherever the ground geometry happens to be cut — and a second,
// much larger noise field darkens and lightens broad areas to break up the
// repeat that 4K tiles still show at this scale.
shader_type spatial;
render_mode cull_back, diffuse_burley, specular_schlick_ggx;

group_uniforms layer_grass;
uniform sampler2D grass_albedo : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D grass_normal : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D grass_rough : hint_default_white, filter_linear_mipmap_anisotropic, repeat_enable;

group_uniforms layer_litter;
uniform sampler2D litter_albedo : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D litter_normal : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D litter_rough : hint_default_white, filter_linear_mipmap_anisotropic, repeat_enable;

group_uniforms layer_moss;
uniform sampler2D moss_albedo : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D moss_normal : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D moss_rough : hint_default_white, filter_linear_mipmap_anisotropic, repeat_enable;

group_uniforms layer_stone;
uniform sampler2D stone_albedo : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D stone_normal : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D stone_rough : hint_default_white, filter_linear_mipmap_anisotropic, repeat_enable;

group_uniforms tiling;
/// World metres per texture repeat. Larger = the texture covers more ground.
uniform float tile_size : hint_range(0.5, 20.0) = 3.0;
uniform float normal_strength : hint_range(0.0, 4.0) = 1.2;

group_uniforms blending;
/// World size of one patch of a given material. Big on purpose — small values
/// turn the ground into confetti.
uniform float patch_size : hint_range(5.0, 200.0) = 42.0;
/// How hard the four layers compete. 1 = mushy crossfade everywhere,
/// high = crisp patches with narrow seams.
uniform float patch_contrast : hint_range(1.0, 16.0) = 5.0;

group_uniforms variation;
/// Broad light/dark drift laid over everything, to hide the tile repeat.
uniform float macro_size : hint_range(20.0, 400.0) = 130.0;
uniform float macro_strength : hint_range(0.0, 1.0) = 0.35;
uniform vec3 ground_tint : source_color = vec3(1.0, 1.0, 1.0);

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

float fbm(vec2 p) {
	float total = 0.0;
	float amp = 0.5;
	for (int i = 0; i < 4; i++) {
		total += vnoise(p) * amp;
		p *= 2.07;
		amp *= 0.5;
	}
	return total;
}

varying vec3 world_pos;

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec2 uv = world_pos.xz / tile_size;
	vec2 puv = world_pos.xz / patch_size;

	// Four independent noise fields, one per layer, then a sharpened normalise.
	// Whichever field happens to be highest at a point wins there, so the layers
	// interlock naturally instead of one being painted on top of another.
	vec4 w = vec4(
		fbm(puv),
		fbm(puv + vec2(17.3, 5.1)),
		fbm(puv + vec2(-8.7, 23.4)),
		fbm(puv + vec2(41.2, -13.8))
	);
	w = pow(max(w, vec4(0.0001)), vec4(patch_contrast));
	w /= (w.x + w.y + w.z + w.w);

	vec3 albedo =
		texture(grass_albedo, uv).rgb * w.x +
		texture(litter_albedo, uv).rgb * w.y +
		texture(moss_albedo, uv).rgb * w.z +
		texture(stone_albedo, uv).rgb * w.w;

	vec3 nrm =
		(texture(grass_normal, uv).rgb * 2.0 - 1.0) * w.x +
		(texture(litter_normal, uv).rgb * 2.0 - 1.0) * w.y +
		(texture(moss_normal, uv).rgb * 2.0 - 1.0) * w.z +
		(texture(stone_normal, uv).rgb * 2.0 - 1.0) * w.w;

	float rough =
		texture(grass_rough, uv).r * w.x +
		texture(litter_rough, uv).r * w.y +
		texture(moss_rough, uv).r * w.z +
		texture(stone_rough, uv).r * w.w;

	// Very large-scale brightness drift. This is what stops the eye from
	// locking onto the repeat when looking across open ground.
	float macro = fbm(world_pos.xz / macro_size);
	albedo *= mix(1.0, 0.55 + macro, macro_strength);

	ALBEDO = albedo * ground_tint;
	ROUGHNESS = clamp(rough, 0.05, 1.0);
	SPECULAR = 0.35;
	NORMAL_MAP = normalize(nrm) * 0.5 + 0.5;
	NORMAL_MAP_DEPTH = normal_strength;
}
