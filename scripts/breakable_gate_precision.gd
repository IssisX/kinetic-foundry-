extends "res://scripts/breakable_gate.gd"

const PrecisionFracture = preload(
    "res://scripts/precision_fracture_network.gd"
)
const DeformableSurfaceScene = preload(
    "res://scripts/deformable_surface.gd"
)

var panel_surfaces: Array[MeshInstance3D] = []
var _pending_amount: Array[float] = [0.0, 0.0]
var _pending_direction: Array[Vector3] = [Vector3.ZERO, Vector3.ZERO]
var _pending_break: Array[bool] = [false, false]
var _fallback_scheduled: Array[bool] = [false, false]
var _last_impact_world: Array[Vector3] = [Vector3.ZERO, Vector3.ZERO]
var _last_impact_energy: Array[float] = [0.0, 0.0]
var _last_impact_direction: Array[Vector3] = [Vector3.FORWARD, Vector3.FORWARD]

func _ready() -> void:
    super()
    add_to_group("physical_event_listener")
    _upgrade_solver_resolution()

func _upgrade_solver_resolution() -> void:
    panel_surfaces.clear()
    for index: int in panels.size():
        if not is_instance_valid(panels[index]):
            continue
        var network := PrecisionFracture.new()
        network.configure_grid(
            9,
            9,
            Vector3(4.0, 0.0, 4.0),
            310.0,
            205.0,
            true
        )
        panel_networks[index] = network

        var surface := DeformableSurfaceScene.new()
        surface.name = "LiveDeformation_%d" % index
        panels[index].add_child(surface)
        surface.configure(
            network,
            9,
            9,
            DeformableSurfaceScene.PLANE_VERTICAL,
            Color(0.18, 0.185, 0.17),
            -0.135
        )
        panel_surfaces.append(surface)

func damage_panel(
        index: int,
        amount: float,
        direction: Vector3
) -> void:
    if not _valid_panel(index):
        return
    var world_point := panels[index].global_position
    _apply_health_damage(index, amount, direction, world_point)
    _pending_amount[index] += maxf(amount, 0.0)
    _pending_direction[index] = direction
    _pending_break[index] = panel_health[index] <= 0.0
    if not _fallback_scheduled[index]:
        _fallback_scheduled[index] = true
        call_deferred("_flush_fallback_impact", index)

func physical_event(event: Dictionary) -> void:
    if breached:
        return
    var event_type := str(event.get("type", ""))
    if event_type != "machine_contact" and event_type != "debris_impact":
        return
    var position_value: Variant = event.get("position", Vector3.ZERO)
    var world_point := position_value as Vector3
    var panel_index := _panel_for_world_point(world_point)
    if panel_index < 0:
        return

    var event_mass := maxf(float(event.get("mass", 1.0)), 1.0)
    var event_impulse := maxf(float(event.get("impulse", 0.0)), 0.0)
    var impact_energy := maxf(
        0.5 * event_impulse * event_impulse / event_mass,
        _pending_amount[panel_index] * _pending_amount[panel_index] * 1.8
    )
    var direction := _impact_direction_for_panel(panel_index, world_point)
    _apply_local_impact(
        panel_index,
        world_point,
        direction,
        event_impulse,
        impact_energy
    )
    _pending_amount[panel_index] = 0.0
    _pending_direction[panel_index] = Vector3.ZERO
    _fallback_scheduled[panel_index] = false

    if _pending_break[panel_index] or panel_health[panel_index] <= 0.0:
        _pending_break[panel_index] = false
        _break_panel_at(
            panel_index,
            direction,
            world_point,
            impact_energy
        )

func apply_world_loads(loads: Array, delta: float) -> void:
    if breached:
        return
    wedge_mass = 0.0
    var strongest_energy := 0.0
    var strongest_world_point := global_position
    var strongest_index := 0
    var wedge_side := 0.0

    for network in panel_networks:
        network.clear_forces()

    for body_value in loads:
        var body := body_value as Node3D
        if body == null or not is_instance_valid(body):
            continue
        var gate_local := to_local(body.global_position)
        if (
            absf(gate_local.x) > 4.25
            or absf(gate_local.z) > 1.10
            or gate_local.y < 0.05
            or gate_local.y > 4.45
        ):
            continue
        var mass_value: Variant = body.get("mass")
        var body_mass := float(mass_value) if mass_value != null else 0.0
        if body_mass < 45.0:
            continue

        wedge_mass += body_mass
        wedge_side += signf(gate_local.x) * body_mass
        var panel_index := 0 if gate_local.x <= 0.0 else 1
        if panel_index >= panel_networks.size() or not is_instance_valid(panels[panel_index]):
            continue

        var panel_local := panels[panel_index].to_local(body.global_position)
        var solver_point := Vector3(
            clampf(panel_local.x, -2.0, 2.0),
            0.0,
            clampf(panel_local.y, -2.0, 2.0)
        )
        var body_velocity := Vector3.ZERO
        if body is RigidBody3D:
            body_velocity = body.linear_velocity
        var panel_force_world := (
            body_velocity * body_mass * 3.0
            + Vector3.DOWN * body_mass * 9.81
        )
        var local_force := panels[panel_index].global_basis.inverse() * panel_force_world
        panel_networks[panel_index].apply_force(
            solver_point,
            Vector3(local_force.x, local_force.z, local_force.y)
        )

        var normal_speed := absf(body_velocity.z)
        var energy := 0.5 * body_mass * normal_speed * normal_speed
        if energy > strongest_energy:
            strongest_energy = energy
            strongest_world_point = body.global_position
            strongest_index = panel_index

    for index: int in panel_networks.size():
        panel_networks[index].step(delta)
        _sync_surface(index)
        _apply_network_pose(index)

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
    var index := strongest_index
    if strongest_energy <= 0.0:
        index = 0 if wedge_side <= 0.0 else 1
        strongest_world_point = panels[index].global_position
    var direction := Vector3(
        -1.0 if index == 0 else 1.0,
        0.12,
        -1.0
    ).normalized()
    _apply_health_damage(index, damage, direction, strongest_world_point)
    if panel_health[index] <= 0.0:
        _break_panel_at(
            index,
            direction,
            strongest_world_point,
            maxf(strongest_energy, damage * damage * 2.0)
        )

