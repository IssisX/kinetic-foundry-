extends StaticBody3D

var gate_owner

func machine_hit(amount: float, direction: Vector3) -> void:
    machine_hit_at(amount, direction, global_position, amount * 42.0)

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
