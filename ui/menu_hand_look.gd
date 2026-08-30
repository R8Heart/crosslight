extends Node3D
class_name MenuHandLook

## Makes the hand+lantern rig glance toward the mouse cursor -- attach this
## to the node that plays the role player.tscn's Head/Camera3D/ViewmodelPivot
## plays in-game (call it HandAnchor). LanternRig and Orb (player/lantern_rig.gd,
## player/orb.gd) are copied under it completely unchanged: LanternRig reacts
## to its parent's world orientation, not to raw mouse input, so it can't
## tell this isn't the real player.
##
## Chosen node structure (build this in the menu's .tscn):
##   HandAnchor  (this script)
##     HandModel        <- res://assets/hand/fist.glb
##       LanternRig      <- player/lantern_rig.gd, same install pose as player.tscn
##         LanternVisual  <- res://assets/hand/lantern.glb
##           Orb           <- player/orb.gd, + Glass + OrbLight, same as player.tscn
##
## Unlike the in-game look (relative mouse-delta, cursor captured), a menu
## leaves the cursor free to click buttons, so this reads the cursor's
## absolute position instead and clamps the glance to a small cone around
## whatever rest pose HandAnchor is placed at in the editor -- it's meant to
## hold roughly one pose (reaching toward the camera, slightly toward the
## menu list) and just glance within it, not free-look like a camera.

const LOOK_SMOOTH := 15.0

## How far the hand can glance from its rest pose, in radians. Keep small --
## a subtle reactive glance, not a look-around camera.
@export var yaw_range := 0.18
@export var pitch_range := 0.12

## Idle life while the cursor sits still, matching the feel of player.gd's
## IDLE_SWAY_AMOUNT/SPEED so the hand doesn't look frozen between moves.
const IDLE_ROT_AMOUNT := 0.02
const IDLE_ROT_SPEED := 0.4
const IDLE_POS_AMOUNT := Vector3(0.01, 0.006, 0.0)
const IDLE_POS_SPEED := 0.5

var _rest_rotation: Vector3
var _rest_position: Vector3
var _target_yaw := 0.0
var _target_pitch := 0.0
var _yaw := 0.0
var _pitch := 0.0

func _ready() -> void:
	_rest_rotation = rotation
	_rest_position = position

func _process(delta: float) -> void:
	# Polled directly instead of read from _unhandled_input: that only fires
	# for input events the GUI layer didn't already consume, so the moment
	# the cursor sat over any interactive Control (a slider, a checkbox --
	# anything with the default mouse_filter of STOP) the hand would freeze
	# on its last target and then jump the moment the cursor cleared it.
	# Polling the viewport's own mouse position every frame doesn't care
	# what's under the cursor.
	var vp_size := get_viewport().get_visible_rect().size
	if vp_size.x > 0.0 and vp_size.y > 0.0:
		var mouse_pos := get_viewport().get_mouse_position()
		var centered: Vector2 = (mouse_pos / vp_size) * 2.0 - Vector2.ONE
		_target_yaw = centered.x * yaw_range
		_target_pitch = -centered.y * pitch_range

	var t := clampf(delta * LOOK_SMOOTH, 0.0, 1.0)
	_yaw = lerp_angle(_yaw, _target_yaw, t)
	_pitch = lerp_angle(_pitch, _target_pitch, t)

	var time := Time.get_ticks_msec() / 1000.0
	var idle_rot := sin(time * IDLE_ROT_SPEED) * IDLE_ROT_AMOUNT
	rotation = _rest_rotation + Vector3(_pitch, _yaw + idle_rot, 0.0)

	position = _rest_position + Vector3(
		sin(time * IDLE_POS_SPEED) * IDLE_POS_AMOUNT.x,
		sin(time * IDLE_POS_SPEED * 0.6) * IDLE_POS_AMOUNT.y,
		0.0
	)
