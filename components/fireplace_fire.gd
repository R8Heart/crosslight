@tool
class_name FireplaceFire
extends Node3D

## Genuinely volumetric fire: a box whose interior is raymarched against a
## scrolling 3D noise field (see fire_volume.gdshader). Sparks and smoke
## are particles around it.
##
## It is a volume rather than a sprite because every flat approach was
## tried here first and each failed the same way. Soft procedural sprites
## only ever add up to a round orange glow -- round blobs cannot make a
## sharp tapering tongue no matter how many are stacked. A sprite sheet of
## filmed fire fixes the tongues but is still a picture on a card: it
## turns to face the camera, so it slides across the logs as the player
## walks around the hearth, and it has no correct appearance from above.
## A raymarched volume has none of those problems -- it occupies space,
## stays put in the logs, and is right from any angle, because what is
## being drawn is a density field rather than an image of a fire.
##
## Runs as @tool so the fire is live in the editor viewport while you size
## it. All the child nodes are built without an owner, so they exist at
## runtime only and never get written into the scene file.
##
## The *light* is deliberately not created here. Put an OmniLight3D with
## world_light.gd in the firebox as usual -- that already does the flame
## flicker and the world-switch colour swap, and ZoneManager picks it up on
## its own when it walks the room's group.

## Size of the flame volume, in metres. This is the box the fire is
## raymarched inside, so it is literally the fire's extent.
@export var width := 0.5:
	set(value):
		width = value
		_rebuild()
@export var depth := 0.35:
	set(value):
		depth = value
		_rebuild()
## How tall the flames stand, in metres. The flame fades out before the
## top of the box, so this is the reach of the tips rather than a hard
## ceiling.
@export var height := 0.6:
	set(value):
		height = value
		_rebuild()
## How fast the noise field scrolls through the flame -- i.e. how quickly
## the licks change shape.
@export var rise_speed := 0.027:
	set(value):
		rise_speed = value
		_apply_volume_params()
## Size of the noise features carving the flame. Small changes matter a
## lot here; the useful range is roughly 0.3 to 0.7.
@export var noise_scale := 0.45:
	set(value):
		noise_scale = value
		_apply_volume_params()
## How much noise has to be present before gas burns there. Raise it for
## a sparser, more broken-up fire; lower it for a solid body of flame.
@export_range(0.0, 1.0) var noise_threshold := 0.43:
	set(value):
		noise_threshold = value
		_apply_volume_params()
## How sharply the flame narrows from base to tip. 0 is a column.
@export_range(0.0, 1.0) var taper := 0.425:
	set(value):
		taper = value
		_apply_volume_params()
## Hardness of the flame's edges. Low values give crisp tongues, high
## values soften them toward smoke.
@export_range(0.5, 20.0) var edge_sharpness := 4.5:
	set(value):
		edge_sharpness = value
		_apply_volume_params()
## How much the licks curl and writhe rather than rising straight.
@export var wobble_strength := 2.0:
	set(value):
		wobble_strength = value
		_apply_volume_params()
## Size of the white-hot heart inside the flame.
@export_range(0.0, 20.0) var core_glow := 16.0:
	set(value):
		core_glow = value
		_apply_volume_params()
## Raymarch samples. This shader is efficient enough that 6 is the
## author's own recommendation; it also spends extra steps automatically
## when viewed at a grazing angle.
@export_range(2, 24) var quality_steps := 6:
	set(value):
		quality_steps = value
		_apply_volume_params()
## Diagnostic only: draws the proxy quad as a flat green rectangle and
## skips the raymarch. Tells apart "the surface isn't drawing" from "it
## draws but the volume is empty".
@export var debug_show_proxy := false:
	set(value):
		debug_show_proxy = value
		_apply_volume_params()
## Overall brightness, as a multiplier on the shader's own emission
## scale. 1.0 is the look the shader was authored at.
@export var intensity := 1.0:
	set(value):
		intensity = value
		_apply_brightness()
## Slow sparks drifting up out of the fire.
@export var embers_enabled := true:
	set(value):
		embers_enabled = value
		_rebuild()
@export var ember_particles := 14:
	set(value):
		ember_particles = value
		_rebuild()
