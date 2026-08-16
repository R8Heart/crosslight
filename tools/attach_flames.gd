@tool
extends EditorScript

## Run from the Script editor (File > Run / Ctrl+Shift+X) with main open and
## edited. Attaches a FlameEffect (see components/flame_effect.gd) as a
## child of every WorldLight-scripted Omni/Spot light in the scene, sized
## roughly off that light's own energy so small candles get small flames
## and the chandelier's brighter bulbs get bigger ones. Skips lights that
## already have a flame child, so it's safe to re-run after adding new
## fixtures.

const FLAME_SCRIPT := preload("res://components/flame_effect.gd")

func _run() -> void:
	var root := get_editor_interface().get_edited_scene_root()
	if root == null:
		print("FLAMES: no scene is open in the editor -- open main first.")
		return

	var added := 0
	var skipped := 0
	var stack: Array[Node] = [root]
	while not stack.is_empty():
		var node: Node = stack.pop_back()
		for child in node.get_children():
			stack.push_back(child)

		var is_flame_light := (node is OmniLight3D or node is SpotLight3D) and node.get_script() != null
		if not is_flame_light:
			continue

		var already_has_flame := false
		for c in node.get_children():
			if c is FlameEffect:
				already_has_flame = true
				break
		if already_has_flame:
			skipped += 1
			continue

		var energy: float = node.light_energy
		var height := clampf(0.12 + energy * 0.05, 0.12, 0.4)

		var flame_node := Node3D.new()
		flame_node.set_script(FLAME_SCRIPT)
		flame_node.name = "Flame"
		node.add_child(flame_node)
		flame_node.owner = root

		var flame := flame_node as FlameEffect
		flame.flame_height = height
		flame.flame_width = height * 0.45
		flame.intensity = clampf(1.2 + energy * 0.15, 1.2, 2.2)

		added += 1

	print("FLAMES: added %d, skipped %d already-flamed light(s). Save with Ctrl+S." % [added, skipped])
