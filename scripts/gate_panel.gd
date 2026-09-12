extends StaticBody3D

var gate_owner

func machine_hit(amount: float, direction: Vector3) -> void:
    var world_point := _infer_machine_contact_point()
    machine_hit_at(
        amount,
        direction,
        world_point,
        _infer_impact_energy(amount)
    )

func machine_hit_at(
        amount: float,
        direction: Vector3,
        world_point: Vector3,
        impact_energy: float
) -> void:
    if gate_owner == null:
        return
    var index := int(get_meta("gate_index", -1))
    if gate_owner.has_method("damage_panel_at"):
        gate_owner.damage_panel_at(
            index,
            amount,
            direction,
            world_point,
            impact_energy
        )
    else:
        gate_owner.damage_panel(index, amount, direction)

func _infer_machine_contact_point() -> Vector3:
    var probe := global_position
    var best_distance := INF
    for machine in get_tree().get_nodes_in_group("machine"):
        if not is_instance_valid(machine):
            continue
        if not machine.has_method("get_sustained_contact_state"):
            continue
        var state: Dictionary = machine.get_sustained_contact_state()
        var position_value: Variant = state.get(
            "position",
            machine.global_position
        )
        var candidate := position_value as Vector3
        var distance := candidate.distance_to(global_position)
        if distance < best_distance:
            best_distance = distance
            probe = candidate
    var local := to_local(probe)
    local.x = clampf(local.x, -2.0, 2.0)
    local.y = clampf(local.y, -2.0, 2.0)
    local.z = clampf(local.z, -0.13, 0.13)
    return to_global(local)

func _infer_impact_energy(amount: float) -> float:
    var energy := amount * amount * 3.2
    for machine in get_tree().get_nodes_in_group("machine"):
        if not is_instance_valid(machine):
            continue
        if not machine.has_method("get_sustained_contact_state"):
            continue
        var state: Dictionary = machine.get_sustained_contact_state()
        var force := maxf(float(state.get("force", 0.0)), amount)
        var effort := clampf(float(state.get("effort", 0.0)), 0.0, 1.0)
        var held_mass := maxf(float(state.get("held_mass", 0.0)), 0.0)
        energy = maxf(
            energy,
            force * force * (0.34 + effort * 0.72)
            * (1.0 + held_mass / 620.0)
        )
    return energy
