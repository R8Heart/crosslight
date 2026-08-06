extends Node3D

## The glowing orb held in the player's hand — the character's own soul, and the
## only light he has.
##
## During a world switch it is the one thing that does NOT go dark: while
## every other light in the world is dimming into it, the orb swells and
## burns harder, holds through the blackout as the only thing left, then
## flares as it throws the new world back out. All of that timing comes from
## WorldState (see world_state.gd), which is the single clock for the switch.

const REAL_LIGHT := Color(1.0, 0.55, 0.15)
const REAL_CORE := Color(1.0, 0.85, 0.5)
const REAL_MID := Color(1.0, 0.55, 0.15)
const REAL_RIM := Color(1.0, 0.4, 0.05)

const OTHER_LIGHT := Color(0.25, 1.0, 0.45)
const OTHER_CORE := Color(0.75, 1.0, 0.8)
const OTHER_MID := Color(0.3, 1.0, 0.5)
const OTHER_RIM := Color(0.05, 0.8, 0.3)

## How much brighter the orb gets at the peak of a switch, on top of
## whatever it is normally tuned to -- reached at the end of the inhale,
## held through the dark, spent on the burst.
const SURGE_LIGHT := 2.4
const SURGE_GLOW := 3.2
## How far past the surface the release pulse travels before it dies out.
const WAVE_END := 1.4

const FLICKER_AMOUNT := 0.2
const FLICKER_SPEED := 3.0

## The orb is a loose ball rattling around inside the lantern's cage, not
## glued to it: gravity constantly pulls it toward whatever is "down" in the
## lantern's own current tilt, the lantern's slide (see lantern_rig.gd) kicks
## it sideways, and it bounces off the cage wall instead of just clamping —
## the same lag-and-settle family of tricks used everywhere else on this
## rig, just as a real little 3D roll instead of a position lag.
@export var roll_gravity := 2.4
@export var roll_damping := 2.2
## How far the orb's centre may stray from its resting position before it's
## treated as hitting the cage wall. Kept a little short of the actual glass
## so the visible sphere never pokes through.
@export var cage_radius := 0.075
## Fraction of the inward velocity kept (reflected) on a wall hit — 0 stops
## it dead, 1 would be a perfectly elastic bounce.
@export var bounce_restitution := 0.4
@export var kick_amplify := 1.6
@export var kick_clamp := 0.03

@onready var glass: MeshInstance3D = $Glass
@onready var light: OmniLight3D = $OrbLight

var _noise := FastNoiseLite.new()
var _glass_mat: ShaderMaterial

var _base_local_pos := Vector3.ZERO
var _lantern_rig: Node3D
var _lag_rig_pos := Vector3.ZERO
var _velocity := Vector3.ZERO

## 0 = Real, 1 = Otherside — the colour blend.
var _transition := 0.0
## 0 -> 1 -> 0 across any switch, in either direction; drives the surge.
var _surge := 0.0
## Radius of the travelling wavefront, always sweeps outward.
var _wave := 0.0

## Read from the scene rather than hardcoded, so tuning done by hand in the
## editor survives — an earlier version overwrote it every frame instead.
var _base_energy := 1.0
var _base_glow := 2.2

func _ready() -> void:
	_noise.frequency = 1.5
	_glass_mat = glass.get_surface_override_material(0) as ShaderMaterial

	_base_energy = light.light_energy
	if _glass_mat:
		var glow = _glass_mat.get_shader_parameter("glow_intensity")
		if glow != null:
			_base_glow = glow

	_base_local_pos = position
	# Orb -> LanternVisual -> LanternRig: LanternRig's own position IS its
	# slide offset (see lantern_rig.gd), which is itself already a lagged
	# echo of the hand's bob — reading it here is what jostles the orb
	# sideways, one link further down the chain than the lantern's own kick.
	_lantern_rig = get_parent().get_parent()
	if _lantern_rig:
		_lag_rig_pos = _lantern_rig.position

	WorldState.world_changed.connect(_on_world_changed)
	_transition = 0.0 if WorldState.current_world == WorldState.World.REAL else 1.0