## Thin smoke wisps above the flame tips. Alpha-blended dark grey rather
## than additive like everything else here -- smoke *occludes* what's
## behind it, and an additive smoke would brighten the chimney instead of
## darkening it.
@export var smoke_enabled := true:
	set(value):
		smoke_enabled = value
		_rebuild()
@export var smoke_particles := 8:
	set(value):
		smoke_particles = value
		_rebuild()

## Spark colours, hot end first. The flame body gets its colour from the
## shader's own temperature ramp, so these only tint the embers.
@export var color_core := Color(1.0, 0.55, 0.12):
	set(value):
		color_core = value
		_apply_world_colors()
@export var color_mid := Color(0.95, 0.25, 0.03):
	set(value):
		color_mid = value
		_apply_world_colors()
## Otherside palette. `otherside_mid` doubles as the tint laid over the
## flame body itself, which is the one place the fire gets recoloured.
@export var otherside_core := Color(0.55, 1.0, 0.7)
@export var otherside_mid := Color(0.12, 0.85, 0.35)

## Zone-culling multiplier, owned by ZoneManager -- same contract as
## WorldLight.zone_dim and WorldEmissive.zone_dim.
var zone_dim := 1.0:
	set(value):
		zone_dim = value
		_apply_brightness()

const FLAME_SHADER := preload("res://assets/shaders/fire_volume.gdshader")
## The shader's emission scale at intensity 1.0. Its own default is 12.5,
## which is what its colours were balanced against, so `intensity` rides
## on top of that rather than replacing it.
const EMISSION_BASE := 12.5

## The box the fire is raymarched inside, and its material.
var _flame_volume: MeshInstance3D
var _flame_shader_mat: ShaderMaterial
var _embers: GPUParticles3D
var _smoke: GPUParticles3D
var _ember_mat: StandardMaterial3D
## Last brightness actually written to the materials. Writing a material
## property re-uploads it to the GPU, so skip the write when the value
## hasn't moved -- _process() runs this every frame.
var _last_brightness := -1.0
var _rebuild_queued := false

func _ready() -> void:
	_rebuild()
	if not Engine.is_editor_hint():
		WorldState.world_changed.connect(_on_world_changed)

## Tracks WorldState.darkness so the fire is swallowed along with every
## other light source during a world switch, instead of staying lit while
## the room around it goes black.
func _process(_delta: float) -> void:
	if not Engine.is_editor_hint():
		_apply_brightness()

## Exported values are assigned one at a time as the scene loads, and
## dragging a slider in the inspector fires its setter many times a
## second -- so coalesce all of that into at most one rebuild per frame
## rather than tearing the particle systems down and back up on every
## individual assignment.
func _rebuild() -> void:
	if not is_inside_tree() or _rebuild_queued:
		return
	_rebuild_queued = true
	_do_rebuild.call_deferred()

func _do_rebuild() -> void:
	_rebuild_queued = false

	if _flame_volume:
		_flame_volume.queue_free()
	_flame_volume = null
	if _embers:
		_embers.queue_free()
	if _smoke:
		_smoke.queue_free()
	_embers = null
	_smoke = null
	_ember_mat = null
	_flame_shader_mat = null

	_build_flame_volume()
	if embers_enabled:
		_embers = _build_embers()
		add_child(_embers)
	if smoke_enabled:
		_smoke = _build_smoke()
		add_child(_smoke)
	_apply_world_colors()
	_last_brightness = -1.0
	_apply_brightness()
	update_configuration_warnings()

## The fire. The mesh is only a proxy screen the shader marches through:
## it billboards so it always covers the volume, while the flame itself is
## anchored in world space around this node's origin. The node therefore
## sits at the *base* of the fire, not its centre.
func _build_flame_volume() -> void:
	_flame_shader_mat = ShaderMaterial.new()
	_flame_shader_mat.shader = FLAME_SHADER
	_flame_shader_mat.set_shader_parameter("sample_noise", _build_noise())

	var quad := QuadMesh.new()
	# Generous: the proxy has to cover the flame from every angle, including
	# after the shader pushes it along the camera axis. Anything it covers
	# that the volume doesn't fill discards in the first few instructions.
	var span: float = maxf(width, height) * 2.4
	quad.size = Vector2(span, span)
	quad.material = _flame_shader_mat

	_flame_volume = MeshInstance3D.new()
	_flame_volume.mesh = quad
	_flame_volume.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# The vertex shader billboards and offsets the quad, and Godot culls
	# against the authored AABB from *before* that runs -- a flat quad's
	# slab goes edge-on and the fire vanishes. Same trap as
	# world_transition.gdshader; same fix.
	_flame_volume.custom_aabb = AABB(Vector3(-span, -span, -span) * 0.5, Vector3(span, span, span))
	add_child(_flame_volume)
	_apply_volume_params()