func _flush_fallback_impact(index: int) -> void:
    if index < 0 or index >= _fallback_scheduled.size():
        return
    _fallback_scheduled[index] = false
    if breached or _pending_amount[index] <= 0.0 or not _valid_panel(index):
        return
    var amount := _pending_amount[index]
    var direction := _pending_direction[index]
    var world_point := panels[index].global_position
    var impulse := amount * 3.2
    var energy := amount * amount * 1.8
    _pending_amount[index] = 0.0
    _pending_direction[index] = Vector3.ZERO
    _apply_local_impact(index, world_point, direction, impulse, energy)
    if _pending_break[index] or panel_health[index] <= 0.0:
        _pending_break[index] = false
        _break_panel_at(index, direction, world_point, energy)

func _apply_health_damage(
        index: int,
        amount: float,
        direction: Vector3,
        world_point: Vector3
) -> void:
    if not _valid_panel(index):
        return
    panel_health[index] = maxf(0.0, panel_health[index] - maxf(amount, 0.0))
    MaterialFx.steel(
        get_parent(),
        world_point,
        direction,
        clampf(amount / 18.0, 0.55, 5.0)
    )

func _apply_local_impact(
        index: int,
        world_point: Vector3,
        direction: Vector3,
        impulse_magnitude: float,
        impact_energy: float
) -> void:
    if not _valid_panel(index) or index >= panel_networks.size():
        return
    var panel := panels[index]
    var panel_local := panel.to_local(world_point)
    var solver_point := Vector3(
        clampf(panel_local.x, -1.98, 1.98),
        0.0,
        clampf(panel_local.y, -1.98, 1.98)
    )
    var world_direction := direction.normalized()
    if world_direction.length_squared() < 0.001:
        world_direction = _impact_direction_for_panel(index, world_point)
    var local_direction := panel.global_basis.inverse() * world_direction
    var solver_impulse := Vector3(
        local_direction.x,
        local_direction.z,
        local_direction.y
    ).normalized() * maxf(impulse_magnitude, 1.0)

    var network = panel_networks[index]
    if network.has_method("apply_impact"):
        network.apply_impact(
            solver_point,
            solver_impulse,
            maxf(impact_energy, 0.0)
        )
    else:
        network.apply_force(solver_point, solver_impulse * 8.0)
        network.step(1.0 / 90.0)

    _last_impact_world[index] = world_point
    _last_impact_energy[index] = impact_energy
    _last_impact_direction[index] = world_direction
    _sync_surface(index)
    _apply_network_pose(index)

func _apply_network_pose(index: int) -> void:
    if not _valid_panel(index) or index >= panel_networks.size():
        return
    var state: Dictionary = panel_networks[index].get_deformation_state()
    var base_position := _panel_base_positions[index]
    panels[index].position = base_position + Vector3(
        0.0,
        0.0,
        clampf(float(state.get("average", Vector3.ZERO).y) * 0.18, -0.10, 0.10)
    )
    panels[index].rotation.x = clampf(
        float(state.get("pitch", 0.0)) * 0.13,
        -0.10,
        0.10
    )
    panels[index].rotation.y = clampf(
        float(state.get("roll", 0.0)) * 0.18,
        -0.14,
        0.14
    )

func _sync_surface(index: int) -> void:
    if index < 0 or index >= panel_surfaces.size():
        return
    var surface := panel_surfaces[index]
    if is_instance_valid(surface) and surface.has_method("sync_from_network"):
        surface.sync_from_network()

func _break_panel(index: int, direction: Vector3) -> void:
    if not _valid_panel(index):
        return
    var world_point := _last_impact_world[index]
    if world_point == Vector3.ZERO:
        world_point = panels[index].global_position
    _break_panel_at(
        index,
        direction,
        world_point,
        maxf(_last_impact_energy[index], 5200.0)
    )

