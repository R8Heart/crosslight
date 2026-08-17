extends Area3D
class_name ZoneTrigger

## Drop one of these in each room (a box covering its floor is enough,
## doesn't need to hug the doorway precisely) and set zone_id to match
## the Group name the room's content is tagged with.
@export var zone_id: StringName = &""
## Set false for zones you're leaving into darkness (e.g. stepping back
## outside) — the flash is for arriving into light, not departing it.
@export var flash_on_enter := true

func _ready() -> void:
	add_to_group(&"zone_triggers")
	body_entered.connect(_on_body_entered)

func _on_body_entered(body: Node3D) -> void:
	if zone_id != &"" and body.is_in_group(&"player"):
		ZoneManager.enter_zone(zone_id, flash_on_enter)
