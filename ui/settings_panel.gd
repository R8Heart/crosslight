class_name SettingsPanel
extends VBoxContainer

## Self-contained settings screen -- display mode, resolution, render scale,
## FPS cap, vsync, volume, mouse sensitivity, invert-Y, FOV, brightness,
## debug overlay. Reads and writes the Settings autoload directly, so any
## caller can just add one of these as a child instead of rebuilding the
## same ~140 lines (originally lived only in ui/pause_menu.gd; extracted so
## the main menu's settings screen didn't have to duplicate it).
##
## Caller decides what "back" means (show the pause menu's main panel, show
## the main menu's title screen, ...) by connecting `back_pressed`; this
## panel doesn't assume anything about what it's shown inside of, including
## its own starting visibility -- set `.visible` after adding it.
##
## Display mode and resolution changes are risky (a bad resolution can leave
## the player stuck looking at an unusable window with no way to click a
## "back" button). Both go through _begin_display_change() /
## _show_display_confirm(): the new setting is applied immediately so the
## player can see it, then a confirm dialog with a 5s countdown offers to
## keep it or roll back to whatever was active before the change.

signal back_pressed

var _display_mode_option: OptionButton
var _resolution_option: OptionButton
var _fps_cap_option: OptionButton
var _vsync_check: CheckBox
var _invert_check: CheckBox
var _overlay_check: CheckBox
var _sliders: Array[Dictionary] = []

var _display_confirm: ConfirmationDialog
var _display_confirm_timer: Timer
var _display_confirm_seconds := 0
const _DISPLAY_CONFIRM_SECONDS := 5

var _pending_old_fullscreen := true
var _pending_old_resolution := Vector2i(1920, 1080)

func _ready() -> void:
	add_theme_constant_override("separation", 8)
	_build()
	_build_display_confirm()
	_sync_to_settings()

func _build() -> void:
	add_child(_label("НАСТРОЙКИ", true))

	_display_mode_option = OptionButton.new()
	_display_mode_option.add_item("Полноэкранный", 0)
	_display_mode_option.add_item("Оконный", 1)
	_display_mode_option.item_selected.connect(_on_display_mode_selected)
	add_child(_row("Экран", _display_mode_option))

	_resolution_option = OptionButton.new()
	for res in Settings.RESOLUTIONS:
		_resolution_option.add_item("%d x %d" % [res.x, res.y])
	_resolution_option.item_selected.connect(_on_resolution_selected)
	add_child(_row("Разрешение", _resolution_option))

	add_child(_slider_row("Качество рендера", 50, 100, 5, Settings.set_render_scale, "render_scale", 100.0, "%d%%"))

	_fps_cap_option = OptionButton.new()
	for cap in Settings.FPS_CAPS:
		_fps_cap_option.add_item("Без ограничения" if cap == 0 else "%d FPS" % cap)
	_fps_cap_option.item_selected.connect(_on_fps_cap_selected)
	add_child(_row("Ограничение кадров", _fps_cap_option))

	var vsync_check := CheckBox.new()
	vsync_check.text = "Вкл"
	vsync_check.toggled.connect(func(pressed): Settings.set_vsync(pressed))
	add_child(_row("Вертикальная синхронизация", vsync_check))
	_vsync_check = vsync_check

	add_child(_slider_row("Громкость", 0, 100, 5, Settings.set_master_volume, "master_volume", 100.0, "%d%%"))

	add_child(_slider_row("Чувствительность мыши", 20, 300, 10, Settings.set_mouse_sensitivity, "mouse_sensitivity", 100.0, "%d%%"))

	var invert_check := CheckBox.new()
	invert_check.text = "Вкл"
	invert_check.toggled.connect(func(pressed): Settings.set_invert_y(pressed))
	add_child(_row("Инверсия мыши по Y", invert_check))
	_invert_check = invert_check

	add_child(_slider_row("Угол обзора (FOV)", 60, 100, 1, Settings.set_fov, "fov", 1.0, "%d°"))

	add_child(_slider_row("Яркость", 50, 150, 5, Settings.set_brightness, "brightness", 100.0, "%d%%"))

	var overlay_check := CheckBox.new()
	overlay_check.text = "Вкл"
	overlay_check.toggled.connect(func(pressed): Settings.set_show_debug_overlay(pressed))
	add_child(_row("Отладочная статистика", overlay_check))
	_overlay_check = overlay_check

	var back := Button.new()
	back.text = "Назад"
	back.pressed.connect(func(): back_pressed.emit())
	add_child(back)

