class_name WorldEmissive
extends MeshInstance3D

## The material counterpart to WorldLight (see world_light.gd): attach
## directly to a MeshInstance3D whose surface material glows, so the glass
## itself is extinguished and relit along with the light inside it instead
## of staying visibly lit while the world around it goes black.
##
## Duplicates the surface material on ready before touching it, so this
## never silently repaints every other user of what might be a shared
## material resource -- each lit object gets its own instance to animate.

@export var surface_index: int = 0
@export var otherside_emission := Color(0.35, 1.0, 0.5)
@export var otherside_albedo := Color(0.6, 1.0, 0.75, 0.35)
## Negative = keep the material's current emission_energy_multiplier.
@export var otherside_energy := -1.0

## Zone-culling multiplier, owned by ZoneManager -- same contract as
## WorldLight.zone_dim. The glowing glass has to dim along with the light
## inside it, otherwise an unlit room's fixtures still read as "on".
var zone_dim := 1.0

var _mat: StandardMaterial3D
var _real_emission: Color
var _real_albedo: Color
var _real_energy: float

func _ready() -> void:
	var base := get_surface_override_material(surface_index)
	if base == null and mesh:
		base = mesh.surface_get_material(surface_index)
	if base == null or not (base is StandardMaterial3D):
		return

	_mat = base.duplicate() as StandardMaterial3D
	set_surface_override_material(surface_index, _mat)

	_real_emission = _mat.emission
	_real_albedo = _mat.albedo_color
	_real_energy = _mat.emission_energy_multiplier

	WorldState.world_changed.connect(_on_world_changed)
	_apply_world(WorldState.current_world)

func _process(_delta: float) -> void:
	if not _mat:
		return
	# Runs every frame now, not only mid-transition: zone_dim changes while
	# the world phase is IDLE (walking between rooms), and the old early-out
	# meant those changes were never actually written to the material.
	_mat.emission_energy_multiplier = _target_energy() * (1.0 - WorldState.darkness) * zone_dim

func _target_energy() -> float:
	if WorldState.current_world == WorldState.World.OTHERSIDE:
		return _real_energy if otherside_energy < 0.0 else otherside_energy
	return _real_energy

## Snapped, not tweened -- see the note in world_light.gd.
func _apply_world(world) -> void:
	if not _mat:
		return
	var is_real: bool = world == WorldState.World.REAL
	_mat.emission = _real_emission if is_real else otherside_emission
	_mat.albedo_color = _real_albedo if is_real else otherside_albedo
	_mat.emission_energy_multiplier = _target_energy() * (1.0 - WorldState.darkness) * zone_dim

func _on_world_changed(new_world) -> void:
	_apply_world(new_world)
