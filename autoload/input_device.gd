extends Node

## Tracks which input device family is currently "active" -- keyboard/mouse
## or gamepad -- based on whichever one last produced real input, and lets
## UI adapt to it (see action_glyph() below, used by player.gd's interact
## hint). Switching is automatic and instant: the moment either device
## produces a real event, it becomes active. No per-scene wiring needed --
## this is an autoload, so it sees every event regardless of what scene is
## loaded.
##
## Gamepad support itself (the actual left-stick-move / right-stick-look /
## button bindings) lives entirely in project.godot's Input Map -- nothing
## here does any of that. This singleton only answers "which device is the
## player using right now" and "what should I print on screen for this
## action on that device".

signal device_changed(is_gamepad: bool)

enum Device { KEYBOARD_MOUSE, GAMEPAD }
enum Layout { XBOX, PLAYSTATION }

var current: Device = Device.KEYBOARD_MOUSE
## Which physical controller last produced input, so button glyphs can
## reflect its actual layout (Xbox vs PlayStation face-button names).
var active_joypad_id := 0

## Only these two axes count as "the player nudged a stick" for device-
## switching purposes -- trigger axes (JOY_AXIS_TRIGGER_LEFT/RIGHT) rest at
## -1.0 on some drivers rather than 0.0, which would otherwise make an
## untouched controller look "active" the instant it's plugged in.
const _STICK_AXES := [JOY_AXIS_LEFT_X, JOY_AXIS_LEFT_Y, JOY_AXIS_RIGHT_X, JOY_AXIS_RIGHT_Y]
const _STICK_DEADZONE := 0.2

const _XBOX_NAMES := {
	JOY_BUTTON_A: "A", JOY_BUTTON_B: "B", JOY_BUTTON_X: "X", JOY_BUTTON_Y: "Y",
	JOY_BUTTON_LEFT_SHOULDER: "LB", JOY_BUTTON_RIGHT_SHOULDER: "RB",
	JOY_BUTTON_LEFT_STICK: "L3", JOY_BUTTON_RIGHT_STICK: "R3",
	JOY_BUTTON_START: "Menu", JOY_BUTTON_BACK: "View",
	JOY_BUTTON_DPAD_UP: "D-Up", JOY_BUTTON_DPAD_DOWN: "D-Down",
	JOY_BUTTON_DPAD_LEFT: "D-Left", JOY_BUTTON_DPAD_RIGHT: "D-Right",
}
const _PLAYSTATION_NAMES := {
	JOY_BUTTON_A: "Крест", JOY_BUTTON_B: "Круг", JOY_BUTTON_X: "Квадрат", JOY_BUTTON_Y: "Треугольник",
	JOY_BUTTON_LEFT_SHOULDER: "L1", JOY_BUTTON_RIGHT_SHOULDER: "R1",
	JOY_BUTTON_LEFT_STICK: "L3", JOY_BUTTON_RIGHT_STICK: "R3",
	JOY_BUTTON_START: "Options", JOY_BUTTON_BACK: "Share",
	JOY_BUTTON_DPAD_UP: "D-Up", JOY_BUTTON_DPAD_DOWN: "D-Down",
	JOY_BUTTON_DPAD_LEFT: "D-Left", JOY_BUTTON_DPAD_RIGHT: "D-Right",
}

## While GamepadCursor is warping the OS cursor to follow the stick, mouse
## events arriving until this timestamp are ignored for device-switching
## purposes -- see suppress_mouse_switch() below for why this needs to be a
## time window rather than just checking the synthetic event's own device
## id: warp_mouse() can make some backends echo back a REAL, normal-device
## InputEventMouseMotion as a side effect, and without this that would flip
## us right back to keyboard/mouse the instant the cursor moved, fighting
## the stick for control every single frame.
var _suppress_mouse_until_msec := 0

func _input(event: InputEvent) -> void:
	if event is InputEventJoypadButton:
		_set_device(Device.GAMEPAD, event.device)
	elif event is InputEventJoypadMotion:
		var motion := event as InputEventJoypadMotion
		if motion.axis in _STICK_AXES and absf(motion.axis_value) > _STICK_DEADZONE:
			_set_device(Device.GAMEPAD, event.device)
	elif event is InputEventKey:
		_set_device(Device.KEYBOARD_MOUSE)
	elif event is InputEventMouseButton or event is InputEventMouseMotion:
		if event.device != -2 and Time.get_ticks_msec() >= _suppress_mouse_until_msec:
			_set_device(Device.KEYBOARD_MOUSE)

## Called by GamepadCursor right before it warps the OS cursor each frame it
## moves. duration_msec only needs to cover a frame or two of echo, not the
## whole time the cursor is active -- once the player actually lets go of
## the stick and picks up the real mouse, warping stops and this window
## lapses almost immediately, so genuine mouse input still switches us back
## correctly.
func suppress_mouse_switch(duration_msec := 150) -> void:
	_suppress_mouse_until_msec = Time.get_ticks_msec() + duration_msec

func _set_device(device: Device, joypad_id := -1) -> void:
	if joypad_id >= 0:
		active_joypad_id = joypad_id
	if device != current:
		current = device
		device_changed.emit(current == Device.GAMEPAD)

func is_gamepad() -> bool:
	return current == Device.GAMEPAD

## Best-effort guess at controller family for button-glyph purposes --
## Godot has no universal "give me the brand" API, so this pattern-matches
## the OS-reported controller name. Falls back to Xbox-style naming
## (A/B/X/Y), the most broadly recognized regardless of what's actually in
## someone's hands.
func layout() -> Layout:
	var joy_name := Input.get_joy_name(active_joypad_id).to_lower()
	if "sony" in joy_name or "playstation" in joy_name or "dualshock" in joy_name or "dualsense" in joy_name:
		return Layout.PLAYSTATION
	return Layout.XBOX

## Short label for whatever's currently bound to `action` on the active
## device -- "E", "X", "ЛКМ", etc. Picks the first matching-device event
## in the action's binding list, so if an action is ever bound to more than
## one key/button on the same device, whichever was added first wins.
func action_glyph(action: StringName) -> String:
	for event: InputEvent in InputMap.action_get_events(action):
		if is_gamepad():
			if event is InputEventJoypadButton:
				var joy_button := event as InputEventJoypadButton
				return _button_name(joy_button.button_index)
		else:
			if event is InputEventKey:
				var key_event := event as InputEventKey
				var keycode := DisplayServer.keyboard_get_keycode_from_physical(key_event.physical_keycode)
				return OS.get_keycode_string(keycode)
			elif event is InputEventMouseButton:
				var mouse_event := event as InputEventMouseButton
				return _mouse_button_name(mouse_event.button_index)
	return "?"

func _button_name(button_index: int) -> String:
	var table := _PLAYSTATION_NAMES if layout() == Layout.PLAYSTATION else _XBOX_NAMES
	var found: String = table.get(button_index, "Btn%d" % button_index)
	return found

func _mouse_button_name(button_index: int) -> String:
	match button_index:
		MOUSE_BUTTON_LEFT: return "ЛКМ"
		MOUSE_BUTTON_RIGHT: return "ПКМ"
		MOUSE_BUTTON_MIDDLE: return "СКМ"
		_: return "Mouse%d" % button_index
