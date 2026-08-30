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
	changed.emit()

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
