extends "res://scripts/excavator.gd"

const MaterialFx = preload("res://scripts/material_fx.gd")

const MACHINE_EFFECTIVE_MASS := 2600.0
const TRACK_HALF_WIDTH := 1.48
const TRACK_HALF_LENGTH := 2.20
const ARM_EFFECTIVE_MASS := 360.0
const FORCE_TO_NEWTONS := 145.0

var _hydraulic_fx_budget := 0.0
var _previous_hydraulic_health := 260.0
var _actuator_effort := 0.0
var _contact_age := 0.0
var _contact_targets: Array[Node] = []
var _stability_ratio := 0.0
var _stability_lateral := 0.0
var _stability_longitudinal := 0.0
var _tip_direction_local := Vector3.ZERO
var _stability_damage_bank := 0.0
var _stability_notice_cooldown := 0.0
var _physical_event_cooldown := 0.0

func get_operator_view_anchor() -> Node3D:
    var anchor := get_node_or_null("OperatorView") as Node3D
    if anchor != null:
        anchor.position = Vector3(-0.66, 2.78, 0.12)
        anchor.rotation_degrees = Vector3(-1.0, 0.0, 0.0)
    return anchor

func get_operator_fov() -> float:
    return 72.0

func get_control_profile() -> Dictionary:
    return {
        "machine_name": "EXCAVATOR",
        "mode": "OPERATOR POV // HYDRAULIC WORKER CONTROL",
        "primary": "CURL / SMASH",
        "secondary": "RELEASE" if is_holding_load() else "CLAMP",
        "tertiary": "EXIT",
        "left_hint": "DRIVE / STEER",
        "right_hint": "SWING BOOM / LIFT",
        "center_hint": "BUCKET FORCE + LOAD PATH + STABILITY"
    }

func _physics_process(delta: float) -> void:
    _hydraulic_fx_budget = maxf(0.0, _hydraulic_fx_budget - delta)
    _stability_notice_cooldown = maxf(
        0.0,
        _stability_notice_cooldown - delta
    )
    _physical_event_cooldown = maxf(
        0.0,
        _physical_event_cooldown - delta
    )
    _update_stability(delta)
    super(delta)
    if _contact_targets.is_empty():
        _contact_age = move_toward(_contact_age, 0.0, delta * 5.0)
    else:
        _contact_age = minf(_contact_age + delta, 2.0)
    _apply_stability_consequence(delta)

func get_tool_force() -> float:
    var base_force := super()
    var hydraulic_ratio := maxf(get_hydraulic_ratio(), 0.18)
    var commanded_pressure := _actuator_effort * lerpf(
        42.0,
        118.0,
        hydraulic_ratio
    )
    var braced_gain := 1.0 + _load_path_resistance * 0.34
    return minf((base_force + commanded_pressure) * braced_gain, 245.0)

func set_load_path_feedback(state: Dictionary) -> void:
    if not state.has("reaction_ratio"):
        super(state)
        return
    var target := clampf(
        float(state.get("reaction_ratio", 0.0)),
        0.0,
        1.0
    )
    _load_path_resistance = move_toward(
        _load_path_resistance,
        target,
        0.30
    )

func get_sustained_contact_state() -> Dictionary:
    var valid_contacts: Array[Node] = []
    for collider in _contact_targets:
        if is_instance_valid(collider):
            valid_contacts.append(collider)
    var direction := -_tool.global_basis.z
    if _tool_tip_velocity.length_squared() > 0.04:
        direction = _tool_tip_velocity.normalized()
    var held_mass := 0.0
    if is_holding_load():
        held_mass = float(held_load.get("mass"))
    return {
        "active": not valid_contacts.is_empty(),
        "contacts": valid_contacts,
        "position": _tool.global_position,
        "direction": direction,
        "force": get_tool_force(),
        "effort": _actuator_effort,
        "persistence": _contact_age,
        "reaction_ratio": _load_path_resistance,
        "held_mass": held_mass,
        "stability_ratio": _stability_ratio
    }

