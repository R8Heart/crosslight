extends CanvasLayer
class_name SceneLoader

## Threaded scene load with a fade-to-black beat and a progress readout --
## the project's first-ever scene transition (menu -> estate). Builds its
## own UI in code, same pattern as ui/pause_menu.gd, so nothing needs to be
## hand-assembled in the caller's .tscn.
##
## The estate is a genuinely heavy scene (tens of thousands of nodes), so
## the load can take several seconds -- a plain fade-to-black with nothing
## else reads as a hang. A percentage readout is the whole fix.
##
## This project only ever needs one transition (menu -> estate), so this
## stays a single-purpose helper instead of a general scene-manager
## abstraction built for transitions that don't exist yet.
##
## Usage, from whatever script drives the main menu's "Новая игра" button:
##   var loader: SceneLoader = preload("res://ui/scene_loader.gd").new()
##   get_tree().root.add_child(loader)
##   loader.load_scene("res://rooms/estate_exterior.scn")

const FADE_TIME := 0.35
const DOT_CYCLE_FRAMES := 20
const FOG_SHADER := preload("res://assets/shaders/menu_fog_overlay.gdshader")

var _fade: ColorRect
var _text_fog: ColorRect
var _label: Label
var _loading := false

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	layer = 100

	_fade = ColorRect.new()
	_fade.color = Color(0, 0, 0, 0)
	_fade.set_anchors_preset(Control.PRESET_FULL_RECT)
	_fade.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_fade)

	# Same drifting-fog shader as the menu background (ui/main_menu.tscn's
	# FogOverlay), but sized to just the strip behind the loading text
	# instead of the whole screen -- reuses its own left-to-right gradient
	# uniforms, just mapped across this smaller box instead of the full
	# width, so it still reads as "dense near the text, clear past it".
	_text_fog = ColorRect.new()
	var fog_mat := ShaderMaterial.new()
	fog_mat.shader = FOG_SHADER
	fog_mat.set_shader_parameter("density", 1.4)
	fog_mat.set_shader_parameter("gradient_start", 0.0)
	fog_mat.set_shader_parameter("gradient_end", 0.9)
	# Observed backwards from the plain (non-reversed) formula on this
	# particular rect -- flipped here rather than re-deriving why, since
	# the visible result is what actually matters.
	fog_mat.set_shader_parameter("gradient_reverse", true)
	fog_mat.set_shader_parameter("vertical_softness", 0.8)
	_text_fog.material = fog_mat
	_text_fog.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_text_fog.anchor_left = 0.0
	_text_fog.anchor_right = 0.0
	_text_fog.anchor_top = 0.5
	_text_fog.anchor_bottom = 0.5
	_text_fog.offset_left = 0.0
	_text_fog.offset_right = 660.0
	_text_fog.offset_top = -70.0
	_text_fog.offset_bottom = 70.0
	_text_fog.modulate.a = 0.0
	add_child(_text_fog)

	_label = Label.new()
	# Anchored to the left edge with a fixed left offset, not centered --
	# and left-aligned text within that box, so the growing "..." just
	# appends past the end of the existing text instead of the whole line
	# re-centering (and visibly shifting) every time its width changes.
	_label.anchor_left = 0.0
	_label.anchor_right = 0.0
	_label.anchor_top = 0.5
	_label.anchor_bottom = 0.5
	_label.offset_left = 90.0
	_label.offset_right = 90.0 + 500.0
	_label.offset_top = -30.0
	_label.offset_bottom = 30.0
	_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_label.add_theme_font_size_override("font_size", 26)
	_label.add_theme_color_override("font_color", Color(0.85, 0.85, 0.85))
	_label.modulate.a = 0.0
	add_child(_label)

func load_scene(path: String) -> void:
	if _loading:
		return
	_loading = true
	ResourceLoader.load_threaded_request(path)

	var fade_in := create_tween()
	fade_in.tween_property(_fade, "color:a", 1.0, FADE_TIME)
	fade_in.parallel().tween_property(_label, "modulate:a", 1.0, FADE_TIME)
	fade_in.parallel().tween_property(_text_fog, "modulate:a", 1.0, FADE_TIME)
	await fade_in.finished

	# No percentage: this scene is one big compressed blob rather than many
	# discrete sub-resources, so Godot's progress estimate for it sits flat
	# for most of the load and then jumps straight to done -- a number here
	# would just read as broken. The dots are just to show it's alive.
	var frame := 0
	while ResourceLoader.load_threaded_get_status(path) == ResourceLoader.THREAD_LOAD_IN_PROGRESS:
		@warning_ignore("integer_division")
		var dots := ".".repeat((frame / DOT_CYCLE_FRAMES) % 4)
		_label.text = "Загрузка усадьбы%s" % dots
		frame += 1
		await get_tree().process_frame

	var packed: PackedScene = ResourceLoader.load_threaded_get(path)
	if packed == null:
		push_error("SceneLoader: failed to load '%s'." % path)
		_loading = false
		return

	var old_scene := get_tree().current_scene
	var new_scene := packed.instantiate()
	get_tree().root.add_child(new_scene)
	get_tree().current_scene = new_scene
	if old_scene:
		old_scene.queue_free()

	var fade_out := create_tween()
	fade_out.tween_property(_fade, "color:a", 0.0, FADE_TIME)
	fade_out.parallel().tween_property(_label, "modulate:a", 0.0, FADE_TIME)
	fade_out.parallel().tween_property(_text_fog, "modulate:a", 0.0, FADE_TIME)
	await fade_out.finished
	queue_free()
