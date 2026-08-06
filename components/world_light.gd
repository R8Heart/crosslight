class_name WorldLight
extends Light3D

## Attach directly to any Light3D (Omni/Spot/Directional) to make it take
## part in the world switch: it dims to nothing as the world is dragged
## into the orb, swaps colour unseen in the dark, and comes back up in the
## new world's colour (see world_state.gd for the phase timing).
##
## The dimming is what actually darkens the world -- a black rectangle over
## the screen would hide the lights but not the fact that they were still
## lighting things. Scaling real light energy means shadows and falloff
## collapse properly as the light is swallowed.
##
## Whatever colour/energy the light already has in the editor is read as its
## "Real" state automatically on ready -- only the Otherside target needs to
## be filled in here, so wiring up an existing hand-tuned light costs one
## field, not a duplicated set of constants.

@export var otherside_color := Color(0.35, 1.0, 0.5)
## Negative = keep whatever energy this light already has; only the colour
## shifts. Set a real value here only if this light should also get
## brighter or dimmer on the Otherside.
@export var otherside_energy := -1.0

var _real_color: Color
var _real_energy: float

func _ready() -> void:
	_real_color = light_color
	_real_energy = light_energy
	WorldState.world_changed.connect(_on_world_changed)
	_apply_world(WorldState.current_world)

func _process(_delta: float) -> void:
	if WorldState.phase == WorldState.Phase.IDLE:
		return
	light_energy = _target_energy() * (1.0 - WorldState.darkness)

func _target_energy() -> float:
	if WorldState.current_world == WorldState.World.OTHERSIDE:
		return _real_energy if otherside_energy < 0.0 else otherside_energy
	return _real_energy

## Snapped, not tweened: this only ever runs mid-blackout, so a crossfade
## here would be invisible at best and would fight the dimming at worst.
func _apply_world(world) -> void:
	light_color = _real_color if world == WorldState.World.REAL else otherside_color
	light_energy = _target_energy() * (1.0 - WorldState.darkness)

func _on_world_changed(new_world) -> void:
	_apply_world(new_world)
