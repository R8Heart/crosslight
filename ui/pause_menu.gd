extends CanvasLayer

## Pause + settings overlay. Builds its own Control tree in code (no hand-
## authored .tscn UI needed) -- toggled by player.gd on "ui_cancel" via
## toggle_pause(). Stays processing while the tree is paused so its own
## buttons/sliders keep working.
##
## Escape while the settings sub-panel is open steps back to the main
## panel instead of closing the whole menu -- handled here in _input()
## (which runs before player.gd's _unhandled_input) so the two don't
## fight over the same keypress; consuming the event here stops it from
## also reaching player.gd's handler that turn.

var _main_panel: VBoxContainer
var _settings_panel: SettingsPanel

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	layer = 50
	visible = false
	_build_ui()

func _input(event: InputEvent) -> void:
	if not visible:
		return
	if (event.is_action_pressed("ui_cancel") or event.is_action_pressed(&"gamepad_back")) and _settings_panel.visible:
		_show_main_panel()
		get_viewport().set_input_as_handled()

func toggle_pause() -> void:
	if visible:
		_close()
	else:
		_open()

func _open() -> void:
	visible = true
	get_tree().paused = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_show_main_panel()

func _close() -> void:
	visible = false
	get_tree().paused = false
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	Settings._save()

func _show_main_panel() -> void:
	_main_panel.visible = true
	_settings_panel.visible = false

func _show_settings_panel() -> void:
	_main_panel.visible = false
	_settings_panel.visible = true

## ---------------------------------------------------------------------
## UI construction
## ---------------------------------------------------------------------

func _build_ui() -> void:
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.6)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(dim)

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(center)

	var panel := PanelContainer.new()
	center.add_child(panel)

	var margin := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 28)
	panel.add_child(margin)

	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 10)
	root.custom_minimum_size = Vector2(360, 0)
	margin.add_child(root)

	_main_panel = _build_main_panel()
	_settings_panel = SettingsPanel.new()
	_settings_panel.in_game = true
	_settings_panel.visible = false
	_settings_panel.back_pressed.connect(_show_main_panel)
	root.add_child(_main_panel)
	root.add_child(_settings_panel)

func _label(text: String, big := false) -> Label:
	var l := Label.new()
	l.text = text
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	if big:
		l.add_theme_font_size_override("font_size", 22)
	return l

func _build_main_panel() -> VBoxContainer:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 10)

	box.add_child(_label("ПАУЗА", true))

	var resume := Button.new()
	resume.text = "Продолжить"
	resume.pressed.connect(_close)
	box.add_child(resume)

	var settings_btn := Button.new()
	settings_btn.text = "Настройки"
	settings_btn.pressed.connect(_show_settings_panel)
	box.add_child(settings_btn)

	var quit := Button.new()
	quit.text = "Выйти из игры"
	quit.pressed.connect(func(): get_tree().quit())
	box.add_child(quit)

	return box

