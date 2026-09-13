class_name LoadPathCoupler
extends Node

var structure
var excavator
var _sample_timer := 0.0

func configure(structure_node, machine_node = null) -> void:
    structure = structure_node
    excavator = machine_node

func _physics_process(delta: float) -> void:
    _sample_timer -= delta
    if _sample_timer > 0.0:
        return
    var sample_delta := 0.10
    _sample_timer = sample_delta
    var loads := get_tree().get_nodes_in_group("physics_prop")

    if structure != null and structure.has_method("apply_world_loads"):
        structure.apply_world_loads(loads, sample_delta)

    var structural_state := {}
    if structure != null and structure.has_method("get_load_path_state"):
        structural_state = structure.get_load_path_state()

    var gate_state := {}
    for gate in get_tree().get_nodes_in_group("breachable"):
        if gate.has_method("apply_world_loads"):
            gate.apply_world_loads(loads, sample_delta)
        if gate.has_method("get_load_path_state"):
            gate_state = gate.get_load_path_state()

    var gate_damage := float(gate_state.get("damage", 0.0))
    for machine in get_tree().get_nodes_in_group("machine"):
        if machine == null or not is_instance_valid(machine):
            continue
        if not machine.has_method("set_load_path_feedback"):
            continue
        var contact_state := {}
        if machine.has_method("get_sustained_contact_state"):
            contact_state = machine.get_sustained_contact_state()
        var combined := structural_state.duplicate(true)
        var deformation: Dictionary = combined.get("deformation", {})
        deformation = deformation.duplicate(true)
        deformation["max_displacement"] = maxf(
            float(deformation.get("max_displacement", 0.0)),
            gate_damage * 0.7
        )
        combined["deformation"] = deformation
        combined["reaction_ratio"] = _contact_reaction(contact_state)
        combined["contact_active"] = bool(contact_state.get("active", false))
        machine.set_load_path_feedback(combined)

func _contact_reaction(contact_state: Dictionary) -> float:
    if not bool(contact_state.get("active", false)):
        return 0.0

    var force_ratio := clampf(
        float(contact_state.get("force", 0.0)) / 210.0,
        0.0,
        1.0
    )
    var effort := clampf(
        float(contact_state.get("effort", 0.0)),
        0.0,
        1.0
    )
    var persistence := clampf(
        float(contact_state.get("persistence", 0.0)) / 0.45,
        0.0,
        1.0
    )
    var reaction := 0.0
    var contacts_value: Variant = contact_state.get("contacts", [])
    var contacts: Array = contacts_value as Array

    for collider_value in contacts:
        var collider := collider_value as Node
        if collider == null or not is_instance_valid(collider):
            continue
        var owner := _load_path_owner(collider)
        if owner != null and owner.has_method("get_load_path_state"):
            var owner_state: Dictionary = owner.call("get_load_path_state") as Dictionary
            reaction = maxf(
                reaction,
                _owner_reaction(
                    owner_state,
                    force_ratio,
                    effort,
                    persistence
                )
            )
        elif collider is StaticBody3D:
            reaction = maxf(
                reaction,
                clampf(
                    0.20
                    + effort * 0.40
                    + force_ratio * 0.18
                    + persistence * 0.10,
                    0.0,
                    0.82
                )
            )
    return reaction

func _load_path_owner(collider: Node) -> Node:
    var current: Node = collider
    while current != null:
        if current == structure:
            return current
        if current.is_in_group("breachable"):
            return current
        current = current.get_parent()
    return null

func _owner_reaction(
        state: Dictionary,
        force_ratio: float,
        effort: float,
        persistence: float
) -> float:
    var deformation: Dictionary = state.get("deformation", {})
    var damage := maxf(
        float(state.get("damage", 0.0)),
        float(deformation.get("damage", 0.0))
    )
    var broken := maxf(
        float(state.get("broken_fraction", 0.0)),
        float(deformation.get("broken_fraction", 0.0))
    )
    var displacement := float(
        deformation.get("max_displacement", 0.0)
    )
    var overload := clampf(
        float(state.get("overload_ratio", 0.0)) / 1.6,
        0.0,
        1.0
    )
    var intact := clampf(
        1.0 - damage * 0.58 - broken * 0.82,
        0.14,
        1.0
    )
    var stiffness := clampf(
        float(state.get("stiffness_ratio", 1.0)),
        0.12,
        1.0
    )
    if deformation.has("stiffness_ratio"):
        stiffness = minf(
            stiffness,
            clampf(float(deformation.get("stiffness_ratio", 1.0)), 0.12, 1.0)
        )
    intact *= lerpf(0.22, 1.0, stiffness)
    var wave_peak := clampf(
        float(deformation.get("wave_peak", 0.0)),
        0.0,
        1.0
    )
    var yielding := clampf(displacement / 0.90, 0.0, 1.0)
    var commanded := (
        0.18
        + force_ratio * 0.27
        + effort * 0.30
        + persistence * 0.16
        + overload * 0.10
        + wave_peak * 0.08
    )
    return clampf(
        commanded * intact - yielding * 0.10,
        0.05,
        1.0
    )