extends Node

## Rooms register their content by adding the room's root node to a Group
## named after the zone (e.g. "hall", "living_room"). ZoneTrigger areas
## placed in each room announce entry; this just flips visibility for the
## previous/new zone's group members, which is enough to stop Godot from
## computing lighting/shadows for anything the player can't currently see.

signal zone_entered(zone_id: StringName, flash: bool)

var current_zone: StringName = &""

func _ready() -> void:
	await get_tree().process_frame
	var known_zones: Dictionary = {}
	for trigger in get_tree().get_nodes_in_group(&"zone_triggers"):
		known_zones[trigger.zone_id] = true
	for zone_id in known_zones:
		_set_zone_visible(zone_id, false)

func enter_zone(zone_id: StringName, flash: bool = true) -> void:
	if zone_id == current_zone or zone_id == &"":
		return
	var previous := current_zone
	current_zone = zone_id
	if previous != &"":
		_set_zone_visible(previous, false)
	_set_zone_visible(zone_id, true)
	zone_entered.emit(zone_id, flash)

func _set_zone_visible(zone_id: StringName, should_be_visible: bool) -> void:
	for node in get_tree().get_nodes_in_group(zone_id):
		if node is Node3D:
			node.visible = should_be_visible
