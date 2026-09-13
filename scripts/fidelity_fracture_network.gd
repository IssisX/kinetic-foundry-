class_name FidelityFractureNetwork
extends "res://scripts/fracture_network.gd"

## Same fracture authority as FractureNetwork, but component target comes from
## the shared fidelity service instead of a hard-coded gameplay cap.

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
