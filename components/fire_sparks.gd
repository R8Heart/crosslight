@tool
class_name FireSparks
extends Node3D

## Sparks drifting up off the log bed. This is what's left after two
## volumetric flame attempts (billboard sprite sheet, then raymarched SDF)
## both got scrapped -- the glowing logs plus FireLight already carry the
## fireplace, and sparks are the one cheap layer left that reads as fire
## without trying to paint an actual flame shape again.
##
## Runs as @tool so the spark drift is visible in the editor viewport while
## sizing it. The particle node is built without an owner, so it exists at
## runtime only and never gets written into the scene file.

## Footprint of the log bed the sparks rise from, in metres.
@export var width := 0.5:
	set(value):
		width = value
		_rebuild()
@export var depth := 0.35:
	set(value):
		depth = value
		_rebuild()
## How high a spark climbs before dying, roughly -- drives initial velocity.
@export var height := 0.6:
	set(value):
		height = value
		_rebuild()
@export var spark_particles := 10:
	set(value):
		spark_particles = value
		_rebuild()
## Overall brightness.
@export var intensity := 2.0:
	set(value):
		intensity = value
		_apply_brightness()

## Spark colours, hot end first.
@export var color_core := Color(1.0, 0.55, 0.12):
	set(value):
		color_core = value
		_apply_world_colors()
@export var color_mid := Color(0.95, 0.25, 0.03):
	set(value):
		color_mid = value
		_apply_world_colors()
## Otherside palette -- same motion, wrong colour.
@export var otherside_core := Color(0.55, 1.0, 0.7)
@export var otherside_mid := Color(0.12, 0.85, 0.35)

## Zone-culling multiplier, owned by ZoneManager -- same contract as
## WorldLight.zone_dim and WorldEmissive.zone_dim.
var zone_dim := 1.0:
	set(value):
		zone_dim = value
		_apply_brightness()

var _sparks: GPUParticles3D
var _spark_mat: StandardMaterial3D
var _last_brightness := -1.0
var _rebuild_queued := false

func _ready() -> void:
	_rebuild()
	if not Engine.is_editor_hint():
		WorldState.world_changed.connect(_on_world_changed)

func _process(_delta: float) -> void:
	if not Engine.is_editor_hint():
		_apply_brightness()

## Exported values are assigned one at a time as the scene loads, and
## dragging a slider in the inspector fires its setter many times a
## second -- so coalesce all of that into at most one rebuild per frame
## rather than tearing the particle system down and back up repeatedly.
func _rebuild() -> void:
	if not is_inside_tree() or _rebuild_queued:
		return
	_rebuild_queued = true
	_do_rebuild.call_deferred()

func _do_rebuild() -> void:
	_rebuild_queued = false

	if _sparks:
		_sparks.queue_free()
	_sparks = _build_sparks()
	add_child(_sparks)

	_apply_world_colors()
	_last_brightness = -1.0
	_apply_brightness()

func _apply_brightness() -> void:
	if not _spark_mat or not _sparks:
		return
	var darkness: float = 0.0 if Engine.is_editor_hint() else WorldState.darkness
	var lit := intensity * zone_dim * (1.0 - darkness)
	if is_equal_approx(lit, _last_brightness):
		return
	_last_brightness = lit

	_spark_mat.albedo_color = Color(lit, lit, lit, 1.0)
	# Fully dark means an unlit room, so stop simulating entirely rather
	# than paying for particle work nobody can see.
	_sparks.emitting = lit > 0.01

func _on_world_changed(new_world) -> void:
	_apply_world_colors(new_world)

func _apply_world_colors(world = null) -> void:
	if not _sparks:
		return
	if world == null:
		world = WorldState.World.REAL if Engine.is_editor_hint() else WorldState.current_world
	var is_real: bool = world == WorldState.World.REAL
	var core := color_core if is_real else otherside_core
	var mid := color_mid if is_real else otherside_mid
	var process := _sparks.process_material as ParticleProcessMaterial
	process.color_ramp = _spark_ramp(core, mid)

func _build_sparks() -> GPUParticles3D:
	var p := GPUParticles3D.new()
	p.amount = spark_particles
	# An ember's whole job is to drift well clear of the fire before it dies.
	p.lifetime = 2.6
	p.randomness = 0.8
	p.fixed_fps = 30

	_spark_mat = _sprite_material()
	var quad := QuadMesh.new()
	# Fixed size, not derived from width/height -- a spark is a physical
	# scrap of glowing ash roughly the same size in every fireplace.
	quad.size = Vector2(0.012, 0.012)
	quad.material = _spark_mat
	p.draw_pass_1 = quad

	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	pm.emission_box_extents = Vector3(width * 0.45, 0.02, depth * 0.45)
	pm.direction = Vector3(0, 1, 0)
	pm.spread = 25.0
	# Fast enough to climb clear of the log pile and read against the dark
	# chimney above it; sparks that never leave the fire are lost in it.
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

## Additive unshaded billboard. Brightness rides on albedo_color rather
## than an emission slot because emission isn't modulated by the particle
## colour ramp, which would leave every spark the same colour regardless
## of how far through its flight it was.
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

## Round soft-edged speck, generated rather than imported.
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
## out right at the end, rather than fading the whole way like flame does.
func _spark_ramp(core: Color, mid: Color) -> GradientTexture1D:
	var g := Gradient.new()
	g.set_offset(0, 0.0)
	g.set_color(0, Color(core.r, core.g, core.b, 1.0))
	g.set_offset(1, 1.0)
	g.set_color(1, Color(mid.r, mid.g, mid.b, 0.0))
	g.add_point(0.75, Color(mid.r, mid.g, mid.b, 0.9))
	var t := GradientTexture1D.new()
	t.gradient = g
	return t

## Particles start small, bloom out as they rise, then shrink away rather
## than blinking out at full size.
func _scale_curve() -> CurveTexture:
	var c := Curve.new()
	c.add_point(Vector2(0.0, 0.45))
	c.add_point(Vector2(0.3, 1.0))
	c.add_point(Vector2(0.7, 0.85))
	c.add_point(Vector2(1.0, 0.1))
	var t := CurveTexture.new()
	t.curve = c
	return t
