extends CanvasLayer

## Drives a virtual mouse cursor from the left stick whenever a gamepad is
## the active input device (see autoload/input_device.gd) AND the game
## isn't in first-person mouse-look (Input.mouse_mode == MOUSE_MODE_CAPTURED,
## set by player.gd during gameplay and released by ui/pause_menu.gd while
## paused) -- which is exactly the menu/UI contexts (main menu, pause menu,
## settings) with zero per-scene wiring needed.
##
## Reuses move_left/move_right/move_forward/move_back for stick input --
## the same actions the player walks with -- since nothing is walking while
## a menu has focus, so the same stick doing double duty as a menu cursor
## is the standard, expected control scheme.
##
## Implementation: rather than reimplementing focus-based navigation across
## every menu (main_menu.gd/settings_panel.gd/pause_menu.gd all use mouse
## hover/press signals, not Control focus traversal), this moves the real
## OS cursor to follow the stick and hides it, drawing a custom sprite in
## its place, and synthesizes real mouse motion/button events so Godot's
## GUI system can't tell the difference from an actual mouse. Every
## existing hover/click/drag handler -- including HSlider dragging in
## ui/settings_panel.gd -- keeps working completely unchanged.

const SPEED := 900.0 ## pixels/sec at full stick deflection
const DEADZONE := 0.15
## Marks every event this class synthesizes so input_device.gd can tell it
## apart from a real mouse and not immediately flip back to keyboard/mouse
## the instant the virtual cursor moves.
const _SYNTHETIC_DEVICE_ID := -2

const _CursorIconScript := preload("res://autoload/gamepad_cursor_icon.gd")

var _cursor: Control
var _pos := Vector2.ZERO
var _active := false

func _ready() -> void:
	layer = 100
	process_mode = Node.PROCESS_MODE_ALWAYS
	_cursor = _CursorIconScript.new()
	_cursor.size = Vector2(56, 56)
	_cursor.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_cursor.visible = false
	add_child(_cursor)

func _process(delta: float) -> void:
	# Checked every frame rather than only on InputDevice.device_changed:
	# mouse_mode can flip (pause menu opening/closing, gameplay starting)
	# without any new input event firing at all.
	var should_be_active := InputDevice.is_gamepad() and Input.mouse_mode != Input.MOUSE_MODE_CAPTURED
	if should_be_active != _active:
		_set_active(should_be_active)
	if not _active:
		return

	var stick := Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	if stick.length() > DEADZONE:
		_move_cursor(stick * SPEED * delta)

	_cursor.position = _pos - _cursor.size * 0.5
	# Set dynamically (not a typed property access) rather than typing
	# _cursor as the icon script's own class_name -- that name is only
	# resolvable once Godot has rescanned global classes, which doesn't
	# reliably happen the moment a brand-new class_name is added.
	_cursor.set("hovering", get_viewport().gui_get_hovered_control() != null)

	# A dedicated action rather than the engine's built-in ui_accept: that
	# one turned out to have no actual gamepad binding in this project
	# (same surprise as ui_cancel not opening the pause menu -- see
	# project.godot's pause_gamepad/gamepad_confirm/gamepad_back entries),
	# so don't trust engine ui_* defaults to already cover a controller.
	if Input.is_action_just_pressed(&"gamepad_confirm"):
		_synthesize_click(true)
	elif Input.is_action_just_released(&"gamepad_confirm"):
		_synthesize_click(false)

func _move_cursor(delta_move: Vector2) -> void:
	var vp_size := get_viewport().get_visible_rect().size
	var new_pos := (_pos + delta_move).clamp(Vector2.ZERO, vp_size)
	delta_move = new_pos - _pos
	_pos = new_pos
	if delta_move == Vector2.ZERO:
		return

	# Actually move the OS cursor -- needed so polling reads like
	# get_viewport().get_mouse_position() (ui/menu_hand_look.gd uses this
	# for its cursor-glance effect) see the right, current value. warp_mouse
	# wants window-relative pixels, not the viewport's own logical
	# coordinate space -- this project stretches that logical space to fit
	# the actual window (project.godot's window/stretch settings), so on
	# anything but a 1:1 window the two differ and warping with the raw
	# logical _pos lands the real cursor somewhere else entirely.
	InputDevice.suppress_mouse_switch()
	Input.warp_mouse(get_viewport().get_screen_transform() * _pos)

	# ...and also feed a real motion event through the GUI pipeline --
	# warp_mouse() deliberately does NOT generate one, but Controls like
	# HSlider track drags by listening for motion events while a button is
	# held, not by polling position, so without this a slider could only
	# ever jump to a click point, never be dragged.
	#
	# push_input() specifically, NOT Input.parse_input_event(): that one
	# updates Input's own global state (is_action_pressed, tracked mouse
	# position) but was the likely reason clicks never reached any button
	# -- push_input() is the call that actually drives a Viewport's GUI
	# dispatch (hover tracking, _gui_input, Button press/release).
	var motion := InputEventMouseMotion.new()
	motion.device = _SYNTHETIC_DEVICE_ID
	motion.position = _pos
	motion.global_position = _pos
	motion.relative = delta_move
	# in_local_coords=true: _pos is already in this viewport's own logical
	# coordinate space (the same space Controls use for their own
	# .position) -- the default false would tell push_input to treat it as
	# raw window/screen coordinates and re-transform it, double-applying
	# the stretch scale on top of what's already correct.
	get_viewport().push_input(motion, true)

func _synthesize_click(pressed: bool) -> void:
	var ev := InputEventMouseButton.new()
	ev.device = _SYNTHETIC_DEVICE_ID
	ev.button_index = MOUSE_BUTTON_LEFT
	ev.pressed = pressed
	ev.position = _pos
	ev.global_position = _pos
	get_viewport().push_input(ev, true)

func _set_active(active: bool) -> void:
	_active = active
	_cursor.visible = active
	if active:
		_pos = get_viewport().get_mouse_position()
		Input.mouse_mode = Input.MOUSE_MODE_HIDDEN
	elif Input.mouse_mode == Input.MOUSE_MODE_HIDDEN:
		# Only restore visibility if mouse_mode is still what WE set it to --
		# if it's already something else (e.g. MOUSE_MODE_CAPTURED because
		# gameplay started), that owner is in charge of it now.
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
