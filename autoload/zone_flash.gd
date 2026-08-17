extends CanvasLayer

## The "eyes adjusting" beat when walking into a lit zone from the dark —
## a brief warm overexposure that eases out, not a hard flashbang.
const FLASH_COLOR := Color(1.0, 0.93, 0.8)
const FLASH_ALPHA := 0.35
const FADE_TIME := 0.45

var _rect: ColorRect

func _ready() -> void:
	layer = 100
	_rect = ColorRect.new()
	_rect.color = FLASH_COLOR
	_rect.color.a = 0.0
	_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_rect)
	ZoneManager.zone_entered.connect(_on_zone_entered)

func _on_zone_entered(_zone_id: StringName, flash: bool) -> void:
	if not flash:
		return
	_rect.color.a = FLASH_ALPHA
	var tween := create_tween()
	tween.tween_property(_rect, "color:a", 0.0, FADE_TIME) \
		.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_SINE)
