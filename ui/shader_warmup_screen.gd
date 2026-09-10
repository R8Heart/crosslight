extends CanvasLayer

## The game's actual entry point (see project.godot's run/main_scene) --
## gates everything behind ShaderWarmup so the very first frame the player
## ever sees isn't a mid-game freeze the moment a heavy pipeline (TAA, a
## higher shadow filter, MSAA) gets touched for the first time. Same
## reasoning as ui/scene_loader.gd: a plain black screen with no feedback
## for a multi-second wait reads as a hang, so this shows real progress.
##
## Skips itself entirely (no visible screen at all, straight to the next
## scene) when ShaderWarmup.needs_warmup() is false -- which is the common
## case on every launch after the first, so repeat boots stay instant.

const _MAIN_MENU := "res://ui/main_menu.tscn"

var _bar: ProgressBar
var _status: Label

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	layer = 100

	if not ShaderWarmup.needs_warmup():
		_continue()
		return

	_build_ui()
	ShaderWarmup.progress.connect(_on_progress)
	ShaderWarmup.finished.connect(_continue)
	ShaderWarmup.run()

func _build_ui() -> void:
	var bg := ColorRect.new()
	bg.color = Color(0.02, 0.02, 0.03)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

	var box := VBoxContainer.new()
	box.set_anchors_preset(Control.PRESET_CENTER)
	box.custom_minimum_size = Vector2(420, 0)
	box.position -= Vector2(210, 40)
	box.add_theme_constant_override("separation", 12)
	add_child(box)

	var title := Label.new()
	title.text = "Подготовка графики"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 22)
	title.add_theme_color_override("font_color", Color(0.85, 0.85, 0.85))
	box.add_child(title)

	_bar = ProgressBar.new()
	_bar.min_value = 0
	_bar.max_value = 1
	_bar.value = 0
	_bar.show_percentage = false
	_bar.custom_minimum_size = Vector2(0, 18)
	box.add_child(_bar)

	_status = Label.new()
	_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_status.add_theme_font_size_override("font_size", 14)
	_status.add_theme_color_override("font_color", Color(0.55, 0.55, 0.55))
	box.add_child(_status)

func _on_progress(current: int, total: int, room_name: String) -> void:
	_bar.max_value = total
	_bar.value = current
	_status.text = "%d / %d -- %s" % [current, total, room_name]

## main_menu.tscn is light (a handful of nodes plus a hand/lantern rig),
## nowhere near estate_exterior's "tens of thousands of nodes" -- a plain
## scene swap is fast enough that it doesn't need SceneLoader's threaded
## load and progress dots (which are labelled "Загрузка усадьбы" anyway,
## the wrong text for landing on the menu).
func _continue() -> void:
	get_tree().change_scene_to_file(_MAIN_MENU)
