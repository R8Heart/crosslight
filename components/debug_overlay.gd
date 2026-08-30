extends Label

## Small always-on-top perf readout (F3 to hide/show) so optimization passes
## can be judged against real numbers on the player's own hardware instead
## of guessed at from the editor.
##
## Also logs a CSV row every LOG_INTERVAL seconds -- position + every
## Performance monitor that matters -- so a play session can be walked once
## and analyzed afterward instead of guessing camera angles blind. In an
## exported build this writes next to the executable (res:// is read-only
## once packed into a .pck) so a playtester can just find the file and send
## it back; in the editor it keeps landing at the project root as before.

const LOG_INTERVAL := 0.25

var _f3_was_down := false
var _log_file: FileAccess
var _log_timer := 0.0
var _t := 0.0
var _session_id: String

func _ready() -> void:
	_session_id = "%08x" % randi()
	_log_file = FileAccess.open(_log_path(), FileAccess.WRITE)
	if _log_file:
		_write_session_header()
		_log_file.store_line("t,pos_x,pos_y,pos_z,yaw_deg,pitch_deg,fps,frame_ms,phys_ms,draw_calls,objects,prims,vram_mb,ram_mb,nodes,phys_active,pipe_mesh,pipe_surface,pipe_draw,pipe_spec")
	# The settings menu owns whether this is shown; F3 still toggles it
	# in-place for a quick look without opening the menu.
	Settings.changed.connect(_apply_setting)
	_apply_setting()
	# Marks which room a stretch of rows was recorded in, so a dip in the
	# FPS column can be tied to a specific room without cross-referencing
	# separate console output.
	ZoneManager.zone_entered.connect(_on_zone_entered)

## Exported builds run with res:// packed read-only into a .pck, so writing
## there silently fails (FileAccess.open returns null) and no log is ever
## produced -- this was happening on every exported build until now. The
## executable's own folder is always writable and is exactly where a
## playtester would look for "the file next to the game".
##
## In-editor, res:// *is* the project folder on disk, so writing there
## used to work -- but the editor's own filesystem watcher notices the new
## file and tries to import it as a resource, sometimes while the log
## itself still has the file open, throwing "Cannot open file" import
## errors into the console on every single test run (plus leaving stray
## .csv.import clutter behind). user:// isn't scanned for imports at all,
## and the Output/Debugger panels are already right there while testing
## from the editor, so nothing is lost by not having it next to a project
## folder that isn't an actual build anyway.
func _log_path() -> String:
	var filename := "crosslight_log_%s.csv" % Time.get_datetime_string_from_system(false, true).replace(":", "-").replace(" ", "_")
	if OS.has_feature("editor"):
		return "user://" + filename
	return OS.get_executable_path().get_base_dir().path_join(filename)

## One-time block ahead of the CSV rows: enough about the machine and its
## settings to explain an FPS column without having to ask the playtester
## follow-up questions.
func _write_session_header() -> void:
	var v := Engine.get_version_info()
	var mem := OS.get_memory_info()
	var screen := DisplayServer.screen_get_size()
	_log_file.store_line("# Crosslight playtest log")
	_log_file.store_line("# session_id=%s started=%s" % [_session_id, Time.get_datetime_string_from_system()])
	_log_file.store_line("# godot=%d.%d.%d %s" % [v.major, v.minor, v.patch, v.status])
	_log_file.store_line("# os=%s %s" % [OS.get_name(), OS.get_version()])
	_log_file.store_line("# cpu=%s cores=%d ram_mb=%.0f" % [OS.get_processor_name(), OS.get_processor_count(), mem.get("physical", 0) / 1048576.0])
	_log_file.store_line("# gpu=%s vendor=%s driver_api=%s" % [
		RenderingServer.get_video_adapter_name(), RenderingServer.get_video_adapter_vendor(), RenderingServer.get_video_adapter_api_version()])
	_log_file.store_line("# screen=%dx%d refresh_hz=%.0f" % [screen.x, screen.y, DisplayServer.screen_get_refresh_rate()])
	_log_file.store_line("# settings: fullscreen=%s resolution=%s render_scale=%.2f vsync=%s max_fps=%d sensitivity=%.2f invert_y=%s fov=%.0f brightness=%.2f volume=%.2f" % [
		Settings.fullscreen, Settings.window_resolution, Settings.render_scale, Settings.vsync, Settings.max_fps,
		Settings.mouse_sensitivity, Settings.invert_y, Settings.fov, Settings.brightness, Settings.master_volume])

