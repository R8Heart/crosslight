@tool
class_name Moonbeam
extends Node3D

## One shaft of moonlight through a window. Place this node at the window,
## rotated so its local -Z points the way the light should fall into the
## room (same convention as any Godot light), and it builds the whole
## setup: a shadow-casting SpotLight3D, a FogVolume for the light to
## actually scatter through, and drifting dust motes.
##
## Three things have to line up for a visible shaft, and missing any one of
## them makes it look like nothing is happening:
##
## 1. The light needs Volumetric Fog Energy above zero (light_volumetric_fog_energy
##    below). A light with this at 0 contributes nothing to fog no matter how
##    the fog itself is configured -- this is set here, so it's handled.
## 2. There has to be fog in the beam's path. The FogVolume below provides
##    it locally, so global fog density can stay at ~0.
## 3. The WorldEnvironment's volumetric fog has to be tuned for detail, not
##    range. Defaults aimed at outdoor scenes (Length 90m, Anisotropy 0.2)
##    smear a shaft into uniform haze. See the header notes in the scene, or:
##      Environment > Volumetric Fog > Length: 15-25 (not 90)
##      Environment > Volumetric Fog > Anisotropy: 0.8 (not 0.2)
##      Project Settings > Rendering > Volumetric Fog > Volume Size/Depth: 64+
##
## Runs as @tool so the beam is visible in the editor while aiming it.
## Children are built without an owner, so nothing is written to the scene
## file -- it's rebuilt on load.

@export var beam_length := 10.0:
	set(value):
		beam_length = value
		_rebuild()
## Cone half-angle in degrees -- how wide the shaft spreads by the far end.
@export var beam_angle := 22.0:
	set(value):
		beam_angle = value
		_rebuild()
@export var moon_color := Color(0.72, 0.8, 1.0):
	set(value):
		moon_color = value
		_rebuild()
@export var light_energy := 3.0:
	set(value):
		light_energy = value
		_rebuild()
## Falloff of brightness over distance. THE setting that decides whether
## there's a visible shaft at all: at the default 1.0 the light dies within
## a metre or two of the source and there's simply nothing left to scatter
## further down the beam. Low values carry the light the full range, which
## is what makes the shaft read.
@export_range(0.1, 2.0, 0.05) var light_attenuation := 0.35:
	set(value):
		light_attenuation = value
		_rebuild()
## How far back outside the window to push the actual light source, along
## +Z (away from the room). Real moonlight comes from outside, so the
## window frame sits between the light and the room -- it silhouettes and
## casts shadow bars instead of being lit head-on, which is what makes the
## reveals and jambs light up wrongly when the light sits indoors.
## The fog and dust stay put inside the room regardless.
@export var light_setback := 3.0:
	set(value):
		light_setback = value
		_rebuild()
## How strongly this light shows up in the fog. This is the setting that
## makes the shaft visible at all -- raise it before touching anything else.
@export var fog_energy := 1.5:
	set(value):
		fog_energy = value
		_rebuild()
## Local fog density in the beam's path. Global fog density can stay near
## zero; this is what the light actually scatters through. Small numbers go
## a long way -- 0.5 here is thick enough to stand inside a milk bottle.
@export var fog_density := 0.04:
	set(value):
		fog_density = value
		_rebuild()
@export var dust_count := 60:
	set(value):
		dust_count = value
		_rebuild()
@export var dust_size := 0.015:
	set(value):
		dust_size = value
		_rebuild()

var _light: SpotLight3D
var _fog: FogVolume
var _dust: GPUParticles3D
var _rebuild_queued := false

func _ready() -> void:
	_rebuild()

func _rebuild() -> void:
	if not is_inside_tree() or _rebuild_queued:
		return
	_rebuild_queued = true
	_do_rebuild.call_deferred()

func _do_rebuild() -> void:
	_rebuild_queued = false
	for child in [_light, _fog, _dust]:
		if child:
			child.queue_free()

	_light = _build_light()
	add_child(_light)
	_fog = _build_fog()
	add_child(_fog)
	_dust = _build_dust()
	add_child(_dust)

	# Children are deliberately created without an owner (so they never get
	# written into the scene file), which also means they don't appear in
	# the Scene dock -- there's no way to eyeball whether this ran. Hence
	# the print: if this line isn't in Output, the build didn't happen.
	print("MOONBEAM: built at %s, shining toward %s (light=%s fog=%s dust=%s)" % [
		global_position,
		-global_transform.basis.z,
		is_instance_valid(_light),
		is_instance_valid(_fog),
		is_instance_valid(_dust),
	])

func _build_light() -> SpotLight3D:
	var l := SpotLight3D.new()
	l.light_color = moon_color
	l.light_energy = light_energy
	# The whole point: without this the light is invisible inside fog.
	l.light_volumetric_fog_energy = fog_energy
	# Shadows are what carve the window's mullions into the shaft. Without
	# them it's an even cone of light, which reads as a spotlight, not
	# moonlight through glass.
	l.shadow_enabled = true
	# Range has to cover the setback too, or the beam dies before it even
	# reaches the glass.
	l.spot_range = beam_length + light_setback
	l.spot_angle = beam_angle
	l.spot_attenuation = light_attenuation
	l.spot_angle_attenuation = 0.4
	# Pushed back outside; the fog volume and dust below stay at the window
	# and in the room, where the visible shaft belongs.
	l.position = Vector3(0, 0, light_setback)
	return l

## A box of fog just big enough to hold the cone. Keeping it local means
## the rest of the level doesn't need global fog density raised (which
## would haze up every room and cost performance everywhere).
func _build_fog() -> FogVolume:
	var fv := FogVolume.new()
	var mat := FogMaterial.new()
	mat.density = fog_density
	mat.albedo = Color(1, 1, 1)
	# Soften the box's own edges so it doesn't end in a visible straight cut.
	mat.edge_fade = 0.4

	var width := 2.0 * beam_length * tan(deg_to_rad(beam_angle))
	fv.size = Vector3(width, width, beam_length)
	fv.position = Vector3(0, 0, -beam_length * 0.5)
	fv.material = mat
	return fv

func _build_dust() -> GPUParticles3D:
	var p := GPUParticles3D.new()
	p.amount = dust_count
	p.lifetime = 8.0
	p.randomness = 0.9
	p.fixed_fps = 30
	p.position = Vector3(0, 0, -beam_length * 0.5)

	var half_width := beam_length * tan(deg_to_rad(beam_angle))
	# Set by hand and generously: motes drifting outside a tight AABB just
	# stop being drawn, which reads as them vanishing mid-air.
	p.visibility_aabb = AABB(
		Vector3(-half_width * 1.5, -half_width * 1.5, -beam_length * 0.75),
		Vector3(half_width * 3.0, half_width * 3.0, beam_length * 1.5)
	)

	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	mat.billboard_keep_scale = true
	mat.vertex_color_use_as_albedo = true
	mat.disable_receive_shadows = true
	mat.albedo_texture = _soft_speck()
	mat.albedo_color = moon_color

	var quad := QuadMesh.new()
	quad.size = Vector2(dust_size, dust_size)
	quad.material = mat
	p.draw_pass_1 = quad

	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	pm.emission_box_extents = Vector3(half_width, half_width, beam_length * 0.5)
	# Dust doesn't travel anywhere -- it hangs and wanders. Spread 180 with
	# near-zero velocity gives that, rather than a directional stream.
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
	p.process_material = pm
	return p

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

## Fade each mote in and back out over its life so none of them pop into or
## out of existence mid-air.
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
