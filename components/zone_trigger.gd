extends Area3D
class_name ZoneTrigger

## Fires when the player physically walks into this zone. Put one of these
## per room (a box over the floor is enough); its zone_id must match the
## Group name the room's Light3D nodes are tagged with.
##
## Doors leading into a zone are NOT wired here -- a door usually lives in
## a different scene file than the room's own trigger (e.g. the living
## room's entrance door is built into first_floor.tscn's wall), so a
## NodePath authored in one can't reach a node saved in the other. Instead
## each SwingDoor declares its own `reveals_zone` export and tells
## ZoneManager directly when it opens.
@export var zone_id: StringName = &""

func _ready() -> void:
	add_to_group(&"zone_triggers")
	body_entered.connect(_on_body_entered)

	# Area3D only signals bodies that enter *after* it starts monitoring --
	# the player spawning already inside their starting room never fires
	# body_entered at all.
	await get_tree().physics_frame
	for body in get_overlapping_bodies():
		if body.is_in_group(&"player"):
			print("[ZONE] trigger %s (zone_id='%s') -- player already overlapping at start" % [get_path(), zone_id])
			ZoneManager.enter_zone(zone_id)

func _on_body_entered(body: Node3D) -> void:
	if zone_id != &"" and body.is_in_group(&"player"):
		print("[ZONE] trigger %s (zone_id='%s') -- body_entered" % [get_path(), zone_id])
		ZoneManager.enter_zone(zone_id)
