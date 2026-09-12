class_name CameraRig
extends Node3D

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

func _ready() -> void:
    _camera = Camera3D.new()
    _camera.current = true
    _camera.fov = _third_person_fov
    _camera.keep_aspect = Camera3D.KEEP_WIDTH
    _camera.near = 0.075
    add_child(_camera)

func set_target(node: Node3D) -> void:
    target = node

func set_on_foot_profile(camera_distance: float = 6.25, camera_height: float = 2.30, fov: float = 72.0) -> void:
    distance = camera_distance
    height = camera_height
    _third_person_fov = fov
    minimum_distance = 1.85
    pitch = clampf(pitch, -0.60, 0.16)
    if not _machine_view and not _manual_capture:
        _camera.fov = _third_person_fov

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
    target = next_target

func add_machine_impulse(amount: float, local_direction: Vector3 = Vector3(0.0, 0.0, 1.0)) -> void:
    if not _machine_view:
        return
    _machine_camera_shake += local_direction.normalized() * clampf(amount, 0.0, 0.065)

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
    _camera.current = true
    _camera.look_at(look_at, Vector3.UP)

func clear_capture_pose() -> void:
    _manual_capture = false
    if _machine_view:
        _camera.top_level = true
        _camera.fov = _machine_fov
    else:
        _camera.top_level = false
        _camera.position = Vector3.ZERO
        _camera.rotation = Vector3.ZERO
        _camera.fov = _third_person_fov

func apply_look(delta: Vector2) -> void:
    if _manual_capture or _machine_view:
        return
    yaw -= delta.x * look_sensitivity
    pitch -= delta.y * look_sensitivity
    pitch = clampf(pitch, -0.60, 0.16)

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

    _camera.fov = _third_person_fov
    var anchor := target.global_position + Vector3.UP * height
    var basis := Basis(Vector3.UP, yaw)
    var back := basis * Vector3(0.0, 0.0, distance)
    var vertical := Vector3.UP * (-sin(pitch) * distance)
    var desired := anchor + back + vertical
    if collision_enabled:
        desired = _resolve_camera_collision(anchor, desired)
    var response := 16.0 if global_position.distance_to(desired) > 1.4 else 11.0
    global_position = global_position.lerp(desired, 1.0 - exp(-response * delta))
    _camera.look_at(anchor, Vector3.UP)

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
    _camera.current = true
    _machine_camera_shake = _machine_camera_shake.lerp(Vector3.ZERO, 1.0 - exp(-17.0 * delta))
    _camera.global_position += _camera.global_basis * _machine_camera_shake

func _resolve_camera_collision(anchor: Vector3, desired: Vector3) -> Vector3:
    var ray := desired - anchor
    var ray_len := ray.length()
    if ray_len <= minimum_distance:
        return desired
    var query := PhysicsRayQueryParameters3D.create(anchor, desired, 1 | 2 | 8)
    if target != null:
        query.exclude = [target]
    query.collide_with_areas = false
    var hit := get_world_3d().direct_space_state.intersect_ray(query)
    if hit.is_empty():
        return desired
    var dir := ray.normalized()
    var safe_len := maxf(minimum_distance, anchor.distance_to(hit.position) - collision_margin)
    return anchor + dir * safe_len

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
