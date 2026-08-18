@tool
extends EditorScript

## Copies a hand-configured dual_face_wall material (stone on one face,
## wallpaper on the other) from whichever wall already has it onto every
## other CSGShape3D named "wall*" in the currently open scene.
##
## Deliberately does NOT copy face_b_direction verbatim -- that value
## describes which of *that specific box's* local axes points into the
## room, which depends on how that one box happens to be oriented. Blindly
## copying it would put wallpaper on the outward-facing side of any wall
## that isn't rotated the same way as the reference. Instead, for each
## wall this works out which of its six local face directions points most
## toward the room's centre (averaged from every wall's own position) and
## uses that.
##
## Usage: open the scene with the reference wall already configured,
## select this script in the FileSystem dock, File > Run (or the Run
## button in the script editor).

const SHADER_PATH := "res://assets/shaders/dual_face_wall.gdshader"

func _run() -> void:
	var root := get_scene()
	if not root:
		push_error("Open the scene containing the walls first.")
		return

	var walls: Array[CSGShape3D] = []
	_collect_walls(root, walls)
	if walls.is_empty():
		push_error("No CSGShape3D nodes named 'wall*' found in this scene.")
		return

	var reference: CSGShape3D = null
	var ref_mat: ShaderMaterial = null
	var use_override := false
	for w in walls:
		var m := w.material as ShaderMaterial
		if m and m.shader and m.shader.resource_path == SHADER_PATH:
			reference = w
			ref_mat = m
			break
		m = w.material_override as ShaderMaterial
		if m and m.shader and m.shader.resource_path == SHADER_PATH:
			reference = w
			ref_mat = m
			use_override = true
			break
	if not reference:
		push_error("No wall is using dual_face_wall.gdshader yet (checked Material and Material Override) -- configure one by hand first, that's the one this copies from.")
		return

	var center := Vector3.ZERO
	for w in walls:
		center += w.global_position
	center /= walls.size()

	var applied := 0
	for w in walls:
		if w == reference:
			continue
		var mat := ref_mat.duplicate() as ShaderMaterial
		mat.set_shader_parameter("face_b_direction", _inward_local_direction(w, center))
		if use_override:
			w.material_override = mat
		else:
			w.material = mat
		applied += 1
		print("  %s -> face_b_direction %s" % [w.get_path(), mat.get_shader_parameter("face_b_direction")])

	print("dual_face_wall: reference was %s, applied to %d other wall(s). Save the scene to keep this." \
		% [reference.get_path(), applied])

func _collect_walls(node: Node, out: Array[CSGShape3D]) -> void:
	if node is CSGShape3D and node.name.to_lower().begins_with("wall"):
		out.append(node)
	for child in node.get_children():
		_collect_walls(child, out)

## Of the wall's six local axis directions, returns whichever one points
## most toward the room centre once transformed into world space -- that's
## the face material B (wallpaper) should end up on.
func _inward_local_direction(wall: Node3D, center: Vector3) -> Vector3:
	var to_center := center - wall.global_position
	if to_center.length() < 0.0001:
		return Vector3(0.0, 0.0, 1.0)
	to_center = to_center.normalized()

	var basis := wall.global_transform.basis
	var candidates := [
		Vector3(1, 0, 0), Vector3(-1, 0, 0),
		Vector3(0, 1, 0), Vector3(0, -1, 0),
		Vector3(0, 0, 1), Vector3(0, 0, -1),
	]
	var best: Vector3 = candidates[0]
	var best_dot := -INF
	for dir in candidates:
		var world_dir: Vector3 = (basis * dir).normalized()
		var d: float = world_dir.dot(to_center)
		if d > best_dot:
			best_dot = d
			best = dir
	return best
