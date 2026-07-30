extends Node3D

## The glowing orb held in the player's hand. Replaces the torch entirely —
## a glass-look sphere (orb_glass.gdshader: real screen refraction + fresnel
## rim + specular highlights, not just a transparent+emissive material) with
## an inner light, recoloring between Real (warm orange) and Otherside
## (green) on world switch, same trigger as the old torch (`toggle_torch`
## input action, see player.gd).

const REAL_LIGHT := Color(1.0, 0.55, 0.15)
const REAL_CORE := Color(1.0, 0.85, 0.5)
const REAL_MID := Color(1.0, 0.55, 0.15)
const REAL_RIM := Color(1.0, 0.4, 0.05)

const OTHER_LIGHT := Color(0.25, 1.0, 0.45)
const OTHER_CORE := Color(0.75, 1.0, 0.8)
const OTHER_MID := Color(0.3, 1.0, 0.5)
const OTHER_RIM := Color(0.05, 0.8, 0.3)

const BASE_LIGHT_ENERGY := 1.055
const FLICKER_AMOUNT := 0.2
const FLICKER_SPEED := 3.0

@onready var glass: MeshInstance3D = $Glass
@onready var light: OmniLight3D = $OrbLight

var _noise := FastNoiseLite.new()
var _glass_mat: ShaderMaterial

func _ready() -> void:
	_noise.frequency = 1.5
	_glass_mat = glass.get_surface_override_material(0) as ShaderMaterial

	WorldState.world_changed.connect(_on_world_changed)
	_apply(WorldState.current_world)

func _process(_delta: float) -> void:
	var t := Time.get_ticks_msec() / 1000.0
	light.light_energy = BASE_LIGHT_ENERGY + _noise.get_noise_1d(t * FLICKER_SPEED) * FLICKER_AMOUNT

func _on_world_changed(new_world) -> void:
	_apply(new_world)

func _apply(world) -> void:
	var is_real: bool = world == WorldState.World.REAL

	light.light_color = REAL_LIGHT if is_real else OTHER_LIGHT

	if _glass_mat:
		_glass_mat.set_shader_parameter("color_core", REAL_CORE if is_real else OTHER_CORE)
		_glass_mat.set_shader_parameter("color_mid", REAL_MID if is_real else OTHER_MID)
		_glass_mat.set_shader_parameter("color_rim", REAL_RIM if is_real else OTHER_RIM)