## 3D noise the flame is carved out of. These settings are the ones the
## upstream shader was authored against and it is genuinely sensitive to
## them: high frequency, four octaves with lacunarity 3, its own domain
## warp, and a colour ramp that pushes contrast. Smooth low-octave noise
## produces glowing haze instead of tongues no matter what the shader
## parameters say.
func _build_noise() -> NoiseTexture3D:
	var n := FastNoiseLite.new()
	n.noise_type = FastNoiseLite.TYPE_VALUE
	n.frequency = 0.3
	n.fractal_octaves = 4
	n.fractal_lacunarity = 3.0
	n.fractal_gain = 1.0
	n.fractal_weighted_strength = 1.0
	n.domain_warp_enabled = true
	n.domain_warp_fractal_octaves = 1

	var ramp := Gradient.new()
	ramp.set_offset(0, 0.141667)
	ramp.set_offset(1, 0.841667)

	var tex := NoiseTexture3D.new()
	tex.noise = n
	tex.seamless = true
	tex.seamless_blend_skirt = 1.0
	tex.normalize = false
	tex.color_ramp = ramp
	return tex

## Live shader values, kept out of _build_flame_volume so tweaking them in
## the inspector doesn't tear the volume down and regenerate the noise
## texture on every keystroke.
func _apply_volume_params() -> void:
	if not _flame_shader_mat:
		return
	_flame_shader_mat.set_shader_parameter("fire_width", maxf(width, 0.01))
	_flame_shader_mat.set_shader_parameter("fire_height", maxf(height, 0.01))
	_flame_shader_mat.set_shader_parameter("taper_factor", taper)
	_flame_shader_mat.set_shader_parameter("time_scale", rise_speed)
	_flame_shader_mat.set_shader_parameter("noise_scale", noise_scale)
	_flame_shader_mat.set_shader_parameter("noise_threshold", noise_threshold)
	_flame_shader_mat.set_shader_parameter("sharpness_cutoff", edge_sharpness)
	_flame_shader_mat.set_shader_parameter("wobble_strength", wobble_strength)
	_flame_shader_mat.set_shader_parameter("raymarch_steps", quality_steps)
	_flame_shader_mat.set_shader_parameter("core_glow_multiplier", core_glow)
	_flame_shader_mat.set_shader_parameter("debug_show_proxy", debug_show_proxy)

func _get_configuration_warnings() -> PackedStringArray:
	var warnings: PackedStringArray = []

	if width > height * 1.3:
		warnings.append(
			"Width (%.2f m) is much greater than Height (%.2f m), so the flame volume is wider than it is tall and the fire will look squashed. Real flames are taller than their base." \
			% [width, height])

	if height > 1.2:
		warnings.append(
			"Height is %.2f m -- flames will shoot far past the firebox. A fire in a hearth reaches roughly 0.3-0.6 m." % height)
	return warnings

func _apply_brightness() -> void:
	var darkness: float = 0.0 if Engine.is_editor_hint() else WorldState.darkness
	var lit := intensity * zone_dim * (1.0 - darkness)
	if is_equal_approx(lit, _last_brightness):
		return
	_last_brightness = lit

	if _flame_shader_mat:
		# The shader's own scale: it multiplies the composited colour into
		# both ALBEDO and EMISSION, so this is what makes the fire bleed
		# light into the room past the environment's glow threshold.
		_flame_shader_mat.set_shader_parameter("emission_strength", EMISSION_BASE * lit)
	if _ember_mat:
		_ember_mat.albedo_color = Color(lit, lit, lit, 1.0)

	# Fully dark means an unlit room, so stop drawing and simulating
	# entirely rather than paying for work nobody can see.
	var burning := lit > 0.01
	if _flame_volume:
		_flame_volume.visible = burning
	if _embers:
		_embers.emitting = burning
	if _smoke:
		_smoke.emitting = burning

func _on_world_changed(new_world) -> void:
	_apply_world_colors(new_world)

