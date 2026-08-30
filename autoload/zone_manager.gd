extends Node

## Rooms tag their light fixtures into a Group named after the zone
## (e.g. "hall", "living_room"), and this fades those lights up/down as the
## player moves between zones.
##
## It also hides whole rooms the player cannot see into -- see the "Room
## visibility culling" block below. That is a separate concern from the
## lighting above and only ever touches the six side rooms; an earlier
## attempt that hid rooms indiscriminately made walls and furniture vanish
## in plain sight, which is why the cullable set and the adjacency table are
## both spelled out explicitly rather than inferred.
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

## --- Room visibility culling ---
##
## Measured 2026-08-28: frustum culling alone leaves one open doorway
## rendering the entire estate behind it -- facing a wall in the kitchen is
## 101 FPS / 421 draw calls, facing the door is 37 FPS / 1049 calls. Godot's
## own OccluderInstance3D is the textbook fix, but it does not recognise CSG
## geometry (godot#104883, confirmed), and the walls here are ~390 CSG nodes,
## so that route can't be relied on. This does the same job explicitly: hide
## whole room branches the player cannot currently be looking into.
##
## Only the six side rooms are ever culled. The hall, balcony and the
## exterior are deliberately never touched -- the hall spans two floors and
## is visible from almost everywhere, and the courtyard is visible through
## windows from inside, so hiding either would pop geometry in view.
##
## Crucially this hides a room's *contents*, never its shell. Neighbouring
## rooms share walls: one CSGBox serves as both rooms' side of the same
## partition, and some rooms have no wall of their own where they abut the
## next one. Hiding a whole room therefore punched visible holes through
## into the room beyond. Furniture and decor is where the polygons actually
## are anyway, so culling just that keeps nearly all of the saving with none
## of the holes.
const CULL_ROOMS := true

## Child branches of a room that are safe to hide: its furniture, props and
## decorative trim. Everything else in the room (walls, floors, ceiling,
## windows, doors) stays drawn always, because it either forms the shell
## the player sees from the next room, or has to stay interactive.
const CULLABLE_BRANCHES: Array[String] = [
	"decor",
	"ceiling_decor",
	"plintus_wood",
	"plintus_vertical",
	"lights",
]

## Which rooms stay drawn while standing in a given zone: the room itself,
## plus whatever is genuinely visible through its doorways. Anything not
## listed here is hidden. Rooms are a chain per wing (hall -> drawing room ->
## music room -> card room, hall -> dining -> kitchen -> pantry), so each
## room only ever needs its immediate neighbours.
const ROOM_ADJACENCY := {
	&"hall": [&"living_room", &"dining_room"],
	&"living_room": [&"music_room"],
	&"music_room": [&"living_room", &"card_room"],
	&"card_room": [&"music_room"],
	&"dining_room": [&"kitchen"],
	&"kitchen": [&"dining_room", &"storage_room"],
	&"storage_room": [&"kitchen"],
	&"estate": [],
}

## Every room this system is allowed to hide. A zone missing from here (the
## hall, the exterior) is simply never touched.
const CULLABLE_ROOMS: Array[StringName] = [
	&"living_room", &"music_room", &"card_room",
	&"dining_room", &"kitchen", &"storage_room",
]

## Fired after a zone change is fully applied (visibility + lighting already
## switched). components/debug_overlay.gd taps this to mark which room a
## stretch of the perf log was recorded in.
signal zone_entered(zone_id: StringName)

var current_zone: StringName = &""

var _original_energy: Dictionary = {} # plain Light3D -> float
var _active_tweens: Dictionary = {} # Node -> Tween
## zone_id -> the room's root Node3D, resolved once by name on first use.
var _room_roots: Dictionary = {}

## Deliberately does nothing at boot. This used to run the initial
## darken-every-other-zone pass directly in _ready() -- but an autoload's
## _ready() fires exactly once, at the very start of the whole app session.
## That was fine back when the estate was itself the main scene, but once a
## menu scene came first, this ran against the menu (zero ZoneTriggers in
## it) and never got a second chance once the estate loaded later: every
## light everywhere was staying at its authored brightness forever, only
## ever actually dimming the first time a zone was live-exited during play.
## See darken_all_except_current(), called from player.gd once the estate
## scene (and its Player) actually exists.
func _ready() -> void:
	pass

