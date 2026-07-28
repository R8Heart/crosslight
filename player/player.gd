extends CharacterBody3D

const SPEED := 4.5
const JUMP_VELOCITY := 4.5
const GRAVITY := 9.8
const MOUSE_SENSITIVITY := 0.0025
const PITCH_LIMIT := 1.4

@onready var head: Node3D = $Head
@onready var interact_ray: RayCast3D = $Head/Camera3D/InteractRay
@onready var hold_point: Marker3D = $Head/Camera3D/HoldPoint
@onready var interact_hint: Label = $HUD/InteractHint

var held_item: Node = null

func _ready() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	WorldState.world_changed.connect(_on_world_changed)

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		rotate_y(-event.relative.x * MOUSE_SENSITIVITY)
		head.rotate_x(-event.relative.y * MOUSE_SENSITIVITY)
		head.rotation.x = clamp(head.rotation.x, -PITCH_LIMIT, PITCH_LIMIT)
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
	elif Input.is_action_just_pressed("jump"):
		velocity.y = JUMP_VELOCITY

	var input_dir := Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	var direction := (transform.basis * Vector3(input_dir.x, 0, input_dir.y)).normalized()
	velocity.x = direction.x * SPEED
	velocity.z = direction.z * SPEED

	move_and_slide()
	_update_interact_hint()

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
