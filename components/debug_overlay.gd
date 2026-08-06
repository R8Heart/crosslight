extends Label

## Small always-on-top perf readout (F3 to hide/show) so optimization passes
## can be judged against real numbers on the player's own hardware instead
## of guessed at from the editor.
##
## Also logs a CSV row every LOG_INTERVAL seconds to perf_log.csv at the
## project root -- position + every Performance monitor that matters, so a
## play session can be walked once and analyzed afterward instead of
## guessing camera angles blind.

const LOG_INTERVAL := 0.25
const LOG_PATH := "res://perf_log.csv"

var _f3_was_down := false
var _log_file: FileAccess
var _log_timer := 0.0
var _t := 0.0

func _ready() -> void:
	_log_file = FileAccess.open(LOG_PATH, FileAccess.WRITE)
	if _log_file:
		_log_file.store_line("t,pos_x,pos_y,pos_z,yaw_deg,pitch_deg,fps,frame_ms,phys_ms,draw_calls,objects,prims,vram_mb,ram_mb,nodes,phys_active,pipe_mesh,pipe_surface,pipe_draw,pipe_spec")

func _process(delta: float) -> void:
	var f3_down := Input.is_physical_key_pressed(KEY_F3)
	if f3_down and not _f3_was_down:
		visible = not visible
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
		text = "pos %.2f, %.2f, %.2f\nFPS %d  (%.1f ms | phys %.1f ms)\ndraw calls %d  objects %d  prims %d\nVRAM %.0f MB  RAM %.0f MB\nnodes %d  phys active %d\n[F3] hide  [logging]" % [
			pos.x, pos.y, pos.z, fps, frame_ms, phys_ms, draw_calls, objects, primitives, vram_mb, ram_mb, nodes, phys_active
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
