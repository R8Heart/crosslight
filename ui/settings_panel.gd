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
var _aa_method_option: OptionButton
var _shadow_filter_option: OptionButton
var _shadows_check: CheckBox
var _moon_shadow_mode_option: OptionButton
var _glow_check: CheckBox
var _fog_check: CheckBox
var _sliders: Array[Dictionary] = []
var _warmup_overlay: CanvasLayer
var _apply_graphics_button: Button
## True while _sync_to_settings() is pushing values onto controls -- guards
## _apply_pipeline_setting() against firing from that programmatic write
## instead of an actual user click/toggle. HSlider has set_value_no_signal()
## for exactly this; OptionButton/CheckBox don't, so this flag is the
## equivalent for them.
var _syncing := false

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
	add_child(_build_presets_row())

	var tabs := TabContainer.new()
	tabs.size_flags_vertical = Control.SIZE_EXPAND_FILL
	tabs.custom_minimum_size = Vector2(0, 260)
	add_child(tabs)

	tabs.add_child(_build_display_tab())
	tabs.add_child(_build_graphics_tab())
	tabs.add_child(_build_lighting_tab())
	tabs.add_child(_build_effects_tab())
	tabs.add_child(_build_controls_tab())
	tabs.add_child(_build_audio_tab())

	var bottom_row := HBoxContainer.new()
	bottom_row.alignment = BoxContainer.ALIGNMENT_CENTER
	bottom_row.add_theme_constant_override("separation", 8)

	# Lives next to "Назад" rather than the graphics presets row -- it's
	# about leaving the screen with everything actually warmed, not about
	# picking a preset.
	_apply_graphics_button = Button.new()
	_apply_graphics_button.text = "Применить графику"
	_apply_graphics_button.visible = false
	_apply_graphics_button.pressed.connect(_run_live_warmup)
	bottom_row.add_child(_apply_graphics_button)

	var back := Button.new()
	back.text = "Назад"
	back.pressed.connect(func(): back_pressed.emit())
	bottom_row.add_child(back)

	add_child(bottom_row)

## One button per Settings.Preset -- applies a whole bundle of graphics
## settings at once for players who'd rather not tune each one by hand, then
## re-syncs every control so the tabs immediately reflect what the preset
## actually set (a slider left showing a stale value after a preset button
## is exactly the kind of thing that reads as broken).
func _build_presets_row() -> HBoxContainer:
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 8)
	row.add_child(_label("Пресет графики:"))
	var presets := [["Низкое", Settings.Preset.LOW], ["Среднее", Settings.Preset.MEDIUM], ["Высокое", Settings.Preset.HIGH]]
	for entry in presets:
		var btn := Button.new()
		btn.text = entry[0]
		var preset_value = entry[1]
		btn.pressed.connect(func():
			_apply_pipeline_setting(func(): Settings.apply_preset(preset_value))
			_sync_to_settings())
		row.add_child(btn)
	return row

func _build_display_tab() -> VBoxContainer:
	var tab := VBoxContainer.new()
	tab.name = "Экран"
	tab.add_theme_constant_override("separation", 8)

	_display_mode_option = OptionButton.new()
	_display_mode_option.add_item("Полноэкранный", 0)
	_display_mode_option.add_item("Оконный", 1)
	_display_mode_option.item_selected.connect(_on_display_mode_selected)
	tab.add_child(_row("Экран", _display_mode_option))

	_resolution_option = OptionButton.new()
	for res in Settings.RESOLUTIONS:
		_resolution_option.add_item("%d x %d" % [res.x, res.y])
	_resolution_option.item_selected.connect(_on_resolution_selected)
	tab.add_child(_row("Разрешение", _resolution_option))

	_fps_cap_option = OptionButton.new()
	for cap in Settings.FPS_CAPS:
		_fps_cap_option.add_item("Без ограничения" if cap == 0 else "%d FPS" % cap)
	_fps_cap_option.item_selected.connect(_on_fps_cap_selected)
	tab.add_child(_row("Ограничение кадров", _fps_cap_option))

	var vsync_check := CheckBox.new()
	vsync_check.text = "Вкл"
	vsync_check.toggled.connect(func(pressed): Settings.set_vsync(pressed))
	tab.add_child(_row("Вертикальная синхронизация", vsync_check))
	_vsync_check = vsync_check

	return tab

