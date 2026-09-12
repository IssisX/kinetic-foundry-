class_name LoadPathCoupler
extends Node

var structure
var excavator
var _sample_timer := 0.0

func configure(structure_node, machine_node) -> void:
    structure = structure_node
    excavator = machine_node

func _physics_process(delta: float) -> void:
    _sample_timer -= delta
    if _sample_timer > 0.0:
        return
    var sample_delta := 0.10
    _sample_timer = sample_delta
    var loads := get_tree().get_nodes_in_group("physics_prop")
    if structure != null and structure.has_method(
        "apply_world_loads"
    ):
        structure.apply_world_loads(loads, sample_delta)
    for gate in get_tree().get_nodes_in_group("breachable"):
        if gate.has_method("apply_world_loads"):
            gate.apply_world_loads(loads, sample_delta)
