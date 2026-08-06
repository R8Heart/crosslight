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

## Live flame flicker -- small candles/lanterns feel dead without it. On by
## default; turn off per-instance for lights that shouldn't breathe (a
## chandelier with many bulbs tends to average out and just read as noise).
@export var flicker_enabled := true
## Fraction of energy the flicker swings by, e.g. 0.12 = +/-12%.
@export_range(0.0, 0.5) var flicker_strength := 0.12
@export_range(0.1, 5.0) var flicker_speed := 1.0

var _real_color: Color
var _real_energy: float
var _flicker_noise := FastNoiseLite.new()
## Random per-instance offset so a row of candles doesn't pulse in lockstep.
var _flicker_seed: float

func _ready() -> void:
	_real_color = light_color
	_real_energy = light_energy
	_flicker_seed = randf() * 1000.0
	_flicker_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX
	_flicker_noise.frequency = 1.0
	WorldState.world_changed.connect(_on_world_changed)
	_apply_world(WorldState.current_world)

func _process(_delta: float) -> void:
	light_energy = _target_energy() * (1.0 - WorldState.darkness) * _flicker_multiplier()

## Two layers, like a real flame: a slow organic drift (noise) for the
## "breathing" and a quick jitter (fast sines) for the restless flicker on
## top of it. Pure sine alone reads as a mechanical pulse, not a flame.
func _flicker_multiplier() -> float:
	if not flicker_enabled:
		return 1.0
	var t := (Time.get_ticks_msec() / 1000.0) * flicker_speed + _flicker_seed
	var drift := _flicker_noise.get_noise_1d(t)
	var jitter := sin(t * 11.3) * 0.35 + sin(t * 23.7) * 0.2
	return 1.0 + (drift * 0.7 + jitter * 0.3) * flicker_strength

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
