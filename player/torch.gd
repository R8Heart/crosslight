extends Node3D

const REAL_CORE := Color(1.0, 0.94, 0.68)
const REAL_MID := Color(1.0, 0.45, 0.07)
const REAL_EDGE := Color(0.55, 0.07, 0.005)
const REAL_LIGHT := Color(1.0, 0.55, 0.15)
const REAL_EMBER_HOT := Color(1.0, 0.86, 0.48)
const REAL_EMBER_COOL := Color(0.9, 0.16, 0.02)

const OTHER_CORE := Color(0.8, 1.0, 0.85)
const OTHER_MID := Color(0.22, 1.0, 0.42)
const OTHER_EDGE := Color(0.02, 0.35, 0.12)
const OTHER_LIGHT := Color(0.25, 1.0, 0.45)
const OTHER_EMBER_HOT := Color(0.75, 1.0, 0.8)
const OTHER_EMBER_COOL := Color(0.05, 0.7, 0.25)

const BASE_LIGHT_ENERGY := 2.5
const FLICKER_AMOUNT := 0.7
const FLICKER_SPEED := 9.0

## How far the flame leans per unit of torch speed, and how far it may lean.
const DRAG_SCALE := 0.02
const DRAG_MAX := 0.055
## Lower = the flame lags longer behind the movement.
const DRAG_RESPONSE := 7.0

## Clearance kept between the flame and its volume wall, so the density always
## fades out before the box edge instead of being clipped into a square.
const SIDE_MARGIN := 0.05
const BASE_MARGIN := 0.02

@onready var flame: MeshInstance3D = $Flame
@onready var haze: MeshInstance3D = $Haze
@onready var light: OmniLight3D = $OmniLight3D
@onready var embers: GPUParticles3D = $Embers

var _noise := FastNoiseLite.new()
var _fire_mat: ShaderMaterial
var _haze_mat: ShaderMaterial
var _ember_mat: ShaderMaterial
var _prev_pos: Vector3
var _drag := Vector3.ZERO
var _last_shape := Vector2.INF

func _ready() -> void:
	_noise.frequency = 2.0
	_fire_mat = flame.get_surface_override_material(0) as ShaderMaterial
	_haze_mat = haze.get_surface_override_material(0) as ShaderMaterial
	_ember_mat = embers.material_override as ShaderMaterial
	_snap_to_torch_head()
	_prev_pos = global_position
	WorldState.world_changed.connect(_on_world_changed)
	_apply(WorldState.current_world)

func _process(delta: float) -> void:
	var t := Time.get_ticks_msec() / 1000.0
	light.light_energy = BASE_LIGHT_ENERGY + _noise.get_noise_1d(t * FLICKER_SPEED) * FLICKER_AMOUNT
	_fit_volumes()
	_update_drag(delta)

## Keeps both ray-marched volumes wrapped around whatever flame size is set, so
## the shape can be tuned freely without ever hitting an invisible wall. Only
## the mesh and the shader bounds are touched — never the node's transform, so
## whatever position, rotation and scale are authored in the editor survive
## into the game unchanged. Re-fitted only when the dimensions actually change.
func _fit_volumes() -> void:
	if _fire_mat == null:
		return

	var height: float = _fire_mat.get_shader_parameter("flame_height")
	var radius: float = _fire_mat.get_shader_parameter("flame_radius")
	var shape := Vector2(height, radius)
	if shape.is_equal_approx(_last_shape):
		return
	_last_shape = shape

	var smoke_extent: float = _fire_mat.get_shader_parameter("smoke_extent")
	var side: float = radius * 1.6 + DRAG_MAX + SIDE_MARGIN
	# The smoke plume keeps rising above the flame's own tip before it fades.
	var top: float = height * (0.5 + maxf(smoke_extent, 0.0)) + BASE_MARGIN
	_apply_volume(flame, _fire_mat, Vector3(-side, -BASE_MARGIN, -side), Vector3(side, top, side))

	if _haze_mat:
		var haze_extent: float = _haze_mat.get_shader_parameter("plume_extent")
		var haze_radius: float = _haze_mat.get_shader_parameter("plume_radius")
		var haze_side: float = haze_radius * 1.8 + DRAG_MAX + SIDE_MARGIN
		var haze_top: float = height * maxf(haze_extent, 0.1) + BASE_MARGIN
		_haze_mat.set_shader_parameter("flame_height", height)
		_apply_volume(haze, _haze_mat,
			Vector3(-haze_side, -BASE_MARGIN, -haze_side),
			Vector3(haze_side, haze_top, haze_side))

