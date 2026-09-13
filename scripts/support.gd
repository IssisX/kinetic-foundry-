extends StaticBody3D

var frame

func machine_hit(amount: float, direction: Vector3) -> void:
    if frame == null:
        return
    var hit_pos := _infer_machine_contact_point()
    var index := int(get_meta("support_index", -1))
    if frame.has_method("damage_support_at"):
        frame.damage_support_at(
            index,
            amount,
            direction,
            hit_pos,
            _infer_impact_energy(amount)
        )
    else:
        frame.damage_support(index, amount, direction)

func machine_hit_at(
        amount: float,
        direction: Vector3,
        world_point: Vector3,
        impact_energy: float
) -> void:
    if frame == null:
        return
    var index := int(get_meta("support_index", -1))
    if frame.has_method("damage_support_at"):
        frame.damage_support_at(
            index,
            amount,
            direction,
            world_point,
            impact_energy
        )
    else:
        frame.damage_support(index, amount, direction)

func _infer_machine_contact_point() -> Vector3:
    var probe := global_position
    var best_distance := INF
    for machine in get_tree().get_nodes_in_group("machine"):
        if not is_instance_valid(machine):
            continue
        if not machine.has_method("get_sustained_contact_state"):
            continue
        var state: Dictionary = machine.get_sustained_contact_state()
        var candidate_value: Variant = state.get(
            "position",
            machine.global_position
        )
        var candidate := candidate_value as Vector3
        var distance := candidate.distance_to(global_position)
        if distance < best_distance:
            best_distance = distance
            probe = candidate
    var local := to_local(probe)
    local.x = clampf(local.x, -0.38, 0.38)
    local.y = clampf(local.y, -2.30, 2.30)
    local.z = clampf(local.z, -0.38, 0.38)
    return to_global(local)

func _infer_impact_energy(amount: float) -> float:
    var force := 0.0
    var effort := 0.0
    for machine in get_tree().get_nodes_in_group("machine"):
        if not is_instance_valid(machine):
            continue
        if not machine.has_method("get_sustained_contact_state"):
            continue
        var state: Dictionary = machine.get_sustained_contact_state()
        force = maxf(force, float(state.get("force", 0.0)))
        effort = maxf(effort, float(state.get("effort", 0.0)))
    return EnergyPartition.nominal_impact_energy(amount, force, effort)
