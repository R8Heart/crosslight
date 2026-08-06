extends Node3D
class_name LanternRig

## The lantern hangs from the grip point, so it doesn't track the hand's
## rotation directly — it has real weight. A torque spring continuously
## pulls it toward hanging at true world-down, integrated into an actual
## angular velocity (so fast camera movement makes it swing and overshoot
## instead of snapping to the new angle), damped so it settles instead of
## oscillating forever. The fist's "slack" (slide) works the same way, as a
## linear spring toward the hand's own bob offset.
##
## Whatever rest position/rotation this node has when the scene starts is
## treated as the reference install pose, not overwritten with an assumed
## identity — hand-tuning the socket's rotation in the editor to fit a
## specific hand mesh has to actually stick, not get reset every frame.

@export var swing_spring := 90.0
@export var swing_damping := 10.0
## Hard ceiling on how far the hang direction may drift from the installed
## rest orientation, in degrees — the actual guarantee that the lantern
## can't swing far enough to intersect the fist, geometric rather than
## collision-based so it can't jitter or tunnel through at high speed.
@export var max_swing_deg := 38.0

@export var slide_spring := 260.0
@export var slide_damping := 18.0
## Metres of play inside the fist "tunnel" — the bail can slide this far
## before the fist itself stops it.
@export var slide_limit := 0.012

var _install_basis := Basis.IDENTITY
var _base_local_pos := Vector3.ZERO

var _ang_vel := Vector3.ZERO
var _lin_vel := Vector3.ZERO

var _viewmodel_pivot: Node3D

func _ready() -> void:
	_install_basis = basis.orthonormalized()
	_base_local_pos = position
	# LanternRig -> HandModel -> ViewmodelPivot: the same bob signal the orb
	# used to read directly, now one hop further up since the lantern sits
	# between the hand and the orb.
	_viewmodel_pivot = get_parent().get_parent()

func _process(delta: float) -> void:
	_update_swing(delta)
	_update_slide(delta)

func _local_down_target() -> Vector3:
	var parent3d := get_parent() as Node3D
	if not parent3d:
		return Vector3.DOWN
	return (parent3d.global_transform.basis.inverse() * Vector3.DOWN).normalized()

## Torque spring: the further the current hang direction is from true
## gravity-down, the harder it's pulled back. Integrated into a real
## angular velocity (not just re-aimed every frame), so a sudden camera
## whip makes it swing past and settle, instead of teleporting to the new
## angle.
func _update_swing(delta: float) -> void:
	var target := _local_down_target()
	var current := (basis * Vector3.DOWN).normalized()

	var axis := current.cross(target)
	var angle := current.angle_to(target)
	if axis.length() > 0.0001 and angle > 0.0001:
		_ang_vel += axis.normalized() * angle * swing_spring * delta
	_ang_vel *= clampf(1.0 - swing_damping * delta, 0.0, 1.0)

	var spin := _ang_vel.length()
	if spin > 0.0001:
		basis = Basis(_ang_vel.normalized(), spin * delta) * basis
	basis = basis.orthonormalized()

	_clamp_swing()

## Keeps the swing within max_swing_deg of the INSTALLED rest orientation
## (not world identity), so the clamp still means "can't swing into the
## fist" no matter how this node's rest pose was rotated in the editor to
## fit a given hand mesh.
func _clamp_swing() -> void:
	var install_down := (_install_basis * Vector3.DOWN).normalized()
	var current_down := (basis * Vector3.DOWN).normalized()
	var off_angle := install_down.angle_to(current_down)
	var max_rad := deg_to_rad(max_swing_deg)
	if off_angle <= max_rad:
		return
	var clamp_axis := install_down.cross(current_down)
	if clamp_axis.length() < 0.0001:
		return
	var clamped_down := install_down.rotated(clamp_axis.normalized(), max_rad)
	var fix_axis := current_down.cross(clamped_down)
	if fix_axis.length() > 0.0001:
		basis = Basis(fix_axis.normalized(), current_down.angle_to(clamped_down)) * basis
	_ang_vel = Vector3.ZERO

## Same spring-toward-target idea as the swing, applied to position: the
## bail slides a little inside the loosely-closed fist, springing toward
## the hand's current bob offset with its own mass instead of just copying
## it, then clamped to the physical slack the fist allows.
func _update_slide(delta: float) -> void:
	if not _viewmodel_pivot:
		return
	var target_offset: Vector3 = _viewmodel_pivot.position
	var current_offset := position - _base_local_pos

	var error := target_offset - current_offset
	_lin_vel += error * slide_spring * delta
	_lin_vel *= clampf(1.0 - slide_damping * delta, 0.0, 1.0)
	current_offset += _lin_vel * delta

	if current_offset.length() > slide_limit:
		var normal := current_offset.normalized()
		current_offset = normal * slide_limit
		_lin_vel = _lin_vel.slide(normal)

	position = _base_local_pos + current_offset
