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

## Fired the instant the leaf starts swinging open (not when it finishes) --
## a draft catching a door disturbs things immediately, not a second later.
signal opened

@export var open_angle_deg: float = 100.0
@export var duration: float = 1.1
## Other leaf(s) of the same doorway -- interacting with this leaf also
## opens/closes these, so either half of a double door works as one switch.
## Only needs to be set on one side; wiring both is fine too (it can't loop,
## since the linked leaf is moved directly, not via its own interact()).
@export var linked_doors: Array[NodePath] = []

var _is_open := false
var _tween: Tween

func interact(_player) -> void:
	_set_state(not _is_open)
	for path in linked_doors:
		var other := get_node_or_null(path) as SwingDoor
		if other:
			other._set_state(_is_open)

func _set_state(open: bool) -> void:
	_is_open = open
	var target := open_angle_deg if _is_open else 0.0
	if _tween and _tween.is_valid():
		_tween.kill()
	_tween = create_tween()
	_tween.tween_property(self, "rotation_degrees:y", target, duration) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	if _is_open:
		opened.emit()
