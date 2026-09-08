shader_type canvas_item;

/// Soft radial darkening toward the screen edges. Used on the main menu's
/// 3D backdrop to hide whatever a wider-than-authored aspect ratio reveals
/// at the frame edges (a cropped mesh boundary, a fog quad's own edge)
/// instead of chasing every screen shape by hand -- the vignette just
/// makes sure nothing hard-edged is ever visible out there regardless of
/// how much extra frustum a given screen shows.

uniform float radius : hint_range(0.0, 1.5) = 0.62;
uniform float softness : hint_range(0.01, 1.5) = 0.7;
uniform float strength : hint_range(0.0, 1.0) = 0.85;
uniform vec4 vignette_color : source_color = vec4(0.0, 0.0, 0.0, 1.0);

void fragment() {
	vec2 uv = UV * 2.0 - 1.0;
	float dist = length(uv);
	float vig = smoothstep(radius, radius + softness, dist);
	COLOR = vec4(vignette_color.rgb, vig * strength);
}
