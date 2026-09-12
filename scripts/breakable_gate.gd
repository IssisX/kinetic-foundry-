extends Node3D

const GeomUtil = preload("res://scripts/geom.gd")
const MaterialFx = preload("res://scripts/material_fx.gd")
const GatePanelScript = preload("res://scripts/gate_panel.gd")
const StructuralDebris = preload(
    "res://scripts/structural_debris.gd"
)
const FractureNetwork = preload(
    "res://scripts/fracture_network.gd"
)

var panel_health := [120.0, 120.0]
var panels: Array[StaticBody3D] = []
var panel_networks: Array[FractureNetwork] = []
var _panel_base_positions: Array[Vector3] = []
var breached := false
var wedge_mass := 0.0
var pry_energy := 0.0
var _load_damage_bank := 0.0

func _ready() -> void:
    add_to_group("breachable")
    _build_gate()

func _build_gate() -> void:
    for side in [-1.0, 1.0]:
        var index := 0 if side < 0.0 else 1
        var panel := StaticBody3D.new()
        panel.position = Vector3(side * 2.15, 2.05, 0.0)
        panel.collision_layer = 8
        panel.collision_mask = 1 | 2 | 4
        panel.set_meta("gate_index", index)
        panel.set_script(GatePanelScript)
        panel.set("gate_owner", self)
        add_child(panel)
        panels.append(panel)
        _panel_base_positions.append(panel.position)
        var frame := GeomUtil.box_mesh(Vector3(4.0, 4.0, 0.24), Color(0.17, 0.18, 0.165), 0.88, 0.26)
        panel.add_child(frame)
        GeomUtil.add_box_collision(panel, Vector3(4.0, 4.0, 0.24))
        for rib in 5:
            var rib_mesh := GeomUtil.box_mesh(Vector3(0.12, 3.55, 0.08), Color(0.40, 0.36, 0.22), 0.80, 0.28)
            rib_mesh.position = Vector3(-1.55 + float(rib) * 0.78, 0.0, -0.17)
            panel.add_child(rib_mesh)
        for stripe in 5:
            var warning := GeomUtil.box_mesh(Vector3(0.66, 0.16, 0.035), Color(0.82, 0.54, 0.08), 0.78, 0.10)
            warning.position = Vector3(-1.25 + float(stripe) * 0.62, -1.45, -0.19)
            warning.rotation.z = 0.55
            panel.add_child(warning)
        var network := FractureNetwork.new()
        network.configure_grid(
            5,
            5,
            Vector3(4.0, 0.0, 4.0),
            310.0,
            205.0,
            true
        )
        panel_networks.append(network)

    for side in [-1.0, 1.0]:
        var post := GeomUtil.static_box(self, "GatePost", Vector3(side * 4.45, 2.5, 0.0), Vector3(0.48, 5.0, 0.72), Color(0.25, 0.25, 0.22))
        var beacon := OmniLight3D.new()
        beacon.position = Vector3(0.0, 2.25, -0.5)
        beacon.light_color = Color(0.98, 0.34, 0.04)
        beacon.light_energy = 1.4
        beacon.omni_range = 4.2
        post.add_child(beacon)

func machine_hit(amount: float, direction: Vector3) -> void:
    if breached:
        return
    var closest := -1
    var best := INF
    for i in panels.size():
        if not is_instance_valid(panels[i]):
            continue
        var d := panels[i].global_position.distance_to(global_position + direction.normalized() * 0.5)
        if d < best:
            best = d
            closest = i
    if closest >= 0:
        damage_panel(closest, amount, direction)

func damage_panel(index: int, amount: float, direction: Vector3) -> void:
    if breached or index < 0 or index >= panels.size() or not is_instance_valid(panels[index]):
        return
    panel_health[index] = maxf(0.0, panel_health[index] - amount)
    var panel := panels[index]
    panel.rotation.y += direction.x * amount * 0.0018
    panel.rotation.x -= direction.y * amount * 0.0009
    if index < panel_networks.size():
        var network: FractureNetwork = panel_networks[index]
        var local_direction := panel.global_basis.inverse() * direction
        network.apply_force(
            Vector3(0.0, 0.0, 0.0),
            Vector3(
                local_direction.x,
                local_direction.z,
                local_direction.y
            ) * amount * 48.0
        )
        network.step(1.0 / 60.0)
        var deformation := network.get_deformation_state()
        panel.rotation.y += clampf(
            float(deformation.roll) * 0.22,
            -0.12,
            0.12
        )
        panel.rotation.z += clampf(
            float(deformation.pitch) * 0.18,
            -0.10,
            0.10
        )
        var base_position := _panel_base_positions[index]
        panel.position = base_position + Vector3(
            0.0,
            0.0,
            clampf(float(deformation.average.y) * 0.18, -0.08, 0.08)
        )
    MaterialFx.steel(get_parent(), panel.global_position + Vector3.UP * 0.6, direction, clampf(amount / 18.0, 0.8, 5.0))
    if panel_health[index] <= 0.0:
        _break_panel(index, direction)
    breached = panel_health[0] <= 0.0 or panel_health[1] <= 0.0

