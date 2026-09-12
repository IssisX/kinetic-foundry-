class_name CameraRig
extends Node3D

const CAMERA_COLLISION_MASK := 1 | 2 | 8
const EVENT_MAX_BLEND := 0.42
const EVENT_MAX_DISTANCE := 38.0

var target: Node3D
var yaw := 0.0
var pitch := -0.16
var distance := 6.25
var height := 2.30
var look_sensitivity := 0.0038
var collision_margin := 0.38
var minimum_distance := 1.85
var collision_enabled := true

var _camera: Camera3D
var _manual_capture := false
var _manual_position := Vector3.ZERO
var _manual_look_at := Vector3.ZERO
var _manual_fov := 68.0

var _third_person_fov := 72.0
var _machine_view := false
var _machine: Node3D
var _machine_anchor: Node3D
var _machine_fov := 76.0
var _machine_camera_shake := Vector3.ZERO

var _ahead_offset := Vector3.ZERO
var _event_point := Vector3.ZERO
var _event_salience := 0.0
var _event_scale := 0.0
var _event_remaining := 0.0
var _event_duration := 0.0
var _event_blend := 0.0
var _manual_override := 0.0
var _current_fov := 72.0

func _ready() -> void:
    _camera = Camera3D.new()
    _camera.current = true
    _camera.fov = _third_person_fov
    _camera.keep_aspect = Camera3D.KEEP_WIDTH
    _camera.near = 0.075
    add_child(_camera)
    _current_fov = _third_person_fov

func set_target(node: Node3D) -> void:
    target = node
    _ahead_offset = Vector3.ZERO
    _event_blend = 0.0

func set_on_foot_profile(camera_distance: float = 6.25, camera_height: float = 2.30, fov: float = 72.0) -> void:
    distance = camera_distance
    height = camera_height
    _third_person_fov = fov
    minimum_distance = 1.85
    pitch = clampf(pitch, -0.60, 0.16)
    if not _machine_view and not _manual_capture:
        _camera.fov = _third_person_fov
        _current_fov = _third_person_fov

func enter_machine_view(machine: Node3D) -> void:
    if machine == null or not is_instance_valid(machine):
        return
    _machine = machine
    _machine_view = true
    target = machine
    _machine_anchor = null
    if machine.has_method("get_operator_view_anchor"):
        _machine_anchor = machine.get_operator_view_anchor()
    if machine.has_method("get_operator_fov"):
        _machine_fov = float(machine.get_operator_fov())
    else:
        _machine_fov = 76.0
    _camera.top_level = true
    _camera.fov = _machine_fov
    _current_fov = _machine_fov
    _machine_camera_shake = Vector3.ZERO

func exit_machine_view(next_target: Node3D) -> void:
    _machine_view = false
    _machine = null
    _machine_anchor = null
    _machine_camera_shake = Vector3.ZERO
    _camera.top_level = false
    _camera.position = Vector3.ZERO
    _camera.rotation = Vector3.ZERO
    _camera.fov = _third_person_fov
    _current_fov = _third_person_fov
    target = next_target
    _ahead_offset = Vector3.ZERO
    _event_blend = 0.0

func add_machine_impulse(amount: float, local_direction: Vector3 = Vector3(0.0, 0.0, 1.0)) -> void:
    if not _machine_view:
        return
    _machine_camera_shake += local_direction.normalized() * clampf(amount, 0.0, 0.065)

func compose_impact(world_position: Vector3, salience: float) -> void:
    if _manual_capture:
        return
    var amount := clampf(salience, 0.0, 1.0)
    if _machine_view:
        var direction := _machine.global_basis.inverse() * (world_position - _camera.global_position).normalized()
        add_machine_impulse(lerpf(0.008, 0.040, amount), direction)
        return
    _queue_event(world_position, amount, amount * 0.18, lerpf(0.20, 0.44, amount))

func compose_collapse(world_position: Vector3, world_extent: float = 10.0) -> void:
    if _manual_capture or _machine_view:
        return
    var scale := clampf(world_extent / 14.0, 0.35, 1.0)
    _queue_event(world_position + Vector3.UP * world_extent * 0.10, 1.0, scale, 1.20)

func _queue_event(world_position: Vector3, salience: float, scale: float, duration: float) -> void:
    if target == null or not is_instance_valid(target):
        return
    if target.global_position.distance_to(world_position) > EVENT_MAX_DISTANCE:
        return
    if _event_remaining > 0.0 and salience < _event_salience * 0.82:
        return
    _event_point = world_position
    _event_salience = clampf(salience, 0.0, 1.0)
    _event_scale = clampf(scale, 0.0, 1.0)
    _event_duration = maxf(duration, 0.05)
    _event_remaining = _event_duration

func is_machine_view() -> bool:
    return _machine_view

func set_capture_pose(position: Vector3, look_at: Vector3, fov: float = 68.0) -> void:
    _manual_capture = true
    _manual_position = position
    _manual_look_at = look_at
    _manual_fov = fov
    _camera.top_level = true
    _camera.global_position = position
    _camera.fov = fov
    _current_fov = fov
    _camera.current = true
    _camera.look_at(look_at, Vector3.UP)

func clear_capture_pose() -> void:
    _manual_capture = false
    if _machine_view:
        _camera.top_level = true
        _camera.fov = _machine_fov
        _current_fov = _machine_fov
    else:
        _camera.top_level = false
        _camera.position = Vector3.ZERO
        _camera.rotation = Vector3.ZERO
        _camera.fov = _third_person_fov
        _current_fov = _third_person_fov

