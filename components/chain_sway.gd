extends Node
class_name ChainSway

## Drives a natural-looking chain-reaction sway across a chain of nested
## pivots (see tools/rig_chandelier_chain.gd) whenever one of `door_paths`
## opens -- a draft catching the door disturbs the chandelier, which swings
## and settles back to rest on its own. Re-triggers every time a watched
## door opens again.
##
## Deliberately not a real coupled-pendulum simulation (that needs solving
## per-link equations of motion). Instead every pivot plays the same
## decaying sine wave, just started a little later and a little bigger than
## the pivot above it -- cheap, stable, and reads as "the disturbance
## travels down the chain and the heavy end swings the most" without any
## risk of the simulation blowing up or drifting.

@export var pivots: Array[NodePath] = []
@export var door_paths: Array[NodePath] = []

## How long the wave takes to reach each successive link, in seconds.
## Small on purpose -- these are short, stiff chain links, not a slack rope.
@export var delay_per_link: float = 0.05
## Radians of swing at the topmost pivot.
@export var base_amplitude: float = 0.035
## Extra amplitude fraction added per link going down the chain -- the
## chandelier body (the heaviest, last "link") ends up swinging the most.
@export var amplitude_growth: float = 0.35
@export var frequency: float = 3.2
@export var damping: float = 1.1

var _pivot_nodes: Array[Node3D] = []
var _time_since_kick := -1.0
var _axis := Vector2.RIGHT

func _ready() -> void:
	for p in pivots:
		var n := get_node_or_null(p)
		if n is Node3D:
			_pivot_nodes.append(n)
		else:
			push_warning("ChainSway: pivot path did not resolve to a Node3D: %s" % p)

	for dp in door_paths:
		var door := get_node_or_null(dp)
		if door and door.has_signal("opened"):
			door.opened.connect(kick)
		else:
			push_warning("ChainSway: door path missing or has no 'opened' signal: %s" % dp)

	print("ChainSway ready: %d/%d pivots resolved, connected to %d door(s)." % [
		_pivot_nodes.size(), pivots.size(), door_paths.size()])
	set_process(false)

## Call directly for a scripted gust (e.g. a broken window, a spell) --
## doors are wired automatically via door_paths.
func kick() -> void:
	# A double door's two leaves both fire 'opened' for the same gust --
	# ignore the second one instead of restarting the wave mid-swing.
	if _time_since_kick >= 0.0 and _time_since_kick < 0.05:
		return
	print("ChainSway: kicked.")
	_time_since_kick = 0.0
	_axis = Vector2(randf_range(-1.0, 1.0), randf_range(-1.0, 1.0)).normalized()
	set_process(true)

func _process(delta: float) -> void:
	_time_since_kick += delta

	var last_index := _pivot_nodes.size() - 1
	var still_moving := false

	for i in _pivot_nodes.size():
		var t := _time_since_kick - i * delay_per_link
		if t < 0.0:
			still_moving = true
			continue

		var envelope := exp(-damping * t) * sin(frequency * t)
		if absf(envelope) > 0.001 or i < last_index:
			still_moving = true

		var amount := base_amplitude * (1.0 + amplitude_growth * i) * envelope
		var pivot := _pivot_nodes[i]
		pivot.rotation.x = _axis.x * amount
		pivot.rotation.z = _axis.y * amount

	if not still_moving:
		_time_since_kick = -1.0
		set_process(false)
