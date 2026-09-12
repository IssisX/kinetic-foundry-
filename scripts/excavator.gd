class_name Excavator
extends CharacterBody3D

const GeomUtil = preload("res://scripts/geom.gd")
const ImpactFx = preload("res://scripts/impact_fx.gd")
const VisualBuilder = preload("res://scripts/excavator_visual.gd")

signal player_entered(machine)
signal player_exited(machine)
signal machine_disabled(machine)

var player_driver: Node3D
var enemy_driver: Node3D
var hud
var camera_rig

var drive_speed := 7.0
var turn_speed := 1.15
var boom_angle := -0.24
var stick_angle := 0.42
var tool_angle := -0.18
var arm_yaw := 0.0
var ai_time := 0.0

var chassis_health := 500.0
var hydraulic_health := 260.0
var track_health := 320.0
var disabled := false
var held_load

var _boom: Node3D
var _stick: Node3D
var _tool: Node3D
var _thumb: Node3D
var _grip_anchor: Node3D
var _impact_probe: Area3D
var _work_light: OmniLight3D
var _engine_cover: MeshInstance3D
var _arm_shapes: Array[CollisionShape3D] = []
var _impact_cooldown := 0.0
var _damage_fx_cooldown := 0.0
var _telemetry_timer := 0.0
var _arm_contact_cooldown := 0.0
var _tool_tip_last := Vector3.ZERO
var _tool_tip_velocity := Vector3.ZERO
var _tool_tip_speed := 0.0
var _tool_motion_ready := false

var _safe_boom_angle := -0.24
var _safe_stick_angle := 0.42
var _safe_tool_angle := -0.18
var _safe_arm_yaw := 0.0
var _hijack_candidate: Node3D
var _hijack_timeout := 0.0

func _ready() -> void:
    add_to_group("machine")
    collision_layer = 2
    collision_mask = 1 | 4 | 8
    var collision := GeomUtil.add_box_collision(self, Vector3(2.95, 1.45, 4.5))
    collision.position.y = 0.90
    var nodes := VisualBuilder.build(self)
    _boom = nodes.boom
    _stick = nodes.stick
    _tool = nodes.tool
    _thumb = nodes.thumb
    _grip_anchor = nodes.grip_anchor
    _impact_probe = nodes.impact_probe
    _work_light = nodes.work_light
    _engine_cover = nodes.engine_cover
    if nodes.has("arm_shapes"):
        for shape in nodes.arm_shapes:
            if shape is CollisionShape3D:
                _arm_shapes.append(shape)
    _store_safe_arm_pose()

func configure(controls, camera) -> void:
    hud = controls
    camera_rig = camera

func set_enemy_driver(driver: Node3D) -> void:
    enemy_driver = driver
    if driver != null:
        driver.visible = false
        driver.process_mode = Node.PROCESS_MODE_DISABLED

func is_player_driven() -> bool:
    return player_driver != null

func is_hijack_in_progress() -> bool:
    return _hijack_candidate != null and is_instance_valid(_hijack_candidate) and _hijack_timeout > 0.0

func get_health_ratio() -> float:
    return clampf(chassis_health / 500.0, 0.0, 1.0)

func get_hydraulic_ratio() -> float:
    return clampf(hydraulic_health / 260.0, 0.0, 1.0)

func get_track_ratio() -> float:
    return clampf(track_health / 320.0, 0.0, 1.0)

func get_tool_force() -> float:
    var chassis_speed := Vector3(velocity.x, 0.0, velocity.z).length()
    return 16.0 + chassis_speed * 10.0 + minf(_tool_tip_speed, 15.0) * 5.8

func is_holding_load() -> bool:
    return held_load != null and is_instance_valid(held_load)