## Force every zone except whichever is current dark immediately, no fade.
## Call this once, right after the player's starting zone has already been
## entered via enter_zone() -- not before -- so the zone the player starts
## in doesn't visibly flash to black before fading back up.
func darken_all_except_current() -> void:
	await get_tree().process_frame
	var known_zones: Dictionary = {}
	for trigger in get_tree().get_nodes_in_group(&"zone_triggers"):
		known_zones[trigger.zone_id] = true
	for zone_id in known_zones:
		if zone_id == current_zone:
			continue
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
	_apply_room_visibility(zone_id)
	_set_zone_lit(zone_id, true)
	if previous != &"":
		_set_zone_lit(previous, false)
	zone_entered.emit(zone_id)

## Shows the current room and its immediate neighbours, hides every other
## cullable room. Runs before the light fades so a room that is about to be
## revealed is already in the tree when its lights start coming up.
func _apply_room_visibility(zone_id: StringName) -> void:
	if not CULL_ROOMS:
		return
	var keep_visible := {zone_id: true}
	for neighbour in ROOM_ADJACENCY.get(zone_id, []):
		keep_visible[neighbour] = true

	var shown: Array[String] = []
	var hidden: Array[String] = []
	for room in CULLABLE_ROOMS:
		var root := _room_root(room)
		if root == null:
			continue
		var should_show: bool = keep_visible.has(room)
		# Only the listed content branches are toggled -- the room's shell
		# (walls/floors/ceiling/windows/doors) is left alone, see
		# CULLABLE_BRANCHES.
		for branch_name in CULLABLE_BRANCHES:
			var branch := root.get_node_or_null(branch_name) as Node3D
			if branch and branch.visible != should_show:
				branch.visible = should_show
		if should_show:
			shown.append(String(room))
		else:
			hidden.append(String(room))
	print("[ZONE] room contents shown: %s | hidden: %s" % [", ".join(shown), ", ".join(hidden)])

## Room roots are Node3Ds named exactly after their zone, instanced into the
## assembled estate scene. Looked up by name rather than by group because the
## zone groups hold light fixtures, not necessarily the room root itself.
func _room_root(zone_id: StringName) -> Node3D:
	if _room_roots.has(zone_id):
		var cached = _room_roots[zone_id]
		return cached if is_instance_valid(cached) else null
	var found := get_tree().root.find_child(String(zone_id), true, false) as Node3D
	if found == null:
		push_warning("ZoneManager: no room root node named '%s' found -- that room will never be culled." % zone_id)
	_room_roots[zone_id] = found
	return found

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
	# Tagging both a room's root *and* its individual lights with the zone
	# group is normal and convenient, but it means a light gets reached
	# twice -- once directly, once by walking down from the root. Left
	# duplicated, each one would be faded twice with two different random
	# stagger delays, the second call killing the first one's tween.
	var seen: Dictionary = {}
	for node in get_tree().get_nodes_in_group(zone_id):
		visited += _collect(node, found, seen)

	if visited > SUSPICIOUS_NODE_COUNT:
		push_warning(
			"ZoneManager: zone '%s' walked %d nodes to find %d fixtures -- its group probably has a whole room root in it instead of just a fixtures container. Check what's tagged with this group." \
			% [zone_id, visited, found.size()])

	return found

## A group member might be a fixture itself, or a container node holding
## several (e.g. "lights2") -- handle both without caring which. Returns
## the number of nodes visited, purely so callers can flag an abnormally
## large walk.
func _collect(node: Node, out: Array, seen: Dictionary) -> int:
	var count := 1
	if (node is Light3D or _uses_zone_dim(node)) and not seen.has(node):
		seen[node] = true
		out.append(node)
	for child in node.get_children():
		count += _collect(child, out, seen)
	return count

## Components that recompute their own real brightness every frame --
## flame flicker, world-switch dimming, particle simulation -- and so
## expose a dedicated zone_dim factor for this system to drive. Writing
## their final brightness directly instead would just get overwritten 60x
## a second and strobe rather than fade. **Add new dimmable component
## types here**; that is the only place this list is spelled out.
func _uses_zone_dim(node: Node) -> bool:
	return node is WorldLight or node is WorldEmissive or node is FireSparks

## Which property carries this fixture's "how lit am I" value. Plain
## Light3Ds have no per-frame writer of their own and take light_energy.
func _dim_property(node: Node) -> String:
	if _uses_zone_dim(node):
		return "zone_dim"
	return "light_energy"

func _lit_value(node: Node) -> float:
	if _uses_zone_dim(node):
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
