@tool
extends EditorScript

## Run from the Script editor (File > Run / Ctrl+Shift+X) with
## rooms/scn/hall/second_floor.scn open.
##
## The marble pedestal table's own local scale is a clean uniform 16.855 --
## not the problem. It's nested under "window_main_second_floor", which
## itself carries a non-uniform stretch (fitting a window frame), and the
## table inherits that distortion on top of its own scale, landing on the
## (16.855, 25.535, 22.754)-type numbers Jolt complains about. Repeated
## attempts to compensate the table's own CollisionShape3D children kept
## going stale because the source of the non-uniformity (the parent) never
## changed -- fixing the shapes without removing the inherited stretch
## just chases a moving target forever.
##
## Fix: re-parent the table out from under the stretched window frame onto
## a plain, unscaled node (its grandparent, "decor"), using
## global_transform to preserve exactly where it currently sits. Once its
## only scale is its own uniform 16.855, Jolt has nothing to complain
## about and none of its CollisionShape3D children need any compensation
## at all -- reset them back to identity scale for the same reason.

const TABLE_PATH := "hall/second_floor/decor/window_main_second_floor/marble pedestal table 3d model"
const NEW_PARENT_PATH := "hall/second_floor/decor"

func _run() -> void:
	var root := get_editor_interface().get_edited_scene_root()
	if root == null:
		print("FIXPEDESTAL: no scene is open -- open rooms/scn/hall/second_floor.scn first.")
		return

	var table := root.get_node_or_null(TABLE_PATH) as Node3D
	var new_parent := root.get_node_or_null(NEW_PARENT_PATH) as Node3D
	if table == null or new_parent == null:
		print("FIXPEDESTAL: could not find the table or its target parent -- paths may have changed.")
		print("  table found: ", table != null, "  new_parent found: ", new_parent != null)
		return

	var old_parent_scale := (table.get_parent() as Node3D).global_transform.basis.get_scale()
	var xform := table.global_transform

	table.get_parent().remove_child(table)
	new_parent.add_child(table)
	table.owner = root
	table.global_transform = xform

	# The inherited stretch is gone now, so any earlier compensation baked
	# into the collision shapes is not just unneeded, it's actively wrong.
	var reset_count := 0
	for child in table.get_children():
		if child is CollisionShape3D:
			(child as CollisionShape3D).scale = Vector3.ONE
			reset_count += 1

	print("FIXPEDESTAL: re-parented table from a %.3f/%.3f/%.3f-stretched parent onto '%s' (visual position unchanged), reset %d collision shape(s) to identity scale. Save with Ctrl+S." % [
		old_parent_scale.x, old_parent_scale.y, old_parent_scale.z, NEW_PARENT_PATH, reset_count])