func _build_graphics_tab() -> VBoxContainer:
	var tab := VBoxContainer.new()
	tab.name = "Графика"
	tab.add_theme_constant_override("separation", 8)

	tab.add_child(_slider_row("Качество рендера", 50, 100, 5, Settings.set_render_scale, "render_scale", 100.0, "%d%%"))

	# One choice, not three independent toggles -- MSAA+FXAA+TAA can all be
	# switched on together (Godot allows it) but it's wasted GPU cost: FXAA
	# blurs the frame after MSAA already resolved it, throwing away exactly
	# what MSAA paid for.
	_aa_method_option = OptionButton.new()
	_aa_method_option.add_item("Выкл", Settings.AAMethod.NONE)
	_aa_method_option.add_item("FXAA", Settings.AAMethod.FXAA)
	_aa_method_option.add_item("MSAA 2x", Settings.AAMethod.MSAA_2X)
	_aa_method_option.add_item("MSAA 4x", Settings.AAMethod.MSAA_4X)
	_aa_method_option.add_item("TAA", Settings.AAMethod.TAA)
	_aa_method_option.item_selected.connect(func(i): _apply_pipeline_setting(func(): Settings.set_aa_method(i)))
	tab.add_child(_row("Сглаживание", _aa_method_option))

	tab.add_child(_slider_row("Яркость", 50, 150, 5, Settings.set_brightness, "brightness", 100.0, "%d%%"))

	var overlay_check := CheckBox.new()
	overlay_check.text = "Вкл"
	overlay_check.toggled.connect(func(pressed): Settings.set_show_debug_overlay(pressed))
	tab.add_child(_row("Отладочная статистика", overlay_check))
	_overlay_check = overlay_check

	return tab

func _build_lighting_tab() -> VBoxContainer:
	var tab := VBoxContainer.new()
	tab.name = "Свет и тени"
	tab.add_theme_constant_override("separation", 8)

	var shadows_check := CheckBox.new()
	shadows_check.text = "Вкл"
	shadows_check.toggled.connect(func(pressed): _apply_pipeline_setting(func(): Settings.set_shadows_enabled(pressed)))
	tab.add_child(_row("Тени", shadows_check))
	_shadows_check = shadows_check

	_shadow_filter_option = OptionButton.new()
	for label in ["Жёсткие (быстро)", "Мягкие: очень низкое", "Мягкие: низкое", "Мягкие: среднее", "Мягкие: высокое"]:
		_shadow_filter_option.add_item(label)
	_shadow_filter_option.item_selected.connect(func(i): _apply_pipeline_setting(func(): Settings.set_shadow_filter_quality(i)))
	tab.add_child(_row("Качество теней", _shadow_filter_option))

	_moon_shadow_mode_option = OptionButton.new()
	_moon_shadow_mode_option.add_item("Простой (быстро)", 0)
	_moon_shadow_mode_option.add_item("PSSM 2 (средне)", 1)
	_moon_shadow_mode_option.add_item("PSSM 4 (качественно)", 2)
	_moon_shadow_mode_option.item_selected.connect(func(i): _apply_pipeline_setting(func(): Settings.set_moon_shadow_mode(i)))
	tab.add_child(_row("Тень лунного света", _moon_shadow_mode_option))

	tab.add_child(_slider_row("Дальность тени луны", 20, 300, 10, Settings.set_moon_shadow_max_distance, "moon_shadow_max_distance", 1.0, "%d м"))

	var glow_check := CheckBox.new()
	glow_check.text = "Вкл"
	glow_check.toggled.connect(func(pressed): Settings.set_glow_enabled(pressed))
	tab.add_child(_row("Свечение (Glow)", glow_check))
	_glow_check = glow_check

	return tab

func _build_effects_tab() -> VBoxContainer:
	var tab := VBoxContainer.new()
	tab.name = "Эффекты"
	tab.add_theme_constant_override("separation", 8)

	var fog_check := CheckBox.new()
	fog_check.text = "Вкл"
	fog_check.toggled.connect(func(pressed): Settings.set_volumetric_fog_enabled(pressed))
	tab.add_child(_row("Объёмный туман", fog_check))
	_fog_check = fog_check

	tab.add_child(_slider_row("Плотность частиц", 25, 100, 5, Settings.set_particle_density, "particle_density", 100.0, "%d%%"))

	return tab

func _build_controls_tab() -> VBoxContainer:
	var tab := VBoxContainer.new()
	tab.name = "Управление"
	tab.add_theme_constant_override("separation", 8)

	tab.add_child(_slider_row("Чувствительность мыши", 20, 300, 10, Settings.set_mouse_sensitivity, "mouse_sensitivity", 100.0, "%d%%"))

	var invert_check := CheckBox.new()
	invert_check.text = "Вкл"
	invert_check.toggled.connect(func(pressed): Settings.set_invert_y(pressed))
	tab.add_child(_row("Инверсия мыши по Y", invert_check))
	_invert_check = invert_check

	tab.add_child(_slider_row("Угол обзора (FOV)", 60, 100, 1, Settings.set_fov, "fov", 1.0, "%d°"))

	return tab

