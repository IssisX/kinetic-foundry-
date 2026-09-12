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
    var structural_state := {}
    if structure != null and structure.has_method(
        "get_load_path_state"
    ):
        structural_state = structure.get_load_path_state()
    var gate_state := {}
    for gate in get_tree().get_nodes_in_group("breachable"):
        if gate.has_method("apply_world_loads"):
            gate.apply_world_loads(loads, sample_delta)
        if gate.has_method("get_load_path_state"):
            gate_state = gate.get_load_path_state()
    if excavator != null and excavator.has_method(
        "set_load_path_feedback"
    ):
        var combined := structural_state.duplicate()
        var gate_damage := float(gate_state.get("damage", 0.0))
        var deformation: Dictionary = combined.get(
            "deformation",
            {}
        )
        deformation = deformation.duplicate()
        deformation["max_displacement"] = maxf(
            float(deformation.get("max_displacement", 0.0)),
            gate_damage * 0.7
        )
        combined["deformation"] = deformation
        excavator.set_load_path_feedback(combined)