func get_stability_state() -> Dictionary:
    return {
        "ratio": _stability_ratio,
        "lateral": _stability_lateral,
        "longitudinal": _stability_longitudinal,
        "tip_direction_local": _tip_direction_local,
        "braced": _load_path_resistance * _actuator_effort
    }

func _update_stability(delta: float) -> void:
    if _tool == null:
        return
    var gravity := 9.81
    var tool_local := to_local(_tool.global_position)
    var lateral_moment := (
        ARM_EFFECTIVE_MASS
        * gravity
        * absf(tool_local.x)
        * 0.72
    )
    var longitudinal_moment := (
        ARM_EFFECTIVE_MASS
        * gravity
        * maxf(absf(tool_local.z) - 0.85, 0.0)
        * 0.72
    )
    var weighted_direction := Vector3(
        tool_local.x * ARM_EFFECTIVE_MASS,
        0.0,
        tool_local.z * ARM_EFFECTIVE_MASS
    )

    if is_holding_load():
        var load_mass := float(held_load.get("mass"))
        var load_local := to_local(held_load.global_position)
        lateral_moment += load_mass * gravity * absf(load_local.x)
        longitudinal_moment += load_mass * gravity * absf(load_local.z)
        weighted_direction += Vector3(
            load_local.x * load_mass,
            0.0,
            load_local.z * load_mass
        )

    if _load_path_resistance > 0.02 and _actuator_effort > 0.05:
        var contact_force := (
            get_tool_force()
            * FORCE_TO_NEWTONS
            * _load_path_resistance
            * _actuator_effort
        )
        lateral_moment += contact_force * absf(tool_local.x) * 0.36
        longitudinal_moment += contact_force * absf(tool_local.z) * 0.36

    var brace_gain := 1.0 + (
        _load_path_resistance
        * _actuator_effort
        * clampf(1.35 - tool_local.y * 0.18, 0.15, 1.0)
        * 0.46
    )
    var lateral_capacity := (
        MACHINE_EFFECTIVE_MASS
        * gravity
        * TRACK_HALF_WIDTH
        * brace_gain
    )
    var longitudinal_capacity := (
        MACHINE_EFFECTIVE_MASS
        * gravity
        * TRACK_HALF_LENGTH
        * brace_gain
    )
    _stability_lateral = lateral_moment / maxf(lateral_capacity, 1.0)
    _stability_longitudinal = (
        longitudinal_moment / maxf(longitudinal_capacity, 1.0)
    )
    var target_ratio := maxf(
        _stability_lateral,
        _stability_longitudinal
    )
    _stability_ratio = move_toward(
        _stability_ratio,
        target_ratio,
        delta * 2.8
    )
    if weighted_direction.length_squared() > 0.001:
        _tip_direction_local = weighted_direction.normalized()
    else:
        _tip_direction_local = Vector3.ZERO

