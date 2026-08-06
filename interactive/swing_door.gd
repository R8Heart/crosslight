extends AnimatableBody3D
class_name SwingDoor

## One hinged leaf of a double door. The node's own origin *is* the hinge —
## it sits at the edge the door pivots around, with the visual mesh and its
## collision box offset toward the free-swinging side as children. Rotating
## this node (not the mesh) is what swings the door.
##
## The sign of `open_angle_deg` is what decides which way it opens, not
## which physical edge the hinge sits on — a left-hinged and a right-hinged
## leaf swinging inward to meet each other need opposite signs even though
## both "open" toward the same side of the doorway.

@export var open_angle_deg: float = 100.0
@export var duration: float = 1.1

var _is_open := false
var _tween: Tween

func interact(_player) -> void:
	_is_open = not _is_open
	var target := open_angle_deg if _is_open else 0.0
	if _tween and _tween.is_valid():
		_tween.kill()
	_tween = create_tween()
	_tween.tween_property(self, "rotation_degrees:y", target, duration) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