func apply_look(delta: Vector2) -> void:
    if _manual_capture or _machine_view:
        return
    yaw -= delta.x * look_sensitivity
    pitch -= delta.y * look_sensitivity
    pitch = clampf(pitch, -0.60, 0.16)
    if delta.length_squared() > 0.16:
        _manual_override = 0.55
        _event_remaining = minf(_event_remaining, 0.16)

func _process(delta: float) -> void:
    if _manual_capture:
        _camera.global_position = _manual_position
        _camera.fov = _manual_fov
        _camera.current = true
        _camera.look_at(_manual_look_at, Vector3.UP)
        return

    if _machine_view:
        _update_machine_view(delta)
        return

    if target == null or not is_instance_valid(target):
        return

    _manual_override = maxf(0.0, _manual_override - delta)
    _event_remaining = maxf(0.0, _event_remaining - delta)

    var planar_velocity := _target_planar_velocity()
    var speed := planar_velocity.length()
    var commitment := smoothstep(1.15, 4.80, speed)
    var ahead_target := Vector3.ZERO
    if commitment > 0.0:
        ahead_target = planar_velocity.normalized() * lerpf(0.0, 2.15, commitment)
    _ahead_offset = _ahead_offset.lerp(ahead_target, 1.0 - exp(-4.8 * delta))

    var anchor := target.global_position + Vector3.UP * height + _ahead_offset
    var event_target := 0.0
    if _event_remaining > 0.0 and _manual_override <= 0.0:
        var event_phase := _event_remaining / maxf(_event_duration, 0.001)
        var envelope := minf(1.0, (1.0 - event_phase) * 8.0) * minf(1.0, event_phase * 4.0)
        event_target = _event_salience * EVENT_MAX_BLEND * envelope
    _event_blend = lerpf(_event_blend, event_target, 1.0 - exp(-9.0 * delta))

    var look_anchor := anchor.lerp(_event_point, _event_blend)
    var framed_distance := distance * (1.0 + _event_scale * _event_blend * 0.52)
    var basis := Basis(Vector3.UP, yaw)
    var back := basis * Vector3(0.0, 0.0, framed_distance)
    var vertical := Vector3.UP * (-sin(pitch) * framed_distance)
    var desired := anchor + back + vertical
    if collision_enabled:
        desired = _resolve_camera_collision(anchor, desired)
    var response := 16.0 if global_position.distance_to(desired) > 1.4 else 11.0
    global_position = global_position.lerp(desired, 1.0 - exp(-response * delta))
    if collision_enabled:
        global_position = _resolve_camera_collision(anchor, global_position)
    var desired_fov := _third_person_fov + _event_scale * _event_blend * 15.0
    _current_fov = lerpf(_current_fov, desired_fov, 1.0 - exp(-7.0 * delta))
    _camera.fov = _current_fov
    _camera.look_at(look_anchor, Vector3.UP)

func _update_machine_view(delta: float) -> void:
    if _machine == null or not is_instance_valid(_machine):
        return
    if _machine_anchor == null or not is_instance_valid(_machine_anchor):
        if _machine.has_method("get_operator_view_anchor"):
            _machine_anchor = _machine.get_operator_view_anchor()
    if _machine_anchor == null:
        _camera.global_transform = _machine.global_transform.translated_local(Vector3(0.0, 2.7, -0.45))
    else:
        _camera.global_transform = _machine_anchor.global_transform
    _camera.fov = _machine_fov
    _current_fov = _machine_fov
    _camera.current = true
    _machine_camera_shake = _machine_camera_shake.lerp(Vector3.ZERO, 1.0 - exp(-17.0 * delta))
    _camera.global_position += _camera.global_basis * _machine_camera_shake

func _resolve_camera_collision(anchor: Vector3, desired: Vector3) -> Vector3:
    var ray := desired - anchor
    var ray_len := ray.length()
    if ray_len <= minimum_distance:
        return desired
    var sphere := SphereShape3D.new()
    sphere.radius = 0.26
    var query := PhysicsShapeQueryParameters3D.new()
    query.shape = sphere
    query.transform = Transform3D(Basis.IDENTITY, anchor)
    query.motion = ray
    query.collision_mask = CAMERA_COLLISION_MASK
    query.collide_with_areas = false
    if target is CollisionObject3D:
        query.exclude = [target.get_rid()]
    var fractions := get_world_3d().direct_space_state.cast_motion(query)
    if fractions.is_empty() or fractions[0] >= 0.999:
        return desired
    var dir := ray.normalized()
    var safe_len := maxf(minimum_distance, ray_len * fractions[0] - collision_margin)
    return anchor + dir * safe_len

func _target_planar_velocity() -> Vector3:
    if target is CharacterBody3D:
        var velocity: Vector3 = target.velocity
        velocity.y = 0.0
        return velocity
    if target is RigidBody3D:
        var velocity: Vector3 = target.linear_velocity
        velocity.y = 0.0
        return velocity
    return Vector3.ZERO

func flat_forward() -> Vector3:
    var forward := -_camera.global_basis.z
    forward.y = 0.0
    if forward.length_squared() < 0.001:
        return Vector3.FORWARD
    return forward.normalized()

func flat_right() -> Vector3:
    var right := _camera.global_basis.x
    right.y = 0.0
    if right.length_squared() < 0.001:
        return Vector3.RIGHT
    return right.normalized()
