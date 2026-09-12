extends "res://scripts/excavator.gd"

func get_operator_view_anchor() -> Node3D:
    return get_node_or_null("OperatorView") as Node3D

func get_operator_fov() -> float:
    return 78.0

func get_control_profile() -> Dictionary:
    return {
        "machine_name": "EXCAVATOR",
        "mode": "OPERATOR POV // HYDRAULIC WORKER CONTROL",
        "primary": "CURL / SMASH",
        "secondary": "RELEASE" if is_holding_load() else "CLAMP",
        "tertiary": "EXIT",
        "left_hint": "DRIVE / STEER",
        "right_hint": "SWING BOOM / LIFT",
        "center_hint": "BUCKET FORCE + LOAD PATH"
    }

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

func _resolve_arm_contact_pose() -> void:
    super()
    _push_dynamic_arm_contacts()

func _push_dynamic_arm_contacts() -> void:
    if _arm_shapes.is_empty() or get_world_3d() == null:
        return
    var chassis_motion := Vector3(velocity.x, 0.0, velocity.z)
    var motion := _tool_tip_velocity + chassis_motion
    var speed := maxf(_tool_tip_speed, chassis_motion.length())
    if speed < 0.30:
        return

    var direction := motion.normalized() if motion.length_squared() > 0.01 else -_tool.global_basis.z
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
                body.machine_hit(force * 0.42, direction)
            else:
                var impulse_mag: float = minf((8.0 + speed * 7.5) * body.mass, 2400.0)
                var contact_offset: Vector3 = body.to_local(collision.global_position)
                body.apply_impulse(direction * impulse_mag + Vector3.UP * body.mass * 0.55, contact_offset)
                body.apply_torque_impulse(Vector3(direction.z, 0.18, -direction.x) * body.mass * minf(speed, 8.0) * 0.28)

    if not affected.is_empty() and player_driver != null and camera_rig != null and camera_rig.has_method("add_machine_impulse"):
        var local_bump := Vector3(direction.x, minf(speed * 0.035, 0.7), direction.z)
        camera_rig.add_machine_impulse(clampf(0.010 + speed * 0.0018, 0.012, 0.050), local_bump)
