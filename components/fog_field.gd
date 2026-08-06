extends Node3D
class_name FogField

## Keeps a pool of drifting mist puffs alive around the player.
##
## Each puff is its own FogVolume (Ellipsoid shape), repositioned and resized
## every frame, with its own ShaderMaterial whose only per-puff knob is
## `alpha`. An earlier version tried to drive one big FogVolume from a single
## `uniform vec4 puffs[N]` array — the values reached the material fine but
## never actually showed up in the render, while plain scalar/vector uniforms
## worked without issue. Real per-instance volumes sidestep the question of
## why entirely, and read the position/radius for free from the node's own
## transform instead of a hand-rolled distance check.
##
## Whenever a puff dies or is left behind, it reappears somewhere else around
## the player — so there is always mist nearby, never the same mist twice, and
## the cost stays constant regardless of how large the grounds get.

const PUFF_COUNT := 22

@export var player_path: NodePath = ^"../Player"
@export var fog_shader: Shader = preload("res://assets/shaders/fog_field.gdshader")

@export_group("Spawning")
## Puffs appear in a ring at this range, never right on top of the player —
## popping into existence in his face would give the whole thing away.
@export var spawn_radius_min := 7.0
@export var spawn_radius_max := 22.0
## Puffs sit at slightly different heights so overlapping banks read as having
## depth rather than as one flat sheet.
@export var height_min := 0.15
@export var height_max := 1.9
@export var radius_min := 3.5
@export var radius_max := 8.0
## Beyond this the player has simply walked away; recycle rather than wait.
@export var cull_distance := 52.0

@export_group("Life")
@export var life_min := 16.0
@export var life_max := 30.0
## Long, deliberate fades — mist should never be seen switching on.
@export var fade_in := 5.0
@export var fade_out := 6.0

@export_group("Motion")
@export var drift_speed := 0.28
## How flat each puff sits — radius applies horizontally, height is radius
## divided by this.
@export var vertical_squash := 3.4

@export_group("Dispersal")
## How close before a puff starts breaking apart.
@export var disperse_distance := 2.6
## Seconds for a disturbed puff to blow apart and be gone.
@export var disperse_time := 1.8
## How much it swells while breaking up — this is the visible "blown aside".
@export var disperse_growth := 2.4

class Puff:
	var node: FogVolume
	var mat: ShaderMaterial
	var pos := Vector3.ZERO
	var drift := Vector3.ZERO
	var base_radius := 4.0
	var age := 0.0
	var life := 20.0
	## Seconds since the player disturbed it; negative means still intact.
	var disperse := -1.0

var _puffs: Array[Puff] = []
var _player: Node3D

func _ready() -> void:
	_player = get_node_or_null(player_path) as Node3D
	var origin := _player.global_position if _player else Vector3.ZERO

	for i in PUFF_COUNT:
		var fv := FogVolume.new()
		# `shape` is a plain int property, not a GDScript-visible enum — 0 is
		# Ellipsoid (confirmed via ClassDB; World, used by the old single-volume
		# approach, was 4).
		fv.shape = 0
		var mat := ShaderMaterial.new()
		mat.shader = fog_shader
		fv.material = mat
		add_child(fv)

		var p := Puff.new()
		p.node = fv
		p.mat = mat
		_respawn(p, origin)
		# Stagger starting ages, or every puff fades in together on the first
		# frame and dies together twenty seconds later.
		p.age = randf() * p.life
		_puffs.append(p)

func _process(delta: float) -> void:
	var player_pos := _player.global_position if _player else Vector3.ZERO

	for p in _puffs:
		_advance(p, delta, player_pos)
		if _is_spent(p) or p.pos.distance_to(player_pos) > cull_distance:
			_respawn(p, player_pos)

		var r := _radius_of(p)
		p.node.position = p.pos
		p.node.size = Vector3(r * 2.0, (r * 2.0) / vertical_squash, r * 2.0)
		p.mat.set_shader_parameter("alpha", _alpha_of(p))

func _advance(p: Puff, delta: float, player_pos: Vector3) -> void:
	p.age += delta
	p.pos += p.drift * delta

	if p.disperse < 0.0:
		# Bigger puffs start breaking up from further out, since the player
		# reaches their edge sooner.
		var trigger := disperse_distance + p.base_radius * 0.45
		var flat := Vector2(p.pos.x - player_pos.x, p.pos.z - player_pos.z).length()
		if flat < trigger and absf(p.pos.y - player_pos.y) < 3.0:
			p.disperse = 0.0
	else:
		p.disperse += delta

func _is_spent(p: Puff) -> bool:
	if p.disperse >= disperse_time:
		return true
	return p.age >= p.life

func _alpha_of(p: Puff) -> float:
	var in_t := clampf(p.age / maxf(fade_in, 0.01), 0.0, 1.0)
	var out_t := clampf((p.life - p.age) / maxf(fade_out, 0.01), 0.0, 1.0)
	var a := in_t * out_t
	if p.disperse >= 0.0:
		# Thins out fast as it swells, so it visibly comes apart instead of
		# simply shrinking away.
		a *= 1.0 - clampf(p.disperse / maxf(disperse_time, 0.01), 0.0, 1.0)
	return a

func _radius_of(p: Puff) -> float:
	if p.disperse < 0.0:
		return p.base_radius
	var t := clampf(p.disperse / maxf(disperse_time, 0.01), 0.0, 1.0)
	return p.base_radius * lerpf(1.0, disperse_growth, t)

func _respawn(p: Puff, player_pos: Vector3) -> void:
	var angle := randf() * TAU
	var dist := randf_range(spawn_radius_min, spawn_radius_max)
	p.pos = Vector3(
		player_pos.x + cos(angle) * dist,
		randf_range(height_min, height_max),
		player_pos.z + sin(angle) * dist
	)
	p.base_radius = randf_range(radius_min, radius_max)
	p.age = 0.0
	p.life = randf_range(life_min, life_max)
	p.disperse = -1.0

	var d := randf() * TAU
	p.drift = Vector3(cos(d), 0.0, sin(d)) * drift_speed * randf_range(0.4, 1.0)
	p.drift.y = randf_range(-0.015, 0.025)
