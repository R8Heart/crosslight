extends Node
class_name SkyController

## Drives everything about the night: the procedural sky shader, the moon's
## directional light, and the fog — all from one place, so they can never
## disagree with each other.
##
## The whole look is derived every frame from three values: `_transition`
## (0 = Real, 1 = Otherside, snapped mid-blackout by WorldState -- see
## _on_world_changed), `_coverage` (how overcast it currently is) and
## `_flash` (lightning). Nothing else writes to the light or the shader,
## which is what keeps the world-switch, the drifting cloud cover and the
## lightning from fighting each other over the same properties. The moon's
## energy and the scene's ambient are additionally scaled by
## WorldState.darkness every frame, which is what actually makes the world
## go black during a switch rather than just being covered by a screen
## overlay (see world_transition_fx.gd).

@export var moon_light_path: NodePath = ^"../MoonLight"
@export var world_environment_path: NodePath = ^"../WorldEnvironment"

## Where the moon hangs is just MoonLight's own transform now — rotate it
## by hand in the editor like any other node. The sky shader reads Godot's
## built-in LIGHT0_DIRECTION (see night_sky.gdshader), which Godot keeps in
## sync with the light's actual orientation automatically, so the disc
## always matches wherever the light is actually pointed. Nothing here
## computes or overwrites that transform.

## Moonlight at fully clear sky. Thick cloud scales this down toward
## COVERAGE_DIM, which is what makes the ground darken as clouds roll over.
const MOON_ENERGY := 0.42
const COVERAGE_DIM := 0.55

## Overcast drifts slowly between these two extremes forever.
const COVERAGE_MIN := 0.26
const COVERAGE_MAX := 0.60
const COVERAGE_DRIFT_SPEED := 0.035

## A strike is a short burst of a few strokes, then a long wait.
const STRIKE_DURATION := 0.75
const STRIKE_GAP_MIN := 3.5
const STRIKE_GAP_MAX := 11.0
## How much a strike lifts the scene lighting, on top of the moon. Modest on
## purpose: enough to feel the ground flash, not enough to blow it to white.
const STRIKE_LIGHT_BOOST := 0.8

# --- Real world: cold, clear, blue moonlight -------------------------------
const REAL_LIGHT_COLOR := Color(0.62, 0.72, 0.95)
const REAL_SKY := Color(0.004, 0.006, 0.013)
const REAL_MOON_TINT := Color(0.82, 0.88, 1.0)
const REAL_CLOUD_LIT := Color(0.55, 0.62, 0.8)
const REAL_CLOUD_DARK := Color(0.012, 0.016, 0.028)
const REAL_WORLD_TINT := Color(1.0, 1.0, 1.0)
const REAL_FOG := Color(0.012, 0.017, 0.035)
const REAL_AMBIENT := Color(0.05, 0.07, 0.13)
const REAL_MIST_TINT := Color(1.0, 1.0, 1.0)
const REAL_COVERAGE_BIAS := 0.0

# --- Otherside: sickly green, heavier cloud, electrical ---------------------
# Kept deliberately desaturated — a green *cast* over a grey night, not neon.
# Saturated greens here turn the whole sky into a comic-book filter.
const OTHER_LIGHT_COLOR := Color(0.56, 0.78, 0.58)
const OTHER_SKY := Color(0.005, 0.010, 0.007)
const OTHER_MOON_TINT := Color(0.85, 0.97, 0.86)
const OTHER_CLOUD_LIT := Color(0.33, 0.44, 0.35)
const OTHER_CLOUD_DARK := Color(0.020, 0.032, 0.024)
const OTHER_WORLD_TINT := Color(0.93, 1.0, 0.95)
const OTHER_FOG := Color(0.013, 0.026, 0.018)
const OTHER_AMBIENT := Color(0.045, 0.095, 0.062)
const OTHER_MIST_TINT := Color(0.72, 1.0, 0.78)
## The Otherside sky is visibly more clouded over than the real one.
const OTHER_COVERAGE_BIAS := 0.07

const LIGHTNING_COLOR := Color(0.45, 1.0, 0.55)

@onready var moon: DirectionalLight3D = get_node(moon_light_path)
@onready var world_env: WorldEnvironment = get_node(world_environment_path)

var _sky_mat: ShaderMaterial
var _env: Environment
## Read from the scene rather than hardcoded, so ambient tuning done by hand
## in the editor survives instead of being silently overwritten here.
var _base_ambient_energy := 0.12

## 0 = Real, 1 = Otherside. The single source of truth for the whole palette.
var _transition := 0.0
var _coverage := COVERAGE_MIN
var _flash := 0.0

var _coverage_noise := FastNoiseLite.new()
## Cached from the shader so strikes can be placed where the clouds have drifted.
var _cloud_wind := Vector2(0.008, 0.003)
var _strike_countdown := 0.0
var _strike_elapsed := -1.0

func _ready() -> void:
	_env = world_env.environment
	if _env:
		_base_ambient_energy = _env.ambient_light_energy
		if _env.sky:
			_sky_mat = _env.sky.sky_material as ShaderMaterial
	if _sky_mat:
		var w = _sky_mat.get_shader_parameter("cloud_wind")
		if w != null:
			_cloud_wind = w

	_coverage_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX
	_coverage_noise.frequency = 1.0
	_coverage_noise.seed = 1337

	_strike_countdown = randf_range(STRIKE_GAP_MIN, STRIKE_GAP_MAX)

	WorldState.world_changed.connect(_on_world_changed)
	_transition = 0.0 if WorldState.current_world == WorldState.World.REAL else 1.0