func _apply_stability_consequence(delta: float) -> void:
    if _stability_ratio <= 0.88:
        _stability_damage_bank = maxf(
            0.0,
            _stability_damage_bank - delta * 0.8
        )
        return

    var excess := clampf(
        (_stability_ratio - 0.88) / 0.42,
        0.0,
        1.5
    )
    if _tip_direction_local.length_squared() > 0.001:
        var skid_world := global_basis * Vector3(
            _tip_direction_local.x,
            0.0,
            _tip_direction_local.z
        )
        skid_world.y = 0.0
        if skid_world.length_squared() > 0.001:
            skid_world = skid_world.normalized()
            velocity.x += skid_world.x * excess * 0.70
            velocity.z += skid_world.z * excess * 0.70

    _stability_damage_bank += (
        maxf(_stability_ratio - 1.0, 0.0) ** 2
        * delta
        * 18.0
    )
    if _stability_damage_bank >= 1.0:
        var damage := minf(_stability_damage_bank, 3.5)
        _stability_damage_bank -= damage
        track_health = maxf(0.0, track_health - damage * 1.15)
        chassis_health = maxf(0.0, chassis_health - damage * 0.28)
        _refresh_damage_visuals()

    if (
        player_driver != null
        and _stability_ratio > 0.96
        and _stability_notice_cooldown <= 0.0
    ):
        if hud != null:
            hud.set_context(
                "LOAD SHIFT // BRACE BUCKET OR RETRACT ARM"
            )
        if (
            camera_rig != null
            and camera_rig.has_method("add_machine_impulse")
        ):
            var bump := global_basis * Vector3(
                _tip_direction_local.x,
                0.12,
                _tip_direction_local.z
            )
            camera_rig.add_machine_impulse(
                clampf(0.014 + excess * 0.018, 0.014, 0.040),
                bump
            )
        _stability_notice_cooldown = 0.65

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
    var throttle: float = -axis.y
    var steering: float = axis.x
    var forward: Vector3 = -global_basis.z
    var chassis_brace := (
        1.0 - _load_path_resistance * _actuator_effort * 0.34
    )
    var drive_stability := clampf(
        1.0 - maxf(_stability_ratio - 0.70, 0.0) * 0.72,
        0.36,
        1.0
    )
    velocity.x = (
        forward.x
        * throttle
        * drive_speed
        * track_ratio
        * chassis_brace
        * drive_stability
    )
    velocity.z = (
        forward.z
        * throttle
        * drive_speed
        * track_ratio
        * chassis_brace
        * drive_stability
    )
    rotation.y -= (
        steering
        * turn_speed
        * track_ratio
        * drive_stability
        * delta
    )

    var look: Vector2 = hud.consume_look()
    var look_effort := clampf(look.length() / 32.0, 0.0, 1.0)
    var desired_effort := maxf(
        look_effort,
        1.0 if hud.smash_held else 0.0
    )
    _actuator_effort = move_toward(
        _actuator_effort,
        desired_effort,
        delta * (
            7.0
            if desired_effort > _actuator_effort
            else 3.2
        )
    )

    arm_yaw -= look.x * 0.0032 * hydraulic_ratio
    boom_angle += look.y * 0.0026 * hydraulic_ratio
    arm_yaw = clampf(arm_yaw, -1.25, 1.25)
    boom_angle = clampf(boom_angle, -0.95, 0.42)

    if hud.smash_held:
        stick_angle -= 1.05 * hydraulic_ratio * delta
        tool_angle -= 1.30 * hydraulic_ratio * delta
    if hud.consume_attack():
        _actuator_effort = 1.0
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

func _apply_machine_damage(amount: float, direction: Vector3) -> void:
    var hydraulic_before := hydraulic_health
    super(amount, direction)
    var hydraulic_loss := maxf(
        0.0,
        hydraulic_before - hydraulic_health
    )

    if amount >= 10.0:
        MaterialFx.steel(
            get_parent(),
            global_position
            + Vector3.UP * 1.55
            + direction.normalized() * 0.6,
            direction,
            clampf(amount / 18.0, 0.6, 4.0)
        )

    if (
        hydraulic_loss > 2.0
        and hydraulic_health < 190.0
        and _hydraulic_fx_budget <= 0.0
    ):
        var rupture_strength := clampf(
            (260.0 - hydraulic_health) / 62.0,
            0.8,
            4.5
        )
        MaterialFx.hydraulic(
            get_parent(),
            _boom.to_global(Vector3(0.40, 0.18, -1.6))
            if _boom != null
            else global_position + Vector3.UP * 2.4,
            direction + Vector3.UP * 0.55,
            rupture_strength
        )
        _hydraulic_fx_budget = lerpf(
            1.1,
            0.35,
            clampf(
                (190.0 - hydraulic_health) / 150.0,
                0.0,
                1.0
            )
        )
    _previous_hydraulic_health = hydraulic_health

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
        query.collision_mask = 1 | 8
        query.collide_with_bodies = true
        query.collide_with_areas = false
        query.exclude = exclude
        var hits := space.intersect_shape(query, 24)
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
    super(contacts)
    if _physical_event_cooldown > 0.0 or contacts.is_empty():
        return
    var force := get_tool_force()
    if force < 42.0 and _tool_tip_speed < 1.5:
        return
    var held_mass := 0.0
    if is_holding_load():
        held_mass = float(held_load.get("mass"))
    var event_impulse := (
        force
        * (1.0 + minf(_tool_tip_speed, 10.0) * 0.38)
        * (1.0 + held_mass / 520.0)
    )
    get_tree().call_group(
        "physical_event_listener",
        "physical_event",
        {
            "type": "machine_contact",
            "position": _tool.global_position,
            "impulse": event_impulse,
            "mass": MACHINE_EFFECTIVE_MASS + held_mass,
            "fracture": clampf(
                _load_path_resistance * 0.35
                + _actuator_effort * 0.22,
                0.0,
                1.0
            ),
            "radius": 5.5,
            "novelty": clampf(
                0.58 + _contact_age * 0.18,
                0.58,
                1.0
            )
        }
    )
    _physical_event_cooldown = 0.20

