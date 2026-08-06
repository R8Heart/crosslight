@tool
extends EditorScript

## Run from the Script editor (File > Run / Ctrl+Shift+X) with main.scn/
## main.tscn open and edited. Restructures the chandelier's 5 flat chain-
## link siblings (all direct children of the same StaticBody3D, just
## positioned at different heights) into a nested chain of pivots: link1
## contains a pivot at link2's spot, which contains link2 and a pivot at
## link3's spot, and so on, ending with the chandelier body itself as the
## last link. Purely visual (mesh only) -- the collision shapes are left
## exactly where they are, unaffected.
##
## Why nest them at all: a single rotation applied to the topmost pivot
## then compounds naturally through the chain via ordinary parent/child
## transforms, so the bottom swings further than the top with zero extra
## per-link math -- that's what makes it read as a chain bending instead
## of a rigid rod pivoting once at the ceiling.
##
## Uses global_transform to reparent, so nothing visually jumps: Godot
## computes the correct local transform under the new parent for us
## instead of us hand-deriving matrices from the .tscn text.

const CHAIN_PARENT_PATH := "hall/roof/chandelier/StaticBody3D"
const BODY_PATH := "hall/roof/chandelier/StaticBody3D/StaticBody3D"
const LINK_NAMES := [
	"tripo_node_983e82c5-4d8a-4a03-9c2f-9042448f6cd8",
	"tripo_node_983e82c5-4d8a-4a03-9c2f-9042448f6cd9",
	"tripo_node_983e82c5-4d8a-4a03-9c2f-9042448f6cd10",
	"tripo_node_983e82c5-4d8a-4a03-9c2f-9042448f6cd11",
	"tripo_node_983e82c5-4d8a-4a03-9c2f-9042448f6cd12",
]
const DOOR_PATHS := [
	"enter/doors/DoorLeft",
	"enter/doors/DoorRight",
]
const SWAY_SCRIPT_PATH := "res://components/chain_sway.gd"

func _run() -> void:
	var root := get_editor_interface().get_edited_scene_root()
	if root == null:
		print("CHAIN: no scene is open in the editor -- open main first.")
		return

	var chain_parent: Node3D = root.get_node_or_null(CHAIN_PARENT_PATH)
	var body: Node3D = root.get_node_or_null(BODY_PATH)
	if chain_parent == null or body == null:
		print("CHAIN: could not find chandelier nodes -- paths may have changed.")
		return

	var links: Array[Node3D] = []
	for n in LINK_NAMES:
		var link: Node3D = chain_parent.get_node_or_null(n)
		if link == null:
			print("CHAIN: missing link ", n)
			return
		links.append(link)

	var owner_node := chain_parent.owner
	var current_parent: Node3D = chain_parent
	var sway_pivots: Array[Node3D] = []

	for link in links:
		var link_xform := link.global_transform
		link.get_parent().remove_child(link)
		current_parent.add_child(link)
		link.owner = owner_node
		link.global_transform = link_xform

		var pivot := Node3D.new()
		pivot.name = link.name + "_Pivot"
		link.add_child(pivot)
		pivot.owner = owner_node
		pivot.global_transform = link_xform

		sway_pivots.append(pivot)
		current_parent = pivot

	# The chandelier body gets its own trailing pivot too, same as any other
	# link -- it's the heaviest mass on the chain, so per chain_sway.gd's
	# amplitude_growth it ends up swinging the most, exactly as a real
	# chandelier would.
	var body_xform := body.global_transform
	var old_body_parent := body.get_parent()
	old_body_parent.remove_child(body)

	var body_pivot := Node3D.new()
	body_pivot.name = "Body_Pivot"
	current_parent.add_child(body_pivot)
	body_pivot.owner = owner_node
	body_pivot.global_transform = body_xform
	sway_pivots.append(body_pivot)

	body_pivot.add_child(body)
	body.owner = owner_node
	body.global_transform = body_xform

	# Wire up the sway controller itself so no manual NodePath entry in the
	# Inspector is needed.
	var sway := Node.new()
	sway.name = "ChainSway"
	sway.set_script(load(SWAY_SCRIPT_PATH))
	chain_parent.add_child(sway)
	sway.owner = owner_node

	var pivot_paths: Array[NodePath] = []
	for p in sway_pivots:
		pivot_paths.append(sway.get_path_to(p))
	sway.set("pivots", pivot_paths)

	var door_node_paths: Array[NodePath] = []
	for dp in DOOR_PATHS:
		var door := root.get_node_or_null(dp)
		if door:
			door_node_paths.append(sway.get_path_to(door))
		else:
			print("CHAIN: door not found, skipping: ", dp)
	sway.set("door_paths", door_node_paths)

	print("CHAIN: rigged %d links + body into a nested pivot chain under '%s', wired to %d door(s). Save with Ctrl+S." % [
		links.size(), root.name, door_node_paths.size()])
