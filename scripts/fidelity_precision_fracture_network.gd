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
