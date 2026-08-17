extends Node

## Rooms tag their light fixtures into a Group named after the zone
## (e.g. "hall", "living_room"). Geometry/decor is never touched, so
## nothing ever visually disappears -- only the light itself fades out.
## Reacts only to actually crossing a zone's ZoneTrigger; there is no
## door-triggered pre-reveal, that added more confusion (zones lit with
## no way back off) than it was worth.
##
## Two node types count as "a light" here, and a fixture usually has both:
## the Light3D that actually illuminates, and a WorldEmissive glass/shade
## mesh that glows. Dimming only the former leaves fixtures visibly lit in
## an unlit room, which is exactly how the courtyard kept reading as "on"
## after its lights had already been switched off.

const FADE_TIME := 1.2
## Each light in a newly-lit zone starts its fade at a small random offset
## instead of all in the same frame -- a room full of lights catching at
## once in perfect sync reads as a light switch, not candlelight.
const MAX_STAGGER := 0.35
## If a zone's group accidentally contains a whole room root instead of
## just its fixtures, the tree walk below can hit tens of thousands of
## nodes (the hall scenes alone run to 50k+ from baked collision data)
## and stall the main thread long enough to take the renderer down with
## it. This is well above any legitimate fixtures-only container, so if
## a walk crosses it something is mis-tagged -- warn loudly instead of
## silently hanging.
const SUSPICIOUS_NODE_COUNT := 2000

var current_zone: StringName = &""

var _original_energy: Dictionary = {} # plain Light3D -> float
var _active_tweens: Dictionary = {} # Node -> Tween
var _debug_label: Label

func _ready() -> void:
	_setup_debug_label()
	await get_tree().process_frame
	var known_zones: Dictionary = {}
	for trigger in get_tree().get_nodes_in_group(&"zone_triggers"):
		known_zones[trigger.zone_id] = true
	for zone_id in known_zones:
		for node in _find_dimmables(zone_id):
			_set_dark_immediately(node)

## Player physically walked into this zone -- lights it and switches off
## whichever zone they were in before.
func enter_zone(zone_id: StringName) -> void:
	if zone_id == current_zone or zone_id == &"":
		print("[ZONE] enter_zone(%s) ignored, current is already '%s'" % [zone_id, current_zone])
		return
	print("[ZONE] enter_zone: '%s' -> '%s'" % [current_zone, zone_id])
	var previous := current_zone
	current_zone = zone_id
	_update_debug_label()
	_set_zone_lit(zone_id, true)
	if previous != &"":
		_set_zone_lit(previous, false)

func _set_zone_lit(zone_id: StringName, lit: bool) -> void:
	var nodes := _find_dimmables(zone_id)
	print("[ZONE] _set_zone_lit('%s', lit=%s) -- %d fixtures" % [zone_id, lit, nodes.size()])
	for node in nodes:
		var delay := randf_range(0.0, MAX_STAGGER) if lit else 0.0
		_fade(node, lit, delay)

## Deliberately not cached across calls -- group membership only ever
## covers a room's own light fixtures (a few dozen nodes at most), so
## re-walking it each time is cheap, and caching previously caused zones
## to silently miss lights that weren't in the tree yet on first use.
func _find_dimmables(zone_id: StringName) -> Array:
	var found: Array = []
	var visited := 0
	for node in get_tree().get_nodes_in_group(zone_id):
		visited += _collect(node, found)

	if visited > SUSPICIOUS_NODE_COUNT:
		push_warning(
			"ZoneManager: zone '%s' walked %d nodes to find %d fixtures -- its group probably has a whole room root in it instead of just a fixtures container. Check what's tagged with this group." \
			% [zone_id, visited, found.size()])

	return found

## A group member might be a fixture itself, or a container node holding
## several (e.g. "lights2") -- handle both without caring which. Returns
## the number of nodes visited, purely so callers can flag an abnormally
## large walk.
func _collect(node: Node, out: Array) -> int:
	var count := 1
	if node is Light3D or node is WorldEmissive:
		out.append(node)
	for child in node.get_children():
		count += _collect(child, out)
	return count

## Which property carries this fixture's "how lit am I" value. WorldLight
## and WorldEmissive both recompute their real brightness from scratch
## every frame (flicker, world-switch dimming), so writing light_energy /
## emission directly on those gets overwritten 60x a second and strobes
## instead of fading -- they expose a dedicated zone_dim factor to drive
## instead. Plain Light3Ds have no such _process and take light_energy.
func _dim_property(node: Node) -> String:
	if node is WorldLight or node is WorldEmissive:
		return "zone_dim"
	return "light_energy"

func _lit_value(node: Node) -> float:
	if node is WorldLight or node is WorldEmissive:
		return 1.0
	if not _original_energy.has(node):
		_original_energy[node] = (node as Light3D).light_energy
	return float(_original_energy[node])

func _set_dark_immediately(node: Node) -> void:
	# Start every zone dark, and dark *at zero brightness*, not merely
	# hidden -- the brightness value would otherwise sit at its authored
	# level the whole time, so the first fade-in would have nothing to
	# animate from and would snap straight to full.
	_lit_value(node) # caches the authored value before we zero it
	node.set(_dim_property(node), 0.0)
	# Only real lights get hidden. Hiding a WorldEmissive would remove the
	# lamp's glass/shade geometry from the room, not just stop its glow.
	if node is Light3D:
		(node as Light3D).visible = false

func _fade(node: Node, lit: bool, delay: float = 0.0) -> void:
	var property := _dim_property(node)
	var target := _lit_value(node) if lit else 0.0

	if _active_tweens.has(node):
		var old: Tween = _active_tweens[node]
		if old and old.is_valid():
			old.kill()

	var tween := create_tween()
	_active_tweens[node] = tween

	var light := node as Light3D
	if lit and light:
		light.visible = true
	if delay > 0.0:
		tween.tween_interval(delay)

	# EASE_IN_OUT so the light doesn't jump most of the way to full
	# brightness in the first instant and then crawl the last few percent --
	# EASE_OUT was doing exactly that, which read as "snaps on, then a
	# barely visible flicker" instead of a fade.
	tween.tween_property(node, property, target, FADE_TIME) \
		.set_ease(Tween.EASE_IN_OUT).set_trans(Tween.TRANS_SINE)

	if not lit and light:
		tween.tween_callback(func(): light.visible = false)

## Plain on-screen readout, not gameplay UI -- just so the current zone is
## visible at a glance while testing instead of only living in the log.
func _setup_debug_label() -> void:
	var layer := CanvasLayer.new()
	layer.layer = 100
	_debug_label = Label.new()
	_debug_label.position = Vector2(16, 16)
	_debug_label.add_theme_font_size_override("font_size", 20)
	_debug_label.add_theme_color_override("font_color", Color(1.0, 0.95, 0.6))
	_debug_label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.9))
	_debug_label.add_theme_constant_override("shadow_offset_x", 1)
	_debug_label.add_theme_constant_override("shadow_offset_y", 1)
	layer.add_child(_debug_label)
	add_child(layer)
	_update_debug_label()

func _update_debug_label() -> void:
	_debug_label.text = "Zone: %s" % (current_zone if current_zone != &"" else "(none)")