func _process(delta: float) -> void:
	_update_roll(delta)
	_update_transition()
	_update_shader_params()

	var t := Time.get_ticks_msec() / 1000.0
	var flicker := _noise.get_noise_1d(t * FLICKER_SPEED) * FLICKER_AMOUNT

	light.light_color = REAL_LIGHT.lerp(OTHER_LIGHT, _transition)
	light.light_energy = _base_energy + flicker + SURGE_LIGHT * _surge

## The orb gets brighter exactly as the world gets darker: `_surge` tracks
## WorldState.darkness directly rather than running its own tween, so it is
## physically impossible for the two to drift out of sync -- the orb peaks
## precisely when everything else has been swallowed, and fades as the
## release throws that light back out. The travelling pulse through the
## glass only happens on the way back out, timed off the same burst spike
## that drives the screen-space flash (see world_transition_fx.gd).
func _update_transition() -> void:
	_surge = WorldState.darkness
	if WorldState.phase == WorldState.Phase.EXHALE:
		_wave = (1.0 - WorldState.burst) * WAVE_END
	else:
		_wave = 0.0

## Continuous local "gravity" (pulling toward whatever is currently downhill
## inside the lantern's own tilt, per lantern_rig.gd's swing) plus a lateral
## kick whenever the lantern itself suddenly slides, integrated into a real
## velocity — then bounced off an invisible spherical cage wall instead of
## just clamped, so a hard knock actually rebounds instead of going dead.
func _update_roll(delta: float) -> void:
	var parent3d := get_parent() as Node3D
	if parent3d:
		var local_down: Vector3 = (parent3d.global_transform.basis.inverse() * Vector3.DOWN).normalized()
		_velocity += local_down * roll_gravity * delta

	if _lantern_rig:
		var current_rig_pos: Vector3 = _lantern_rig.position
		_lag_rig_pos = _lag_rig_pos.lerp(current_rig_pos, clampf(delta * 6.0, 0.0, 1.0))
		var kick := ((current_rig_pos - _lag_rig_pos) * kick_amplify).limit_length(kick_clamp)
		_velocity += kick

	_velocity *= clampf(1.0 - roll_damping * delta, 0.0, 1.0)
	position += _velocity * delta

	var offset := position - _base_local_pos
	if offset.length() > cage_radius:
		var normal := offset.normalized()
		position = _base_local_pos + normal * cage_radius
		var into_wall := _velocity.dot(normal)
		if into_wall > 0.0:
			_velocity -= normal * into_wall * (1.0 + bounce_restitution)

func _update_shader_params() -> void:
	if not _glass_mat:
		return
	_glass_mat.set_shader_parameter("color_core", REAL_CORE.lerp(OTHER_CORE, _transition))
	_glass_mat.set_shader_parameter("color_mid", REAL_MID.lerp(OTHER_MID, _transition))
	_glass_mat.set_shader_parameter("color_rim", REAL_RIM.lerp(OTHER_RIM, _transition))
	_glass_mat.set_shader_parameter("glow_intensity", _base_glow + SURGE_GLOW * _surge)
	_glass_mat.set_shader_parameter("transition_wave", _wave)
	_glass_mat.set_shader_parameter("transition_energy", _surge)

## Fired mid-blackout (see world_state.gd's _enter_dark): snapping instead
## of tweening is deliberate, the same reasoning as WorldLight/WorldEmissive
## -- darkness is already 1.0 the instant this fires, so the swap is
## invisible regardless, and a leftover tween here would just be one more
## thing that could fall out of step with WorldState's own clock.
func _on_world_changed(new_world) -> void:
	_transition = 0.0 if new_world == WorldState.World.REAL else 1.0