func _break_panel(index: int, direction: Vector3) -> void:
    var old := panels[index]
    if not is_instance_valid(old):
        return
    var transform := old.global_transform
    var break_pos := old.global_position
    var network: FractureNetwork = panel_networks[index]
    network.fracture_into_columns()
    network.step(0.024)
    var specs := network.get_fragment_specs(0.24, 1)
    old.queue_free()
    for i in specs.size():
        var spec: Dictionary = specs[i]
        var debris := StructuralDebris.new()
        get_parent().add_child(debris)
        var local := spec.local_position as Vector3
        debris.global_position = transform * Vector3(
            local.x,
            local.z,
            0.0
        )
        debris.global_basis = transform.basis
        debris.configure(
            Vector3(
                float(spec.size.x),
                float(spec.size.z),
                0.24
            ),
            Color(0.13, 0.14, 0.13),
            maxf(24.0, float(spec.mass)),
            340.0,
            "gate_panel"
        )
        var local_velocity := spec.linear_velocity as Vector3
        debris.linear_velocity = transform.basis * Vector3(
            local_velocity.x,
            local_velocity.z,
            0.0
        )
        debris.apply_central_impulse(
            direction.normalized() * (280.0 + float(i) * 75.0)
            + Vector3.UP * (75.0 + float(i) * 24.0)
        )
        debris.apply_torque_impulse(
            Vector3(direction.z, 0.7, -direction.x) * 260.0
        )
    MaterialFx.steel(get_parent(), break_pos, direction + Vector3.UP * 0.18, 5.2)

func apply_world_loads(loads: Array, delta: float) -> void:
    if breached:
        return
    wedge_mass = 0.0
    var strongest_energy := 0.0
    var wedge_side := 0.0
    for network in panel_networks:
        network.clear_forces()
    for body in loads:
        if not is_instance_valid(body):
            continue
        var local := to_local(body.global_position)
        if (
            absf(local.x) > 4.25
            or absf(local.z) > 1.10
            or local.y < 0.05
            or local.y > 4.45
        ):
            continue
        var body_mass: float = float(body.get("mass"))
        if body_mass < 45.0:
            continue
        wedge_mass += body_mass
        wedge_side += signf(local.x) * body_mass
        if body is RigidBody3D:
            var normal_speed := absf(body.linear_velocity.z)
            strongest_energy = maxf(
                strongest_energy,
                0.5 * body_mass * normal_speed * normal_speed
            )
            var panel_index := 0 if local.x <= 0.0 else 1
            if panel_index < panel_networks.size():
                panel_networks[panel_index].apply_force(
                    Vector3(0.0, 0.0, local.y - 2.05),
                    Vector3(
                        body.linear_velocity.x * body_mass * 3.0,
                        body.linear_velocity.z * body_mass * 3.0,
                        body.linear_velocity.y * body_mass * 3.0
                        - body_mass * 9.81
                    )
                )
    for network in panel_networks:
        network.step(delta)
    pry_energy = move_toward(
        pry_energy,
        strongest_energy,
        delta * 18000.0
    )
    _load_damage_bank += (
        maxf(0.0, wedge_mass - 90.0) * delta * 0.012
        + strongest_energy * 0.00005
    )
    if _load_damage_bank < 1.0:
        return
    var damage := minf(_load_damage_bank, 9.0)
    _load_damage_bank -= damage
    var index := 0 if wedge_side <= 0.0 else 1
    var direction := Vector3(
        -1.0 if index == 0 else 1.0,
        0.12,
        -1.0
    )
    damage_panel(index, damage, direction.normalized())

func get_load_path_state() -> Dictionary:
    var max_damage := 0.0
    var broken_fraction := 0.0
    for network in panel_networks:
        var state := network.get_deformation_state()
        max_damage = maxf(max_damage, float(state.damage))
        broken_fraction = maxf(
            broken_fraction,
            float(state.broken_fraction)
        )
    return {
        "wedge_mass": wedge_mass,
        "pry_energy": pry_energy,
        "damage": max_damage,
        "broken_fraction": broken_fraction,
        "breached": breached
    }
