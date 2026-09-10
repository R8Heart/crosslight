extends Node

## Global, persisted game settings. Every setting here applies immediately
## when changed (no "Apply"/restart step) and is written to
## user://settings.cfg on change. The pause menu (ui/pause_menu.gd) is the
## only thing that edits these values; anything else that cares about a
## setting either reads the property directly (mouse sensitivity, FOV are
## read on demand by player.gd) or reacts to the `changed` signal.
##
## Display confirmation/rollback (the "apply these settings? Y/N with a
## 5s auto-revert" flow) lives in ui/settings_panel.gd, not here -- this
## autoload just applies+saves whatever it's told, immediately.

signal changed

const CONFIG_PATH := "user://settings.cfg"

## Preset resolution list shown in the menu. Not const: on a fresh install
## (no settings.cfg yet) _autodetect_resolution() may insert the monitor's
## native resolution here if it isn't already one of these presets, so the
## player can always select their own screen's actual resolution.
var RESOLUTIONS: Array[Vector2i] = [
	Vector2i(1280, 720),
	Vector2i(1366, 768),
	Vector2i(1600, 900),
	Vector2i(1920, 1080),
	Vector2i(2560, 1440),
	Vector2i(3840, 2160),
]

## Frame-rate cap options, in the order the menu lists them. 0 = uncapped.
## Capping is not just a courtesy to the GPU: left uncapped the engine
## renders as fast as it possibly can at every instant, so the frame time
## swings with whatever is on screen. Pinning it to a rate the machine can
## actually hold everywhere trades peak numbers for a steady frame time,
## which reads as much smoother than a figure that leaps between 30 and 135.
const FPS_CAPS: Array[int] = [0, 24, 30, 60, 90, 120]

var fullscreen := true
var window_resolution := Vector2i(1920, 1080)
var render_scale := 1.0
var vsync := true
var max_fps := 60
var show_debug_overlay := true
var master_volume := 1.0 # linear 0..1, converted to dB when applied
var mouse_sensitivity := 1.0 # multiplier on top of player.gd's base sensitivity
var invert_y := false
var fov := 75.0
var brightness := 1.0

## --- Graphics quality ---
## Index into MSAA_OPTIONS / SHADOW_QUALITY_OPTIONS below, not the raw enum
## value -- keeps the menu's OptionButton index and the saved value the same
## number, same convention as FPS_CAPS above.
var msaa_3d := 0
var fxaa_enabled := false
## Temporal AA -- accumulates samples across frames, so unlike MSAA/FXAA
## (which only smooth geometry edges) it also kills the shimmer/sparkle on
## fine detail and specular highlights at a distance that neither of those
## touch. Tradeoff: faint ghosting/smear trailing fast-moving bright things
## (the lantern flame, LightSpark).
##
## Default OFF, deliberately: toggling use_taa forces the renderer to build
## an extra motion-vector pass and pipeline variants for every visible
## material, synchronously on the main thread. Defaulting this true made
## that compile stall happen on every single boot, before the scene had a
## chance to warm up -- it read as a full hang (confirmed 2026-09-09, had to
## force-close the game). Same failure class as the shader-compile stutter
## already seen in the friend's playtest logs, just moved earlier and made
## unconditional. Leave this false by default; a player who turns it on
## manually eats that one-time stall once, deliberately, instead of it
## ambushing every launch.
var taa_enabled := false
## Matches the project's original authored default (directional shadow was
## SOFT_MEDIUM before this settings system existed -- see project.godot's
## lights_and_shadows/directional_shadow/soft_shadow_filter_quality=3).
## Defaulting lower than that silently downgraded shadow quality below what
## the game always looked like, the moment this feature shipped.
var shadow_filter_quality := 3
## Global on/off for every Light3D's shadow, independent of shadow_filter
## quality -- see _apply_shadows_enabled(), this is the one setting here
## that has to walk the live scene tree rather than just poke Viewport/
## Environment/RenderingServer.
var shadows_enabled := true
var glow_enabled := true
var volumetric_fog_enabled := true
## Multiplies every FireSparks/DustMotes instance's own authored particle
## count (see components/fire_sparks.gd, components/dust_motes.gd) rather
## than being an absolute count -- keeps each instance's hand-tuned relative
## density (a big fireplace vs a single candle) intact at every quality level.
var particle_density := 1.0
## DirectionalLight3D.ShadowMode int (0=Orthogonal, 1=PSSM 2 Splits,
## 2=PSSM 4 Splits) applied specifically to the scene's MoonLight -- found
## by name, see _apply_moon_shadow(). There's only the one directional
## light in this project, so this doesn't need the general group-based
## approach shadows_enabled uses.
var moon_shadow_mode := 1
var moon_shadow_max_distance := 100.0

