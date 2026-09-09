@tool
class_name DustMotes
extends GPUParticles3D

## Attach directly to a GPUParticles3D that's a child of the SpotLight3D
## shining through a window. Fills the light's cone with slow-drifting dust
## specks that catch the light -- the thing that actually sells a moonbeam,
## more than the beam geometry itself does.
##
## Configures the node it's attached to entirely from code, because doing
## this by hand means ~15 separate inspector values across three nested
## resources, and getting any one of them wrong (Amount left at its default
## 8, a tiny emission box, a too-small visibility AABB) makes the whole
## thing look broken in a way that's hard to attribute.
##
## Assumes the parent light shines along its local -Z (Godot's convention
## for SpotLight3D), so the emitter is offset and stretched that way.

## Match these to the SpotLight3D's own Range and roughly its cone width at
## that distance -- the dust should fill the beam, not a box around it.
@export var beam_length := 8.0:
	set(value):
		beam_length = value
		_rebuild()
@export var beam_width := 2.0:
	set(value):
		beam_width = value
		_rebuild()
@export var mote_count := 60:
	set(value):
		mote_count = value
		_rebuild()
@export var mote_size := 0.015:
	set(value):
		mote_size = value
		_rebuild()
@export var mote_color := Color(0.8, 0.86, 1.0):
	set(value):
		mote_color = value
		_apply_color()
## How long a speck lives before fading and respawning. Long, because dust
## shouldn't visibly stream -- it should hang.
@export var mote_lifetime := 8.0:
	set(value):
		mote_lifetime = value
		_rebuild()

var _mote_material: StandardMaterial3D
var _rebuild_queued := false
var _last_particle_density := 1.0

func _ready() -> void:
	_rebuild()
	if not Engine.is_editor_hint():
		Settings.changed.connect(_on_settings_changed)
		_last_particle_density = Settings.particle_density

func _rebuild() -> void:
	if not is_inside_tree() or _rebuild_queued:
		return
	_rebuild_queued = true
	_do_rebuild.call_deferred()

## Settings.particle_density scales this instance's own authored mote_count
## rather than being an absolute number -- same reasoning as
## fire_sparks.gd's _effective_particle_count(). Editor preview always shows
## the full authored count.
func _effective_particle_count() -> int:
	if Engine.is_editor_hint():
		return mote_count
	return maxi(1, roundi(mote_count * Settings.particle_density))

func _on_settings_changed() -> void:
	if not is_equal_approx(Settings.particle_density, _last_particle_density):
		_last_particle_density = Settings.particle_density
		_rebuild()

func _do_rebuild() -> void:
	_rebuild_queued = false

	amount = _effective_particle_count()
	lifetime = mote_lifetime
	randomness = 0.9
	fixed_fps = 30
	# Sit the emitter halfway down the beam rather than at the light itself,
	# or every speck spawns in a clump at the source.
	position = Vector3(0, 0, -beam_length * 0.5)
	# Generous, hand-set box: particles drifting outside a tight AABB just
	# stop being drawn, which reads as "they disappear halfway".
	visibility_aabb = AABB(
		Vector3(-beam_width, -beam_width, -beam_length * 0.6),
		Vector3(beam_width * 2.0, beam_width * 2.0, beam_length * 1.2)
	)

	draw_pass_1 = _build_mesh()
	process_material = _build_process_material()

func _build_mesh() -> QuadMesh:
	_mote_material = StandardMaterial3D.new()
	# Lit, not unshaded: this is what makes a mote actually go dark outside
	# the light's cone and its shadow (the window frame's mullions) instead
	# of glowing the same everywhere regardless of whether real light
	# reaches it. Additive blending still works correctly here -- with
	# near-zero light hitting it a mote's diffuse contribution is near
	# black, which adds essentially nothing, i.e. invisible; lit, it adds a
	# bright speck. disable_ambient_light keeps that contrast sharp: without
	# it the scene's ambient/GI alone would give every mote a faint
	# permanent glow even in full shadow, and "catches the moonlight" stops
	# reading as special.
	_mote_material.shading_mode = BaseMaterial3D.SHADING_MODE_PER_PIXEL
	_mote_material.disable_ambient_light = true
	_mote_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_mote_material.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	_mote_material.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	_mote_material.billboard_keep_scale = true
	_mote_material.vertex_color_use_as_albedo = true
	_mote_material.disable_receive_shadows = false
	_mote_material.albedo_texture = _soft_speck()
	_apply_color()

	var quad := QuadMesh.new()
	quad.size = Vector2(mote_size, mote_size)
	quad.material = _mote_material
	return quad

func _apply_color() -> void:
	if _mote_material:
		_mote_material.albedo_color = mote_color

func _build_process_material() -> ParticleProcessMaterial:
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	pm.emission_box_extents = Vector3(beam_width * 0.5, beam_width * 0.5, beam_length * 0.5)

	# No launch direction worth speaking of -- dust doesn't go anywhere, it
	# hangs and wanders. Spread 180 + near-zero velocity gives that.
	pm.direction = Vector3(0, 1, 0)
	pm.spread = 180.0
	pm.initial_velocity_min = 0.005
	pm.initial_velocity_max = 0.03
	pm.gravity = Vector3(0, -0.015, 0)

	pm.scale_min = 0.4
	pm.scale_max = 1.5
	pm.turbulence_enabled = true
	pm.turbulence_noise_strength = 0.25
	pm.turbulence_noise_scale = 1.8
	pm.color_ramp = _fade_ramp()
	return pm

## Round soft-edged speck, generated rather than imported -- same technique
## as components/fire_sparks.gd's _soft_blob().
func _soft_speck() -> GradientTexture2D:
	var g := Gradient.new()
	g.set_offset(0, 0.0)
	g.set_color(0, Color(1, 1, 1, 1))
	g.set_offset(1, 1.0)
	g.set_color(1, Color(1, 1, 1, 0))
	g.add_point(0.35, Color(1, 1, 1, 0.6))
	var t := GradientTexture2D.new()
	t.gradient = g
	t.fill = GradientTexture2D.FILL_RADIAL
	t.fill_from = Vector2(0.5, 0.5)
	t.fill_to = Vector2(1.0, 0.5)
	t.width = 32
	t.height = 32
	return t

## Fade in and back out over each speck's life, so nothing ever visibly
## pops into or out of existence mid-air.
func _fade_ramp() -> GradientTexture1D:
	var g := Gradient.new()
	g.set_offset(0, 0.0)
	g.set_color(0, Color(1, 1, 1, 0.0))
	g.set_offset(1, 1.0)
	g.set_color(1, Color(1, 1, 1, 0.0))
	g.add_point(0.2, Color(1, 1, 1, 1.0))
	g.add_point(0.8, Color(1, 1, 1, 1.0))
	var t := GradientTexture1D.new()
	t.gradient = g
	return t
