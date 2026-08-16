extends Node3D
class_name FlameEffect

## Drop this under any Light3D (as a child, positioned at the wick/burner
## point) to give it an actual visible flame instead of just casting light
## from empty air. Builds a single small billboard quad with flame.gdshader
## on _ready() -- no per-frame script cost, the flicker/wobble is entirely
## GPU-side in the shader, so this scales to dozens of instances cheaply
## (see tools/attach_flames.gd for the batch pass across existing lights).

@export var flame_height := 0.22
@export var flame_width := 0.1
@export var color_base := Color(1.0, 0.85, 0.35)
@export var color_tip := Color(1.0, 0.32, 0.04)
@export var intensity := 1.5
@export var flicker_speed := 1.8
@export var wobble_amount := 0.15

const FLAME_SHADER := preload("res://assets/shaders/flame.gdshader")

func _ready() -> void:
	var quad := QuadMesh.new()
	quad.size = Vector2(flame_width, flame_height)

	var mat := ShaderMaterial.new()
	mat.shader = FLAME_SHADER
	mat.set_shader_parameter("flame_height", flame_height)
	mat.set_shader_parameter("color_base", color_base)
	mat.set_shader_parameter("color_tip", color_tip)
	mat.set_shader_parameter("intensity", intensity)
	mat.set_shader_parameter("flicker_speed", flicker_speed)
	mat.set_shader_parameter("wobble_amount", wobble_amount)
	# Random per instance so a row of candles doesn't flicker in lockstep.
	mat.set_shader_parameter("time_offset", randf() * 100.0)

	var mesh_instance := MeshInstance3D.new()
	mesh_instance.mesh = quad
	mesh_instance.material_override = mat
	mesh_instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mesh_instance.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
	add_child(mesh_instance)
