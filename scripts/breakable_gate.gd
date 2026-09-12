extends Node3D

const GeomUtil = preload("res://scripts/geom.gd")
const MaterialFx = preload("res://scripts/material_fx.gd")
const GatePanelScript = preload("res://scripts/gate_panel.gd")
const StructuralDebris = preload(
    "res://scripts/structural_debris.gd"
)
const PrecisionFractureNetwork = preload(
    "res://scripts/precision_fracture_network.gd"
)

const PANEL_SIZE := 4.0
const GRID_NODES := 7
const GRID_CELLS := GRID_NODES - 1
const CELL_SIZE := PANEL_SIZE / float(GRID_CELLS)

var panel_health := [120.0, 120.0]
var panels: Array[StaticBody3D] = []
var panel_networks: Array = []
var panel_cells: Array = []
var _panel_base_positions: Array[Vector3] = []
var _last_hit_local: Array[Vector3] = []
var _last_hit_energy: Array[float] = []
var _last_hit_direction: Array[Vector3] = []
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
        _last_hit_local.append(Vector3.ZERO)
        _last_hit_energy.append(0.0)
        _last_hit_direction.append(Vector3.BACK)

        var cells: Array[MeshInstance3D] = []
        for row in GRID_CELLS:
            for column in GRID_CELLS:
                var checker := float((row + column) % 2) * 0.012
                var cell := GeomUtil.box_mesh(
                    Vector3(CELL_SIZE * 0.975, CELL_SIZE * 0.975, 0.20),
                    Color(0.17 + checker, 0.18 + checker, 0.165 + checker),
                    0.88,
                    0.26
                )
                cell.name = "PanelCell_%d_%d" % [column, row]
                cell.position = Vector3(
                    -PANEL_SIZE * 0.5 + CELL_SIZE * (float(column) + 0.5),
                    -PANEL_SIZE * 0.5 + CELL_SIZE * (float(row) + 0.5),
                    0.0
                )
                panel.add_child(cell)
                cells.append(cell)
        panel_cells.append(cells)
        GeomUtil.add_box_collision(
            panel,
            Vector3(PANEL_SIZE, PANEL_SIZE, 0.24)
        )

        for rib in 5:
            var rib_mesh := GeomUtil.box_mesh(
                Vector3(0.09, 3.70, 0.055),
                Color(0.40, 0.36, 0.22),
                0.80,
                0.28
            )
            rib_mesh.position = Vector3(
                -1.55 + float(rib) * 0.78,
                0.0,
                -0.14
            )
            panel.add_child(rib_mesh)
        for stripe in 5:
            var warning := GeomUtil.box_mesh(
                Vector3(0.66, 0.13, 0.030),
                Color(0.82, 0.54, 0.08),
                0.78,
                0.10
            )
            warning.position = Vector3(
                -1.25 + float(stripe) * 0.62,
                -1.45,
                -0.13
            )
            warning.rotation.z = 0.55
            panel.add_child(warning)

        var network := PrecisionFractureNetwork.new()
        network.configure_grid(
            GRID_NODES,
            GRID_NODES,
            Vector3(PANEL_SIZE, 0.0, PANEL_SIZE),
            310.0,
            205.0,
            true
        )
        panel_networks.append(network)
        _update_panel_skin(index)

    for side in [-1.0, 1.0]:
        var post := GeomUtil.static_box(
            self,
            "GatePost",
            Vector3(side * 4.45, 2.5, 0.0),
            Vector3(0.48, 5.0, 0.72),
            Color(0.25, 0.25, 0.22)
        )
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
        var candidate := panels[i].global_position
        var d := candidate.distance_to(
            global_position + direction.normalized() * 0.5
        )
        if d < best:
            best = d
            closest = i
    if closest >= 0:
        damage_panel_at(
            closest,
            amount,
            direction,
            panels[closest].global_position,
            amount * amount * 3.2
        )

func damage_panel(index: int, amount: float, direction: Vector3) -> void:
    if index < 0 or index >= panels.size() or not is_instance_valid(panels[index]):
        return
    damage_panel_at(
        index,
        amount,
        direction,
        panels[index].global_position,
        amount * amount * 3.2
    )

