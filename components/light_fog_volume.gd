@tool
class_name LightFogVolume
extends FogVolume

## Attach directly to a FogVolume that's a child of a SpotLight3D shining
## through a window (sibling of DustMotes, see dust_motes.gd). Self-sizes
## its *length* from the parent light's own spot_range, so that at least
## stays in sync if the light's range is retuned later.
##
## Width is deliberately its own export, NOT derived from the light's
## spot_angle: spot_angle here is tuned wide (55-59 degrees) to throw a nice
## broad patch of light across the floor, but a fog box that wide floods
## almost the whole visible wall with haze instead of reading as a beam --
## found that out the hard way. Match beam_width to whatever DustMotes on
## the same light is using so the fog and the dust occupy the same visual
## column.
##
## Global volumetric fog density is kept low on purpose (see WorldEnvironment
## in estate_exterior.tscn) so the rest of the estate doesn't haze up --
## which means a window light's own light_volumetric_fog_energy has almost
## nothing to scatter through without a local pocket of denser fog right at
## the window. This is that pocket. It does not add a second light; the
## existing SpotLight3D is untouched.

@export var beam_width := 3.5:
	set(value):
		beam_width = value
		_rebuild()
@export var density := 0.03:
	set(value):
		density = value
		_rebuild()
@export var edge_fade := 0.4:
	set(value):
		edge_fade = value
		_rebuild()
@export var albedo := Color(1, 1, 1):
	set(value):
		albedo = value
		_rebuild()

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
	var light := get_parent() as SpotLight3D
	if light == null:
		push_warning("LightFogVolume: parent is not a SpotLight3D -- can't auto-size, skipping.")
		return

	var mat := FogMaterial.new()
	mat.density = density
	mat.albedo = albedo
	mat.edge_fade = edge_fade

	var length := light.spot_range
	size = Vector3(beam_width, beam_width, length)
	# Centered along the light's own -Z, same convention as its cone.
	position = Vector3(0, 0, -length * 0.5)
	material = mat
