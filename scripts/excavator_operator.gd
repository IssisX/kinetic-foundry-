extends "res://scripts/excavator_contact.gd"

const FLOOR_CLEARANCE := 0.16
const CLAMP_CLOSE_SPEED := 3.8
const CLAMP_OPEN_SPEED := 5.2
const CLAMP_RETRY_SECONDS := 0.12

var _clamp_command := false
var _clamp_amount := 0.0
var _clamp_retry := 0.0
var _ai_home := Vector3.ZERO
var _ai_home_ready := false

func get_control_profile() -> Dictionary:
    return {
        "machine_name": "EXCAVATOR",
        "mode": "OPERATOR POV // DIRECT END-EFFECTOR CONTROL",
        "primary": "REACH / CURL",
        "secondary": "RELEASE" if is_holding_load() else "CLAMP",
        "tertiary": "EXIT",
        "left_hint": "LEFT: DRIVE / STEER",
        "right_hint": "RIGHT: SWING / LIFT   •   DRAG REACH/CURL",
        "center_hint": "PHYSICAL THUMB CLAMP • LOAD • FLOOR GUARD"
    }

func _physics_process(delta: float) -> void:
    _clamp_retry = maxf(0.0, _clamp_retry - delta)
    var clamp_target := 1.0 if _clamp_command or is_holding_load() else 0.0
    _clamp_amount = move_toward(
        _clamp_amount,
        clamp_target,
        delta * (CLAMP_CLOSE_SPEED if clamp_target > _clamp_amount else CLAMP_OPEN_SPEED)
    )
    if (
        _clamp_command
        and not is_holding_load()
        and _clamp_amount >= 0.34
        and _clamp_retry <= 0.0
    ):
        _try_grip_load()
        _clamp_retry = CLAMP_RETRY_SECONDS
    super(delta)

func _player_control(delta: float) -> void:
    if hud == null or camera_rig == null:
        return
    var track_ratio := maxf(get_track_ratio(), 0.18)
    var hydraulic_ratio := maxf(get_hydraulic_ratio(), 0.22)
    var stability_authority := clampf(
        1.0 - maxf(_stability_ratio - 0.58, 0.0) * 0.58,
        0.42,
        1.0
    )
    hydraulic_ratio *= (
        (1.0 - _load_path_resistance * 0.42)
        * stability_authority
    )

    var axis: Vector2 = hud.move_axis
    var throttle := -axis.y
    var steering := axis.x
    var forward := -global_basis.z
    var chassis_brace := 1.0 - _load_path_resistance * _actuator_effort * 0.34
    var drive_stability := clampf(
        1.0 - maxf(_stability_ratio - 0.70, 0.0) * 0.72,
        0.36,
        1.0
    )
    velocity.x = forward.x * throttle * drive_speed * track_ratio * chassis_brace * drive_stability
    velocity.z = forward.z * throttle * drive_speed * track_ratio * chassis_brace * drive_stability
    rotation.y -= steering * turn_speed * track_ratio * drive_stability * delta

    var look: Vector2 = hud.consume_look()
    var look_effort := clampf(look.length() / 32.0, 0.0, 1.0)
    _actuator_effort = move_toward(
        _actuator_effort,
        look_effort,
        delta * (7.0 if look_effort > _actuator_effort else 3.2)
    )

    if hud.smash_held:
        # The primary machine button is a draggable precision pad: vertical
        # motion changes reach through the stick, horizontal motion curls the
        # bucket. This decouples the working end effector from house swing.
        stick_angle += look.y * 0.0030 * hydraulic_ratio
        tool_angle -= look.x * 0.0033 * hydraulic_ratio
    else:
        # Normal right-side drag controls only the two large spatial DOFs.
        arm_yaw -= look.x * 0.0029 * hydraulic_ratio
        boom_angle += look.y * 0.0025 * hydraulic_ratio

    # Consume the old combat pulse without adding a canned smash. Impacts now
    # come from real tool velocity and contact energy.
    hud.consume_attack()

    if hud.consume_grab():
        if is_holding_load():
            _clamp_command = false
            _release_load(false)
        else:
            _clamp_command = not _clamp_command
            if _clamp_command:
                _try_grip_load()
                _clamp_retry = CLAMP_RETRY_SECONDS

    if hud.consume_use() or Input.is_physical_key_pressed(KEY_E):
        exit_player()

    arm_yaw = clampf(arm_yaw, -1.25, 1.25)
    boom_angle = clampf(boom_angle, -0.82, 0.42)
    stick_angle = clampf(stick_angle, -0.48, 0.96)
    tool_angle = clampf(tool_angle, -0.92, 0.72)

