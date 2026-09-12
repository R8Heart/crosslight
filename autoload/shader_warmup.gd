extends Node

## Forces every room scene's materials through at least one real draw call,
## off-screen, before the player can reach them mid-game -- so pipeline
## compilation for MSAA/TAA/shadow-configuration changes (the categories
## Godot's own docs call out as NOT covered by the automatic ubershader/
## background-specialization system, see
## https://docs.godotengine.org/en/4.7/tutorials/performance/pipeline_compilations.html)
## happens on a progress screen instead of as a mid-game stutter or, worse,
## a synchronous freeze like the one TAA caused on 2026-09-09.
##
## Runs in two places:
##   - ui/shader_warmup_screen.gd, once, before the main menu, on first
##     launch or whenever something warmup-relevant changed since last time.
##   - ui/settings_panel.gd, briefly and live, whenever the player changes
##     an AA/shadow setting mid-game -- see needs_warmup().
##
## Renders into its own private SubViewport with its own World3D (own_world_3d
## = true), so this never touches or overlaps the actual game world -- safe
## to run while the estate scene is live and the player is standing in it.

signal progress(current: int, total: int, room_name: String)
signal finished

const CACHE_PATH := "user://shader_warmup_cache.cfg"
const VIEWPORT_SIZE := Vector2i(256, 256)

## Scanned broadly rather than limited to rooms/, so a new folder can't be
## silently missed -- but res://ui is excluded wholesale (see _scan_dir):
## menu scenes are live interactive Control trees with their own scripts,
## audio and a SettingsPanel of their own, not passive dioramas. Instancing
## main_menu.tscn here once actually built a second SettingsPanel inside the
## warmup pass, whose own _sync_to_settings() fired the very signals wired
## to trigger a live re-warm, recursively -- confirmed hang, 2026-09-09.
const _SCAN_EXTENSIONS := ["tscn", "scn"]
## estate_exterior instances every room already covered individually below
## it -- loading it too would double memory use for a huge combined AABB
## that doesn't frame any single room usefully. Checked by basename (not
## full filename) and after the .tscn/.scn dedup below, so it catches
## whichever copy of it survives dedup.
const _EXCLUDE_BASENAMES := ["estate_exterior"]
## Same reasoning for both: not passive dioramas. player.scn's _ready() also
## grabs Input.mouse_mode globally and registers into the "player" group --
## instantiating it during a live mid-game re-warm would steal mouse capture
## out from under an open pause menu and plant a second node in that group.
const _EXCLUDE_DIRS := ["res://ui", "res://player"]

## Look in all 6 axis directions from each room's center rather than one
## top-down shot -- most rooms have a ceiling, so a purely top-down camera
## would only ever see roof materials and miss everything inside.
const _CUBE_DIRECTIONS: Array[Vector3] = [
	Vector3.FORWARD, Vector3.BACK, Vector3.LEFT, Vector3.RIGHT, Vector3.UP, Vector3.DOWN,
]

var _viewport: SubViewport
var _camera: Camera3D
var _sun: DirectionalLight3D
var _running := false

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS

## Every combination of AA/shadow settings this project has actually warmed
## before, capped so it can't grow forever across a long session of trying
## presets back and forth. A single remembered value would re-warm every
## time someone flips Low -> High -> Low again; remembering a handful means
## switching back to a combination already paid for costs nothing.
const _MAX_FINGERPRINT_HISTORY := 12

## True if the current scene files (by path+mtime) plus AA/shadow settings
## are a combination this project has never warmed before -- covers first
## launch, a content change, AND a setting changed to something new, but NOT
## switching back to a combination already warmed earlier this history.
func needs_warmup() -> bool:
	var cfg := ConfigFile.new()
	if cfg.load(CACHE_PATH) != OK:
		return true
	var known: Array = cfg.get_value("cache", "fingerprints", [])
	return not (_compute_fingerprint() in known)

func run() -> void:
	if _running:
		return
	_running = true
	_ensure_viewport()

	# Defense against any scene (a stray .tscn debug copy with an embedded
	# Player included, or anything similar added later) whose _ready() pokes
	# global engine state -- confirmed case: player.gd captures the mouse
	# globally, which a paused menu never expects and never undoes on its
	# own. Restoring after every single scene, not just once at the end,
	# means whichever scene did it can't leave the game in that state even
	# for the rest of this pass, regardless of what it turns out to be.
	var restore_mouse_mode := Input.mouse_mode

	var paths := _collect_scene_paths()
	var total := paths.size()
	for i in range(total):
		var path: String = paths[i]
		progress.emit(i + 1, total, path.get_file().get_basename())
		await _warm_scene(path)
		Input.mouse_mode = restore_mouse_mode

	_save_fingerprint()
	_running = false
	finished.emit()

func _compute_fingerprint() -> String:
	var paths := _collect_scene_paths()
	var parts: Array[String] = []
	for path in paths:
		parts.append("%s:%d" % [path, FileAccess.get_modified_time(path)])
	# Every value here gates a distinct pipeline permutation per Godot's own
	# docs (MSAA level, motion vectors i.e. TAA, shadow configuration) --
	# moon_shadow_max_distance is deliberately left out, it's a plain uniform
	# the existing pipeline reads, not a different shader variant.
	parts.append("aa:%d" % Settings.aa_method)
	parts.append("shadow_q:%d" % Settings.shadow_filter_quality)
	parts.append("shadows_on:%s" % Settings.shadows_enabled)
	parts.append("moon_mode:%d" % Settings.moon_shadow_mode)
	return "\n".join(parts).sha256_text()

