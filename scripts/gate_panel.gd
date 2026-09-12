extends StaticBody3D

var gate_owner

func machine_hit(amount: float, direction: Vector3) -> void:
    if gate_owner == null:
        return
    var index := int(get_meta("gate_index", -1))
    gate_owner.damage_panel(index, amount, direction)
