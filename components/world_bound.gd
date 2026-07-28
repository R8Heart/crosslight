class_name WorldBound
extends Node

## Attach as a child of a world-layer container (e.g. "RealWorld"/"Otherside").
## Shows/hides the parent and enables/disables all collision shapes beneath it
## whenever the active world matches this component's "world" value.
@export_enum("Real", "Otherside") var world: int = 0

var _target: Node3D

func _ready() -> void:
	_target = get_parent()
	WorldState.world_changed.connect(_on_world_changed)
	_apply(WorldState.current_world)

func _on_world_changed(new_world) -> void:
	_apply(new_world)

func _apply(active_world) -> void:
	var is_active: bool = active_world == world
	_target.visible = is_active
	_set_collisions_disabled(_target, not is_active)

func _set_collisions_disabled(node: Node, disabled: bool) -> void:
	for child in node.get_children():
		if child is CollisionShape3D or child is CollisionPolygon3D:
			child.disabled = disabled
		_set_collisions_disabled(child, disabled)