func _apply_world_colors(world = null) -> void:
	if world == null:
		world = WorldState.World.REAL if Engine.is_editor_hint() else WorldState.current_world
	var is_real: bool = world == WorldState.World.REAL
	var core := color_core if is_real else otherside_core
	var mid := color_mid if is_real else otherside_mid

	if _flame_shader_mat:
		# The flame's three-stop palette, swapped wholesale on the
		# Otherside. Real-world values are the upstream shader's, which
		# were tuned against its own noise settings.
		var f_core := Color(1.0, 0.9, 0.5) if is_real else otherside_core
		var f_mid := Color(1.0, 0.625, 0.0) if is_real else otherside_mid
		var f_outer := Color(0.8, 0.01, 0.0) if is_real else otherside_mid.darkened(0.6)
		_flame_shader_mat.set_shader_parameter("color_core", f_core)
		_flame_shader_mat.set_shader_parameter("color_mid", f_mid)
		_flame_shader_mat.set_shader_parameter("color_outer", f_outer)
	if _embers:
		var ember_process := _embers.process_material as ParticleProcessMaterial
		# Sparks hold near-full alpha for most of their flight and only
		# wink out at the end -- unlike flame, a spark is a hard bright
		# point, not something that fades as it cools.
		ember_process.color_ramp = _spark_ramp(core, mid)

func _build_embers() -> GPUParticles3D:
	var p := GPUParticles3D.new()
	p.amount = ember_particles
	# Much longer than the flame: an ember's whole job is to drift well
	# clear of the fire before it dies.
	p.lifetime = 2.6
	p.randomness = 0.8
	p.fixed_fps = 30

	_ember_mat = _sprite_material()
	var quad := QuadMesh.new()
	# Fixed size, not derived from the flame sprite: a spark is a physical
	# scrap of glowing ash roughly the same size in every fireplace, and
	# scaling it with the flame just produced glowing golf balls.
	quad.size = Vector2(0.012, 0.012)
	quad.material = _ember_mat
	p.draw_pass_1 = quad

	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	# Sparks come off the whole log bed, unlike the flame sprites which
	# stack in one place -- this is what gives the fire its actual width.
	pm.emission_box_extents = Vector3(width * 0.45, 0.02, depth * 0.45)
	pm.direction = Vector3(0, 1, 0)
	pm.spread = 25.0
	# Fast enough to climb clear of the flame body and be seen against the
	# dark chimney above it; sparks that never leave the fire are lost in
	# it entirely.
	pm.initial_velocity_min = height * 1.2
	pm.initial_velocity_max = height * 2.4
	pm.gravity = Vector3(0, 0.15, 0)
	pm.scale_min = 0.4
	pm.scale_max = 1.0
	pm.scale_curve = _scale_curve()
	pm.turbulence_enabled = true
	pm.turbulence_noise_strength = 1.4
	pm.turbulence_noise_scale = 1.6
	pm.turbulence_influence_min = 0.1
	pm.turbulence_influence_max = 0.5
	p.process_material = pm
	return p

## Thin smoke above the flame tips. Starts where the flames are already
## dying rather than down at the logs, so it reads as the fire's exhaust
## instead of a grey haze sitting in the middle of the fire.
func _build_smoke() -> GPUParticles3D:
	var p := GPUParticles3D.new()
	p.amount = smoke_particles
	p.lifetime = 3.2
	p.randomness = 0.7
	p.fixed_fps = 30

	var quad := QuadMesh.new()
	var puff: float = maxf(width * 0.5, 0.05)
	quad.size = Vector2(puff, puff)
	quad.material = _smoke_material()
	p.draw_pass_1 = quad

	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	pm.emission_box_extents = Vector3(width * 0.3, 0.02, depth * 0.3)
	pm.direction = Vector3(0, 1, 0)
	pm.spread = 8.0
	pm.initial_velocity_min = height * 0.7
	pm.initial_velocity_max = height * 1.0
	pm.gravity = Vector3(0, 0.25, 0)
	pm.scale_min = 0.8
	pm.scale_max = 1.6
	# Smoke expands as it cools and never shrinks back, unlike flame.
	pm.scale_curve = _smoke_scale_curve()
	pm.angular_velocity_min = -15.0
	pm.angular_velocity_max = 15.0
	pm.turbulence_enabled = true
	pm.turbulence_noise_strength = 0.5
	pm.turbulence_noise_scale = 1.2
	pm.turbulence_influence_min = 0.05
	pm.turbulence_influence_max = 0.2
	pm.color_ramp = _smoke_ramp()
	p.process_material = pm
	# Lifted clear of the flame body; the flames themselves reach roughly
	# `height`, so this starts where they're already fading out.
	p.position = Vector3(0, height * 0.8, 0)
	return p

