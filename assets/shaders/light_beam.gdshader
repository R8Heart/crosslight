// Cheap fake volumetric light shaft/god-ray for components/light_shaft.gd --
// a cone mesh (CylinderMesh with top_radius=0) rather than Godot's real
// volumetric fog, which rendered as a flat hazy blob once lit by the
// scene's ambient/GI instead of a directional beam. A textured,
// additively-blended cone is the classic, fully art-directable way games
// have faked this forever -- it reads as a beam by construction, with zero
// dependency on global fog/anisotropy/GI settings.
//
// Deliberately kept to only shader features already proven to work
// elsewhere in this project (see menu_fog_volume.gdshader): no FRONT_FACING,
// no exotic render modes. A spatial shader that fails to compile doesn't
// error loudly -- Godot just falls back to a plain white material, which
// looks exactly like "the effect is broken but nobody said why".
shader_type spatial;
render_mode unshaded, blend_add, cull_disabled, depth_draw_never, shadows_disabled, fog_disabled;

uniform vec4 beam_color : source_color = vec4(0.75, 0.82, 1.0, 1.0);
uniform float intensity : hint_range(0.0, 4.0) = 1.0;
/// Higher = the beam dims out sooner after leaving the window instead of
/// staying bright all the way to the far end.
uniform float length_falloff : hint_range(0.5, 6.0) = 2.0;
/// Higher = the cone's own silhouette fades out harder at grazing angles,
/// which is what stops it reading as a solid paper cone.
uniform float edge_softness : hint_range(0.0, 4.0) = 2.0;
/// CylinderMesh's V direction isn't worth guessing blind -- flip if the
/// beam comes out bright at the far end and dim at the window.
uniform bool flip_length = false;

void fragment() {
	float v = flip_length ? 1.0 - UV.y : UV.y;
	float length_fade = pow(clamp(1.0 - v, 0.0, 1.0), length_falloff);

	// NORMAL and VIEW are both view-space here; abs() covers the back faces
	// that cull_disabled lets through, without needing FRONT_FACING.
	float facing = abs(dot(normalize(NORMAL), normalize(VIEW)));
	float edge_fade = pow(clamp(facing, 0.0, 1.0), edge_softness);

	ALBEDO = beam_color.rgb;
	ALPHA = length_fade * edge_fade * intensity;
}