func _break_panel_at(
        index: int,
        direction: Vector3,
        world_point: Vector3,
        impact_energy: float
) -> void:
    if not _valid_panel(index):
        return
    var old := panels[index]
    var transform := old.global_transform
    var panel_local := old.to_local(world_point)
    var solver_point := Vector3(
        clampf(panel_local.x, -1.98, 1.98),
        0.0,
        clampf(panel_local.y, -1.98, 1.98)
    )
    var local_direction := old.global_basis.inverse() * direction.normalized()
    var solver_direction := Vector3(
        local_direction.x,
        local_direction.z,
        local_direction.y
    )
    var network = panel_networks[index]
    if network.has_method("fracture_localized"):
        network.fracture_localized(
            solver_point,
            maxf(impact_energy, 4200.0),
            solver_direction
        )
        network.fracture_localized(
            solver_point,
            maxf(impact_energy, 4200.0) * 1.18,
            solver_direction.rotated(Vector3.UP, 0.46)
        )
    else:
        network.fracture_into_columns()
    network.step(0.024)

    var specs: Array[Dictionary] = network.get_fragment_specs(0.20, 2)
    if specs.size() < 2:
        network.fracture_into_columns()
        network.step(0.024)
        specs = network.get_fragment_specs(0.20, 2)

    old.queue_free()
    var energy_scale := clampf(sqrt(maxf(impact_energy, 1.0)) / 95.0, 0.8, 3.0)
    var fragment_limit := mini(specs.size(), 12)
    for i: int in fragment_limit:
        var spec: Dictionary = specs[i]
        var local_position := spec.get("local_position", Vector3.ZERO) as Vector3
        var debris := StructuralDebris.new()
        get_parent().add_child(debris)
        var mapped_local := Vector3(
            local_position.x,
            local_position.z,
            local_position.y
        )
        debris.global_position = transform * mapped_local
        debris.global_basis = transform.basis
        var spec_size := spec.get("size", Vector3.ONE) as Vector3
        debris.configure(
            Vector3(
                maxf(0.20, spec_size.x),
                maxf(0.20, spec_size.z),
                maxf(0.16, spec_size.y)
            ),
            Color(0.13, 0.14, 0.13),
            maxf(18.0, float(spec.get("mass", 24.0))),
            340.0,
            "gate_panel"
        )
        var local_velocity := spec.get("linear_velocity", Vector3.ZERO) as Vector3
        debris.linear_velocity = transform.basis * Vector3(
            local_velocity.x,
            local_velocity.z,
            local_velocity.y
        )
        var radial := debris.global_position - world_point
        radial.y *= 0.45
        if radial.length_squared() < 0.001:
            radial = Vector3.UP
        radial = radial.normalized()
        debris.apply_central_impulse(
            direction.normalized() * (140.0 + energy_scale * 115.0)
            + radial * (75.0 + energy_scale * 55.0)
            + Vector3.UP * (45.0 + energy_scale * 30.0)
        )
        debris.apply_torque_impulse(
            radial.cross(direction.normalized())
            * (140.0 + energy_scale * 95.0)
        )

    MaterialFx.steel(
        get_parent(),
        world_point,
        direction + Vector3.UP * 0.15,
        clampf(energy_scale * 1.7, 1.4, 5.8)
    )
    breached = true
    get_tree().call_group(
        "physical_event_listener",
        "physical_event",
        {
            "type": "fracture",
            "position": world_point,
            "impulse": maxf(220.0, sqrt(maxf(impact_energy, 1.0)) * 4.6),
            "mass": 310.0,
            "fracture": 1.0,
            "radius": 6.5,
            "material": "steel",
            "novelty": 1.0
        }
    )

func _panel_for_world_point(world_point: Vector3) -> int:
    var best_index := -1
    var best_score := INF
    for index: int in panels.size():
        if not is_instance_valid(panels[index]):
            continue
        var local := panels[index].to_local(world_point)
        if absf(local.x) > 2.75 or absf(local.y) > 2.75 or absf(local.z) > 3.25:
            continue
        var score := (
            absf(local.z) * 0.55
            + maxf(0.0, absf(local.x) - 2.0)
            + maxf(0.0, absf(local.y) - 2.0)
        )
        if score < best_score:
            best_score = score
            best_index = index
    return best_index

func _impact_direction_for_panel(
        index: int,
        world_point: Vector3
) -> Vector3:
    if not _valid_panel(index):
        return Vector3.FORWARD
    var panel := panels[index]
    var local := panel.to_local(world_point)
    var local_normal := Vector3(0.0, 0.0, -1.0 if local.z < 0.0 else 1.0)
    return (panel.global_basis * local_normal).normalized()

func _valid_panel(index: int) -> bool:
    return (
        not breached
        and index >= 0
        and index < panels.size()
        and is_instance_valid(panels[index])
    )