## Alpha-blended, not additive: smoke has to darken what's behind it.
func _smoke_material() -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.blend_mode = BaseMaterial3D.BLEND_MODE_MIX
	m.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	m.billboard_keep_scale = true
	m.vertex_color_use_as_albedo = true
	m.albedo_texture = _soft_blob()
	m.albedo_color = Color(0.05, 0.045, 0.04)
	return m

## Barely-there wisps: smoke that reads clearly is a bonfire, not a
## well-drawing fireplace.
func _smoke_ramp() -> GradientTexture1D:
	var g := Gradient.new()
	g.set_offset(0, 0.0)
	g.set_color(0, Color(1, 1, 1, 0.0))
	g.set_offset(1, 1.0)
	g.set_color(1, Color(1, 1, 1, 0.0))
	g.add_point(0.25, Color(1, 1, 1, 0.16))
	g.add_point(0.6, Color(1, 1, 1, 0.1))
	return _gradient_texture(g)

func _smoke_scale_curve() -> CurveTexture:
	var c := Curve.new()
	c.add_point(Vector2(0.0, 0.4))
	c.add_point(Vector2(1.0, 1.0))
	var t := CurveTexture.new()
	t.curve = c
	return t

## Additive unshaded billboard for the spark specks. Brightness rides on
## albedo_color rather than an emission slot, because emission isn't
## modulated by the particle colour ramp and every spark would then be the
## same colour regardless of how far through its flight it was.
func _sprite_material() -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	m.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	m.billboard_keep_scale = true
	m.vertex_color_use_as_albedo = true
	m.disable_receive_shadows = true
	m.albedo_texture = _soft_blob()
	return m

## Round soft-edged speck, generated rather than imported -- used for
## sparks and smoke puffs, both of which only need a fuzzy dot. The middle
## stop tightens the core so the dot has a bright centre with a soft halo.
func _soft_blob() -> GradientTexture2D:
	var g := Gradient.new()
	g.set_offset(0, 0.0)
	g.set_color(0, Color(1, 1, 1, 1))
	g.set_offset(1, 1.0)
	g.set_color(1, Color(1, 1, 1, 0))
	g.add_point(0.35, Color(1, 1, 1, 0.55))
	var t := GradientTexture2D.new()
	t.gradient = g
	t.fill = GradientTexture2D.FILL_RADIAL
	t.fill_from = Vector2(0.5, 0.5)
	t.fill_to = Vector2(1.0, 0.5)
	t.width = 64
	t.height = 64
	return t

## Sparks hold a hard bright point for most of their flight and only wink
## out right at the end, rather than fading the whole way.
func _spark_ramp(core: Color, mid: Color) -> GradientTexture1D:
	var g := Gradient.new()
	g.set_offset(0, 0.0)
	g.set_color(0, Color(core.r, core.g, core.b, 1.0))
	g.set_offset(1, 1.0)
	g.set_color(1, Color(mid.r, mid.g, mid.b, 0.0))
	g.add_point(0.75, Color(mid.r, mid.g, mid.b, 0.9))
	return _gradient_texture(g)

func _gradient_texture(g: Gradient) -> GradientTexture1D:
	var t := GradientTexture1D.new()
	t.gradient = g
	return t

## Particles start small, bloom out as they rise, then shrink away rather
## than blinking out at full size. Held near full size through the middle
## of the life so neighbouring sprites stay overlapped long enough to
## merge into one body instead of reading as separate dots.
func _scale_curve() -> CurveTexture:
	var c := Curve.new()
	c.add_point(Vector2(0.0, 0.45))
	c.add_point(Vector2(0.3, 1.0))
	c.add_point(Vector2(0.7, 0.85))
	c.add_point(Vector2(1.0, 0.1))
	var t := CurveTexture.new()
	t.curve = c
	return t
