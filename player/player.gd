extends CharacterBody3D

const SPEED := 2.5
## Debug-only speed multiplier while holding Shift, for quickly crossing the
## large exterior grounds during testing.
const SPRINT_MULTIPLIER := 4.0
const GRAVITY := 9.8
const MOUSE_SENSITIVITY := 0.0025
const PITCH_LIMIT := 1.4
## How quickly the actual view catches up to where the mouse points. High
## enough to stay responsive, low enough that a fast flick has a little
## weight instead of the view snapping frame-perfect with the cursor —
## a body turning its head isn't a camera rotating instantly on a pivot.
const LOOK_SMOOTH := 15.0

## How far the viewmodel swings while walking, in metres — kept small, this
## is meant to read as "alive", not a cartoonish wobble.
const BOB_AMOUNT := Vector3(0.012, 0.018, 0.0)
## Steps per second at full SPEED; scales down with actual speed so bobbing
## stops cleanly rather than freezing mid-swing.
const BOB_FREQUENCY := 0.8
## Slow idle drift when standing still, so the hand never looks frozen.
const IDLE_SWAY_AMOUNT := 0.005
const IDLE_SWAY_SPEED := 0.5
const VIEWMODEL_SMOOTH := 9.0

## How fast the trailing "wake" point catches up to the player. Low values leave
## a longer-lived parted channel through fog behind him (see fog_patch.gdshader).
const WAKE_FOLLOW := 2.2

@onready var head: Node3D = $Head
@onready var interact_ray: RayCast3D = $Head/Camera3D/InteractRay
@onready var hold_point: Marker3D = $Head/Camera3D/HoldPoint
@onready var interact_hint: Label = $HUD/InteractHint
@onready var viewmodel_pivot: Node3D = $Head/Camera3D/ViewmodelPivot

var held_item: Node = null
var _bob_time := 0.0
var _wake_pos := Vector3.ZERO

## Where the mouse wants the view to be, updated instantly on every input
## event; the actual rotation/head.rotation.x below just chase this rather
## than snapping straight to it. Started from the current rotation so the
## view doesn't jerk on the very first frame.
var _target_yaw := 0.0
var _target_pitch := 0.0

func _ready() -> void:
	add_to_group(&"player")
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	WorldState.world_changed.connect(_on_world_changed)
	_wake_pos = global_position
	_target_yaw = rotation.y
	_target_pitch = head.rotation.x

func _process(delta: float) -> void:
	_publish_fog_globals(delta)
	_update_look(delta)

## The actual view eases toward wherever the mouse has pointed it, instead
## of snapping there in the same frame the input arrived — see LOOK_SMOOTH.
func _update_look(delta: float) -> void:
	var t := clampf(delta * LOOK_SMOOTH, 0.0, 1.0)
	rotation.y = lerp_angle(rotation.y, _target_yaw, t)
	head.rotation.x = lerp_angle(head.rotation.x, _target_pitch, t)

## Fog volumes read the player's position through global shader parameters, so
## they can part around him without holding a reference to him. Published from
## here because this is the only node that actually knows where he is.
func _publish_fog_globals(delta: float) -> void:
	var pos := global_position
	_wake_pos = _wake_pos.lerp(pos, clampf(delta * WAKE_FOLLOW, 0.0, 1.0))
	RenderingServer.global_shader_parameter_set(&"player_position", pos)
	RenderingServer.global_shader_parameter_set(&"player_wake", _wake_pos)

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		_target_yaw -= event.relative.x * MOUSE_SENSITIVITY
		_target_pitch -= event.relative.y * MOUSE_SENSITIVITY
		_target_pitch = clamp(_target_pitch, -PITCH_LIMIT, PITCH_LIMIT)
	if event.is_action_pressed("ui_cancel"):
		var captured := Input.mouse_mode == Input.MOUSE_MODE_CAPTURED
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE if captured else Input.MOUSE_MODE_CAPTURED
	if event.is_action_pressed("interact"):
		_try_interact()
	if event.is_action_pressed("toggle_torch"):
		WorldState.toggle()

func _physics_process(delta: float) -> void:
	if not is_on_floor():
		velocity.y -= GRAVITY * delta

	var input_dir := Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	var direction := (transform.basis * Vector3(input_dir.x, 0, input_dir.y)).normalized()
	var current_speed := SPEED * SPRINT_MULTIPLIER if Input.is_physical_key_pressed(KEY_SHIFT) else SPEED
	velocity.x = direction.x * current_speed
	velocity.z = direction.z * current_speed

	move_and_slide()
	_update_interact_hint()
	_update_viewmodel(delta)

## Purely cosmetic viewmodel motion: a walk-cycle bob while moving, falling
## back to a slow idle sway at rest so the hand never looks frozen. Wall
## clipping is handled by the player's own collision shape now, not here —
## none of this touches the tuned rest transform on HandModel itself, it's
## just a small offset applied to its parent pivot.
func _update_viewmodel(delta: float) -> void:
	var speed := Vector2(velocity.x, velocity.z).length()
	var moving := speed > 0.1 and is_on_floor()

	var offset: Vector3
	if moving:
		_bob_time += delta * BOB_FREQUENCY * TAU * (speed / SPEED)
		offset = Vector3(
			sin(_bob_time) * BOB_AMOUNT.x,
			absf(sin(_bob_time)) * BOB_AMOUNT.y,
			0.0
		)
	else:
		var t := Time.get_ticks_msec() / 1000.0
		offset = Vector3(
			sin(t * IDLE_SWAY_SPEED) * IDLE_SWAY_AMOUNT,
			sin(t * IDLE_SWAY_SPEED * 0.6) * IDLE_SWAY_AMOUNT * 0.6,
			0.0
		)

	viewmodel_pivot.position = viewmodel_pivot.position.lerp(offset, delta * VIEWMODEL_SMOOTH)

func _update_interact_hint() -> void:
	interact_ray.force_raycast_update()
	var target := interact_ray.get_collider() if interact_ray.is_colliding() else null
	interact_hint.visible = target != null and target.has_method("interact")

func _try_interact() -> void:
	interact_ray.force_raycast_update()
	if interact_ray.is_colliding():
		var target := interact_ray.get_collider()
		if target and target.has_method("interact"):
			target.interact(self)

func pick_up(item: Node) -> void:
	held_item = item
	item.on_picked_up(hold_point)

func _on_world_changed(new_world) -> void:
	if held_item and held_item.world != new_world:
		var dropped := held_item
		held_item = null
		dropped.return_to_origin()