func request_hijack(player: Node3D) -> bool:
    if disabled or player == null or player_driver != null:
        return false
    var distance: float = global_position.distance_to(player.global_position)
    if distance <= 3.5:
        return try_enter(player)
    var range_value = player.get("machine_climb_range")
    var climb_range: float = float(range_value) if range_value != null else 5.8
    if distance > climb_range or not player.has_method("begin_machine_climb"):
        return false
    _hijack_candidate = player
    _hijack_timeout = 1.5
    if hud != null:
        hud.set_context("HIJACK // LATCHING ON // MACHINE CONTROL PENDING")
    var started: bool = bool(player.begin_machine_climb(self))
    if not started:
        _hijack_candidate = null
        _hijack_timeout = 0.0
    return started

func try_enter(player: Node3D) -> bool:
    if disabled or player == null or player_driver != null:
        return false
    var latched: bool = _hijack_candidate == player or player.get("machine_climb_target") == self
    if not latched and global_position.distance_to(player.global_position) > 3.5:
        return false

    if enemy_driver != null:
        enemy_driver.visible = true
        enemy_driver.process_mode = Node.PROCESS_MODE_INHERIT
        enemy_driver.global_position = global_position + global_basis.x * 2.2 + Vector3.UP * 0.22
        if enemy_driver.has_method("take_hit"):
            enemy_driver.take_hit(global_basis.x * 8.0 + Vector3.UP * 2.5, 40.0)
        enemy_driver = null

    _hijack_candidate = null
    _hijack_timeout = 0.0
    player_driver = player
    velocity.x = 0.0
    velocity.z = 0.0
    player.visible = false
    player.process_mode = Node.PROCESS_MODE_DISABLED
    if hud != null:
        hud.set_machine_mode(true)
        hud.set_context("CONTROL TRANSFERRED // EXCAVATOR ONLINE")
    player_entered.emit(self)
    return true

func exit_player() -> void:
    if player_driver == null:
        return
    _release_load(false)
    var player := player_driver
    player_driver = null
    player.visible = true
    player.process_mode = Node.PROCESS_MODE_INHERIT
    player.global_position = global_position + global_basis.x * 2.8 + Vector3.UP * 0.22
    if hud != null:
        hud.set_machine_mode(false)
        hud.set_context("POWER // COMBAT // MACHINES")
    player_exited.emit(self)

func receive_enemy_hit(damage: float) -> void:
    _apply_machine_damage(damage, Vector3.UP)

func receive_hazard_hit(damage: float, impulse: Vector3) -> void:
    velocity += impulse * 0.22
    _apply_machine_damage(damage * 0.72, impulse.normalized() if impulse.length_squared() > 0.01 else Vector3.UP)

func machine_hit(amount: float, direction: Vector3) -> void:
    velocity += direction.normalized() * minf(amount * 0.018, 3.8)
    _apply_machine_damage(amount * 0.58, direction)

func _apply_machine_damage(amount: float, direction: Vector3) -> void:
    if disabled:
        return
    chassis_health = maxf(0.0, chassis_health - amount)
    var side_load := absf(direction.dot(global_basis.x))
    var vertical_load := absf(direction.y)
    track_health = maxf(0.0, track_health - amount * (0.18 + side_load * 0.36))
    hydraulic_health = maxf(0.0, hydraulic_health - amount * (0.12 + vertical_load * 0.28))
    _damage_fx_cooldown = 0.0
    ImpactFx.spawn(get_parent(), global_position + Vector3.UP * 1.7, direction, Color(1.0, 0.48, 0.08), clampf(amount / 16.0, 0.8, 4.0), 10)
    _refresh_damage_visuals()
    if chassis_health <= 0.0:
        disabled = true
        _release_load(true)
        velocity *= 0.2
        if _work_light != null:
            _work_light.light_energy = 0.0
        machine_disabled.emit(self)

func _refresh_damage_visuals() -> void:
    if _engine_cover == null:
        return
    var c := Color(0.68, 0.37, 0.045)
    if get_health_ratio() < 0.65:
        c = Color(0.55, 0.24, 0.035)
    if get_health_ratio() < 0.32:
        c = Color(0.28, 0.11, 0.025)
    _engine_cover.material_override = GeomUtil.material(c, 0.78, 0.18)