## Publishes the object-space bounds the shader ray-marches, and grows the box
## mesh to cover them. The flame's root is the node's origin and it grows
## upward, so the volume is off-centre; BoxMesh is always centred, hence the
## mesh is sized by the largest extent on each axis and the shader discards the
## rest. Costs a little empty overdraw, but nothing can ever be clipped.
func _apply_volume(target: MeshInstance3D, mat: ShaderMaterial, vmin: Vector3, vmax: Vector3) -> void:
	var box := target.mesh as BoxMesh
	if box:
		box.size = Vector3(
			maxf(absf(vmin.x), absf(vmax.x)),
			maxf(absf(vmin.y), absf(vmax.y)),
			maxf(absf(vmin.z), absf(vmax.z))) * 2.0
	mat.set_shader_parameter("volume_min", vmin)
	mat.set_shader_parameter("volume_max", vmax)

## Real flames lag behind the torch that carries them, so feed the torch's own
## velocity (in the flame's object space, negated) into the shaders.
func _update_drag(delta: float) -> void:
	if delta <= 0.0:
		return

	var velocity := (global_position - _prev_pos) / delta
	_prev_pos = global_position

	var local_vel := global_transform.basis.inverse() * velocity
	var target := (-local_vel * DRAG_SCALE).limit_length(DRAG_MAX)
	_drag = _drag.lerp(target, clampf(delta * DRAG_RESPONSE, 0.0, 1.0))

	if _fire_mat:
		_fire_mat.set_shader_parameter("drag", _drag)
	if _haze_mat:
		_haze_mat.set_shader_parameter("drag", _drag)

## Places the flame on the torch head by reading the model's own geometry.
## Hand-tuned offsets silently break every time the hand is re-posed, so the
## head is located instead: in camera space the torch points up, which makes
## its head simply the topmost slice of the mesh.
func _snap_to_torch_head() -> void:
	var cam := get_parent() as Node3D
	var mesh_inst := _find_mesh(cam)
	if mesh_inst == null:
		push_warning("Torch: no mesh found, flame stays at its authored position")
		return

	var verts: PackedVector3Array = (mesh_inst.mesh as Mesh).surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
	if verts.is_empty():
		return

	var to_cam := cam.global_transform.affine_inverse() * mesh_inst.global_transform
	var sampled := PackedVector3Array()
	var i := 0
	while i < verts.size():
		sampled.append(to_cam * verts[i])
		i += 7

	var max_y := -INF
	var min_y := INF
	for p in sampled:
		max_y = maxf(max_y, p.y)
		min_y = minf(min_y, p.y)

	var cutoff := max_y - (max_y - min_y) * 0.03
	var sum := Vector3.ZERO
	var count := 0
	for p in sampled:
		if p.y >= cutoff:
			sum += p
			count += 1
	if count > 0:
		position = sum / count

func _find_mesh(node: Node) -> MeshInstance3D:
	if node is MeshInstance3D and (node as MeshInstance3D).mesh != null:
		return node
	for child in node.get_children():
		var found := _find_mesh(child)
		if found:
			return found
	return null

func _on_world_changed(new_world) -> void:
	_apply(new_world)

func _apply(world) -> void:
	var is_real: bool = world == WorldState.World.REAL

	light.light_color = REAL_LIGHT if is_real else OTHER_LIGHT

	if _fire_mat:
		_fire_mat.set_shader_parameter("color_core", REAL_CORE if is_real else OTHER_CORE)
		_fire_mat.set_shader_parameter("color_mid", REAL_MID if is_real else OTHER_MID)
		_fire_mat.set_shader_parameter("color_edge", REAL_EDGE if is_real else OTHER_EDGE)

	if _ember_mat:
		_ember_mat.set_shader_parameter("color_hot", REAL_EMBER_HOT if is_real else OTHER_EMBER_HOT)
		_ember_mat.set_shader_parameter("color_cool", REAL_EMBER_COOL if is_real else OTHER_EMBER_COOL)
