@tool
extends EditorScript

## Batch version of the editor's own CSG > "Bake Mesh Instance" (Запечь
## экземпляр сетки), for rooms that are finished being laid out.
##
## Why bother: CSG geometry can't be batched into fewer draw calls, never
## gets automatic mesh LOD, and -- the reason this exists -- is ignored by
## OccluderInstance3D's bake, so the walls that actually block the view
## contribute nothing to occlusion culling while they stay CSG.
##
## Mirrors what the editor button does, node for node: bake the shape to an
## ArrayMesh, add a MeshInstance3D sibling carrying the same transform, and
## leave the original alone apart from hiding it. Nothing is deleted, so
## undoing this by hand is just "delete the *_Baked nodes, unhide the CSG".
## Collision is unaffected either way -- a hidden CSGShape3D with
## use_collision on still collides, so the baked mesh needs no collision of
## its own.
##
## Usage:
##   1. Open the room scene you want to convert (e.g. music_room.tscn).
##   2. Set DRY_RUN below to true, run this (File > Run), read the report.
##   3. Set DRY_RUN to false, run again, then save the scene with Ctrl+S.

## Report only, change nothing. Start here.
const DRY_RUN := false

## Only CSG nodes underneath these branches are touched, so a stray CSG
## helper elsewhere in the scene can't be swept up by accident. Empty array
## means "the whole scene".
const ONLY_BRANCHES: Array[String] = ["floors", "walls", "ceiling"]

const BAKED_SUFFIX := "_Baked"

func _run() -> void:
	var root := get_scene()
	if root == null:
		push_error("CSG BAKE: no scene open in the editor.")
		return

	var targets: Array[CSGShape3D] = []
	if ONLY_BRANCHES.is_empty():
		_collect(root, targets)
	else:
		for branch_name in ONLY_BRANCHES:
			var branch := root.get_node_or_null(branch_name)
			if branch == null:
				print("CSG BAKE: no branch '%s' in this scene, skipping it." % branch_name)
				continue
			_collect(branch, targets)

	if targets.is_empty():
		print("CSG BAKE: found nothing to bake.")
		return

	print("CSG BAKE: %d CSG root shape(s) to bake in '%s'%s" % [
		targets.size(), root.name, "  [DRY RUN -- nothing will change]" if DRY_RUN else ""])

	var baked := 0
	var skipped := 0
	var failed := 0
	var reindexed := 0
	var owner_node := root

	for shape in targets:
		var parent := shape.get_parent()
		if parent == null:
			continue
		# Already baked on an earlier run: don't duplicate it, but do bring
		# its mesh up to date with the indexing fix below, since the first
		# version of this script produced un-indexed meshes that the
		# occluder baker silently ignores.
		var existing := parent.get_node_or_null(shape.name + BAKED_SUFFIX) as MeshInstance3D
		if existing != null:
			if not DRY_RUN and existing.mesh is ArrayMesh:
				existing.mesh = _to_indexed(existing.mesh)
				reindexed += 1
			else:
				skipped += 1
			continue

		if DRY_RUN:
			print("  would bake: %s" % root.get_path_to(shape))
			baked += 1
			continue

		var raw := shape.bake_static_mesh()
		if raw == null:
			print("  FAILED (bake returned nothing): %s" % root.get_path_to(shape))
			failed += 1
			continue
		var mesh := _to_indexed(raw)

		var mi := MeshInstance3D.new()
		mi.name = shape.name + BAKED_SUFFIX
		mi.mesh = mesh
		parent.add_child(mi)
		mi.owner = owner_node
		# bake_static_mesh() returns geometry in the shape's own local space,
		# so the new node has to sit on exactly the same transform to land in
		# the same place.
		mi.transform = shape.transform
		shape.visible = false
		baked += 1
		print("  baked: %s -> %s" % [shape.name, mi.name])

	if DRY_RUN:
		print("CSG BAKE: dry run done -- %d would be baked, %d already had a baked sibling." % [baked, skipped])
		print("          Set DRY_RUN = false and run again to actually do it.")
	else:
		print("CSG BAKE: baked %d, re-indexed %d existing, skipped %d, failed %d. Save the scene with Ctrl+S." % [
			baked, reindexed, skipped, failed])

## OccluderInstance3D's bake silently ignores meshes that have no index
## array, which is exactly what CSGShape3D.bake_static_mesh() hands back --
## that's the whole reason baked CSG walls never showed up as occluders
## (godot#104883). Running each surface back through SurfaceTool welds the
## duplicated vertices and produces the indexed form the baker will accept.
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

## Only CSG shapes that are not themselves inside another CSG shape get
## baked: a CSG node nested under another one is an operand of that parent's
## boolean operation (union/subtraction), and its result is already part of
## what the parent bakes. Baking it separately would duplicate geometry and
## ignore the subtraction it was there to perform.
func _collect(node: Node, out: Array[CSGShape3D]) -> void:
	if node is CSGShape3D:
		if not (node.get_parent() is CSGShape3D):
			out.append(node)
		return # don't descend into a CSG tree
	for child in node.get_children():
		_collect(child, out)