func _on_zone_entered(zone_id: StringName) -> void:
	if _log_file == null:
		return
	_log_file.store_line("ZONE,%.2f,%s" % [_t, zone_id])
	_log_file.flush()

func _apply_setting() -> void:
	visible = Settings.show_debug_overlay

func _process(delta: float) -> void:
	var f3_down := Input.is_physical_key_pressed(KEY_F3)
	if f3_down and not _f3_was_down:
		Settings.set_show_debug_overlay(not Settings.show_debug_overlay)
	_f3_was_down = f3_down

	_t += delta

	var fps := Performance.get_monitor(Performance.TIME_FPS)
	var frame_ms := Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0
	var phys_ms := Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0
	var draw_calls := Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)
	var objects := Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME)
	var primitives := Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME)
	var vram_mb := Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED) / 1048576.0
	var ram_mb := Performance.get_monitor(Performance.MEMORY_STATIC) / 1048576.0
	var nodes := Performance.get_monitor(Performance.OBJECT_NODE_COUNT)
	var phys_active := Performance.get_monitor(Performance.PHYSICS_3D_ACTIVE_OBJECTS)

	if visible:
		var player: Node3D = owner
		var pos := player.global_position if player else Vector3.ZERO
		var zone := String(ZoneManager.current_zone) if ZoneManager.current_zone != &"" else "(none)"
		text = "pos %.2f, %.2f, %.2f\nFPS %d  (%.1f ms | phys %.1f ms)\ndraw calls %d  objects %d  prims %d\nVRAM %.0f MB  RAM %.0f MB\nnodes %d  phys active %d\nzone %s\n[F3] hide  [logging]" % [
			pos.x, pos.y, pos.z, fps, frame_ms, phys_ms, draw_calls, objects, primitives, vram_mb, ram_mb, nodes, phys_active, zone
		]

	_log_timer += delta
	if _log_timer < LOG_INTERVAL:
		return
	_log_timer = 0.0
	_write_log_row(fps, frame_ms, phys_ms, draw_calls, objects, primitives, vram_mb, ram_mb, nodes, phys_active)

func _write_log_row(fps: float, frame_ms: float, phys_ms: float, draw_calls: float, objects: float, primitives: float, vram_mb: float, ram_mb: float, nodes: float, phys_active: float) -> void:
	if _log_file == null:
		return
	var player: Node3D = owner
	var pos := Vector3.ZERO
	var yaw := 0.0
	var pitch := 0.0
	if player:
		pos = player.global_position
		yaw = rad_to_deg(player.rotation.y)
		var head := player.get_node_or_null("Head")
		if head:
			pitch = rad_to_deg(head.rotation.x)

	var pipe_mesh := Performance.get_monitor(Performance.PIPELINE_COMPILATIONS_MESH)
	var pipe_surface := Performance.get_monitor(Performance.PIPELINE_COMPILATIONS_SURFACE)
	var pipe_draw := Performance.get_monitor(Performance.PIPELINE_COMPILATIONS_DRAW)
	var pipe_spec := Performance.get_monitor(Performance.PIPELINE_COMPILATIONS_SPECIALIZATION)

	_log_file.store_line("%.2f,%.2f,%.2f,%.2f,%.1f,%.1f,%d,%.2f,%.2f,%d,%d,%d,%.1f,%.1f,%d,%d,%d,%d,%d,%d" % [
		_t, pos.x, pos.y, pos.z, yaw, pitch, fps, frame_ms, phys_ms,
		draw_calls, objects, primitives, vram_mb, ram_mb, nodes, phys_active,
		pipe_mesh, pipe_surface, pipe_draw, pipe_spec
	])
	_log_file.flush()
