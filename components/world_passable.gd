class_name WorldPassable
extends Node3D

## Organizer node, not a modifier on its parent: whatever CollisionShape3D
## / CollisionPolygon3D live *underneath this node* (direct children or
## nested deeper inside it) turn ghostly in one world -- nothing outside
## this subtree is touched. Move exactly the shapes that should react
## under here, so this can sit right next to unrelated collision (other
## parts of the same mesh, a shared parent) without dragging it along.
## This never touches visibility either, only whether the collision is
## solid -- a window you can still see but walk through in the Otherside
## is the same geometry throughout, it just stops being physically there.
##
## Declared Node3D (not the plainer Node) specifically so global_position
## is available -- this is usually attached directly to a StaticBody3D
## stub (Node3D is still a valid ancestor type for that, so the script
## attaches fine).
##
## Default (Real) matches the common case: solid in the everyday world,
## walk-through in the Otherside.
@export_enum("Real", "Otherside") var solid_in: int = 0

func _ready() -> void:
	add_to_group(&"world_passable")
	WorldState.world_changed.connect(_on_world_changed)
	_apply(WorldState.current_world)

func is_currently_passable() -> bool:
	return WorldState.current_world != solid_in

## Average position of the actual collision shapes underneath this node --
## deliberately *not* just global_position. This is usually a StaticBody3D
## stub whose own origin is wherever it happened to land when placed (the
## base of a window frame, say), while the shapes moved under it for the
## ghosting effect can sit well above that. orb.gd aims its proximity
## reaction at this, so it destabilises where the passable volume actually
## is, not at the stub's local zero.
##
## Cached after the first call: orb.gd asks this every frame (not just on
## its own throttled search), and the collision layout under here is
## static level geometry that never moves at runtime, so re-walking the
## subtree 60 times a second was pure waste -- the exact same shape of bug
## as the ZoneManager one earlier today, just in a new script.
var _effect_center: Vector3
var _effect_center_valid := false

func get_effect_center() -> Vector3:
	if not _effect_center_valid:
		_effect_center = _compute_effect_center()
		_effect_center_valid = true
	return _effect_center

func _compute_effect_center() -> Vector3:
	var points: Array[Vector3] = []
	_collect_collision_positions(self, points)
	if points.is_empty():
		return global_position
	var sum := Vector3.ZERO
	for p in points:
		sum += p
	return sum / points.size()

func _collect_collision_positions(node: Node, out: Array[Vector3]) -> void:
	for child in node.get_children():
		if child is CollisionShape3D or child is CollisionPolygon3D:
			out.append((child as Node3D).global_position)
		_collect_collision_positions(child, out)

func _on_world_changed(new_world) -> void:
	_apply(new_world)

func _apply(active_world) -> void:
	var solid: bool = active_world == solid_in
	_set_collisions_disabled(self, not solid)

func _set_collisions_disabled(node: Node, disabled: bool) -> void:
	for child in node.get_children():
		if child is CollisionShape3D or child is CollisionPolygon3D:
			child.disabled = disabled
		_set_collisions_disabled(child, disabled)