const MSAA_OPTIONS: Array[Viewport.MSAA] = [
	Viewport.MSAA_DISABLED, Viewport.MSAA_2X, Viewport.MSAA_4X,
]
const SHADOW_QUALITY_OPTIONS: Array[RenderingServer.ShadowQuality] = [
	RenderingServer.SHADOW_QUALITY_HARD,
	RenderingServer.SHADOW_QUALITY_SOFT_VERY_LOW,
	RenderingServer.SHADOW_QUALITY_SOFT_LOW,
	RenderingServer.SHADOW_QUALITY_SOFT_MEDIUM,
	RenderingServer.SHADOW_QUALITY_SOFT_HIGH,
]

## Node -> bool, the shadow_enabled each Light3D actually had authored
## before shadows_enabled=false last overrode it -- restored verbatim when
## turned back on, rather than force-enabling shadows on lights that never
## had them (see _apply_shadows_enabled()).
var _shadow_state_cache: Dictionary = {}

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	var first_run := not FileAccess.file_exists(CONFIG_PATH)
	_load()
	if first_run:
		_autodetect_resolution()
	_apply_all()

func _apply_all() -> void:
	_apply_display()
	_apply_render_scale()
	_apply_vsync()
	_apply_max_fps()
	_apply_audio()
	_apply_brightness()
	_apply_msaa()
	_apply_fxaa()
	_apply_taa()
	_apply_shadow_filter_quality()
	apply_scene_dependent()
	changed.emit()

## Everything here only makes sense once the actual game scene (with its
## WorldEnvironment, MoonLight, and Light3D fixtures) exists -- the main
## menu's own tiny 3D backdrop doesn't have a "MoonLight" and its Environment
## is its own separate .tres, so calling this while only the menu is loaded
## is harmless (each apply function no-ops if it can't find its target) but
## also pointless. ui/scene_loader.gd calls this again right after the
## estate scene actually becomes current_scene.
func apply_scene_dependent() -> void:
	_apply_shadows_enabled()
	_apply_glow()
	_apply_volumetric_fog()
	_apply_moon_shadow()

## Runs once, only on a fresh install (no settings.cfg yet). Picks the
## monitor's native resolution as the starting point instead of the
## hardcoded 1920x1080 default, and makes sure that resolution is
## selectable in the menu even if it isn't one of the RESOLUTIONS presets
## (ultrawide monitors, odd laptop panel sizes, etc).
func _autodetect_resolution() -> void:
	var native := DisplayServer.screen_get_size()
	if native.x <= 0 or native.y <= 0:
		return # Headless/unusual environment -- keep the hardcoded default.
	window_resolution = native
	if not RESOLUTIONS.has(native):
		RESOLUTIONS.append(native)
		RESOLUTIONS.sort_custom(func(a, b): return a.x < b.x)

## --- Frame rate cap ---

func set_max_fps(value: int) -> void:
	max_fps = value
	_apply_max_fps()
	_save()
	changed.emit()

func _apply_max_fps() -> void:
	Engine.max_fps = max_fps

## --- Debug overlay (read by components/debug_overlay.gd) ---

func set_show_debug_overlay(value: bool) -> void:
	show_debug_overlay = value
	_save()
	changed.emit()

## --- Display (fullscreen / windowed + resolution) ---

func set_fullscreen(value: bool) -> void:
	fullscreen = value
	_apply_display()
	_save()
	changed.emit()

func set_window_resolution(res: Vector2i) -> void:
	window_resolution = res
	_apply_display()
	_save()
	changed.emit()