func _process(delta: float) -> void:
	_update_coverage()
	_update_lightning(delta)
	_apply()

## Slow organic drift of how overcast it is. Noise rather than a sine so the
## sky never settles into an obvious repeating rhythm.
func _update_coverage() -> void:
	var t := Time.get_ticks_msec() / 1000.0
	var n := _coverage_noise.get_noise_1d(t * COVERAGE_DRIFT_SPEED) * 0.5 + 0.5
	_coverage = lerpf(COVERAGE_MIN, COVERAGE_MAX, n)

func _update_lightning(delta: float) -> void:
	# Storms only happen on the Otherside; the real world stays quietly clear.
	var storm_active := _transition > 0.35

	if _strike_elapsed >= 0.0:
		_strike_elapsed += delta
		if _strike_elapsed >= STRIKE_DURATION:
			_strike_elapsed = -1.0
			_flash = 0.0
			_strike_countdown = randf_range(STRIKE_GAP_MIN, STRIKE_GAP_MAX)
		else:
			_flash = _strike_envelope(_strike_elapsed / STRIKE_DURATION) * _transition
		return

	_flash = 0.0
	if not storm_active:
		return

	_strike_countdown -= delta
	if _strike_countdown <= 0.0:
		_strike_elapsed = 0.0
		if _sky_mat:
			# New strike somewhere else in the cloud layer each time. Offset by
			# the wind so it lands where the clouds actually are right now, not
			# where they were when the level loaded.
			var drift: Vector2 = _cloud_wind * (Time.get_ticks_msec() / 1000.0)
			_sky_mat.set_shader_parameter("lightning_pos",
				drift + Vector2(randf_range(-3.0, 3.0), randf_range(-3.0, 3.0)))

## Real lightning is not one clean fade — it is a hard stroke followed by a
## couple of weaker after-strokes, which is what the extra bumps here are.
func _strike_envelope(x: float) -> float:
	var main := exp(-x * 7.0)
	var second := 0.6 * exp(-absf(x - 0.16) * 45.0)
	var third := 0.35 * exp(-absf(x - 0.29) * 70.0)
	var flicker := 0.75 + 0.25 * sin(x * 120.0)
	return clampf(main * flicker + second + third, 0.0, 1.0)

func _apply() -> void:
	var t := _transition

	var light_color := REAL_LIGHT_COLOR.lerp(OTHER_LIGHT_COLOR, t)
	var coverage := clampf(_coverage + lerpf(REAL_COVERAGE_BIAS, OTHER_COVERAGE_BIAS, t), 0.0, 1.0)

	# Thicker cloud cover means less moonlight reaching the ground.
	var energy := MOON_ENERGY * lerpf(1.0, 1.0 - COVERAGE_DIM, coverage)
	if _flash > 0.0:
		energy += STRIKE_LIGHT_BOOST * _flash
		light_color = light_color.lerp(LIGHTNING_COLOR, clampf(_flash * 0.8, 0.0, 1.0))

	moon.light_color = light_color
	moon.light_energy = energy * (1.0 - WorldState.darkness)

	# Ground mist volumes pick this up through a global shader parameter, so they
	# shift with the world along with everything else (see fog_patch.gdshader).
	var mist_tint := REAL_MIST_TINT.lerp(OTHER_MIST_TINT, t)
	RenderingServer.global_shader_parameter_set(&"world_fog_tint",
		Vector3(mist_tint.r, mist_tint.g, mist_tint.b))

	if _env:
		_env.fog_light_color = REAL_FOG.lerp(OTHER_FOG, t)
		# Shifts the fill light too, otherwise surfaces facing away from the moon
		# stay stubbornly blue while everything else has gone green.
		_env.ambient_light_color = REAL_AMBIENT.lerp(OTHER_AMBIENT, t)
		_env.ambient_light_energy = _base_ambient_energy * (1.0 - WorldState.darkness)

	if not _sky_mat:
		return
	_sky_mat.set_shader_parameter("sky_color", REAL_SKY.lerp(OTHER_SKY, t))
	_sky_mat.set_shader_parameter("moon_tint", REAL_MOON_TINT.lerp(OTHER_MOON_TINT, t))
	_sky_mat.set_shader_parameter("cloud_lit", REAL_CLOUD_LIT.lerp(OTHER_CLOUD_LIT, t))
	_sky_mat.set_shader_parameter("cloud_dark", REAL_CLOUD_DARK.lerp(OTHER_CLOUD_DARK, t))
	_sky_mat.set_shader_parameter("world_tint", REAL_WORLD_TINT.lerp(OTHER_WORLD_TINT, t))
	_sky_mat.set_shader_parameter("cloud_coverage", coverage)
	_sky_mat.set_shader_parameter("lightning_flash", _flash)
	_sky_mat.set_shader_parameter("lightning_color", LIGHTNING_COLOR)

## Fired mid-blackout (see world_state.gd's _enter_dark) -- snapped, not
## tweened, the same reasoning as orb.gd/world_light.gd: darkness is already
## 1.0 the instant this fires, so the swap is invisible regardless.
func _on_world_changed(new_world) -> void:
	_transition = 0.0 if new_world == WorldState.World.REAL else 1.0
