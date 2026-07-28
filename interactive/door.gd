extends StaticBody3D

@export var requires_item_name: String = "key"

var is_open := false

@onready var mesh: MeshInstance3D = $MeshInstance3D
@onready var collision: CollisionShape3D = $CollisionShape3D

func _ready() -> void:
	# Deferred so this runs *after* the parent layer's WorldBound reapplies
	# visibility/collision on the same world_changed signal, otherwise an
	# already-open door would be reset to "closed" every time you switch back.
	WorldState.world_changed.connect(_on_world_changed, CONNECT_DEFERRED)

func interact(player) -> void:
	if is_open:
		return
	if player.held_item and player.held_item.item_name == requires_item_name:
		_open()
	else:
		print("Дверь заперта. Нужен ключ.")

func _open() -> void:
	is_open = true
	collision.disabled = true
	mesh.visible = false
	print("Дверь открыта.")

func _on_world_changed(_new_world) -> void:
	if is_open:
		collision.disabled = true
		mesh.visible = false
