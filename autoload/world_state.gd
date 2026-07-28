extends Node

enum World { REAL, OTHERSIDE }

signal world_changed(new_world: World)

var current_world: World = World.REAL

func switch_to(world: World) -> void:
	if world == current_world:
		return
	current_world = world
	world_changed.emit(current_world)

func toggle() -> void:
	switch_to(World.OTHERSIDE if current_world == World.REAL else World.REAL)
