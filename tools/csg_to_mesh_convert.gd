@tool
extends EditorScript

## Converts a finished room's CSG geometry into plain meshes for good:
## bakes each CSG root into a MeshInstance3D, rebuilds its collision as a
## StaticBody3D + CollisionShape3D underneath, then DELETES the CSG node.
##
## Why not just hide the CSG (what tools/bake_csg_to_mesh.gd did): a hidden
## CSGShape3D is still a live CSG node -- it keeps its generated mesh and
## collision in memory and stays in the scene file. Deleting it is what
## actually removes CSG from the room. MeshInstance3D can't carry collision
## by itself, hence the StaticBody3D wrapper; the shape comes from the CSG's
## own bake_collision_shape(), so it matches the geometry exactly rather
## than being re-approximated by hand.
##
## ⚠ THIS ONE IS DESTRUCTIVE -- the CSG nodes are gone afterwards and the
## room can no longer be edited as CSG. Commit (or copy the .tscn) before
## running it on a room, and only run it on rooms whose layout is finished.
## Everything else about the room -- decor, lights, doors, windows -- is
## untouched.
##
## Usage:
##   1. Open the room scene (e.g. music_room.tscn), make it the active tab.
##   2. DRY_RUN = true, File > Run, read the report.
##   3. DRY_RUN = false, run again, then save the scene with Ctrl+S.

const DRY_RUN := true

## The whole scene is scanned by default -- CSG doesn't always live under a
## tidy "walls"/"floors" branch (the lawns keep theirs at the scene root,
## the kitchen's sits in "decor"), and missing those silently was worse than
## the risk of catching too much. Name a branch here to protect it, e.g.
## ["decor"] to leave hand-built decorative CSG alone in a given room.
const SKIP_BRANCHES: Array[String] = []

## Leftovers from the earlier hide-don't-delete script. Found next to a CSG
## node, they're deleted and regenerated properly rather than left as
## duplicates.
const OLD_BAKED_SUFFIX := "_Baked"

func _run() -> void:
	var root := EditorInterface.get_edited_scene_root()
	if root == null:
		push_error("CSG CONVERT: no scene open in the editor.")
		return

	var targets: Array[CSGShape3D] = []
	for child in root.get_children():
		if String(child.name) in SKIP_BRANCHES:
			print("CSG CONVERT: skipping protected branch '%s'." % child.name)
			continue
		_collect(child, targets)
	# CSG sitting directly at the scene root (the lawns and path do this)
	# would be missed by the loop above, which only walks children.
	if root is CSGShape3D and not (root.get_parent() is CSGShape3D):
		targets.append(root)

	if targets.is_empty():
		print("CSG CONVERT: nothing to convert in '%s'." % root.name)
		return

	print("CSG CONVERT: %d CSG root shape(s) in '%s'%s" % [
		targets.size(), root.name, "  [DRY RUN -- nothing will change]" if DRY_RUN else ""])

	var converted := 0
	var with_collision := 0
	var failed := 0

	for shape in targets:
		var parent := shape.get_parent()
		if parent == null:
			continue

		if DRY_RUN:
			print("  would convert: %s%s" % [
				root.get_path_to(shape),
				"  (+collision)" if shape.use_collision else ""])
			converted += 1
			continue

		var raw := shape.bake_static_mesh()
		if raw == null:
			print("  FAILED (no mesh): %s" % root.get_path_to(shape))
			failed += 1
			continue

		var col_shape: Shape3D = null
		if shape.use_collision:
			col_shape = shape.bake_collision_shape()

		# Capture everything needed before the node goes away.
		var node_name := shape.name
		var node_xform := shape.transform
		var node_index := shape.get_index()
		var layer := shape.collision_layer
		var mask := shape.collision_mask

		# Drop a stale sibling from the older hide-only script, if present.
		var stale := parent.get_node_or_null(String(node_name) + OLD_BAKED_SUFFIX)
		if stale:
			parent.remove_child(stale)
			stale.queue_free()

		# Anything hanging off this CSG node that ISN'T part of the boolean
		# operation has to survive: window models, decor and their collision
		# shapes get parented to walls all over this project, and freeing
		# the CSG node would silently take them with it. (It did -- four
		# arched windows on the second floor vanished this way.) Only the
		# CSG operands themselves are meant to disappear, since the baked
		# mesh already contains their effect.
		var rescued: Array[Node] = []
		for child in shape.get_children():
			if child is CSGShape3D:
				continue
			rescued.append(child)
		for child in rescued:
			shape.remove_child(child)

		# Free the CSG first so the new node can take its exact name.
		parent.remove_child(shape)
		shape.queue_free()

		var mi := MeshInstance3D.new()
		mi.mesh = _to_indexed(raw)
		parent.add_child(mi)
		mi.name = node_name
		mi.owner = root
		mi.transform = node_xform
		parent.move_child(mi, mini(node_index, parent.get_child_count() - 1))

		# Re-home the rescued children under the mesh that replaced their
		# old parent. Same name, same transform, so their local positions
		# still mean what they meant before.
		for child in rescued:
			mi.add_child(child)
			_reassign_owner(child, root)
		if not rescued.is_empty():
			print("    kept %d non-CSG child node(s)" % rescued.size())

		if col_shape != null:
			var body := StaticBody3D.new()
			mi.add_child(body)
			body.name = "StaticBody3D"
			body.owner = root
			body.collision_layer = layer
			body.collision_mask = mask

			var cs := CollisionShape3D.new()
			body.add_child(cs)
			cs.name = "CollisionShape3D"
			cs.owner = root
			cs.shape = col_shape
			with_collision += 1

		converted += 1
		print("  converted: %s%s" % [node_name, "  (+collision)" if col_shape else ""])

	if DRY_RUN:
		print("CSG CONVERT: dry run done -- %d would be converted." % converted)
		print("             Set DRY_RUN = false and run again to actually do it.")
	else:
		print("CSG CONVERT: converted %d (%d with collision), failed %d. Save with Ctrl+S." % [
			converted, with_collision, failed])

