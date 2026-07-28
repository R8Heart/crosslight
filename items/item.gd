extends StaticBody3D

@export_enum("Real", "Otherside") var world: int = 1
@export var item_name: String = "key"

var held := false
var _origin_parent: Node
var _origin_transform: Transform3D

@onready var mesh: MeshInstance3D = $MeshInstance3D
@onready var collision: CollisionShape3D = $CollisionShape3D

func _ready() -> void:
	_origin_parent = get_parent()
	_origin_transform = transform

func interact(player) -> void:
	if held:
		return
	player.pick_up(self)

func on_picked_up(hold_point: Node3D) -> void:
	held = true
	reparent(hold_point, false)
	transform = Transform3D.IDENTITY
	collision.disabled = true

func return_to_origin() -> void:
	held = false
	reparent(_origin_parent, false)
	transform = _origin_transform
	# Reparenting doesn't inherit the layer's disabled state automatically,
	# so re-sync collision to whichever world is active right now.
	collision.disabled = WorldState.current_world != world