func _physics_process(delta: float) -> void:
    _impact_cooldown = maxf(0.0, _impact_cooldown - delta)
    _damage_fx_cooldown = maxf(0.0, _damage_fx_cooldown - delta)
    _telemetry_timer = maxf(0.0, _telemetry_timer - delta)
    _arm_contact_cooldown = maxf(0.0, _arm_contact_cooldown - delta)
    _hijack_timeout = maxf(0.0, _hijack_timeout - delta)
    if _hijack_timeout <= 0.0:
        _hijack_candidate = null

    if disabled:
        velocity.x = move_toward(velocity.x, 0.0, 7.0 * delta)
        velocity.z = move_toward(velocity.z, 0.0, 7.0 * delta)
    elif player_driver != null:
        _player_control(delta)
    elif enemy_driver != null:
        _enemy_control(delta)
    else:
        velocity.x = move_toward(velocity.x, 0.0, 12.0 * delta)
        velocity.z = move_toward(velocity.z, 0.0, 12.0 * delta)

    if not is_on_floor():
        velocity.y -= 26.0 * delta
    move_and_slide()
    _resolve_arm_contact_pose()
    _update_tool_motion(delta)
    _update_held_load()
    _resolve_tool_impacts()
    _update_damage_fx()
    _update_telemetry()

func _player_control(delta: float) -> void:
    if hud == null or camera_rig == null:
        return
    var track_ratio := maxf(get_track_ratio(), 0.18)
    var hydraulic_ratio := maxf(get_hydraulic_ratio(), 0.22)
    var axis: Vector2 = hud.move_axis
    var throttle: float = -axis.y
    var steering: float = axis.x
    var forward: Vector3 = -global_basis.z
    velocity.x = forward.x * throttle * drive_speed * track_ratio
    velocity.z = forward.z * throttle * drive_speed * track_ratio
    rotation.y -= steering * turn_speed * track_ratio * delta

    var look: Vector2 = hud.consume_look()
    arm_yaw -= look.x * 0.0032 * hydraulic_ratio
    boom_angle += look.y * 0.0026 * hydraulic_ratio
    arm_yaw = clampf(arm_yaw, -1.25, 1.25)
    boom_angle = clampf(boom_angle, -0.95, 0.42)

    if hud.smash_held:
        stick_angle -= 1.05 * hydraulic_ratio * delta
        tool_angle -= 1.30 * hydraulic_ratio * delta
    if hud.consume_attack():
        stick_angle -= 0.12 * hydraulic_ratio
        tool_angle -= 0.12 * hydraulic_ratio
        _impact_cooldown = 0.0
    if hud.consume_grab():
        if is_holding_load():
            _release_load(true)
        elif not _try_grip_load():
            stick_angle += 0.24 * hydraulic_ratio
            tool_angle += 0.28 * hydraulic_ratio
    if hud.consume_use() or Input.is_physical_key_pressed(KEY_E):
        exit_player()

    stick_angle = clampf(stick_angle, -0.55, 1.00)
    tool_angle = clampf(tool_angle, -1.0, 0.72)

func _enemy_control(delta: float) -> void:
    if is_hijack_in_progress():
        velocity.x = move_toward(velocity.x, 0.0, 18.0 * delta)
        velocity.z = move_toward(velocity.z, 0.0, 18.0 * delta)
        return
    ai_time += delta
    var target := get_tree().get_first_node_in_group("player")
    if target == null:
        return
    var to_target: Vector3 = target.global_position - global_position
    to_target.y = 0.0
    if to_target.length() > 0.1:
        var desired: float = atan2(-to_target.x, -to_target.z)
        rotation.y = lerp_angle(rotation.y, desired, 0.018)
    var forward: Vector3 = -global_basis.z
    var throttle: float = 1.0 if to_target.length() > 7.0 else 0.0
    var track_ratio := maxf(get_track_ratio(), 0.22)
    velocity.x = forward.x * throttle * drive_speed * 0.48 * track_ratio
    velocity.z = forward.z * throttle * drive_speed * 0.48 * track_ratio
    var hydro := maxf(get_hydraulic_ratio(), 0.24)
    arm_yaw = sin(ai_time * 0.74) * 0.46 * hydro
    boom_angle = -0.35 + sin(ai_time * 0.88) * 0.18 * hydro
    stick_angle = 0.30 + sin(ai_time * 1.14) * 0.22 * hydro
    tool_angle = -0.15 + sin(ai_time * 1.31) * 0.22 * hydro

