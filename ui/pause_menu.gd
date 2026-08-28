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
var _settings_panel: VBoxContainer
var _resolution_option: OptionButton
var _display_mode_option: OptionButton

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	layer = 50
	visible = false
	_build_ui()
	_sync_controls_to_settings()

func _input(event: InputEvent) -> void:
	if not visible:
		return
	if event.is_action_pressed("ui_cancel") and _settings_panel.visible:
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
	_settings_panel = _build_settings_panel()
	root.add_child(_main_panel)
	root.add_child(_settings_panel)

func _label(text: String, big := false) -> Label:
	var l := Label.new()
	l.text = text
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	if big:
		l.add_theme_font_size_override("font_size", 22)
	return l

func _row(caption: String, control: Control) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 16)
	var cap := Label.new()
	cap.text = caption
	cap.custom_minimum_size = Vector2(170, 0)
	row.add_child(cap)
	control.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(control)
	return row

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

func _build_settings_panel() -> VBoxContainer:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 8)
	box.visible = false

	box.add_child(_label("НАСТРОЙКИ", true))

	_display_mode_option = OptionButton.new()
	_display_mode_option.add_item("Полноэкранный", 0)
	_display_mode_option.add_item("Оконный", 1)
	_display_mode_option.item_selected.connect(_on_display_mode_selected)
	box.add_child(_row("Экран", _display_mode_option))

	_resolution_option = OptionButton.new()
	for res in Settings.RESOLUTIONS:
		_resolution_option.add_item("%d x %d" % [res.x, res.y])
	_resolution_option.item_selected.connect(_on_resolution_selected)
	box.add_child(_row("Разрешение (оконный)", _resolution_option))

	box.add_child(_slider_row("Качество рендера", 50, 100, 5, Settings.set_render_scale, "render_scale", 100.0, "%d%%"))

	var vsync_check := CheckBox.new()
	vsync_check.text = "Вкл"
	vsync_check.toggled.connect(func(pressed): Settings.set_vsync(pressed))
	box.add_child(_row("Вертикальная синхронизация", vsync_check))
	_vsync_check = vsync_check

	box.add_child(_slider_row("Громкость", 0, 100, 5, Settings.set_master_volume, "master_volume", 100.0, "%d%%"))

	box.add_child(_slider_row("Чувствительность мыши", 20, 300, 10, Settings.set_mouse_sensitivity, "mouse_sensitivity", 100.0, "%d%%"))

	var invert_check := CheckBox.new()
	invert_check.text = "Вкл"
	invert_check.toggled.connect(func(pressed): Settings.set_invert_y(pressed))
	box.add_child(_row("Инверсия мыши по Y", invert_check))
	_invert_check = invert_check

	box.add_child(_slider_row("Угол обзора (FOV)", 60, 100, 1, Settings.set_fov, "fov", 1.0, "%d°"))

	box.add_child(_slider_row("Яркость", 50, 150, 5, Settings.set_brightness, "brightness", 100.0, "%d%%"))

	var back := Button.new()
	back.text = "Назад"
	back.pressed.connect(_show_main_panel)
	box.add_child(back)

	return box

var _vsync_check: CheckBox
var _invert_check: CheckBox
var _sliders: Array[Dictionary] = []

## Builds one HBoxContainer with a label, an HSlider and a value label.
## `setter` applies the raw Settings value (slider units / display_scale);
## `property_name` is read back via Object.get() for the value label and
## initial slider position, so this stays in sync no matter who else
## changes Settings. Kept to plain data (a Callable + a property name)
## rather than a second lambda -- passing two inline lambdas into one call
## here reliably tripped up GDScript's indentation parsing.
func _slider_row(caption: String, min_v: float, max_v: float, step: float,
		setter: Callable, property_name: String, display_scale: float, fmt: String) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 16)
	var cap := Label.new()
	cap.text = caption
	cap.custom_minimum_size = Vector2(170, 0)
	row.add_child(cap)

	var slider := HSlider.new()
	slider.min_value = min_v
	slider.max_value = max_v
	slider.step = step
	slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(slider)

	var value_label := Label.new()
	value_label.custom_minimum_size = Vector2(48, 0)
	row.add_child(value_label)

	slider.value_changed.connect(func(v):
		setter.call(v / display_scale)
		value_label.text = fmt % roundi(v))

	_sliders.append({
		"slider": slider,
		"value_label": value_label,
		"property_name": property_name,
		"display_scale": display_scale,
		"fmt": fmt,
	})
	return row

func _on_display_mode_selected(index: int) -> void:
	Settings.set_fullscreen(index == 0)
	_resolution_option.disabled = index == 0

func _on_resolution_selected(index: int) -> void:
	Settings.set_window_resolution(Settings.RESOLUTIONS[index])

## Pulls every control's displayed state from the current Settings values
## -- called once on ready, and would need re-calling if something else
## external ever changed Settings while the menu is closed.
func _sync_controls_to_settings() -> void:
	_display_mode_option.selected = 0 if Settings.fullscreen else 1
	_resolution_option.disabled = Settings.fullscreen
	var res_index := Settings.RESOLUTIONS.find(Settings.window_resolution)
	_resolution_option.selected = maxi(res_index, 0)
	_vsync_check.button_pressed = Settings.vsync
	_invert_check.button_pressed = Settings.invert_y

	for entry in _sliders:
		var slider: HSlider = entry["slider"]
		var value_label: Label = entry["value_label"]
		var fmt: String = entry["fmt"]
		var display_value := roundi(Settings.get(entry["property_name"]) * float(entry["display_scale"]))
		slider.set_value_no_signal(display_value)
		value_label.text = fmt % display_value