func damage_panel_at(
        index: int,
        amount: float,
        direction: Vector3,
        world_point: Vector3,
        impact_energy: float
) -> void:
    if (
        breached
        or index < 0
        or index >= panels.size()
        or not is_instance_valid(panels[index])
    ):
        return

    var panel := panels[index]
    var local_point := panel.to_local(world_point)
    local_point.x = clampf(local_point.x, -PANEL_SIZE * 0.5, PANEL_SIZE * 0.5)
    local_point.y = clampf(local_point.y, -PANEL_SIZE * 0.5, PANEL_SIZE * 0.5)
    var network_point := Vector3(local_point.x, 0.0, local_point.y)
    var local_direction := panel.global_basis.inverse() * direction.normalized()
    var network_direction := Vector3(
        local_direction.x,
        local_direction.z,
        local_direction.y
    ).normalized()
    if network_direction.length_squared() < 0.001:
        network_direction = Vector3(0.0, 1.0, 0.0)

    var energy := maxf(
        impact_energy,
        amount * amount * 2.8
    )
    var impulse_magnitude := sqrt(maxf(2.0 * 310.0 * energy, 0.0))
    var network: PrecisionFractureNetwork = panel_networks[index]
    var deformation: Dictionary = network.apply_impact(
        network_point,
        network_direction * impulse_magnitude,
        energy
    )

    _last_hit_local[index] = network_point
    _last_hit_energy[index] = energy
    _last_hit_direction[index] = network_direction

    var energy_gain := lerpf(
        0.88,
        1.28,
        clampf(energy / 15000.0, 0.0, 1.0)
    )
    panel_health[index] = maxf(
        0.0,
        panel_health[index] - amount * energy_gain
    )

    _update_panel_skin(index)

    var local_average: Vector3 = deformation.get("average", Vector3.ZERO)
    var base_position := _panel_base_positions[index]
    panel.position = base_position + Vector3(
        0.0,
        0.0,
        clampf(local_average.y * 0.06, -0.05, 0.05)
    )

    MaterialFx.steel(
        get_parent(),
        world_point,
        direction,
        clampf(energy / 4800.0, 0.7, 5.4)
    )
    _emit_impact_event(
        world_point,
        impulse_magnitude,
        energy,
        float(deformation.get("broken_fraction", 0.0))
    )

    var broken_fraction := float(
        deformation.get("broken_fraction", 0.0)
    )
    var catastrophic := (
        broken_fraction > 0.18
        and energy > 7000.0
    )
    if panel_health[index] <= 0.0 or catastrophic:
        _break_panel(index, direction)
    breached = panel_health[0] <= 0.0 or panel_health[1] <= 0.0

func _update_panel_skin(index: int) -> void:
    if index < 0 or index >= panel_networks.size() or index >= panel_cells.size():
        return
    var network: PrecisionFractureNetwork = panel_networks[index]
    var cells: Array = panel_cells[index]
    for row in GRID_CELLS:
        for column in GRID_CELLS:
            var cell_index := row * GRID_CELLS + column
            if cell_index >= cells.size():
                continue
            var cell := cells[cell_index] as MeshInstance3D
            if cell == null or not is_instance_valid(cell):
                continue
            var state: Dictionary = network.get_cell_state(column, row)
            if state.is_empty():
                continue
            var center_net: Vector3 = state.get("center", Vector3.ZERO)
            var axis_x_net: Vector3 = state.get("axis_x", Vector3.RIGHT)
            var axis_z_net: Vector3 = state.get("axis_z", Vector3.BACK)
            var normal_net: Vector3 = state.get("normal", Vector3.UP)

            var center := Vector3(
                center_net.x,
                center_net.z,
                center_net.y
            )
            var axis_x := Vector3(
                axis_x_net.x,
                axis_x_net.z,
                axis_x_net.y
            ).normalized()
            var axis_y := Vector3(
                axis_z_net.x,
                axis_z_net.z,
                axis_z_net.y
            ).normalized()
            var normal := Vector3(
                normal_net.x,
                normal_net.z,
                normal_net.y
            ).normalized()
            var basis := Basis(axis_x, axis_y, normal).orthonormalized()
            cell.transform = Transform3D(basis, center)
            cell.scale = Vector3(
                clampf(float(state.get("width", CELL_SIZE)) / CELL_SIZE, 0.72, 1.32),
                clampf(float(state.get("height", CELL_SIZE)) / CELL_SIZE, 0.72, 1.32),
                1.0
            )