func _apply_arm_pose() -> void:
    _boom.rotation = Vector3(boom_angle, arm_yaw, 0.0)
    _stick.rotation.x = stick_angle
    _tool.rotation.x = tool_angle
    if _thumb != null:
        _thumb.rotation.x = -0.76 if is_holding_load() else -0.05

func _store_safe_arm_pose() -> void:
    _safe_boom_angle = boom_angle
    _safe_stick_angle = stick_angle
    _safe_tool_angle = tool_angle
    _safe_arm_yaw = arm_yaw

func _set_interpolated_arm_pose(target_boom: float, target_stick: float, target_tool: float, target_yaw: float, t: float) -> void:
    boom_angle = lerpf(_safe_boom_angle, target_boom, t)
    stick_angle = lerpf(_safe_stick_angle, target_stick, t)
    tool_angle = lerpf(_safe_tool_angle, target_tool, t)
    arm_yaw = lerpf(_safe_arm_yaw, target_yaw, t)
    _apply_arm_pose()

func _resolve_arm_contact_pose() -> void:
    var target_boom := boom_angle
    var target_stick := stick_angle
    var target_tool := tool_angle
    var target_yaw := arm_yaw
    _apply_arm_pose()
    var contacts := _collect_hard_arm_contacts()
    if contacts.is_empty():
        _store_safe_arm_pose()
        return

    _react_to_arm_contacts(contacts)
    var low := 0.0
    var high := 1.0
    var best := 0.0
    for _i in 6:
        var mid := (low + high) * 0.5
        _set_interpolated_arm_pose(target_boom, target_stick, target_tool, target_yaw, mid)
        if _collect_hard_arm_contacts().is_empty():
            best = mid
            low = mid
        else:
            high = mid
    _set_interpolated_arm_pose(target_boom, target_stick, target_tool, target_yaw, best)
    _store_safe_arm_pose()

func _collect_hard_arm_contacts() -> Array[Node]:
    var contacts: Array[Node] = []
    if _arm_shapes.is_empty() or get_world_3d() == null:
        return contacts
    var space := get_world_3d().direct_space_state
    var exclude: Array[RID] = [get_rid()]
    if held_load is CollisionObject3D:
        exclude.append(held_load.get_rid())
    for collision in _arm_shapes:
        if collision == null or collision.shape == null:
            continue
        var query := PhysicsShapeQueryParameters3D.new()
        query.shape = collision.shape
        query.transform = collision.global_transform
        query.collision_mask = 8
        query.collide_with_bodies = true
        query.collide_with_areas = false
        query.exclude = exclude
        var hits := space.intersect_shape(query, 16)
        for hit in hits:
            var collider = hit.get("collider")
            if collider == null or collider == self or collider == held_load:
                continue
            if collider is RigidBody3D and not collider.freeze:
                continue
            if not contacts.has(collider):
                contacts.append(collider)
    return contacts

func _react_to_arm_contacts(contacts: Array[Node]) -> void:
    if _arm_contact_cooldown > 0.0:
        return
    var direction := _tool_tip_velocity.normalized() if _tool_tip_velocity.length_squared() > 0.04 else -_tool.global_basis.z
    var force := get_tool_force()
    var damaged := false
    for collider in contacts:
        if collider.has_method("machine_hit"):
            collider.machine_hit(force, direction)
            damaged = true
    velocity -= direction * minf(force * 0.010, 1.6)
    _arm_contact_cooldown = 0.12 if damaged else 0.07
    if hud != null and player_driver != null:
        hud.set_context("ARM CONTACT // LOAD PATH RESISTING MOTION")

