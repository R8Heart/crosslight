@tool
extends EditorScript

## Run from the Script editor (File > Run / Ctrl+Shift+X) with main.scn/
## main.tscn (or whichever scene currently owns the hall chandelier) open.
##
## tools/rig_chandelier_chain.gd set Body_Pivot's transform to the
## chandelier body's own raw origin -- fine for most models, but this
## particular body's origin sits ~6.7 units above its actual mesh (an
## artifact of however the source asset was authored/exported), so the
## chandelier swings on a pivot floating well above its visible geometry.
## Invisible at rest (the whole body is just uniformly offset), but very
## visible mid-swing: the body arcs through a much wider radius than the
## chain link just above it, so the joint visibly pulls apart.
##
## Fix: move Body_Pivot down to coincide with its parent (the last chain
## link's own pivot -- exactly where every other link-to-link joint in this
## chain already sits, by the same convention rig_chandelier_chain.gd used
## everywhere else), then restore the chandelier body's global_transform
## to what it was before the move. Net effect: identical rest-pose
## appearance, but now rotating around the actual joint instead of a point
## floating in space above it.

## Found by name instead of a fixed path -- "chandelier" sits at
## "hall/roof/chandelier" when the whole estate or hall is open, but at
## just "chandelier" when roof.tscn itself is the scene being edited
## directly, and a hardcoded path only ever matches one of those.
const CHANDELIER_NAME := "chandelier"

func _run() -> void:
	var root := get_editor_interface().get_edited_scene_root()
	if root == null:
		print("FIXPIVOT: no scene is open in the editor -- open the scene with the hall chandelier first.")
		return

	var chandelier := root.find_child(CHANDELIER_NAME, true, false) as Node3D
	if chandelier == null:
		print("FIXPIVOT: could not find a node named '%s' anywhere in this scene." % CHANDELIER_NAME)
		return

	var body_pivot := chandelier.find_child("Body_Pivot", true, false) as Node3D
	if body_pivot == null:
		print("FIXPIVOT: no Body_Pivot found under the chandelier -- has it been rigged yet?")
		return

	var last_link_pivot := body_pivot.get_parent() as Node3D
	var body := body_pivot.get_node_or_null("StaticBody3D") as Node3D
	if last_link_pivot == null or body == null:
		print("FIXPIVOT: unexpected hierarchy -- Body_Pivot's parent or its StaticBody3D child is missing.")
		return

	var old_gap := body_pivot.global_position.distance_to(last_link_pivot.global_position)
	var body_xform := body.global_transform

	# Body_Pivot local (0,0,0) == exactly its parent's global transform --
	# the same convention every other pivot in this chain already follows.
	body_pivot.transform = Transform3D.IDENTITY

	# Re-home the body under the corrected pivot without moving it visually.
	body.global_transform = body_xform

	print("FIXPIVOT: Body_Pivot moved %.3f units to coincide with its parent joint. Chandelier body's visible position unchanged. Save with Ctrl+S." % old_gap)
