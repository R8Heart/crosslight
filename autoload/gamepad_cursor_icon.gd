extends Control

## Reticle for autoload/gamepad_cursor.gd. Draws assets/textures/ui/
## gamepad_cursor.png if it exists, in the same warm lantern tone as the
## menu's hover highlight (ui/main_menu.gd's HOVER_COLOR); falls back to a
## plain procedural placeholder otherwise so the cursor still works before
## that file exists.
##
## Brightens and pulls in slightly whenever something interactive is under
## it (see `hovering` below) -- the same kind of feedback a real mouse
## cursor lacks but games with a virtual pointer usually add, so it's
## obvious the thing under the stick is actually clickable.

const _TEXTURE_PATH := "res://assets/textures/ui/gamepad_cursor.png"
const _BASE := Color(1.0, 0.72, 0.35, 1.0)
const _GLOW := Color(1.0, 0.55, 0.15, 1.0)

var hovering := false:
	set(value):
		if hovering == value:
			return
		hovering = value
		queue_redraw()

var _texture: Texture2D

func _ready() -> void:
	if ResourceLoader.exists(_TEXTURE_PATH):
		_texture = load(_TEXTURE_PATH)

func _draw() -> void:
	if _texture:
		_draw_textured()
	else:
		_draw_procedural()

func _draw_textured() -> void:
	var scale_mult: float = 1.15 if hovering else 1.0
	var draw_size := size * scale_mult
	var offset := (size - draw_size) * 0.5
	# Values above 1.0 are a valid, common way to brighten a draw call past
	# its plain albedo without needing a second bright-variant image.
	var tint: Color = Color(1.3, 1.22, 1.05, 1.0) if hovering else Color(1, 1, 1, 1)
	draw_texture_rect(_texture, Rect2(offset, draw_size), false, tint)

func _draw_procedural() -> void:
	var center := size * 0.5
	var pulse: float = 1.15 if hovering else 1.0
	var glow_boost: float = 1.6 if hovering else 1.0

	# Soft outer halo -- a handful of fading circles standing in for a
	# blurred glow, since Control._draw() has no blur filter of its own.
	for i in range(5, 0, -1):
		var r: float = (3.0 + i * 2.0) * pulse
		var a: float = 0.05 * i * glow_boost
		draw_circle(center, r, Color(_GLOW.r, _GLOW.g, _GLOW.b, a))

	# Bright core.
	draw_circle(center, 2.5 * pulse, _BASE)
	draw_arc(center, 2.5 * pulse, 0.0, TAU, 16, Color(1, 1, 1, 0.85), 1.0, true)

	# Four corner ticks, camera-focus-reticle style -- pull in slightly
	# tighter around the core when hovering, like the reticle "grabbing"
	# whatever's underneath it.
	var inner: float = (10.0 if hovering else 11.0) * pulse
	var outer: float = inner + 4.0
	for i in 4:
		var dir := Vector2.RIGHT.rotated(i * PI / 2.0 + PI / 4.0)
		draw_line(center + dir * inner, center + dir * outer, _BASE, 2.0)