func _build_audio_tab() -> VBoxContainer:
	var tab := VBoxContainer.new()
	tab.name = "Звук"
	tab.add_theme_constant_override("separation", 8)

	tab.add_child(_slider_row("Громкость", 0, 100, 5, Settings.set_master_volume, "master_volume", 100.0, "%d%%"))

	return tab

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
	_syncing = true
	_display_mode_option.selected = 0 if Settings.fullscreen else 1
	var res_index := Settings.RESOLUTIONS.find(Settings.window_resolution)
	_resolution_option.selected = maxi(res_index, 0)
	_vsync_check.button_pressed = Settings.vsync
	_invert_check.button_pressed = Settings.invert_y
	_overlay_check.button_pressed = Settings.show_debug_overlay
	var cap_index := Settings.FPS_CAPS.find(Settings.max_fps)
	_fps_cap_option.selected = maxi(cap_index, 0)

	_aa_method_option.selected = Settings.aa_method
	_shadow_filter_option.selected = Settings.shadow_filter_quality
	_shadows_check.button_pressed = Settings.shadows_enabled
	_moon_shadow_mode_option.selected = Settings.moon_shadow_mode
	_glow_check.button_pressed = Settings.glow_enabled
	_fog_check.button_pressed = Settings.volumetric_fog_enabled

	for entry in _sliders:
		var slider: HSlider = entry["slider"]
		var value_label: Label = entry["value_label"]
		var fmt: String = entry["fmt"]
		var display_value := roundi(Settings.get(entry["property_name"]) * float(entry["display_scale"]))
		slider.set_value_no_signal(display_value)
		value_label.text = fmt % display_value
	_syncing = false
	_update_apply_button()

## MSAA/TAA/FXAA/shadow-filter/shadow-mode changes can each force the
## renderer to compile pipeline variants it's never needed before -- but
## running the (multi-second) re-warm after every single click here made
## trying a few of these back to back miserable. So: the setting itself
## applies immediately (cheap, live preview, no reason to hold that back),
## and only the actual warmup pass is deferred to an explicit "Применить
## графику" button (_build_presets_row) that appears while anything's
## pending -- one pass covers however many of these got changed in a row.
func _apply_pipeline_setting(setter: Callable) -> void:
	if _syncing:
		return
	setter.call()
	_update_apply_button()

func _update_apply_button() -> void:
	if _apply_graphics_button:
		_apply_graphics_button.visible = ShaderWarmup.needs_warmup()

func _run_live_warmup() -> void:
	if _warmup_overlay != null:
		return
	_warmup_overlay = CanvasLayer.new()
	_warmup_overlay.layer = 100
	get_tree().root.add_child(_warmup_overlay)

	var bg := ColorRect.new()
	bg.color = Color(0, 0, 0, 0.85)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_STOP
	_warmup_overlay.add_child(bg)

	var box := VBoxContainer.new()
	box.set_anchors_preset(Control.PRESET_CENTER)
	box.custom_minimum_size = Vector2(420, 0)
	box.position -= Vector2(210, 30)
	box.add_theme_constant_override("separation", 10)
	_warmup_overlay.add_child(box)

	var title := Label.new()
	title.text = "Обновление графики..."
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 18)
	title.add_theme_color_override("font_color", Color(0.85, 0.85, 0.85))
	box.add_child(title)

	var bar := ProgressBar.new()
	bar.min_value = 0
	bar.max_value = 1
	bar.show_percentage = false
	bar.custom_minimum_size = Vector2(0, 16)
	box.add_child(bar)

	var status := Label.new()
	status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	status.add_theme_font_size_override("font_size", 12)
	status.add_theme_color_override("font_color", Color(0.55, 0.55, 0.55))
	box.add_child(status)

	var on_progress := func(current: int, total: int, room_name: String):
		bar.max_value = total
		bar.value = current
		status.text = "%d / %d -- %s" % [current, total, room_name]
	ShaderWarmup.progress.connect(on_progress)

	ShaderWarmup.run()
	await ShaderWarmup.finished

	ShaderWarmup.progress.disconnect(on_progress)
	_warmup_overlay.queue_free()
	_warmup_overlay = null
	_update_apply_button()
