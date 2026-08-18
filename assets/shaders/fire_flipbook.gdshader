shader_type spatial;
// Additive so the flipbook's black background drops out for free, and
// unshaded because fire emits light rather than receiving it. Never
// writes depth: the flame is a volume standing among the logs, and
// depth-writing would make it slice them.
render_mode blend_add, unshaded, cull_disabled, depth_draw_never, shadows_disabled;

uniform sampler2D atlas : source_color, filter_linear_mipmap;
uniform int h_frames = 6;
uniform int v_frames = 6;
// Sub-region of each frame to actually show, in 0..1 frame space. Stock
// fire flipbooks are often mostly smoke plume with a small flame in it --
// blown up to fill a quad, that leaves a fire a few centimetres across
// inside a metre of haze. Cropping to just the flame is what makes the
// fire the size of the quad rather than the smoke.
uniform vec2 frame_crop_center = vec2(0.5, 0.5);
uniform vec2 frame_crop_size = vec2(1.0, 1.0);
// Playback rate. Frame count / this = loop length, so 36 frames at 30fps
// is a 1.2s loop.
uniform float fps = 30.0;
uniform vec3 tint : source_color = vec3(1.0, 1.0, 1.0);
// Scales the whole thing; the room's glow kicks in past 2.2, so values
// above that make the fire actually bleed light into the room.
uniform float brightness = 2.2;
// Per-instance phase, so two fireplaces in one room don't flicker in
// perfect sync.
uniform float time_offset = 0.0;

void vertex() {
	// Y-billboard: spins to face the camera around the vertical axis only.
	// A full billboard would tilt the flame when the player looks up or
	// down, and fire that leans back at you reads as broken instantly.
	vec3 cam_right = normalize(cross(vec3(0.0, 1.0, 0.0), INV_VIEW_MATRIX[2].xyz));
	MODELVIEW_MATRIX = VIEW_MATRIX * mat4(
		vec4(cam_right, 0.0),
		vec4(0.0, 1.0, 0.0, 0.0),
		vec4(normalize(cross(cam_right, vec3(0.0, 1.0, 0.0))), 0.0),
		MODEL_MATRIX[3]);
	// Undo the model's own scale being eaten by the basis replacement
	// above -- the quad still has to keep the size it was authored at.
	MODELVIEW_MATRIX[0] *= length(MODEL_MATRIX[0]);
	MODELVIEW_MATRIX[1] *= length(MODEL_MATRIX[1]);
	MODELVIEW_MATRIX[2] *= length(MODEL_MATRIX[2]);
}

void fragment() {
	int total = max(h_frames * v_frames, 1);
	int frame = int(mod((TIME + time_offset) * fps, float(total)));
	vec2 grid = vec2(float(h_frames), float(v_frames));
	// Atlas rows run top-to-bottom while UV.y runs the same way here, so
	// no flip is needed -- frame 0 is the top-left cell.
	vec2 cell = vec2(float(frame % h_frames), float(frame / h_frames));
	// Clamped so a crop window placed near a frame edge samples its own
	// border rather than bleeding into the neighbouring frame.
	vec2 local = clamp(frame_crop_center + (UV - vec2(0.5)) * frame_crop_size,
			vec2(0.0), vec2(1.0));
	vec2 uv = (local + cell) / grid;

	vec4 c = texture(atlas, uv);
	ALBEDO = c.rgb * tint * brightness;
	// Sheets shot on black sometimes ship without a real alpha channel.
	// Falling back to luminance means those still key out cleanly instead
	// of drawing an opaque black square around the flame.
	float lum = dot(c.rgb, vec3(0.299, 0.587, 0.114));
	ALPHA = max(c.a, lum);
}