func _enemy_control(delta: float) -> void:
    if not _ai_home_ready:
        _ai_home = global_position
        _ai_home_ready = true
    if is_hijack_in_progress():
        velocity.x = move_toward(velocity.x, 0.0, 18.0 * delta)
        velocity.z = move_toward(velocity.z, 0.0, 18.0 * delta)
        return

    ai_time += delta
    var home_delta := _ai_home - global_position
    home_delta.y = 0.0
    var track_ratio := maxf(get_track_ratio(), 0.22)
    if home_delta.length() > 3.2:
        var home_dir := home_delta.normalized()
        velocity.x = home_dir.x * drive_speed * 0.26 * track_ratio
        velocity.z = home_dir.z * drive_speed * 0.26 * track_ratio
        rotation.y = rotate_toward(
            rotation.y,
            atan2(-home_dir.x, -home_dir.z),
            0.55 * delta
        )
    else:
        velocity.x = move_toward(velocity.x, 0.0, 10.0 * delta)
        velocity.z = move_toward(velocity.z, 0.0, 10.0 * delta)

    # Hostile operator works the machine in its zone instead of shadowing the
    # player across the yard.
    var hydro := maxf(get_hydraulic_ratio(), 0.24)
    arm_yaw = sin(ai_time * 0.58) * 0.34 * hydro
    boom_angle = -0.10 + sin(ai_time * 0.62) * 0.10 * hydro
    stick_angle = 0.26 + sin(ai_time * 0.74) * 0.14 * hydro
    tool_angle = -0.06 + sin(ai_time * 0.91) * 0.18 * hydro

func _apply_arm_pose() -> void:
    _boom.rotation = Vector3(boom_angle, arm_yaw, 0.0)
    _stick.rotation.x = stick_angle
    _tool.rotation.x = tool_angle
    if _thumb != null:
        _thumb.rotation.x = lerpf(-0.05, -0.94, _clamp_amount)

func _resolve_arm_contact_pose() -> void:
    _apply_arm_pose()
    _enforce_floor_clearance()
    super()

func _enforce_floor_clearance() -> void:
    # Flat-yard ground is handled analytically here. This prevents the bucket
    # from living inside the floor without paying multiple intersect_shape
    # queries and rollback searches every physics tick.
    for _i in 4:
        var low_y := _tool_low_point_y()
        if low_y >= FLOOR_CLEARANCE:
            return
        var deficit := FLOOR_CLEARANCE - low_y
        boom_angle = minf(0.42, boom_angle + clampf(deficit * 0.18, 0.025, 0.16))
        stick_angle = minf(0.96, stick_angle + clampf(deficit * 0.10, 0.015, 0.10))
        tool_angle = minf(0.72, tool_angle + clampf(deficit * 0.14, 0.018, 0.12))
        _apply_arm_pose()

func _tool_low_point_y() -> float:
    var lowest := INF
    for point in [
        Vector3(-0.90, -0.78, -1.18),
        Vector3(0.90, -0.78, -1.18),
        Vector3(-0.90, -0.72, -0.40),
        Vector3(0.90, -0.72, -0.40)
    ]:
        lowest = minf(lowest, _tool.to_global(point).y)
    return lowest

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
        # Layer 1 is the static floor. The cheap floor guard above owns that
        # boundary; expensive hard-contact rollback is reserved for actual
        # structural/world interaction on layer 8.
        query.collision_mask = 8
        query.collide_with_bodies = true
        query.collide_with_areas = false
        query.exclude = exclude
        var hits := space.intersect_shape(query, 20)
        for hit in hits:
            var collider = hit.get("collider")
            if collider == null or collider == self or collider == held_load:
                continue
            if collider is RigidBody3D and not collider.freeze:
                continue
            if not contacts.has(collider):
                contacts.append(collider)
    return contacts

func _try_grip_load() -> bool:
    if _impact_probe == null:
        return false
    var hydraulic_ratio := maxf(get_hydraulic_ratio(), 0.18)
    var stability_penalty := clampf(
        1.0 - maxf(_stability_ratio - 0.72, 0.0) * 0.55,
        0.42,
        1.0
    )
    var mass_limit := lerpf(520.0, 1350.0, hydraulic_ratio) * stability_penalty
    var best: RigidBody3D = null
    var best_score := INF

    for body in _impact_probe.get_overlapping_bodies():
        if body == self or not (body is RigidBody3D):
            continue
        var rigid := body as RigidBody3D
        if rigid.freeze or rigid.mass > mass_limit:
            continue
        var offset := rigid.global_position - _grip_anchor.global_position
        var distance := offset.length()
        if distance > 2.25:
            continue
        var local := _grip_anchor.global_basis.inverse() * offset
        if absf(local.x) > 1.35 or absf(local.y) > 1.45 or local.z > 0.75:
            continue
        var mass_ratio := rigid.mass / maxf(mass_limit, 1.0)
        var score := distance + mass_ratio * 0.42
        if score < best_score:
            best_score = score
            best = rigid

    if best == null:
        if hud != null and player_driver != null and _clamp_command:
            hud.set_context("THUMB CLOSING // PLACE LOAD BETWEEN BUCKET + THUMB")
        return false

    held_load = best
    _set_machine_hold(held_load, true)
    if hud != null:
        hud.set_context(
            "LOAD CAPTURED // MOVE TOOL TO LIFT • OPEN CLAMP TO RELEASE"
        )
    return true

func _release_load(with_throw: bool) -> void:
    _clamp_command = false
    super(with_throw)
