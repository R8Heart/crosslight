extends Node

## Global, persisted game settings. Every setting here applies immediately
## when changed (no "Apply"/restart step) and is written to
## user://settings.cfg on change. The pause menu (ui/pause_menu.gd) is the
## only thing that edits these values; anything else that cares about a
## setting either reads the property directly (mouse sensitivity, FOV are
## read on demand by player.gd) or reacts to the `changed` signal.

signal changed

const CONFIG_PATH := "user://settings.cfg"

const RESOLUTIONS: Array[Vector2i] = [
	Vector2i(1280, 720),
	Vector2i(1366, 768),
	Vector2i(1600, 900),
	Vector2i(1920, 1080),
	Vector2i(2560, 1440),
	Vector2i(3840, 2160),
]

var fullscreen := true
var window_resolution := Vector2i(1920, 1080)
var render_scale := 1.0
var vsync := true
var master_volume := 1.0 # linear 0..1, converted to dB when applied
var mouse_sensitivity := 1.0 # multiplier on top of player.gd's base sensitivity
var invert_y := false
var fov := 75.0
var brightness := 1.0

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_load()
	_apply_all()

func _apply_all() -> void:
	_apply_display()
	_apply_render_scale()
	_apply_vsync()
	_apply_audio()
	_apply_brightness()
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

func _apply_display() -> void:
	if fullscreen:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
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
	master_volume = cfg.get_value("audio", "master_volume", master_volume)
	mouse_sensitivity = cfg.get_value("controls", "mouse_sensitivity", mouse_sensitivity)
	invert_y = cfg.get_value("controls", "invert_y", invert_y)
	fov = cfg.get_value("controls", "fov", fov)
	brightness = cfg.get_value("display", "brightness", brightness)
