@tool
extends EditorScript

## One-shot cleanup: removes every FlameEffect node added by
## tools/attach_flames.gd (run this once, then delete both tool scripts and
## the flame shader/component if the attempt is being scrapped entirely).

func _run() -> void:
	var root := get_editor_interface().get_edited_scene_root()
	if root == null:
		print("REMOVE_FLAMES: no scene is open in the editor -- open main first.")
		return

	var to_remove: Array[Node] = []
	var stack: Array[Node] = [root]
	while not stack.is_empty():
		var node: Node = stack.pop_back()
		for child in node.get_children():
			stack.push_back(child)
		if node is FlameEffect:
			to_remove.append(node)

	for n in to_remove:
		n.get_parent().remove_child(n)
		n.free()

	print("REMOVE_FLAMES: removed %d flame node(s). Save with Ctrl+S." % to_remove.size())