## Fullscreen uses WINDOW_MODE_EXCLUSIVE_FULLSCREEN rather than the plain
## FULLSCREEN mode so that window_resolution actually takes effect while
## fullscreen -- exclusive fullscreen changes the monitor's video mode
## instead of just filling it at native res. This is most reliable on
## Windows; other platforms may silently ignore the resolution and behave
## like a normal fullscreen window.
func _apply_display() -> void:
	if fullscreen:
		DisplayServer.window_set_size(window_resolution)
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN)
		DisplayServer.window_set_size(window_resolution)
	else:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
		DisplayServer.window_set_size(window_resolution)
		# Center the window -- resizing alone can leave it partially off-screen
		# depending on where it was previously.
		var screen_size := DisplayServer.screen_get_size()
		DisplayServer.window_set_position((screen_size - window_resolution) / 2)

## --- Render scale (3D resolution scaling -- the main performance lever) ---

func set_render_scale(value: float) -> void:
	render_scale = clampf(value, 0.5, 1.0)
	_apply_render_scale()
	_save()
	changed.emit()

func _apply_render_scale() -> void:
	get_tree().root.scaling_3d_scale = render_scale

## --- VSync ---

func set_vsync(value: bool) -> void:
	vsync = value
	_apply_vsync()
	_save()
	changed.emit()

func _apply_vsync() -> void:
	DisplayServer.window_set_vsync_mode(
		DisplayServer.VSYNC_ENABLED if vsync else DisplayServer.VSYNC_DISABLED
	)

## --- Audio ---

func set_master_volume(value: float) -> void:
	master_volume = clampf(value, 0.0, 1.0)
	_apply_audio()
	_save()
	changed.emit()

func _apply_audio() -> void:
	var bus := AudioServer.get_bus_index("Master")
	if bus == -1:
		return
	AudioServer.set_bus_mute(bus, master_volume <= 0.0)
	if master_volume > 0.0:
		AudioServer.set_bus_volume_db(bus, linear_to_db(master_volume))

## --- Brightness (Environment post-process adjustment -- found live rather
## than baked into a scene file, since which room scene is active varies) ---

func set_brightness(value: float) -> void:
	brightness = clampf(value, 0.5, 1.5)
	_apply_brightness()
	_save()
	changed.emit()

func _apply_brightness() -> void:
	var world_env := get_tree().root.find_child("WorldEnvironment", true, false) as WorldEnvironment
	if world_env == null or world_env.environment == null:
		return
	world_env.environment.adjustment_enabled = true
	world_env.environment.adjustment_brightness = brightness

## --- Graphics quality ---

func set_msaa_3d(index: int) -> void:
	msaa_3d = clampi(index, 0, MSAA_OPTIONS.size() - 1)
	_apply_msaa()
	_save()
	changed.emit()

func _apply_msaa() -> void:
	get_viewport().msaa_3d = MSAA_OPTIONS[msaa_3d]

func set_fxaa_enabled(value: bool) -> void:
	fxaa_enabled = value
	_apply_fxaa()
	_save()
	changed.emit()

func _apply_fxaa() -> void:
	get_viewport().screen_space_aa = (
		Viewport.SCREEN_SPACE_AA_FXAA if fxaa_enabled else Viewport.SCREEN_SPACE_AA_DISABLED
	)

func set_taa_enabled(value: bool) -> void:
	taa_enabled = value
	_apply_taa()
	_save()
	changed.emit()

func _apply_taa() -> void:
	get_viewport().use_taa = taa_enabled

func set_shadow_filter_quality(index: int) -> void:
	shadow_filter_quality = clampi(index, 0, SHADOW_QUALITY_OPTIONS.size() - 1)
	_apply_shadow_filter_quality()
	_save()
	changed.emit()

## Global, not per-viewport -- Godot only exposes one shadow filter quality
## for the whole renderer (confirmed against the engine docs before building
## this), so directional and positional lights always match each other here.
func _apply_shadow_filter_quality() -> void:
	var q := SHADOW_QUALITY_OPTIONS[shadow_filter_quality]
	RenderingServer.directional_soft_shadow_filter_set_quality(q)
	RenderingServer.positional_soft_shadow_filter_set_quality(q)