func _update_tool_motion(delta: float) -> void:
    var tip := _tool.to_global(Vector3(0.0, -0.20, -1.10))
    if not _tool_motion_ready:
        _tool_tip_last = tip
        _tool_motion_ready = true
        return
    _tool_tip_velocity = (tip - _tool_tip_last) / maxf(delta, 0.001)
    _tool_tip_speed = _tool_tip_velocity.length()
    _tool_tip_last = tip

func _try_grip_load() -> bool:
    var best = null
    var best_distance := INF
    for body in _impact_probe.get_overlapping_bodies():
        if body == self or not body.is_in_group("physics_prop") or body.mass > 420.0:
            continue
        var d: float = body.global_position.distance_to(_grip_anchor.global_position)
        if d < best_distance:
            best_distance = d
            best = body
    if best == null:
        return false
    held_load = best
    if held_load.has_method("set_held"):
        held_load.set_held(true)
    hud.set_context("LOAD CLAMPED // MOVE ARM TO CARRY // CLAMP TO RELEASE")
    return true

func _update_held_load() -> void:
    if not is_holding_load():
        held_load = null
        return
    held_load.global_position = _grip_anchor.global_position
    held_load.global_basis = _grip_anchor.global_basis

func _release_load(with_throw: bool) -> void:
    if not is_holding_load():
        held_load = null
        return
    var load = held_load
    held_load = null
    if load.has_method("set_held"):
        load.set_held(false)
    if with_throw and load is RigidBody3D:
        load.linear_velocity = _tool_tip_velocity + velocity * 0.85
        load.angular_velocity = Vector3(_tool_tip_velocity.z, 0.8, -_tool_tip_velocity.x) * 0.16
    if hud != null:
        hud.set_context("DIRECT BOOM // PHYSICAL BUCKET // HYDRAULIC THUMB")

func _resolve_tool_impacts() -> void:
    if _impact_cooldown > 0.0:
        return
    var chassis_speed := Vector3(velocity.x, 0.0, velocity.z).length()
    if chassis_speed < 0.45 and _tool_tip_speed < 1.0:
        return
    var force := get_tool_force()
    var impact_dir := _tool_tip_velocity.normalized() if _tool_tip_velocity.length_squared() > 0.04 else -_tool.global_basis.z
    for body in _impact_probe.get_overlapping_bodies():
        if body == self or body == held_load:
            continue
        if body.has_method("machine_hit"):
            body.machine_hit(force, impact_dir)
            _impact_cooldown = 0.15
        elif body.has_method("take_hit"):
            var push := impact_dir * (10.0 + minf(_tool_tip_speed, 12.0)) + Vector3.UP * 4.5
            body.take_hit(push, 42.0 + minf(_tool_tip_speed, 12.0) * 1.2)
            _impact_cooldown = 0.15
        elif body is RigidBody3D and not body.freeze:
            body.apply_impulse(impact_dir * minf(force * body.mass * 0.035, 2200.0), body.to_local(_tool.global_position))
            _impact_cooldown = 0.12

func _update_damage_fx() -> void:
    if get_health_ratio() > 0.58 or _damage_fx_cooldown > 0.0:
        return
    _damage_fx_cooldown = 0.65 if get_health_ratio() > 0.28 else 0.32
    var color := Color(0.30, 0.28, 0.24) if get_health_ratio() > 0.28 else Color(0.12, 0.11, 0.10)
    ImpactFx.spawn(get_parent(), global_position + Vector3(0.75, 2.7, 0.6), Vector3.UP, color, 1.3, 5)
    if _work_light != null and get_health_ratio() < 0.32:
        _work_light.light_energy = 0.7 + absf(sin(Time.get_ticks_msec() * 0.012)) * 1.1

func _update_telemetry() -> void:
    if hud == null or player_driver == null or not hud.has_method("set_machine_telemetry") or _telemetry_timer > 0.0:
        return
    _telemetry_timer = 0.08
    hud.set_machine_telemetry(
        get_health_ratio(),
        get_hydraulic_ratio(),
        get_track_ratio(),
        clampf(get_tool_force() / 130.0, 0.0, 1.0),
        is_holding_load()
    )
