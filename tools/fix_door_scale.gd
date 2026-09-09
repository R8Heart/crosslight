@tool
extends EditorScript

## Run from the Script editor (File > Run / Ctrl+Shift+X). Select the
## "doors" container (or any ancestor of one or more SwingDoor nodes) in
## the Scene dock first -- this only touches the current selection, same
## safety convention as tools/fix_nonuniform_collision.gd.
##
## The recurring door-stretching/shrinking bug traces back to scene data,
## not physics: a "doors" container gets non-uniformly scaled by hand to
## fit a doorway (e.g. (1.27, 1.825, 0.5)) instead of the door mesh itself,
## and the SwingDoor leaves under it often carry their own small leftover
## non-uniform scale too (e.g. (1.03, 1.005, 1), usually copied from an
## earlier door). AnimatableBody3D + Jolt does not tolerate a non-uniform
## scale sitting on the body's own transform chain -- swing_door.gd's
## per-frame rotation_degrees writes during the open/close Tween round-trip
## through the physics server, and each round-trip has a chance to bake in
## a little more error, compounding with every toggle.
##
## Fix: push every non-uniform scale as far down the tree as it will go,
## preserving each node's global_transform exactly (so nothing visually
## moves or resizes) -- first flattening the container's own scale into its
## immediate children, then flattening each SwingDoor's own scale into
## *its* children (the door mesh, its OccluderInstance3D, and its
## CollisionShape3D). What's left: the container and every SwingDoor body
## sit at a clean uniform (1,1,1), and the doorway's actual sizing lives
## entirely in leaf mesh/shape nodes, where non-uniform scale is harmless.
##
## DRY_RUN defaults to true -- prints what it would flatten without
## touching anything. Read the list, then set this to false and run again.
const DRY_RUN := false

func _run() -> void:
	var selected := get_editor_interface().get_selection().get_selected_nodes()
	if selected.is_empty():
		print("FIXDOORSCALE: nothing selected. Select the 'doors' container (or a SwingDoor's ancestor) in the Scene dock first.")
		return

	var flattened := 0
	for root in selected:
		flattened += _flatten_if_needed(root as Node3D, "container")
		var stack: Array[Node] = [root]
		while not stack.is_empty():
			var node: Node = stack.pop_back()
			for child in node.get_children():
				stack.push_back(child)
			if node is SwingDoor:
				flattened += _flatten_if_needed(node as Node3D, "door")

	if DRY_RUN:
		print("FIXDOORSCALE (DRY RUN, nothing applied): would flatten %d node(s). Set DRY_RUN = false to actually apply." % flattened)
	else:
		print("FIXDOORSCALE: flattened %d node(s) to uniform scale. Save with Ctrl+S." % flattened)

## If `node`'s own local scale isn't uniform (1,1,1), zero it and push the
## difference into each child instead, keeping every child's global
## transform bit-for-bit identical -- Node3D.global_transform's setter does
## the actual re-derivation of the child's new local transform for us.
func _flatten_if_needed(node: Node3D, label: String) -> int:
	if node == null:
		return 0
	var s := node.scale
	if is_equal_approx(s.x, 1.0) and is_equal_approx(s.y, 1.0) and is_equal_approx(s.z, 1.0):
		return 0

	var path := str(node.get_path())
	print("  %s '%s' has scale %s -- %s" % [label, path, s, "would flatten onto children" if DRY_RUN else "flattening onto children"])
	if DRY_RUN:
		return 1

	var children_xforms: Dictionary = {}
	for child in node.get_children():
		if child is Node3D:
			children_xforms[child] = (child as Node3D).global_transform

	node.scale = Vector3.ONE

	for child in children_xforms:
		(child as Node3D).global_transform = children_xforms[child]

	return 1