func set_shadows_enabled(value: bool) -> void:
	shadows_enabled = value
	_apply_shadows_enabled()
	_save()
	changed.emit()

## Walks the live scene tree for every Light3D and forces shadow_enabled off
## (caching what it actually was first), or restores each one's cached
## authored value when turned back on. Deliberately not group-tag based:
## retrofitting a group onto ~20 lights scattered across a dozen scene files
## would mean editing every one of those files by hand; a one-time tree walk
## costs nothing that matters (it's not per-frame) and needs touching
## nothing else.
func _apply_shadows_enabled() -> void:
	var root := get_tree().current_scene
	if root == null:
		return
	_walk_shadows(root)

func _walk_shadows(node: Node) -> void:
	if node is Light3D:
		var light := node as Light3D
		if shadows_enabled:
			if _shadow_state_cache.has(light):
				light.shadow_enabled = _shadow_state_cache[light]
				_shadow_state_cache.erase(light)
		elif not _shadow_state_cache.has(light):
			_shadow_state_cache[light] = light.shadow_enabled
			light.shadow_enabled = false
	for child in node.get_children():
		_walk_shadows(child)

func set_glow_enabled(value: bool) -> void:
	glow_enabled = value
	_apply_glow()
	_save()
	changed.emit()

func _apply_glow() -> void:
	var env := _current_environment()
	if env:
		env.glow_enabled = glow_enabled

func set_volumetric_fog_enabled(value: bool) -> void:
	volumetric_fog_enabled = value
	_apply_volumetric_fog()
	_save()
	changed.emit()

func _apply_volumetric_fog() -> void:
	var env := _current_environment()
	if env:
		env.volumetric_fog_enabled = volumetric_fog_enabled

## World3D.environment tracks whatever WorldEnvironment node is currently
## active for this viewport, so this works regardless of which scene
## (menu or estate) is loaded, with no group tag or node path needed.
func _current_environment() -> Environment:
	var world := get_viewport().world_3d
	return world.environment if world else null

func set_particle_density(value: float) -> void:
	particle_density = clampf(value, 0.25, 1.0)
	_save()
	changed.emit() # FireSparks/DustMotes react to this themselves.

func set_moon_shadow_mode(index: int) -> void:
	moon_shadow_mode = clampi(index, 0, 2)
	_apply_moon_shadow()
	_save()
	changed.emit()

func set_moon_shadow_max_distance(value: float) -> void:
	moon_shadow_max_distance = clampf(value, 20.0, 300.0)
	_apply_moon_shadow()
	_save()
	changed.emit()

func _apply_moon_shadow() -> void:
	var moon := get_tree().root.find_child("MoonLight", true, false) as DirectionalLight3D
	if moon == null:
		return
	moon.directional_shadow_mode = moon_shadow_mode as DirectionalLight3D.ShadowMode
	moon.directional_shadow_max_distance = moon_shadow_max_distance

## --- Quality presets ---
## One button applies a whole bundle at once for players who don't want to
## tune each slider by hand. Render scale is deliberately left alone here --
## it's already its own prominent slider and changing it as a side effect of
## a "Low" button would be surprising.
enum Preset { LOW, MEDIUM, HIGH }

func apply_preset(preset: Preset) -> void:
	match preset:
		Preset.LOW:
			set_msaa_3d(0)
			set_fxaa_enabled(false)
			set_shadow_filter_quality(1)
			set_shadows_enabled(false)
			set_glow_enabled(false)
			set_volumetric_fog_enabled(false)
			set_particle_density(0.25)
		Preset.MEDIUM:
			set_msaa_3d(0)
			set_fxaa_enabled(true)
			set_shadow_filter_quality(3)
			set_shadows_enabled(true)
			set_glow_enabled(true)
			set_volumetric_fog_enabled(true)
			set_particle_density(0.5)
		Preset.HIGH:
			set_msaa_3d(1)
			set_fxaa_enabled(false)
			set_shadow_filter_quality(4)
			set_shadows_enabled(true)
			set_glow_enabled(true)
			set_volumetric_fog_enabled(true)
			set_particle_density(1.0)