func _resolve_arm_contact_pose() -> void:
    var target_boom := boom_angle
    var target_stick := stick_angle
    var target_tool := tool_angle
    var target_yaw := arm_yaw
    _apply_arm_pose()
    var contacts := _collect_hard_arm_contacts()
    _contact_targets.clear()
    for collider in contacts:
        if is_instance_valid(collider):
            _contact_targets.append(collider)
    if contacts.is_empty():
        _store_safe_arm_pose()
        _push_dynamic_arm_contacts()
        return

    _react_to_arm_contacts(contacts)
    var low := 0.0
    var high := 1.0
    var best := 0.0
    for _i in 6:
        var mid := (low + high) * 0.5
        _set_interpolated_arm_pose(
            target_boom,
            target_stick,
            target_tool,
            target_yaw,
            mid
        )
        if _collect_hard_arm_contacts().is_empty():
            best = mid
            low = mid
        else:
            high = mid
    _set_interpolated_arm_pose(
        target_boom,
        target_stick,
        target_tool,
        target_yaw,
        best
    )
    _store_safe_arm_pose()
    _push_dynamic_arm_contacts()

func _push_dynamic_arm_contacts() -> void:
    if _arm_shapes.is_empty() or get_world_3d() == null:
        return
    var chassis_motion := Vector3(velocity.x, 0.0, velocity.z)
    var motion := _tool_tip_velocity + chassis_motion
    var speed := maxf(_tool_tip_speed, chassis_motion.length())
    if speed < 0.30:
        return

    var direction := (
        motion.normalized()
        if motion.length_squared() > 0.01
        else -_tool.global_basis.z
    )
    var force := get_tool_force()
    var space := get_world_3d().direct_space_state
    var exclude: Array[RID] = [get_rid()]
    if held_load is CollisionObject3D:
        exclude.append(held_load.get_rid())

    var affected: Dictionary = {}
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
        var hits := space.intersect_shape(query, 24)
        for hit in hits:
            var body = hit.get("collider")
            if not (body is RigidBody3D) or body.freeze or body == held_load:
                continue
            var id: int = body.get_instance_id()
            if affected.has(id):
                continue
            affected[id] = true
            if body.has_method("machine_hit"):
                _deliver_machine_hit(
                    body,
                    force * 0.42,
                    direction,
                    collision.global_position
                )
            else:
                var impulse_mag: float = minf(
                    (8.0 + speed * 7.5) * body.mass,
                    2400.0
                )
                var contact_offset: Vector3 = body.to_local(
                    collision.global_position
                )
                body.apply_impulse(
                    direction * impulse_mag
                    + Vector3.UP * body.mass * 0.55,
                    contact_offset
                )
                body.apply_torque_impulse(
                    Vector3(direction.z, 0.18, -direction.x)
                    * body.mass
                    * minf(speed, 8.0)
                    * 0.28
                )

    if not affected.is_empty():
        MaterialFx.steel(
            get_parent(),
            _tool.global_position,
            direction,
            clampf(force / 42.0, 0.7, 3.6)
        )
        if (
            player_driver != null
            and camera_rig != null
            and camera_rig.has_method("add_machine_impulse")
        ):
            var local_bump := Vector3(
                direction.x,
                minf(speed * 0.035, 0.7),
                direction.z
            )
            camera_rig.add_machine_impulse(
                clampf(
                    0.010 + speed * 0.0018,
                    0.012,
                    0.050
                ),
                local_bump
            )