func _break_panel(index: int, direction: Vector3) -> void:
    var old := panels[index]
    if not is_instance_valid(old):
        return
    var transform := old.global_transform
    var break_pos := old.global_position
    var network: PrecisionFractureNetwork = panel_networks[index]
    network.fracture_localized(
        _last_hit_local[index],
        maxf(_last_hit_energy[index], 7600.0),
        _last_hit_direction[index]
    )
    network.step(0.024)
    var specs := network.get_fragment_specs(0.24, 1)
    old.queue_free()

    var event_energy := maxf(_last_hit_energy[index], 7600.0)
    for i in specs.size():
        var spec: Dictionary = specs[i]
        var debris := StructuralDebris.new()
        get_parent().add_child(debris)
        var local: Vector3 = spec.get("local_position", Vector3.ZERO)
        debris.global_position = transform * Vector3(
            local.x,
            local.z,
            local.y
        )
        debris.global_basis = transform.basis
        var size_net: Vector3 = spec.get(
            "size",
            Vector3(CELL_SIZE, 0.24, CELL_SIZE)
        )
        var fragment_size := Vector3(
            maxf(0.22, size_net.x),
            maxf(0.22, size_net.z),
            maxf(0.18, size_net.y)
        )
        var fragment_mass := maxf(18.0, float(spec.get("mass", 24.0)))
        debris.configure(
            fragment_size,
            Color(0.13, 0.14, 0.13),
            fragment_mass,
            340.0,
            "gate_panel"
        )
        var velocity_net: Vector3 = spec.get(
            "linear_velocity",
            Vector3.ZERO
        )
        debris.linear_velocity = transform.basis * Vector3(
            velocity_net.x,
            velocity_net.z,
            velocity_net.y
        )
        var kick := minf(
            sqrt(2.0 * fragment_mass * event_energy) * 0.12,
            fragment_mass * 11.0
        )
        debris.apply_central_impulse(
            direction.normalized() * kick
            + Vector3.UP * fragment_mass * 0.55
        )
        var angular_value: Variant = spec.get(
            "angular_velocity",
            Vector3.ZERO
        )
        debris.angular_velocity += angular_value as Vector3

    panel_health[index] = 0.0
    breached = true
    MaterialFx.steel(
        get_parent(),
        break_pos,
        direction + Vector3.UP * 0.18,
        clampf(event_energy / 2600.0, 3.0, 7.0)
    )
    get_tree().call_group(
        "physical_event_listener",
        "physical_event",
        {
            "type": "fracture",
            "position": break_pos,
            "impulse": sqrt(2.0 * 310.0 * event_energy),
            "mass": 310.0,
            "fracture": 1.0,
            "radius": PANEL_SIZE,
            "novelty": 1.0,
            "material": "steel"
        }
    )

func apply_world_loads(loads: Array, delta: float) -> void:
    if breached:
        return
    wedge_mass = 0.0
    var strongest_energy := 0.0
    var strongest_world_point := global_position + Vector3.UP * 2.0
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
            var kinetic_energy := (
                0.5 * body_mass * normal_speed * normal_speed
            )
            if kinetic_energy > strongest_energy:
                strongest_energy = kinetic_energy
                strongest_world_point = body.global_position
            var panel_index := 0 if local.x <= 0.0 else 1
            if panel_index < panel_networks.size():
                var panel := panels[panel_index]
                if is_instance_valid(panel):
                    var panel_local := panel.to_local(body.global_position)
                    panel_networks[panel_index].apply_force(
                        Vector3(
                            panel_local.x,
                            0.0,
                            panel_local.y
                        ),
                        Vector3(
                            body.linear_velocity.x * body_mass * 3.0,
                            body.linear_velocity.z * body_mass * 3.0,
                            body.linear_velocity.y * body_mass * 3.0
                            - body_mass * 9.81
                        )
                    )

    for i in panel_networks.size():
        panel_networks[i].step(delta)
        _update_panel_skin(i)

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
    ).normalized()
    damage_panel_at(
        index,
        damage,
        direction,
        strongest_world_point,
        maxf(strongest_energy, damage * damage * 2.0)
    )

func get_load_path_state() -> Dictionary:
    var max_damage := 0.0
    var broken_fraction := 0.0
    var max_displacement := 0.0
    for network in panel_networks:
        var state: Dictionary = network.get_deformation_state()
        max_damage = maxf(
            max_damage,
            float(state.get("damage", 0.0))
        )
        broken_fraction = maxf(
            broken_fraction,
            float(state.get("broken_fraction", 0.0))
        )
        max_displacement = maxf(
            max_displacement,
            float(state.get("max_displacement", 0.0))
        )
    return {
        "wedge_mass": wedge_mass,
        "pry_energy": pry_energy,
        "damage": max_damage,
        "broken_fraction": broken_fraction,
        "deformation": {
            "max_displacement": max_displacement,
            "damage": max_damage,
            "broken_fraction": broken_fraction
        },
        "breached": breached
    }

func _emit_impact_event(
        world_point: Vector3,
        impulse: float,
        energy: float,
        broken_fraction: float
) -> void:
    get_tree().call_group(
        "physical_event_listener",
        "physical_event",
        {
            "type": "machine_contact",
            "position": world_point,
            "impulse": impulse,
            "mass": 310.0,
            "fracture": clampf(
                broken_fraction * 2.5 + energy / 22000.0,
                0.0,
                1.0
            ),
            "radius": maxf(CELL_SIZE, sqrt(energy) * 0.015),
            "novelty": clampf(0.58 + energy / 18000.0, 0.58, 1.0),
            "material": "steel"
        }
    )