func _save_fingerprint() -> void:
	var cfg := ConfigFile.new()
	cfg.load(CACHE_PATH) # fine if this fails (no cache file yet) -- known stays []
	var known: Array = cfg.get_value("cache", "fingerprints", [])
	var fp := _compute_fingerprint()
	if not (fp in known):
		known.append(fp)
	if known.size() > _MAX_FINGERPRINT_HISTORY:
		known = known.slice(known.size() - _MAX_FINGERPRINT_HISTORY)
	cfg.set_value("cache", "fingerprints", known)
	cfg.save(CACHE_PATH)

## Nearly every scene in this project has a deliberate text-copy twin kept
## around purely so it can be read/grepped (see the crosslight-tscn-debug-
## copies project note) -- same content, not a second scene to warm. This
## turned out to run deeper than one .tscn next to its .scn in the same
## folder: rooms/scn/ and rooms/tscn/ are two whole parallel trees, and a
## room can have a copy sitting stale in either one. Confirmed the hard way
## (2026-09-10) -- rooms/scn/kitchen/kitchen.tscn hadn't been touched since
## August and referenced a door asset that no longer exists; warming both it
## and the real, current rooms/tscn/kitchen/kitchen.scn doubled the load and
## helped exhaust VRAM (0x8007000e) into a crash.
##
## So: group by BASENAME ALONE, wherever in the tree it lives, and keep only
## the most recently modified one. Doesn't assume either folder name means
## "the real one" -- the user's own resave habit means whichever copy was
## touched last is the one actually reflecting current content, regardless
## of which tree it happens to sit in.
func _collect_scene_paths() -> Array[String]:
	var raw: Array[String] = []
	_scan_dir("res://", raw)

	var best: Dictionary = {} # basename -> path
	var best_mtime: Dictionary = {} # basename -> modified time
	for path in raw:
		var key := path.get_file().get_basename()
		var mtime := FileAccess.get_modified_time(path)
		if not best.has(key) or mtime > best_mtime[key]:
			best[key] = path
			best_mtime[key] = mtime

	var out: Array[String] = []
	for key in best:
		if key in _EXCLUDE_BASENAMES:
			continue
		out.append(best[key])
	out.sort()
	return out

func _scan_dir(path: String, out: Array[String]) -> void:
	if path in _EXCLUDE_DIRS:
		return
	var dir := DirAccess.open(path)
	if dir == null:
		return
	dir.list_dir_begin()
	var entry_name := dir.get_next()
	while entry_name != "":
		if entry_name == "." or entry_name == "..":
			entry_name = dir.get_next()
			continue
		var full := path.path_join(entry_name)
		if dir.current_is_dir():
			if not entry_name.begins_with("."):
				_scan_dir(full, out)
		elif entry_name.get_extension() in _SCAN_EXTENSIONS:
			out.append(full)
		entry_name = dir.get_next()
	dir.list_dir_end()

## Built once and reused across every room -- own_world_3d isolates it from
## the actual game's World3D so instantiating a room's absolute-coordinate
## content in here can never visually or physically overlap the real scene,
## even while this runs live mid-game (see ui/settings_panel.gd).
func _ensure_viewport() -> void:
	if _viewport != null:
		_apply_current_aa_settings()
		return

	_viewport = SubViewport.new()
	_viewport.size = VIEWPORT_SIZE
	_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	_viewport.use_occlusion_culling = false
	_viewport.own_world_3d = true
	add_child(_viewport)

	_camera = Camera3D.new()
	_camera.fov = 170.0
	_camera.near = 0.05
	_camera.current = true
	_viewport.add_child(_camera)

	_sun = DirectionalLight3D.new()
	_sun.rotation_degrees = Vector3(-45.0, 20.0, 0.0)
	_sun.shadow_enabled = true
	_viewport.add_child(_sun)

	_apply_current_aa_settings()

## The AA method is per-Viewport -- Settings.gd applies it to the main
## viewport, so this SubViewport needs the same call made against it or it'd
## warm the wrong pipeline variants. Shadow filter quality is global
## (RenderingServer-wide), already in effect here with no extra step.
func _apply_current_aa_settings() -> void:
	Settings.apply_aa_to_viewport(_viewport)
	_sun.shadow_enabled = Settings.shadows_enabled
	_sun.directional_shadow_mode = Settings.moon_shadow_mode as DirectionalLight3D.ShadowMode

func _warm_scene(path: String) -> void:
	var packed: PackedScene = load(path)
	if packed == null:
		return
	var inst := packed.instantiate()
	_viewport.add_child(inst)
	_force_particles_emitting(inst)

	var aabb := _compute_aabb(inst)
	var center := aabb.get_center() if aabb.size != Vector3.ZERO else Vector3.ZERO
	_camera.global_position = center
	_camera.far = maxf(aabb.size.length(), 10.0) + 10.0
	_sun.global_position = center + Vector3.UP * 50.0

	for dir in _CUBE_DIRECTIONS:
		var up := Vector3.UP if absf(dir.y) < 0.99 else Vector3.FORWARD
		_camera.look_at(center + dir, up)
		await get_tree().process_frame

	inst.queue_free()
	await get_tree().process_frame

func _force_particles_emitting(node: Node) -> void:
	if node is GPUParticles3D:
		var particles := node as GPUParticles3D
		particles.emitting = true
		particles.restart()
	for child in node.get_children():
		_force_particles_emitting(child)

func _compute_aabb(node: Node) -> AABB:
	var state := {"aabb": AABB(), "first": true}
	_accumulate_aabb(node, state)
	return state["aabb"]

func _accumulate_aabb(node: Node, state: Dictionary) -> void:
	if node is VisualInstance3D:
		var world_aabb: AABB = node.global_transform * node.get_aabb()
		if state["first"]:
			state["aabb"] = world_aabb
			state["first"] = false
		else:
			state["aabb"] = state["aabb"].merge(world_aabb)
	for child in node.get_children():
		_accumulate_aabb(child, state)
