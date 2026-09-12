class_name CameraRig
extends Node3D

var target: Node3D
var yaw := 0.0
var pitch := -0.23
var distance := 9.4
var height := 3.1
var look_sensitivity := 0.0038
var collision_margin := 0.42
var minimum_distance := 2.7
var collision_enabled := true

var _camera: Camera3D
var _manual_capture := false
var _manual_position := Vector3.ZERO
var _manual_look_at := Vector3.ZERO
var _manual_fov := 68.0

func _ready() -> void:
    _camera = Camera3D.new()
    _camera.current = true
    _camera.fov = 68.0
    _camera.keep_aspect = Camera3D.KEEP_WIDTH
    _camera.near = 0.12
    add_child(_camera)

func set_target(node: Node3D) -> void:
    target = node

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
    _camera.top_level = false
    _camera.position = Vector3.ZERO
    _camera.rotation = Vector3.ZERO
    _camera.fov = 68.0

func apply_look(delta: Vector2) -> void:
    if _manual_capture:
        return
    yaw -= delta.x * look_sensitivity
    pitch -= delta.y * look_sensitivity
    pitch = clampf(pitch, -0.72, 0.20)

func _process(delta: float) -> void:
    if _manual_capture:
        _camera.global_position = _manual_position
        _camera.fov = _manual_fov
        _camera.current = true
        _camera.look_at(_manual_look_at, Vector3.UP)
        return
    if target == null or not is_instance_valid(target):
        return
    var anchor := target.global_position + Vector3.UP * height
    var basis := Basis(Vector3.UP, yaw)
    var back := basis * Vector3(0.0, 0.0, distance)
    var vertical := Vector3.UP * (-sin(pitch) * distance)
    var desired := anchor + back + vertical
    if collision_enabled:
        desired = _resolve_camera_collision(anchor, desired)
    var response := 13.0 if global_position.distance_to(desired) > 2.2 else 9.0
    global_position = global_position.lerp(desired, 1.0 - exp(-response * delta))
    _camera.look_at(anchor, Vector3.UP)

func _resolve_camera_collision(anchor: Vector3, desired: Vector3) -> Vector3:
    var ray := desired - anchor
    var ray_len := ray.length()
    if ray_len <= minimum_distance:
        return desired
    var query := PhysicsRayQueryParameters3D.create(anchor, desired, 2 | 8)
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
