@tool
extends EditorScript

## Run this from the Script editor (File > Run, or Ctrl+Shift+X) while the
## scene you want to retune (main.scn) is the active tab, then save with
## Ctrl+S without switching tabs first. Edits the live scene tree in place
## -- no format conversion, no headless resave, so nested scene instances
## stay intact.
##
## Does two things in one pass:
## 1. Every SpotLight3D in this scene turned out to be the same wall-sconce
##    fixture, apparently meant to be an OmniLight3D (it's even still named
##    "OmniLight3D") -- a cone light needs correct aim to look right, and
##    this one doesn't have it, which produced a sharp wedge of light
##    instead of a soft glow. Converted to a real OmniLight3D, which
##    sidesteps aiming entirely.
## 2. Widens the reach of non-shadow flame lights (candelabra, sconces,
##    street lamps) and softens their falloff so they light the room
##    instead of just themselves, and caps light_specular so the wider
##    reach doesn't turn into bright specular blobs on nearby walls.
##    Shadow-casting lights (chandelier) only get a small, capped range
##    nudge, left alone otherwise, to avoid undoing the shadow-cost work.
##
## Safe to re-run any time after adding new fixtures -- already-good
## lights are left untouched and print nothing, and repeated runs
## converge instead of compounding.

const MIN_RANGE := 16.0
const MAX_ATTEN := 1.3
const SHADOW_RANGE_BOOST := 1.2
## Absolute ceiling for shadow-casting lights, not a per-run multiplier --
## re-running this tool is safe and converges here instead of compounding
## +20% forever.
const SHADOW_RANGE_CAP := 13.5
## Godot's own default is 0.5. A few fixtures were set well above that
## (the chandelier was 2.545!), which barely showed at the old tiny ranges
## but turns into a bright specular blob on nearby walls now that lights
## reach much further.
const MAX_SPECULAR := 0.6

func _run() -> void:
	var root := get_editor_interface().get_edited_scene_root()
	if root == null:
		print("RELIGHT: no scene is open in the editor -- open main.scn first.")
		return

	var spots: Array[SpotLight3D] = []
	var stack: Array[Node] = [root]
	while not stack.is_empty():
		var node: Node = stack.pop_back()
		for child in node.get_children():
			stack.push_back(child)
		if node is SpotLight3D:
			spots.append(node)

	for spot in spots:
		_spot_to_omni(spot)

	var touched := 0
	var omni_seen := 0
	stack = [root]
	while not stack.is_empty():
		var node: Node = stack.pop_back()
		for child in node.get_children():
			stack.push_back(child)
		if node is OmniLight3D:
			omni_seen += 1
			if _retune(node):
				touched += 1

	print("RELIGHT: converted %d sconces, retuned %d / %d omni lights on '%s'. Save with Ctrl+S now." % [
		spots.size(), touched, omni_seen, root.name])

func _spot_to_omni(spot: SpotLight3D) -> void:
	var parent := spot.get_parent()
	var idx := spot.get_index()
	var owner_node := spot.owner
	var had_script := spot.get_script() != null

	var omni := OmniLight3D.new()
	omni.name = spot.name
	omni.transform = spot.transform
	omni.visible = spot.visible
	omni.light_color = spot.light_color
	omni.light_energy = spot.light_energy
	omni.light_indirect_energy = spot.light_indirect_energy
	omni.light_volumetric_fog_energy = spot.light_volumetric_fog_energy
	omni.light_specular = spot.light_specular
	omni.light_size = spot.light_size
	omni.light_bake_mode = spot.light_bake_mode
	omni.light_cull_mask = spot.light_cull_mask
	omni.shadow_enabled = spot.shadow_enabled
	omni.shadow_bias = spot.shadow_bias
	omni.shadow_normal_bias = spot.shadow_normal_bias
	omni.shadow_opacity = spot.shadow_opacity
	omni.shadow_blur = spot.shadow_blur
	omni.shadow_reverse_cull_face = spot.shadow_reverse_cull_face
	omni.omni_range = spot.spot_range
	omni.omni_attenuation = spot.spot_attenuation

	if had_script:
		omni.set_script(spot.get_script())
		omni.otherside_color = spot.otherside_color
		omni.otherside_energy = spot.otherside_energy
		omni.flicker_enabled = spot.flicker_enabled
		omni.flicker_strength = spot.flicker_strength
		omni.flicker_speed = spot.flicker_speed

	parent.add_child(omni)
	parent.move_child(omni, idx)
	omni.owner = owner_node

	parent.remove_child(spot)
	spot.free()

	print("  %s/%s  spot -> omni  range=%.3f atten=%.3f" % [parent.name, omni.name, omni.omni_range, omni.omni_attenuation])

func _retune(light: OmniLight3D) -> bool:
	var before_range := light.omni_range
	var before_atten := light.omni_attenuation
	var before_specular := light.light_specular
	var shadow := light.shadow_enabled

	var new_range := before_range
	var new_atten := before_atten
	var new_specular := minf(before_specular, MAX_SPECULAR)

	if shadow:
		new_range = minf(before_range * SHADOW_RANGE_BOOST, SHADOW_RANGE_CAP)
	else:
		new_range = maxf(before_range, MIN_RANGE)
		new_atten = minf(before_atten, MAX_ATTEN)

	var range_changed := not is_equal_approx(new_range, before_range)
	var atten_changed := not is_equal_approx(new_atten, before_atten)
	var specular_changed := not is_equal_approx(new_specular, before_specular)
	if not (range_changed or atten_changed or specular_changed):
		return false

	print("  %s/%s  shadow=%s  range %.3f -> %.3f  atten %.3f -> %.3f  specular %.3f -> %.3f" % [
		light.get_parent().name if light.get_parent() else "?", light.name,
		shadow, before_range, new_range, before_atten, new_atten, before_specular, new_specular])

	light.light_specular = new_specular
	light.omni_range = new_range
	light.omni_attenuation = new_atten
	return true