## --- Controls (read directly by player.gd, no apply step needed) ---

func set_mouse_sensitivity(value: float) -> void:
	mouse_sensitivity = clampf(value, 0.2, 3.0)
	_save()
	changed.emit()

func set_invert_y(value: bool) -> void:
	invert_y = value
	_save()
	changed.emit()

func set_fov(value: float) -> void:
	fov = clampf(value, 60.0, 100.0)
	_save()
	changed.emit()

## --- Persistence ---

func _save() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("display", "fullscreen", fullscreen)
	cfg.set_value("display", "window_resolution", window_resolution)
	cfg.set_value("display", "render_scale", render_scale)
	cfg.set_value("display", "vsync", vsync)
	cfg.set_value("display", "max_fps", max_fps)
	cfg.set_value("debug", "show_overlay", show_debug_overlay)
	cfg.set_value("audio", "master_volume", master_volume)
	cfg.set_value("controls", "mouse_sensitivity", mouse_sensitivity)
	cfg.set_value("controls", "invert_y", invert_y)
	cfg.set_value("controls", "fov", fov)
	cfg.set_value("display", "brightness", brightness)
	cfg.set_value("graphics", "msaa_3d", msaa_3d)
	cfg.set_value("graphics", "fxaa_enabled", fxaa_enabled)
	cfg.set_value("graphics", "taa_enabled", taa_enabled)
	cfg.set_value("graphics", "shadow_filter_quality", shadow_filter_quality)
	cfg.set_value("graphics", "shadows_enabled", shadows_enabled)
	cfg.set_value("graphics", "glow_enabled", glow_enabled)
	cfg.set_value("graphics", "volumetric_fog_enabled", volumetric_fog_enabled)
	cfg.set_value("graphics", "particle_density", particle_density)
	cfg.set_value("graphics", "moon_shadow_mode", moon_shadow_mode)
	cfg.set_value("graphics", "moon_shadow_max_distance", moon_shadow_max_distance)
	cfg.save(CONFIG_PATH)

func _load() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(CONFIG_PATH) != OK:
		return # No saved file yet -- keep the defaults declared above.
	fullscreen = cfg.get_value("display", "fullscreen", fullscreen)
	window_resolution = cfg.get_value("display", "window_resolution", window_resolution)
	render_scale = cfg.get_value("display", "render_scale", render_scale)
	vsync = cfg.get_value("display", "vsync", vsync)
	max_fps = cfg.get_value("display", "max_fps", max_fps)
	show_debug_overlay = cfg.get_value("debug", "show_overlay", show_debug_overlay)
	master_volume = cfg.get_value("audio", "master_volume", master_volume)
	mouse_sensitivity = cfg.get_value("controls", "mouse_sensitivity", mouse_sensitivity)
	invert_y = cfg.get_value("controls", "invert_y", invert_y)
	fov = cfg.get_value("controls", "fov", fov)
	brightness = cfg.get_value("display", "brightness", brightness)
	msaa_3d = cfg.get_value("graphics", "msaa_3d", msaa_3d)
	fxaa_enabled = cfg.get_value("graphics", "fxaa_enabled", fxaa_enabled)
	taa_enabled = cfg.get_value("graphics", "taa_enabled", taa_enabled)
	shadow_filter_quality = cfg.get_value("graphics", "shadow_filter_quality", shadow_filter_quality)
	shadows_enabled = cfg.get_value("graphics", "shadows_enabled", shadows_enabled)
	glow_enabled = cfg.get_value("graphics", "glow_enabled", glow_enabled)
	volumetric_fog_enabled = cfg.get_value("graphics", "volumetric_fog_enabled", volumetric_fog_enabled)
	particle_density = cfg.get_value("graphics", "particle_density", particle_density)
	moon_shadow_mode = cfg.get_value("graphics", "moon_shadow_mode", moon_shadow_mode)
	moon_shadow_max_distance = cfg.get_value("graphics", "moon_shadow_max_distance", moon_shadow_max_distance)
