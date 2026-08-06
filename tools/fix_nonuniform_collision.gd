@tool
extends EditorScript

## Run from the Script editor (File > Run / Ctrl+Shift+X) with main open and
## edited. Jolt Physics can't apply non-uniform scale to a collision shape --
## when a CollisionShape3D's *global* scale isn't uniform (usually because a
## parent decoration was stretched unevenly, e.g. the fountain at (6,2,6)),
## Jolt silently swaps in the average of the three axes instead. The result
## still LOOKS right in the editor and in "visible collision shapes" debug
## draw (both just show the authored shape), but the actual solid volume
## Jolt uses is a different size -- usually taller/wider than it looks,
## which is exactly what reads as an invisible wall in a spot that looks
## totally clear.
##
## Fix: bake the real effective size (computed from the live global scale,
## not hand-derived) directly into the shape resource's own radius/height/
## size, then null out the CollisionShape3D's own local scale contribution
## so its *global* scale becomes uniform (1,1,1) -- Jolt then reads exactly
## the shape we intend, no averaging involved. Position/rotation untouched.
##
## Only handles simple parametric shapes (Box/Capsule/Cylinder/Sphere) --
## anything else (Convex/Concave point-cloud shapes) is reported, not
## touched, since correcting those means rescaling every point rather than
## one or two numbers.

func _run() -> void:
	var root := get_editor_interface().get_edited_scene_root()
	if root == null:
		print("FIXCOLLISION: no scene is open in the editor -- open main first.")
		return

	var fixed := 0
	var skipped := 0
	var stack: Array[Node] = [root]
	while not stack.is_empty():
		var node: Node = stack.pop_back()
		for child in node.get_children():
			stack.push_back(child)
		if node is CollisionShape3D:
			var result := _check_and_fix(node as CollisionShape3D)
			if result == 1:
				fixed += 1
			elif result == -1:
				skipped += 1

	print("FIXCOLLISION: fixed %d non-uniform collision shape(s), %d flagged for manual review. Save with Ctrl+S." % [fixed, skipped])

## Returns 1 if fixed, -1 if flagged/skipped (non-uniform but unsupported
## shape type), 0 if it was already fine.
func _check_and_fix(cs: CollisionShape3D) -> int:
	if cs.shape == null:
		return 0

	var scale := cs.global_transform.basis.get_scale()
	var uniform := is_equal_approx(scale.x, scale.y) and is_equal_approx(scale.y, scale.z)
	if uniform:
		return 0

	# Untyped on purpose: needs to hold Box/Sphere/Capsule/Cylinder shapes
	# interchangeably and set whichever type-specific property applies below
	# (.size, .radius, .height) without the static type checker rejecting
	# member access that's only valid on the narrowed subtype.
	var shape = cs.shape
	var path := str(cs.get_path())

	if shape is BoxShape3D:
		shape = shape.duplicate()
		shape.size = Vector3(shape.size.x * scale.x, shape.size.y * scale.y, shape.size.z * scale.z)
	elif shape is SphereShape3D:
		shape = shape.duplicate()
		shape.radius = shape.radius * ((scale.x + scale.y + scale.z) / 3.0)
	elif shape is CapsuleShape3D:
		shape = shape.duplicate()
		shape.radius = shape.radius * ((scale.x + scale.z) / 2.0)
		shape.height = shape.height * scale.y
	elif shape is CylinderShape3D:
		shape = shape.duplicate()
		shape.radius = shape.radius * ((scale.x + scale.z) / 2.0)
		shape.height = shape.height * scale.y
	elif shape is ConvexPolygonShape3D:
		shape = shape.duplicate()
		var pts: PackedVector3Array = shape.points
		for i in pts.size():
			pts[i] = Vector3(pts[i].x * scale.x, pts[i].y * scale.y, pts[i].z * scale.z)
		shape.points = pts
	elif shape is ConcavePolygonShape3D:
		shape = shape.duplicate()
		var faces: PackedVector3Array = shape.get_faces()
		for i in faces.size():
			faces[i] = Vector3(faces[i].x * scale.x, faces[i].y * scale.y, faces[i].z * scale.z)
		shape.set_faces(faces)
	else:
		print("  SKIP (unsupported shape %s, needs manual fix): %s  global_scale=%s" % [
			shape.get_class(), path, scale])
		return -1

	# Cancel the inherited scale at this node so the shape (now baked to the
	# right absolute size) ends up with a uniform global scale of 1.
	var parent3d := cs.get_parent() as Node3D
	var parent_scale := parent3d.global_transform.basis.get_scale()
	cs.scale = Vector3(1.0 / parent_scale.x, 1.0 / parent_scale.y, 1.0 / parent_scale.z)
	cs.shape = shape

	print("  FIXED: %s  was global_scale=%s -> now uniform" % [path, scale])
	return 1
