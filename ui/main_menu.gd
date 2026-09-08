extends Control

## Builds the main menu's left-side item list in code (same self-building
## pattern as ui/pause_menu.gd) and wires each item to what it actually
## does. Attach this to the MainMenu root -- it adds the list as a sibling
## of whatever 3D backdrop/fog nodes are already there in the scene.
##
## Deliberately not a VBoxContainer: a Container re-asserts its children's
## position on every layout pass, which fights a Tween trying to slide a
## button sideways on hover. Each item's vertical position is just set
## once at build time instead.

## Font comes from the project-wide default (Project Settings -> General ->
## Gui -> Theme -> Custom Font, set to Cormorant Garamond) rather than a
## per-widget override -- Cinzel was tried first but turned out to have no
## Cyrillic glyphs at all, confirmed via fontTools, so every letter of the
## Russian menu text was silently falling back to Godot's built-in font;
## easier to fix that once project-wide than per node.
const SettingsPanelScript := preload("res://ui/settings_panel.gd")
const SceneLoaderScript := preload("res://ui/scene_loader.gd")
const VignetteShader := preload("res://assets/shaders/vignette.gdshader")

const ITEMS := ["Новая игра", "Настройки", "Выйти"]
const ITEM_FONT_SIZE := 32
const ITEM_SPACING := 64.0
const LIST_LEFT_MARGIN := 110.0

## Cool, slightly desaturated off-white at rest; warms up to the lantern's
## own amber on hover so the highlighted item reads as "caught the light".
const NORMAL_COLOR := Color(0.80, 0.83, 0.78, 0.88)
const HOVER_COLOR := Color(1.0, 0.82, 0.5, 1.0)
const OUTLINE_COLOR := Color(0.0, 0.0, 0.0, 0.55)

const HOVER_SHIFT := 26.0
const HOVER_SCALE := 1.1
const ANIM_TIME := 0.22

var _list_root: Control
var _settings_panel: SettingsPanel
var _item_tweens: Dictionary = {}

func _ready() -> void:
	_build_vignette()
	_build_list()
	_list_root.modulate.a = 0.0

	var hand := get_node("ViewportBackground/SubViewport/handAnchor") as MenuHandLook
	hand.play_intro()

	var tw := create_tween()
	tw.tween_property(_list_root, "modulate:a", 1.0, 1.2)

## A wider-than-authored screen (ultrawide monitors especially) reveals more
## of the 3D backdrop's frustum at the edges than this scene was framed
## for -- the hand model's mesh boundary and the fog quads' own edges are
## only ever meant to be seen cropped by the frame, not head-on. Rather
## than chase every possible aspect ratio by hand, darken the screen edges
## so nothing hard-edged is visible out there regardless of screen shape.
func _build_vignette() -> void:
	var vignette := ColorRect.new()
	vignette.set_anchors_preset(Control.PRESET_FULL_RECT)
	vignette.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vignette.material = ShaderMaterial.new()
	vignette.material.shader = VignetteShader
	add_child(vignette)

## ---------------------------------------------------------------------
## List construction
## ---------------------------------------------------------------------

func _build_list() -> void:
	_list_root = Control.new()
	_list_root.set_anchors_preset(Control.PRESET_CENTER_LEFT)
	_list_root.position = Vector2(LIST_LEFT_MARGIN, -ITEM_SPACING * (ITEMS.size() - 1) / 2.0)
	_list_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_list_root)

	var actions := [_on_new_game, _on_settings, _on_quit]
	for i in ITEMS.size():
		_add_item(ITEMS[i], i * ITEM_SPACING, actions[i])

func _add_item(text: String, y: float, action: Callable) -> void:
	var btn := Button.new()
	btn.text = text
	btn.flat = true
	btn.focus_mode = Control.FOCUS_NONE
	btn.mouse_filter = Control.MOUSE_FILTER_STOP
	btn.position = Vector2(0, y)
	btn.pivot_offset = Vector2(0, ITEM_FONT_SIZE * 0.7)

	btn.add_theme_font_size_override("font_size", ITEM_FONT_SIZE)
	btn.add_theme_color_override("font_color", NORMAL_COLOR)
	btn.add_theme_color_override("font_hover_color", NORMAL_COLOR)
	btn.add_theme_color_override("font_pressed_color", HOVER_COLOR)
	btn.add_theme_color_override("font_focus_color", NORMAL_COLOR)
	btn.add_theme_color_override("font_outline_color", OUTLINE_COLOR)
	btn.add_theme_constant_override("outline_size", 6)

	btn.pressed.connect(action)
	btn.mouse_entered.connect(func(): _animate_item(btn, true))
	btn.mouse_exited.connect(func(): _animate_item(btn, false))
	_list_root.add_child(btn)

## Highlight + slide-right + scale-up on hover, all in one tween so they
## read as a single reaction rather than three separate ones landing at
## slightly different times.
func _animate_item(btn: Button, hovered: bool) -> void:
	var old: Tween = _item_tweens.get(btn)
	if old and old.is_valid():
		old.kill()

	var tw := create_tween().set_parallel(true).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	_item_tweens[btn] = tw

	var target_color := HOVER_COLOR if hovered else NORMAL_COLOR
	var target_scale := Vector2.ONE * (HOVER_SCALE if hovered else 1.0)
	var target_x := HOVER_SHIFT if hovered else 0.0

	tw.tween_property(btn, "theme_override_colors/font_color", target_color, ANIM_TIME)
	tw.tween_property(btn, "scale", target_scale, ANIM_TIME)
	tw.tween_property(btn, "position:x", target_x, ANIM_TIME)

## ---------------------------------------------------------------------
## Actions
## ---------------------------------------------------------------------

func _on_new_game() -> void:
	var loader: Node = SceneLoaderScript.new()
	get_tree().root.add_child(loader)
	loader.load_scene("res://rooms/estate_exterior.scn")

func _on_settings() -> void:
	if _settings_panel == null:
		_settings_panel = SettingsPanelScript.new()
		_settings_panel.set_anchors_preset(Control.PRESET_CENTER_LEFT)
		_settings_panel.position = Vector2(LIST_LEFT_MARGIN, -220.0)
		_settings_panel.custom_minimum_size = Vector2(420, 0)
		_settings_panel.back_pressed.connect(_show_list)
		add_child(_settings_panel)
	_list_root.visible = false
	_settings_panel.visible = true

func _show_list() -> void:
	_settings_panel.visible = false
	_list_root.visible = true

func _on_quit() -> void:
	get_tree().quit()
