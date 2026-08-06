extends Node

## Drives the whole world-switch as a three-act sequence, and every other
## system reads its timing from here rather than running its own private
## tween: the world's light is dragged into the orb (INHALE), everything
## goes black for a beat (DARK), then the new colour bursts back out of it
## (EXHALE).
##
## The colour swap happens at the INHALE->DARK boundary, i.e. while the
## screen is black -- that is the whole point of the dark beat. Crossfading
## colours in the light, the way this used to, meant the world had visibly
## finished changing colour before anything dramatic happened to it, which
## read as an unmotivated flash rather than a transformation.

enum World { REAL, OTHERSIDE }
enum Phase { IDLE, INHALE, DARK, EXHALE }

## Fired at the moment the world actually flips -- mid-DARK, unseen.
signal world_changed(new_world: World)
signal transition_started(to_world: World)
signal transition_finished()

## Per-phase, so the pacing can be retuned without touching anything else.
## Inhale is the longest on purpose: the pull needs time to read as the
## world being dragged somewhere, while the burst is meant to feel sudden.
const INHALE_TIME := 1.35
const DARK_TIME := 0.35
const EXHALE_TIME := 1.1
const TOTAL_TIME := INHALE_TIME + DARK_TIME + EXHALE_TIME

var current_world: World = World.REAL
var phase: Phase = Phase.IDLE

## 0 = normally lit, 1 = fully swallowed. Every light in the game scales
## its energy by (1 - darkness), which is what makes the world actually go
## dark rather than just being covered by a black rectangle.
var darkness := 0.0
## Signed spatial distortion: >0 drags space inward toward the orb,
## <0 throws it back out. Read by world_transition.gdshader.
var swirl := 0.0
## Brief white-hot flash at the instant the orb lets go.
var burst := 0.0

var _phase_t := 0.0
var _pending_world: World = World.REAL

func is_locked() -> bool:
	return phase != Phase.IDLE

func switch_to(world: World) -> void:
	if world == current_world or is_locked():
		return
	_pending_world = world
	phase = Phase.INHALE
	_phase_t = 0.0
	transition_started.emit(world)

func toggle() -> void:
	switch_to(World.OTHERSIDE if current_world == World.REAL else World.REAL)

func _process(delta: float) -> void:
	if phase == Phase.IDLE:
		return

	_phase_t += delta

	match phase:
		Phase.INHALE:
			var t := clampf(_phase_t / INHALE_TIME, 0.0, 1.0)
			# Accelerating rather than linear: the world resists at first,
			# then goes all at once, like something losing its grip.
			var eased := t * t * t
			darkness = eased
			swirl = eased
			burst = 0.0
			if _phase_t >= INHALE_TIME:
				_enter_dark()

		Phase.DARK:
			darkness = 1.0
			swirl = 1.0
			burst = 0.0
			if _phase_t >= DARK_TIME:
				phase = Phase.EXHALE
				_phase_t = 0.0

		Phase.EXHALE:
			var t := clampf(_phase_t / EXHALE_TIME, 0.0, 1.0)
			# Mirror of the inhale curve: violent at the start, settling.
			var eased := 1.0 - pow(1.0 - t, 3.0)
			darkness = 1.0 - eased
			# Negative = space is thrown outward instead of pulled in.
			swirl = -(1.0 - eased)
			# Sharp spike right at the release, gone almost immediately.
			burst = pow(1.0 - t, 6.0)
			if _phase_t >= EXHALE_TIME:
				_finish()

func _enter_dark() -> void:
	phase = Phase.DARK
	_phase_t = 0.0
	darkness = 1.0
	swirl = 1.0
	# The actual flip, hidden inside the blackout.
	current_world = _pending_world
	world_changed.emit(current_world)

func _finish() -> void:
	phase = Phase.IDLE
	_phase_t = 0.0
	darkness = 0.0
	swirl = 0.0
	burst = 0.0
	transition_finished.emit()
