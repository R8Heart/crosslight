extends MeshInstance3D
class_name WorldTransitionFX

## Draws the world-switch (see world_state.gd for the phase timing it reads
## every frame): space twisted and dragged into the orb, a beat of black,
## then thrown back out in the new colour.
##
## Owns no timing of its own on purpose -- WorldState is the single clock,
## so this can never drift out of step with the lights and materials that
## are dimming and swapping alongside it.
##
## Parented directly under Camera3D as a 2x2 QuadMesh whose vertex shader
## bypasses the normal transform (see the shader) so it always fills the
## screen without needing to be sized against the camera's FOV.

@export var orb_path: NodePath

## Colour the world is dragged toward on the way in, and flung out in on
## the way back. Sampled from whichever world is being left / entered.
const REAL_TINT := Color(1.0, 0.55, 0.18)
const OTHER_TINT := Color(0.3, 1.0, 0.45)

var _cam: Camera3D
var _orb: Node3D
var _mat: ShaderMaterial

func _ready() -> void:
	# The vertex shader ignores this node's real transform entirely (see the
	# shader), but Godot's frustum culling runs on the mesh's AABB before
	# that shader ever executes -- sitting right on top of the camera, the
	# real 2x2 quad AABB reads as degenerate/behind-the-near-plane and gets
	# culled before it can draw. A huge fake AABB makes it always pass.
	set_custom_aabb(AABB(Vector3(-1000, -1000, -1000), Vector3(2000, 2000, 2000)))

	_cam = get_parent() as Camera3D
	_orb = get_node_or_null(orb_path)
	_mat = material_override as ShaderMaterial

func _process(_delta: float) -> void:
	if not _mat:
		return

	_mat.set_shader_parameter("swirl", WorldState.swirl)
	_mat.set_shader_parameter("darkness", WorldState.darkness)
	_mat.set_shader_parameter("burst", WorldState.burst)

	# Pulled *toward* the colour being left while inhaling, and thrown out
	# in the colour being entered -- the swap lands in the dark between the
	# two, so the burst is already the new world's colour.
	var is_real: bool = WorldState.current_world == WorldState.World.REAL
	_mat.set_shader_parameter("tint", REAL_TINT if is_real else OTHER_TINT)

	if not _cam:
		return
	var vp := get_viewport().get_visible_rect().size
	_mat.set_shader_parameter("aspect", vp.x / maxf(vp.y, 1.0))

	# Track the orb's actual position on screen so the pull always
	# originates from the light in the player's hand, wherever they happen
	# to be looking, rather than from a fixed point on the screen.
	if _orb:
		var screen_pos := _cam.unproject_position(_orb.global_position)
		var uv := screen_pos / vp
		# Behind the camera unprojects to nonsense; keep the vortex pinned
		# just off the relevant edge instead of teleporting it.
		if _cam.is_position_behind(_orb.global_position):
			uv = Vector2(clampf(uv.x, -0.5, 1.5), 1.2)
		_mat.set_shader_parameter("orb_uv", uv)
