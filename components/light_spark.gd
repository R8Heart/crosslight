class_name LightSpark
extends Node3D

## A small glowing "soul-spark" that flies from the player's lantern orb to
## a room light's position when a new zone is entered -- the lantern (the
## player's own soul, see player/orb.gd) reaching out to kindle each
## fixture itself, rather than the room's lights just fading on in place.
##
## Deliberately has no real Light3D of its own. Some rooms have 40+
## fixtures -- flying that many fully dynamic lights across a room at once
## would be expensive and read as chaos rather than magic. This is only
## the visible trail; zone_manager.gd fades the real fixture in once the
## spark actually arrives (see `arrived`).
##
## The glow is real bloom, not a fake bright sprite: the project's
## WorldEnvironment already has Glow enabled (see rooms/estate_exterior.tscn),
## which reacts to pixels over 1.0 brightness -- colours here are
## deliberately pushed well past that (HDR_BOOST) so the post-process
## actually picks them up, instead of just being a saturated-but-capped
## additive blob that never blooms.

signal arrived

## Constant speed rather than a fixed duration -- a spark to a light 2m
## away and one 25m away should feel like the same kind of thing moving at
## the same speed, not one crawling and one teleporting.
const SPEED := 18.0
const MIN_FLIGHT_TIME := 0.15
const MAX_FLIGHT_TIME := 0.8
## How high the flight arcs above a straight line between start and end,
## as a fraction of the straight-line distance -- 0 would be a flat line.
const ARC_HEIGHT_FRACTION := 0.3
## Short fixed burst straight out of the lantern before the curve takes
## over -- without this the very first motion was toward the arc's peak
## (strongly upward), which read as "drifts up from nowhere" instead of
## "left the lantern", especially for nearby lights where that first
## upward pull dominates the whole flight.
const LAUNCH_BURST_DISTANCE := 0.4

## How far past 1.0 the core/halo colours are pushed so Glow actually
## triggers on them. Godot's Glow bloom threshold is luminance-based, not
## alpha-based, so this has to live in the colour, not the opacity.
const HDR_BOOST := 3.5
const HALO_HDR_BOOST := 1.6

## Starts as a tight little spark and grows into its full glow over the
## flight -- a fixed-size dot the whole way read as a rendered sprite
## sliding around; growing out of a small point as it picks up speed reads
## as something igniting, not just translating. Small: right at launch the
## spark is only centimetres from the camera, so anything not genuinely
## tiny there reads as huge purely from being that close.
const START_SCALE := 0.08

var _p0: Vector3
var _p1: Vector3
var _p2: Vector3
var _p3: Vector3
var _t := 0.0
var _flight_time := 1.0
var _core: MeshInstance3D
var _halo: MeshInstance3D
var _trail: GPUParticles3D
var _pulse_seed := 0.0

## Kicks the spark off. Call once, right after instancing. `forward` is the
## direction it should visibly burst out of the lantern in (typically the
## orb's own -Z, i.e. wherever the player is currently facing) -- distinct
## from the direction to the target, which is what the rest of the flight
## curves toward.
func launch(from: Vector3, to: Vector3, forward: Vector3, core_color: Color, mid_color: Color) -> void:
	global_position = from
	_pulse_seed = randf() * TAU

	var dist := from.distance_to(to)
	_flight_time = clampf(dist / SPEED, MIN_FLIGHT_TIME, MAX_FLIGHT_TIME)

	var launch_dir := forward.normalized() if forward.length() > 0.01 else Vector3.FORWARD

	# Sideways offset too, not just up -- a room full of sparks all bowing
	# through the exact same vertical plane reads as one repeated animation
	# rather than independent flight.
	var side := Vector3(randf_range(-1.0, 1.0), 0.0, randf_range(-1.0, 1.0))
	if side.length() > 0.01:
		side = side.normalized()

	_p0 = from
	# First control point: the short forward burst. Second control point:
	# approaches the target from above/the side, same arcing feel the
	# quadratic version had, just now as the *second half* of the curve
	# instead of the whole thing.
	_p1 = from + launch_dir * LAUNCH_BURST_DISTANCE
	_p2 = to + Vector3.UP * (dist * ARC_HEIGHT_FRACTION) + side * (dist * 0.1)
	_p3 = to

	_build_visual(core_color, mid_color)

func _build_visual(core_color: Color, mid_color: Color) -> void:
	# Two-layer glow, same trick real lantern/orb work in this project
	# leans on (see player/orb.gd's glass shader): a small hot core that
	# does most of the actual bloom, plus a larger, much softer halo behind
	# it so the light reads as coming from a genuine soft source instead of
	# a hard little dot with a HDR pixel in the middle of it.
	_halo = MeshInstance3D.new()
	_halo.mesh = _billboard_quad(0.09, _radial_material(mid_color * HALO_HDR_BOOST, 0.55))
	add_child(_halo)

	_core = MeshInstance3D.new()
	_core.mesh = _billboard_quad(0.028, _radial_material(core_color * HDR_BOOST, 1.0))
	add_child(_core)

	_trail = _build_trail(core_color, mid_color)
	add_child(_trail)

