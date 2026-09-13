class_name FidelityPrecisionFractureNetwork
extends "res://scripts/precision_fracture_network.gd"

## Precision-contact variant with the same energy law and fidelity-owned
## component budget. The parent still owns localized denting and crack cuts.

func fracture_by_energy(
        local_point: Vector3,
        impact_direction: Vector3,
        available_energy: float,
        _target_components: int = 7
) -> Dictionary:
    return super.fracture_by_energy(
        local_point,
        impact_direction,
        available_energy,
        Fidelity.max_shards()
    )

func get_node_heat(index: int) -> float:
    if index < 0 or index >= _positions.size():
        return 0.0
    var peak_tensile := 0.0
    for bond in _bonds:
        var first := int(bond.a)
        var second := int(bond.b)
        if first != index and second != index:
            continue
        var effective_rest := maxf(
            float(bond.rest) * (1.0 + float(bond.plastic)),
            0.0001
        )
        var current := _positions[first].distance_to(_positions[second])
        peak_tensile = maxf(
            peak_tensile,
            maxf(0.0, (current - effective_rest) / effective_rest)
        )
    return smoothstep(0.002, 0.080, peak_tensile)

func get_node_load(index: int) -> float:
    if index < 0 or index >= _positions.size():
        return 0.0
    var accumulated := 0.0
    for bond in _bonds:
        if int(bond.a) == index or int(bond.b) == index:
            accumulated += absf(float(bond.lambda))
    var reference := maxf(_node_mass * 9.81 * 0.020, 0.001)
    return clampf(1.0 - exp(-accumulated / reference), 0.0, 1.0)

func get_bond_visuals() -> Array[Dictionary]:
    var result: Array[Dictionary] = super.get_bond_visuals()
    for index in mini(result.size(), _bonds.size()):
        var bond: Dictionary = _bonds[index]
        var first := int(bond.a)
        var second := int(bond.b)
        var effective_rest := maxf(
            float(bond.rest) * (1.0 + float(bond.plastic)),
            0.0001
        )
        var current := _positions[first].distance_to(_positions[second])
        result[index]["lambda"] = absf(float(bond.lambda))
        result[index]["opening"] = maxf(0.0, current - effective_rest)
    return result