## Builds the confirm/rollback dialog used for display-mode and resolution
## changes. process_mode is ALWAYS on both the dialog and its timer because
## this panel is also embedded in the pause menu, which pauses the tree --
## the countdown has to keep running even while the game is paused.
func _build_display_confirm() -> void:
	_display_confirm = ConfirmationDialog.new()
	_display_confirm.title = "Настройки экрана"
	_display_confirm.dialog_text = "Применить текущие настройки экрана?"
	_display_confirm.ok_button_text = "Да"
	_display_confirm.process_mode = Node.PROCESS_MODE_ALWAYS
	_display_confirm.confirmed.connect(_on_display_confirm_accepted)
	_display_confirm.canceled.connect(_on_display_confirm_declined)
	add_child(_display_confirm)

	_display_confirm_timer = Timer.new()
	_display_confirm_timer.wait_time = 1.0
	_display_confirm_timer.one_shot = false
	_display_confirm_timer.process_mode = Node.PROCESS_MODE_ALWAYS
	_display_confirm_timer.timeout.connect(_on_display_confirm_tick)
	add_child(_display_confirm_timer)

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

## Builds one HBoxContainer with a label, an HSlider and a value label. See
## the original in ui/pause_menu.gd's history for why setter+property_name
## is passed as plain data rather than a second lambda.
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
	_begin_display_change()
	Settings.set_fullscreen(index == 0)
	_show_display_confirm()

func _on_resolution_selected(index: int) -> void:
	_begin_display_change()
	Settings.set_window_resolution(Settings.RESOLUTIONS[index])
	_show_display_confirm()

func _on_fps_cap_selected(index: int) -> void:
	Settings.set_max_fps(Settings.FPS_CAPS[index])

## Snapshots the pre-change display state, but only if there isn't already
## an unconfirmed change in flight -- if the player flips fullscreen and
## then immediately picks a new resolution before answering the dialog,
## "revert" should still mean "back to how it was before either change",
## not "back to the fullscreen toggle a second ago".
func _begin_display_change() -> void:
	if not _display_confirm.visible:
		_pending_old_fullscreen = Settings.fullscreen
		_pending_old_resolution = Settings.window_resolution

func _show_display_confirm() -> void:
	_display_confirm_seconds = _DISPLAY_CONFIRM_SECONDS
	_display_confirm.get_cancel_button().text = "Нет (%d)" % _display_confirm_seconds
	_display_confirm.popup_centered()
	_display_confirm_timer.start()

func _on_display_confirm_tick() -> void:
	_display_confirm_seconds -= 1
	if _display_confirm_seconds <= 0:
		_display_confirm_timer.stop()
		_display_confirm.hide()
		_revert_display_change()
	else:
		_display_confirm.get_cancel_button().text = "Нет (%d)" % _display_confirm_seconds

func _on_display_confirm_accepted() -> void:
	_display_confirm_timer.stop()

## Fires on explicit "Нет" AND on closing the dialog via Esc/X -- both mean
## "don't keep this", so both roll back.
func _on_display_confirm_declined() -> void:
	_display_confirm_timer.stop()
	_revert_display_change()

func _revert_display_change() -> void:
	Settings.set_fullscreen(_pending_old_fullscreen)
	Settings.set_window_resolution(_pending_old_resolution)
	_sync_to_settings()

## Pulls every control's displayed state from the current Settings values.
## Called once after _build(); call again if this panel could be shown
## after Settings changed elsewhere while it wasn't visible.
func _sync_to_settings() -> void:
	_display_mode_option.selected = 0 if Settings.fullscreen else 1
	var res_index := Settings.RESOLUTIONS.find(Settings.window_resolution)
	_resolution_option.selected = maxi(res_index, 0)
	_vsync_check.button_pressed = Settings.vsync
	_invert_check.button_pressed = Settings.invert_y
	_overlay_check.button_pressed = Settings.show_debug_overlay
	var cap_index := Settings.FPS_CAPS.find(Settings.max_fps)
	_fps_cap_option.selected = maxi(cap_index, 0)

	for entry in _sliders:
		var slider: HSlider = entry["slider"]
		var value_label: Label = entry["value_label"]
		var fmt: String = entry["fmt"]
		var display_value := roundi(Settings.get(entry["property_name"]) * float(entry["display_scale"]))
		slider.set_value_no_signal(display_value)
		value_label.text = fmt % display_value