## A camera-facing additive quad with a soft radial falloff -- reads as a
## glowing point of light rather than a visible geometric shape, unlike a
## flat-shaded sphere mesh.
func _billboard_quad(size: float, mat: StandardMaterial3D) -> QuadMesh:
	var q := QuadMesh.new()
	q.size = Vector2(size, size)
	q.material = mat
	return q

func _radial_material(color: Color, alpha: float) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	mat.vertex_color_use_as_albedo = true
	mat.disable_receive_shadows = true
	mat.albedo_texture = _soft_speck()
	mat.albedo_color = Color(color.r, color.g, color.b, alpha)
	return mat

## Emits in world space so the trail stays strung out behind the spark's
## path instead of bunching up around wherever the node currently is.
func _build_trail(core_color: Color, mid_color: Color) -> GPUParticles3D:
	var p := GPUParticles3D.new()
	p.amount = 40
	p.lifetime = 0.55
	p.randomness = 0.5
	p.fixed_fps = 30
	p.local_coords = false

	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	mat.billboard_keep_scale = true
	mat.vertex_color_use_as_albedo = true
	mat.disable_receive_shadows = true
	mat.albedo_texture = _soft_speck()
	var quad := QuadMesh.new()
	quad.size = Vector2(0.028, 0.028)
	quad.material = mat
	p.draw_pass_1 = quad

	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	pm.emission_sphere_radius = 0.02
	pm.direction = Vector3.ZERO
	pm.spread = 180.0
	# Near-zero drift -- the trail should read as specks hanging in the air
	# where the spark just was, not scattering away from the path.
	pm.initial_velocity_min = 0.005
	pm.initial_velocity_max = 0.03
	pm.gravity = Vector3(0, -0.01, 0)
	pm.scale_min = 0.5
	pm.scale_max = 1.3
	pm.scale_curve = _trail_scale_curve()
	pm.color_ramp = _fade_ramp(core_color * HDR_BOOST * 0.7, mid_color * HALO_HDR_BOOST)
	p.process_material = pm
	return p

func _process(delta: float) -> void:
	_t += delta / _flight_time
	if _t >= 1.0:
		global_position = _p3
		_finish()
		return
	global_position = _cubic_bezier(_p0, _p1, _p2, _p3, _t)

	# Grows from a tight little spark up to full size over the flight --
	# eased so it stays small early (right when it's closest to the camera,
	# where even a small quad reads huge from sheer proximity) and most of
	# the growth happens in the second half, closer to the target.
	var grow := lerpf(START_SCALE, 1.0, pow(_t, 3.0))

	# A slow, gentle pulse on the halo -- a perfectly steady glow reads as a
	# rendered sprite; a very slight breathing motion reads as something
	# alive, matching the orb's own flicker (see player/orb.gd).
	var pulse := 0.85 + 0.15 * sin(Time.get_ticks_msec() / 1000.0 * 5.0 + _pulse_seed)
	_halo.scale = Vector3.ONE * (grow * pulse)
	_core.scale = Vector3.ONE * grow

func _cubic_bezier(p0: Vector3, p1: Vector3, p2: Vector3, p3: Vector3, t: float) -> Vector3:
	var a := p0.lerp(p1, t)
	var b := p1.lerp(p2, t)
	var c := p2.lerp(p3, t)
	return a.lerp(b, t).lerp(b.lerp(c, t), t)

func _finish() -> void:
	set_process(false)
	arrived.emit()
	_core.visible = false
	_halo.visible = false
	_trail.emitting = false
	# Let the last few trail particles fade out naturally instead of the
	# node vanishing mid-glow.
	get_tree().create_timer(_trail.lifetime + 0.1).timeout.connect(queue_free)

## Round soft-edged speck, same technique as components/fire_sparks.gd.
func _soft_speck() -> GradientTexture2D:
	var g := Gradient.new()
	g.set_offset(0, 0.0)
	g.set_color(0, Color(1, 1, 1, 1))
	g.set_offset(1, 1.0)
	g.set_color(1, Color(1, 1, 1, 0))
	g.add_point(0.3, Color(1, 1, 1, 0.7))
	g.add_point(0.6, Color(1, 1, 1, 0.25))
	var t := GradientTexture2D.new()
	t.gradient = g
	t.fill = GradientTexture2D.FILL_RADIAL
	t.fill_from = Vector2(0.5, 0.5)
	t.fill_to = Vector2(1.0, 0.5)
	t.width = 64
	t.height = 64
	return t

func _fade_ramp(core_color: Color, mid_color: Color) -> GradientTexture1D:
	var g := Gradient.new()
	g.set_offset(0, 0.0)
	g.set_color(0, Color(core_color.r, core_color.g, core_color.b, 1.0))
	g.set_offset(1, 1.0)
	g.set_color(1, Color(mid_color.r, mid_color.g, mid_color.b, 0.0))
	g.add_point(0.55, Color(mid_color.r, mid_color.g, mid_color.b, 0.75))
	var t := GradientTexture1D.new()
	t.gradient = g
	return t

## Trail specks bloom in for their first instant rather than popping to
## full size, then shrink away over the rest of their life.
func _trail_scale_curve() -> CurveTexture:
	var c := Curve.new()
	c.add_point(Vector2(0.0, 0.3))
	c.add_point(Vector2(0.15, 1.0))
	c.add_point(Vector2(1.0, 0.15))
	var t := CurveTexture.new()
	t.curve = c
	return t