## Re-parenting clears a node's owner, and a node with no owner is simply
## dropped when the scene is saved. Instanced sub-scenes are the exception:
## their internals must keep pointing at the instance, so only the node
## itself is re-owned there, not everything underneath it.
func _reassign_owner(node: Node, root: Node) -> void:
	node.owner = root
	if node.scene_file_path != "":
		return
	for child in node.get_children():
		_reassign_owner(child, root)

## OccluderInstance3D's bake ignores meshes with no index array, which is
## what bake_static_mesh() returns. Re-indexing here keeps the door open for
## occlusion work later without having to redo the conversion.
func _to_indexed(mesh: ArrayMesh) -> ArrayMesh:
	var out := ArrayMesh.new()
	for i in mesh.get_surface_count():
		var st := SurfaceTool.new()
		st.create_from(mesh, i)
		st.index()
		var committed := st.commit()
		if committed == null or committed.get_surface_count() == 0:
			continue
		out.add_surface_from_arrays(
			Mesh.PRIMITIVE_TRIANGLES, committed.surface_get_arrays(0))
		out.surface_set_material(out.get_surface_count() - 1, mesh.surface_get_material(i))
	return out if out.get_surface_count() > 0 else mesh

## A CSG node nested inside another one is an operand of that parent's
## boolean operation (the doorway being subtracted, say). Only the outermost
## shape is baked -- its result already includes what the children did.
##
## Nodes belonging to an instanced sub-scene are skipped: their owner is the
## instance, not this scene, so converting them here would write a pile of
## overrides into the wrong file instead of editing the room itself. That
## matters if this is ever run with estate_exterior open, which instances
## every room -- convert rooms one at a time, in their own scene.
func _collect(node: Node, out: Array[CSGShape3D]) -> void:
	var scene_root := EditorInterface.get_edited_scene_root()
	if node.owner != scene_root:
		return
	if node is CSGShape3D:
		if not (node.get_parent() is CSGShape3D):
			out.append(node)
		return
	for child in node.get_children():
		_collect(child, out)
