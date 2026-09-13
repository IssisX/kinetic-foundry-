class_name FractureNetwork
extends RefCounted

## Deterministic, energy-bounded deformation and fracture network.
##
## The graph is the authority for elastic motion, permanent set, damage,
## topology, fragment mass, and release velocity. Gameplay and rendering
## consume this state; neither invents a second destruction result.

const EnergyPartition = preload("res://scripts/energy_partition.gd")

signal topology_changed(component_count: int)

## Maps authored spring stiffness into an XPBD compliance.
const STIFFNESS_TO_COMPLIANCE := 280.0
## Duals are kept between steps. Zeroing them every substep throws away the
## constraint impulse estimate that fracture, audio and admittance read.
const WARM_START_RETENTION := 0.6

## _residual_energy is spare energy banked from past hits, awaiting a
## fracture event that can spend it as extra fragment velocity. Nothing
## drained it before now: a structure absorbing many small hits without
## ever breaking could bank an unbounded amount, then release all of it
## at once on whatever hit finally cracked it - a single joule-accurate
## impact producing a burst disproportionate to that impact. Real spare
## energy leaks away as heat and sound; this does too, and is hard-capped
## so a burst of hits in one tick cannot bank past what one severe impact
## would deliver.
const RESIDUAL_DECAY_PER_SECOND := 0.35
const RESIDUAL_ENERGY_CEILING := 60000.0

var columns := 0
var rows := 0
var span := Vector3.ONE
var total_mass := 1.0
var yield_strain := 0.018
var damage_onset := 0.036
var failure_strain := 0.18
var hardening := 0.22
var thickness := 0.24
var fracture_energy_density := 420.0
var solver_iterations := 5
var pin_boundary := false
var pin_corners := true

var _rest_positions: Array[Vector3] = []
var _positions: Array[Vector3] = []
var _velocities: Array[Vector3] = []
var _forces: Array[Vector3] = []
var _previous_positions: Array[Vector3] = []
var _pinned: Array[bool] = []
var _bonds: Array[Dictionary] = []
var _node_mass := 1.0
var _topology_dirty := true
var _component_count := 1
var _last_reported_components := 1
var _max_displacement := 0.0
var _revision := 0
var _input_energy := 0.0
var _plastic_energy := 0.0
var _surface_energy := 0.0
var _residual_energy := 0.0
var _release_momentum := Vector3.ZERO
var _release_point := Vector3.ZERO
var _release_direction := Vector3.UP
var _fracture_finalized := false
var _last_impact_point := Vector3.ZERO
var _last_impact_direction := Vector3.UP
var _last_substep_delta := 0.016
var _last_impact_radius := 0.0
var _retired: Array[bool] = []
var _wave: Array[float] = []
var _crack_fronts: Array[Dictionary] = []
var _crack_budget := 0.0

## Instant crush at the contact. The rest of the fracture share is spent by
## crack fronts as the elastic wave arrives, not sprayed across the plate.
const CORE_FRACTURE_SHARE := 0.14
const WAVE_DECAY_PER_SECOND := 7.5
const MAX_CRACK_FRONTS := 8


func configure_grid(
        grid_columns: int,
        grid_rows: int,
        grid_span: Vector3,
        mass_value: float,
        toughness: float,
        boundary_pins: bool = false,
        material_thickness: float = 0.24,
        fracture_energy: float = 420.0
) -> void:
    columns = maxi(2, grid_columns)
    rows = maxi(2, grid_rows)
    span = grid_span
    total_mass = maxf(0.1, mass_value)
    yield_strain = clampf(toughness * 0.0001, 0.010, 0.032)
    damage_onset = yield_strain * 2.0
    failure_strain = clampf(
        damage_onset + toughness * 0.00042,
        0.095,
        0.26
    )
    hardening = clampf(
        0.12 + toughness * 0.0003,
        0.12,
        0.42
    )
    thickness = maxf(material_thickness, 0.04)
    fracture_energy_density = maxf(fracture_energy, 40.0)
    pin_boundary = boundary_pins
    pin_corners = not boundary_pins
    _rest_positions.clear()
    _positions.clear()
    _velocities.clear()
    _forces.clear()
    _previous_positions.clear()
    _pinned.clear()
    _retired.clear()
    _wave.clear()
    _crack_fronts.clear()
    _crack_budget = 0.0
    _bonds.clear()

    var count := columns * rows
    _node_mass = total_mass / float(count)
    for row in rows:
        var z := lerpf(
            -span.z * 0.5,
            span.z * 0.5,
            float(row) / float(rows - 1)
        )
        for column in columns:
            var x := lerpf(
                -span.x * 0.5,
                span.x * 0.5,
                float(column) / float(columns - 1)
            )
            var position := Vector3(x, 0.0, z)
            _rest_positions.append(position)
            _positions.append(position)
            _velocities.append(Vector3.ZERO)
            _forces.append(Vector3.ZERO)
            _previous_positions.append(position)
            _pinned.append(_is_pinned(column, row))
            _retired.append(false)
            _wave.append(0.0)

    for row in rows:
        for column in columns:
            var index := _index(column, row)
            if column + 1 < columns:
                _add_bond(index, _index(column + 1, row), 1.0)
            if row + 1 < rows:
                _add_bond(index, _index(column, row + 1), 0.92)
            if column + 1 < columns and row + 1 < rows:
                _add_bond(
                    index,
                    _index(column + 1, row + 1),
                    0.54
                )
                _add_bond(
                    _index(column + 1, row),
                    _index(column, row + 1),
                    0.54
                )
    _topology_dirty = true
    _component_count = 1
    _last_reported_components = 1
    _revision = 1
    _input_energy = 0.0
    _plastic_energy = 0.0
    _surface_energy = 0.0
    _residual_energy = 0.0
    _release_momentum = Vector3.ZERO
    _fracture_finalized = false


func _is_pinned(column: int, row: int) -> bool:
    if pin_boundary:
        return (
            column == 0
            or row == 0
            or column == columns - 1
            or row == rows - 1
        )
    if not pin_corners:
        return false
    return (
        (column == 0 or column == columns - 1)
        and (row == 0 or row == rows - 1)
    )


func _index(column: int, row: int) -> int:
    return row * columns + column


func _add_bond(
        first: int,
        second: int,
        stiffness_scale: float
) -> void:
    var rest_length := _rest_positions[first].distance_to(
        _rest_positions[second]
    )
    var stiffness := total_mass * 18.0 * stiffness_scale
    _bonds.append({
        "a": first,
        "b": second,
        "rest": rest_length,
        "stiffness": stiffness,
        "compliance": 1.0 / maxf(stiffness * STIFFNESS_TO_COMPLIANCE, 1.0),
        "lambda": 0.0,
        "plastic": 0.0,
        "history": 0.0,
        "fracture_work": 0.0,
        "fracture_cost": fracture_energy_density
            * thickness
            * rest_length
            * 0.44,
        "damage": 0.0,
        "active": true
    })


func apply_force(local_point: Vector3, force: Vector3) -> void:
    if _positions.is_empty() or force.length_squared() < 0.0001:
        return
    var radius := maxf(_cell_scale() * 1.6, 0.28)
    var weight_sum := 0.0
    var weights: Array[float] = []
    for i in _positions.size():
        if bool(_retired[i]):
            weights.append(0.0)
            continue
        var weight := _wendland(
            _positions[i].distance_to(local_point) / radius
        )
        weights.append(weight)
        weight_sum += weight
    if weight_sum <= 0.0:
        var nearest := _nearest_nodes(local_point, 1)
        if nearest.is_empty():
            return
        var index := int(nearest[0].index)
        if not bool(_retired[index]):
            _forces[index] += force
        return
    for i in _positions.size():
        if weights[i] <= 0.0:
            continue
        _forces[i] += force * (weights[i] / weight_sum)


func apply_impact(
        local_point: Vector3,
        impulse: Vector3,
        impact_energy: float
) -> Dictionary:
    if _positions.is_empty():
        return {}
    var energy := clampf(impact_energy, 0.0, 250000.0)
    var safe_impulse := impulse.limit_length(
        sqrt(maxf(2.0 * total_mass * energy, 0.0))
    )
    _last_impact_point = local_point
    _last_impact_direction = (
        safe_impulse.normalized()
        if safe_impulse.length_squared() > 0.0001
        else Vector3.UP
    )
    _last_impact_radius = impact_kernel_radius(energy)
    _release_point = local_point
    _release_direction = _last_impact_direction
    _release_momentum += safe_impulse
    _input_energy += energy

    var radius := _last_impact_radius
    var weight_sum := 0.0
    var weights: Array[float] = []
    for i in _positions.size():
        if bool(_retired[i]):
            weights.append(0.0)
            continue
        var weight := _wendland(
            _positions[i].distance_to(local_point) / maxf(radius, 0.001)
        )
        weights.append(weight)
        weight_sum += weight
    if weight_sum <= 0.0:
        var nearest := _nearest_nodes(local_point, 1)
        if not nearest.is_empty():
            var index := int(nearest[0].index)
            weights[index] = 1.0
            weight_sum = 1.0
    for i in _positions.size():
        if weights[i] <= 0.0:
            continue
        var weight := weights[i] / maxf(weight_sum, 0.001)
        if not _pinned[i] or _fracture_finalized:
            _velocities[i] += (
                safe_impulse * weight / maxf(_node_mass, 0.001)
            )

    var terms := EnergyPartition.split(energy)
    var core_share := float(terms.fracture) * (
        CORE_FRACTURE_SHARE / maxf(EnergyPartition.FRACTURE_SHARE, 0.001)
    )
    var front_share := maxf(float(terms.fracture) - core_share, 0.0)
    var bond_radius := radius * 0.72
    var bond_weights: Array[float] = []
    var bond_weight_sum := 0.0
    for bond in _bonds:
        var midpoint := (
            _positions[int(bond.a)]
            + _positions[int(bond.b)]
        ) * 0.5
        var weight := _wendland(
            midpoint.distance_to(local_point) / maxf(bond_radius, 0.001)
        )
        bond_weights.append(weight)
        if bool(bond.active):
            bond_weight_sum += weight

    if bond_weight_sum <= 0.0:
        bond_weight_sum = 0.001
    for bond_index in _bonds.size():
        var bond := _bonds[bond_index]
        if not bool(bond.active):
            continue
        var work := core_share * (
            bond_weights[bond_index] / bond_weight_sum
        )
        if work <= 0.0:
            continue
        bond.fracture_work = float(bond.fracture_work) + work
        var work_damage := float(bond.fracture_work) / maxf(
            float(bond.fracture_cost),
            0.001
        )
        bond.damage = maxf(float(bond.damage), work_damage)
        if float(bond.damage) >= 1.0:
            _break_bond(bond)
    _crack_budget = minf(
        _crack_budget + front_share,
        RESIDUAL_ENERGY_CEILING
    )
    _seed_crack_fronts(local_point, _last_impact_direction, energy)
    _residual_energy = minf(
        _residual_energy + float(terms.residual),
        RESIDUAL_ENERGY_CEILING
    )
    _revision += 1
    _refresh_topology()
    return get_energy_state()


func _nearest_nodes(local_point: Vector3, count: int) -> Array:
    var result: Array = []
    for i in _positions.size():
        if i < _retired.size() and bool(_retired[i]):
            continue
        var entry := {
            "index": i,
            "distance": _positions[i].distance_squared_to(local_point)
        }
        var insert_at := result.size()
        for j in result.size():
            if float(entry.distance) < float(result[j].distance):
                insert_at = j
                break
        result.insert(insert_at, entry)
        if result.size() > count:
            result.pop_back()
    return result


func clear_forces() -> void:
    for i in _forces.size():
        _forces[i] = Vector3.ZERO


func step(delta: float) -> void:
    if _positions.is_empty():
        return
    var safe_delta := clampf(delta, 0.002, 0.12)
    var substeps := clampi(ceili(safe_delta / 0.016), 1, 8)
    var sub_delta := safe_delta / float(substeps)
    _last_substep_delta = sub_delta
    _residual_energy *= exp(-RESIDUAL_DECAY_PER_SECOND * safe_delta)
    for bond in _bonds:
        if bool(bond.active):
            bond.lambda = float(bond.lambda) * WARM_START_RETENTION
        else:
            bond.lambda = 0.0
    for _i in substeps:
        _step_substep(sub_delta)
    clear_forces()
    _refresh_topology()


func _step_substep(delta: float) -> void:
    var inverse_mass := 1.0 / maxf(_node_mass, 0.001)
    for i in _positions.size():
        _previous_positions[i] = _positions[i]
        if is_retired(i):
            _velocities[i] = Vector3.ZERO
            continue
        if _pinned[i] and not _fracture_finalized:
            _positions[i] = _rest_positions[i]
            _velocities[i] = Vector3.ZERO
            continue
        _velocities[i] += _forces[i] * inverse_mass * delta
        _positions[i] += _velocities[i] * delta

    for bond in _bonds:
        if not bool(bond.active):
            bond.lambda = 0.0
            continue
        _update_bond_material(bond)

    for _iteration in solver_iterations:
        for bond in _bonds:
            if bool(bond.active):
                _project_bond(bond, delta, inverse_mass)

    var moved := false
    for i in _positions.size():
        if is_retired(i):
            _velocities[i] = Vector3.ZERO
            continue
        if _pinned[i] and not _fracture_finalized:
            _positions[i] = _rest_positions[i]
            _velocities[i] = Vector3.ZERO
            continue
        _velocities[i] = (
            (_positions[i] - _previous_positions[i]) / delta
        ) * exp(-3.8 * delta)
        var displacement := _positions[i] - _rest_positions[i]
        var limit := maxf(span.length() * 0.42, 0.8)
        if displacement.length() > limit:
            _positions[i] = (
                _rest_positions[i]
                + displacement.normalized() * limit
            )
            _velocities[i] *= 0.24
        moved = moved or displacement.length_squared() > 0.000001
    _update_wave(delta)
    _advance_crack_fronts(delta)
    if moved:
        _revision += 1


func _update_bond_material(bond: Dictionary) -> void:
    var first := int(bond.a)
    var second := int(bond.b)
    var length := _positions[first].distance_to(_positions[second])
    var rest := maxf(float(bond.rest), 0.0001)
    var total_strain := (length - rest) / rest
    var plastic := float(bond.plastic)
    var elastic_strain := total_strain - plastic
    var yield_limit := yield_strain + hardening * absf(plastic)
    if absf(elastic_strain) > yield_limit:
        var returned := minf(
            absf(elastic_strain) - yield_limit,
            0.025
        )
        var plastic_delta := (
            signf(elastic_strain) * returned * 0.42
        )
        bond.plastic = plastic + plastic_delta
        _plastic_energy += (
            absf(plastic_delta)
            * float(bond.stiffness)
            * rest
            * 0.08
        )

    var tensile_strain := maxf(0.0, total_strain)
    var history := maxf(float(bond.history), tensile_strain)
    bond.history = history
    var strain_damage := clampf(
        (history - damage_onset)
        / maxf(failure_strain - damage_onset, 0.001),
        0.0,
        1.0
    )
    bond.damage = maxf(float(bond.damage), strain_damage)
    if float(bond.damage) >= 1.0:
        _break_bond(bond)


func _project_bond(
        bond: Dictionary,
        delta: float,
        inverse_mass: float
) -> void:
    var first := int(bond.a)
    var second := int(bond.b)
    var offset := _positions[second] - _positions[first]
    var length := offset.length()
    if length < 0.0001:
        return
    var first_weight := (
        0.0
        if _pinned[first] and not _fracture_finalized
        else inverse_mass
    )
    var second_weight := (
        0.0
        if _pinned[second] and not _fracture_finalized
        else inverse_mass
    )
    var effective_rest := float(bond.rest) * (
        1.0 + float(bond.plastic)
    )
    var constraint := length - effective_rest
    var damage_scale := maxf(
        (1.0 - float(bond.damage)) ** 2,
        0.025
    )
    var alpha := (
        float(bond.compliance)
        / damage_scale
        / (delta * delta)
    )
    var delta_lambda := (
        -constraint - alpha * float(bond.lambda)
    ) / maxf(first_weight + second_weight + alpha, 0.0001)
    bond.lambda = float(bond.lambda) + delta_lambda
    var correction := offset / length * delta_lambda
    _positions[first] -= correction * first_weight
    _positions[second] += correction * second_weight


func _break_bond(bond: Dictionary) -> void:
    if not bool(bond.active):
        return
    bond.active = false
    bond.damage = 1.0
    _surface_energy += float(bond.fracture_cost)
    _topology_dirty = true
    _revision += 1


func _refresh_topology() -> void:
    if not _topology_dirty:
        return
    var components := _components()
    _component_count = components.size()
    _topology_dirty = false
    if _component_count != _last_reported_components:
        _last_reported_components = _component_count
        topology_changed.emit(_component_count)


func has_fractured() -> bool:
    _refresh_topology()
    return _component_count > 1


func get_broken_fraction() -> float:
    if _bonds.is_empty():
        return 0.0
    var broken := 0
    for bond in _bonds:
        if not bool(bond.active):
            broken += 1
    return float(broken) / float(_bonds.size())


func get_deformation_state() -> Dictionary:
    var maximum := 0.0
    var sag := 0.0
    var average := Vector3.ZERO
    var left_height := 0.0
    var right_height := 0.0
    var front_height := 0.0
    var back_height := 0.0
    var left_count := 0.0
    var right_count := 0.0
    var front_count := 0.0
    var back_count := 0.0
    for i in _positions.size():
        var displacement := _positions[i] - _rest_positions[i]
        maximum = maxf(maximum, displacement.length())
        sag = maxf(sag, -displacement.y)
        average += displacement
        if _rest_positions[i].x < 0.0:
            left_height += displacement.y
            left_count += 1.0
        else:
            right_height += displacement.y
            right_count += 1.0
        if _rest_positions[i].z < 0.0:
            front_height += displacement.y
            front_count += 1.0
        else:
            back_height += displacement.y
            back_count += 1.0
    if not _positions.is_empty():
        average /= float(_positions.size())
    _max_displacement = maximum
    var roll := (
        right_height / maxf(right_count, 1.0)
        - left_height / maxf(left_count, 1.0)
    ) / maxf(span.x, 0.1)
    var pitch := (
        back_height / maxf(back_count, 1.0)
        - front_height / maxf(front_count, 1.0)
    ) / maxf(span.z, 0.1)
    return {
        "max_displacement": maximum,
        "sag": sag,
        "average": average,
        "roll": clampf(roll, -0.42, 0.42),
        "pitch": clampf(pitch, -0.42, 0.42),
        "damage": _mean_damage(),
        "broken_fraction": get_broken_fraction(),
        "components": _component_count,
        "stiffness_ratio": get_stiffness_ratio(),
        "wave_peak": get_wave_peak(),
        "energy": get_energy_state()
    }


func _mean_damage() -> float:
    if _bonds.is_empty():
        return 0.0
    var total := 0.0
    for bond in _bonds:
        total += float(bond.damage)
    return total / float(_bonds.size())


func fracture_by_energy(
        local_point: Vector3,
        direction: Vector3,
        available_energy: float,
        max_fragments: int = -1
) -> Dictionary:
    var fragment_cap := max_fragments if max_fragments > 0 else Fidelity.max_shards()
    var energy := clampf(available_energy, 0.0, 300000.0)
    _last_impact_point = local_point
    _last_impact_direction = (
        direction.normalized()
        if direction.length_squared() > 0.0001
        else Vector3.UP
    )
    _release_point = local_point
    _release_direction = _last_impact_direction
    _input_energy += energy
    var mean_cost := 0.0
    for bond in _bonds:
        mean_cost += float(bond.fracture_cost)
    mean_cost /= maxf(float(_bonds.size()), 1.0)
    var desired := clampi(
        1 + int(floor(sqrt(
            energy / maxf(mean_cost * 2.6, 1.0)
        ))),
        2,
        mini(fragment_cap, _positions.size())
    )
    var budget := energy * 0.42
    var labels: Array[int] = []
    var boundary_cost := INF
    while desired >= 2:
        labels = _partition_labels(
            desired,
            local_point,
            _last_impact_direction
        )
        boundary_cost = _partition_cost(labels)
        if boundary_cost <= budget:
            break
        desired -= 1
    if desired < 2:
        _residual_energy = minf(
            _residual_energy + energy * 0.18,
            RESIDUAL_ENERGY_CEILING
        )
        return get_energy_state()

    for bond in _bonds:
        var first := int(bond.a)
        var second := int(bond.b)
        if labels[first] != labels[second]:
            _break_bond(bond)
    _fracture_finalized = true
    for i in _pinned.size():
        _pinned[i] = false
    _residual_energy = minf(
        _residual_energy + maxf(
            0.0,
            energy - boundary_cost - energy * 0.24
        ),
        RESIDUAL_ENERGY_CEILING
    )
    _refresh_topology()
    return get_energy_state()


func fracture_into_columns() -> void:
    # Compatibility path for old callers; no canned topology remains.
    fracture_by_energy(
        _last_impact_point,
        _last_impact_direction,
        maxf(_input_energy, fracture_energy_density * 18.0),
        mini(columns, Fidelity.max_shards())
    )


func _partition_labels(
        count: int,
        local_point: Vector3,
        direction: Vector3
) -> Array[int]:
    var seeds: Array[int] = []
    seeds.append(int(_nearest_nodes(local_point, 1)[0].index))
    var planar_direction := Vector3(direction.x, 0.0, direction.z)
    if planar_direction.length_squared() < 0.001:
        planar_direction = Vector3(1.0, 0.0, 0.0)
    planar_direction = planar_direction.normalized()
    while seeds.size() < count:
        var best_index := 0
        var best_score := -INF
        for candidate in _positions.size():
            if seeds.has(candidate):
                continue
            var nearest_seed := INF
            for seed in seeds:
                nearest_seed = minf(
                    nearest_seed,
                    _positions[candidate].distance_squared_to(
                        _positions[seed]
                    )
                )
            var impact_offset := _positions[candidate] - local_point
            var direction_bias := absf(
                impact_offset.normalized().dot(planar_direction)
            )
            var score := nearest_seed * (
                1.0 + direction_bias * 0.24
            )
            if score > best_score:
                best_score = score
                best_index = candidate
        seeds.append(best_index)

    var labels: Array[int] = []
    for node in _positions.size():
        var best_label := 0
        var best_distance := INF
        for label in seeds.size():
            var offset := _positions[node] - _positions[seeds[label]]
            var along := offset.dot(planar_direction)
            var across := offset - planar_direction * along
            var anisotropic_distance := (
                along * along * 0.72
                + across.length_squared() * 1.18
            )
            if anisotropic_distance < best_distance:
                best_distance = anisotropic_distance
                best_label = label
        labels.append(best_label)
    return labels


func _partition_cost(labels: Array[int]) -> float:
    var cost := 0.0
    for bond in _bonds:
        if not bool(bond.active):
            continue
        if labels[int(bond.a)] == labels[int(bond.b)]:
            continue
        cost += float(bond.fracture_cost) * (
            1.0 - float(bond.damage) * 0.82
        )
    return cost


func get_fragment_specs(
        fragment_thickness: float = 0.20,
        minimum_nodes: int = 1
) -> Array[Dictionary]:
    _refresh_topology()
    var result: Array[Dictionary] = []
    for component in _components():
        if component.size() < minimum_nodes:
            continue
        result.append(_component_spec(
            component,
            fragment_thickness
        ))
    if result.is_empty():
        return result

    var common_velocity := (
        _release_momentum / maxf(total_mass, 0.001)
    )
    var direction_sum := Vector3.ZERO
    for spec in result:
        var radial := (
            spec.local_position as Vector3
        ) - _release_point
        radial += _release_direction * maxf(
            span.length() * 0.08,
            0.2
        )
        if radial.length_squared() < 0.0001:
            radial = _release_direction
        spec["release_axis"] = radial.normalized()
        direction_sum += (
            spec.release_axis as Vector3
        ) * float(spec.mass)
    var mean_axis := direction_sum / maxf(total_mass, 0.001)
    var unit_energy := 0.0
    for spec in result:
        var relative_axis := (
            spec.release_axis as Vector3
        ) - mean_axis
        spec["release_axis"] = relative_axis
        unit_energy += (
            0.5
            * float(spec.mass)
            * relative_axis.length_squared()
        )
    var release_scale := sqrt(
        maxf(_residual_energy * 0.68, 0.0)
        / maxf(unit_energy, 0.001)
    )
    for spec in result:
        spec.linear_velocity = (
            spec.linear_velocity as Vector3
            + common_velocity
            + (spec.release_axis as Vector3) * release_scale
        )
        spec.erase("release_axis")
    return result


func _component_spec(
        component: Array,
        fragment_thickness: float
) -> Dictionary:
    var minimum := Vector3(INF, INF, INF)
    var maximum := Vector3(-INF, -INF, -INF)
    var center := Vector3.ZERO
    var velocity := Vector3.ZERO
    for index in component:
        var position := _positions[index]
        minimum.x = minf(minimum.x, position.x)
        minimum.y = minf(minimum.y, position.y)
        minimum.z = minf(minimum.z, position.z)
        maximum.x = maxf(maximum.x, position.x)
        maximum.y = maxf(maximum.y, position.y)
        maximum.z = maxf(maximum.z, position.z)
        center += position
        velocity += _velocities[index]
    center /= float(component.size())
    velocity /= float(component.size())
    var angular_momentum := Vector3.ZERO
    var inertia := Vector3.ZERO
    for index in component:
        var offset := _positions[index] - center
        var relative_velocity := _velocities[index] - velocity
        angular_momentum += offset.cross(
            relative_velocity * _node_mass
        )
        inertia.x += _node_mass * (
            offset.y * offset.y + offset.z * offset.z
        )
        inertia.y += _node_mass * (
            offset.x * offset.x + offset.z * offset.z
        )
        inertia.z += _node_mass * (
            offset.x * offset.x + offset.y * offset.y
        )
    var cell_width := span.x / float(maxi(columns - 1, 1))
    var cell_depth := span.z / float(maxi(rows - 1, 1))
    var footprint_points: Array[Vector2] = []
    for index in component:
        var point := _positions[index]
        for corner in [
            Vector2(-0.46, -0.46),
            Vector2(0.46, -0.46),
            Vector2(0.46, 0.46),
            Vector2(-0.46, 0.46)
        ]:
            footprint_points.append(Vector2(
                point.x + corner.x * cell_width,
                point.z + corner.y * cell_depth
            ))
    var world_hull := _convex_hull(footprint_points)
    var local_hull := PackedVector2Array()
    for point in world_hull:
        local_hull.append(point - Vector2(center.x, center.z))
    return {
        "local_position": center,
        "size": Vector3(
            maxf(
                0.24,
                maximum.x - minimum.x + cell_width * 0.52
            ),
            maxf(
                fragment_thickness,
                maximum.y - minimum.y + fragment_thickness
            ),
            maxf(
                0.24,
                maximum.z - minimum.z + cell_depth * 0.52
            )
        ),
        "mass": _node_mass * float(component.size()),
        "linear_velocity": velocity,
        "angular_velocity": Vector3(
            angular_momentum.x / maxf(inertia.x, 0.001),
            angular_momentum.y / maxf(inertia.y, 0.001),
            angular_momentum.z / maxf(inertia.z, 0.001)
        ),
        "hull": local_hull,
        "nodes": component
    }


func _convex_hull(points: Array[Vector2]) -> Array[Vector2]:
    if points.size() <= 3:
        return points
    var sorted: Array[Vector2] = points.duplicate()
    for i in range(1, sorted.size()):
        var value: Vector2 = sorted[i]
        var insert_at := i
        while insert_at > 0 and _point_after(
                sorted[insert_at - 1], value
        ):
            sorted[insert_at] = sorted[insert_at - 1]
            insert_at -= 1
        sorted[insert_at] = value
    var lower: Array[Vector2] = []
    for point in sorted:
        while lower.size() >= 2 and _cross_2d(
                lower[-2], lower[-1], point
        ) <= 0.0:
            lower.pop_back()
        lower.append(point)
    var upper: Array[Vector2] = []
    for reverse_index in range(sorted.size() - 1, -1, -1):
        var point: Vector2 = sorted[reverse_index]
        while upper.size() >= 2 and _cross_2d(
                upper[-2], upper[-1], point
        ) <= 0.0:
            upper.pop_back()
        upper.append(point)
    lower.pop_back()
    upper.pop_back()
    lower.append_array(upper)
    return lower


func _point_after(first: Vector2, second: Vector2) -> bool:
    return (
        first.x > second.x
        or (is_equal_approx(first.x, second.x) and first.y > second.y)
    )


func _cross_2d(
        origin: Vector2,
        first: Vector2,
        second: Vector2
) -> float:
    var a := first - origin
    var b := second - origin
    return a.x * b.y - a.y * b.x


func get_revision() -> int:
    return _revision


func get_grid_size() -> Vector2i:
    return Vector2i(columns, rows)


func get_node_count() -> int:
    return _positions.size()


func get_bond_count() -> int:
    return _bonds.size()


func get_node_position(index: int) -> Vector3:
    if index < 0 or index >= _positions.size():
        return Vector3.ZERO
    return _positions[index]


func get_node_damage(index: int) -> float:
    var damage := 0.0
    var count := 0.0
    for bond in _bonds:
        if int(bond.a) == index or int(bond.b) == index:
            damage += float(bond.damage)
            count += 1.0
    return damage / maxf(count, 1.0)


## Peak tensile elastic strain on the bonds meeting at this node, mapped to
## 0..1. This is the field the skin reads as heat; it is not a temperature.
func get_node_heat(index: int) -> float:
    if index < 0 or index >= _positions.size():
        return 0.0
    var peak := 0.0
    for bond in _bonds:
        if not bool(bond.active):
            continue
        if int(bond.a) != index and int(bond.b) != index:
            continue
        var rest := maxf(float(bond.rest), 0.0001)
        var length := _positions[int(bond.a)].distance_to(
            _positions[int(bond.b)]
        )
        var elastic := (length - rest) / rest - float(bond.plastic)
        peak = maxf(peak, absf(elastic))
    return smoothstep(0.2, 1.0, peak / maxf(failure_strain, 0.0001))


## Constraint impulse carried by this node, as a fraction of its own weight.
## lambda / dt is the axial force estimate; anything that wants to know how
## hard the structure is working reads this rather than a HUD scalar.
func get_node_load(index: int) -> float:
    if index < 0 or index >= _positions.size():
        return 0.0
    var impulse := 0.0
    for bond in _bonds:
        if not bool(bond.active):
            continue
        if int(bond.a) != index and int(bond.b) != index:
            continue
        impulse += absf(float(bond.lambda))
    var force := impulse / maxf(_last_substep_delta, 0.0001)
    var ratio := force / maxf(_node_mass * 9.81, 0.001)
    return ratio / (1.0 + ratio)


func get_bond_visuals() -> Array[Dictionary]:
    var result: Array[Dictionary] = []
    for bond in _bonds:
        result.append({
            "a": int(bond.a),
            "b": int(bond.b),
            "damage": float(bond.damage),
            "lambda": float(bond.lambda),
            "plastic": float(bond.plastic),
            "active": bool(bond.active)
        })
    return result


func get_energy_state() -> Dictionary:
    return {
        "input": _input_energy,
        "plastic": _plastic_energy,
        "surface": _surface_energy,
        "residual": _residual_energy,
        "crack_budget": _crack_budget,
        "components": _component_count,
        "stiffness_ratio": get_stiffness_ratio()
    }


func impact_kernel_radius(energy: float) -> float:
    var cell := _cell_scale()
    var energy_ratio := clampf(
        energy / maxf(total_mass * 18.0, 1.0),
        0.0,
        6.0
    )
    return cell * clampf(0.82 + sqrt(energy_ratio) * 1.05, 0.82, 2.65)


func get_last_impact_point() -> Vector3:
    return _last_impact_point


func get_last_impact_direction() -> Vector3:
    return _last_impact_direction


func get_last_impact_radius() -> float:
    return _last_impact_radius


func is_retired(index: int) -> bool:
    if index < 0 or index >= _retired.size():
        return false
    return bool(_retired[index])


func nearest_node_index(local_point: Vector3) -> int:
    var nearest := _nearest_nodes(local_point, 1)
    if nearest.is_empty():
        return -1
    return int(nearest[0].index)


func get_node_wave(index: int) -> float:
    if index < 0 or index >= _wave.size():
        return 0.0
    var intensity := float(_wave[index])
    return intensity / (1.0 + intensity)


func get_wave_peak() -> float:
    var peak := 0.0
    for i in _wave.size():
        if is_retired(i):
            continue
        peak = maxf(peak, float(_wave[i]))
    return peak / (1.0 + peak)


func get_stiffness_ratio() -> float:
    if _bonds.is_empty():
        return 1.0
    var total := 0.0
    for bond in _bonds:
        if not bool(bond.active):
            continue
        var damage_scale := maxf((1.0 - float(bond.damage)) ** 2, 0.0)
        total += damage_scale
    return clampf(total / float(_bonds.size()), 0.0, 1.0)


func get_crack_front_points() -> Array[Vector3]:
    var points: Array[Vector3] = []
    for front in _crack_fronts:
        if not bool(front.get("alive", false)):
            continue
        var index := int(front.get("index", -1))
        if index < 0 or index >= _positions.size() or is_retired(index):
            continue
        points.append(_positions[index])
    return points


func _seed_crack_fronts(
        local_point: Vector3,
        direction: Vector3,
        energy: float
) -> void:
    var origin := nearest_node_index(local_point)
    if origin < 0:
        return
    var energy_ratio := clampf(
        energy / maxf(total_mass * 18.0, 1.0),
        0.0,
        4.0
    )
    var count := clampi(3 + int(energy_ratio), 3, 7)
    var planar := Vector3(direction.x, 0.0, direction.z)
    if planar.length_squared() < 0.001:
        planar = Vector3(1.0, 0.0, 0.0)
    planar = planar.normalized()
    var seed := local_point.x * 12.9898 + local_point.z * 78.233
    var spin := fmod(absf(seed) * 0.17, TAU)
    var per_front := _crack_budget / float(count)
    var alive_count := 0
    for front in _crack_fronts:
        if bool(front.get("alive", false)):
            alive_count += 1
    for ray_index in count:
        if alive_count >= MAX_CRACK_FRONTS:
            break
        var angle := spin + TAU * float(ray_index) / float(count)
        var ray_dir := Vector3(cos(angle), 0.0, sin(angle))
        if ray_index == 0:
            ray_dir = planar
        _crack_fronts.append({
            "index": origin,
            "direction": ray_dir.normalized(),
            "budget": per_front,
            "alive": true
        })
        alive_count += 1


func _update_wave(delta: float) -> void:
    if _wave.size() != _positions.size():
        _wave.resize(_positions.size())
    var decay := exp(-WAVE_DECAY_PER_SECOND * delta)
    for i in _positions.size():
        if is_retired(i):
            _wave[i] = 0.0
            continue
        var kinetic := (
            0.5
            * _node_mass
            * _velocities[i].length_squared()
        )
        _wave[i] = maxf(float(_wave[i]) * decay, kinetic)


func _advance_crack_fronts(delta: float) -> void:
    if _crack_fronts.is_empty() or _crack_budget <= 0.0:
        return
    var hops := clampi(ceili(delta / 0.006), 1, 5)
    for _hop in hops:
        var advanced := false
        for front_index in _crack_fronts.size():
            if _advance_one_front(front_index):
                advanced = true
        if not advanced:
            break


func _advance_one_front(front_index: int) -> bool:
    var front: Dictionary = _crack_fronts[front_index]
    if not bool(front.get("alive", false)):
        return false
    var node := int(front.get("index", -1))
    if node < 0 or node >= _positions.size() or is_retired(node):
        front.alive = false
        _crack_fronts[front_index] = front
        return false
    var budget := float(front.get("budget", 0.0))
    if budget < 1.0:
        front.alive = false
        _crack_fronts[front_index] = front
        return false
    var dir: Vector3 = front.get("direction", Vector3.RIGHT)
    if dir.length_squared() < 0.0001:
        dir = Vector3.RIGHT
    dir = dir.normalized()

    var best_bond: Dictionary = {}
    var best_other := -1
    var best_score := -INF
    for bond in _bonds:
        if not bool(bond.active):
            continue
        var other := -1
        if int(bond.a) == node:
            other = int(bond.b)
        elif int(bond.b) == node:
            other = int(bond.a)
        else:
            continue
        if is_retired(other):
            continue
        var offset := _positions[other] - _positions[node]
        if offset.length_squared() < 0.000001:
            continue
        var align := offset.normalized().dot(dir)
        if align < 0.12:
            continue
        var tensile := _bond_tensile_energy(bond)
        var local_wave := 0.5 * (
            float(_wave[node]) + float(_wave[other])
        )
        var score := (
            (tensile + local_wave * 0.45)
            * (0.50 + 0.50 * align)
            * (1.0 + float(bond.damage) * 0.85)
        )
        if score > best_score:
            best_score = score
            best_bond = bond
            best_other = other
    if best_other < 0 or best_bond.is_empty():
        front.alive = false
        _crack_fronts[front_index] = front
        return false

    var cost := float(best_bond.fracture_cost) * maxf(
        1.0 - float(best_bond.damage),
        0.12
    )
    var available := budget + float(_wave[node]) * 6.0
    if available < cost * 0.28:
        best_bond.damage = clampf(
            float(best_bond.damage) + 0.07,
            0.0,
            1.0
        )
        best_bond.history = maxf(
            float(best_bond.history),
            damage_onset + float(best_bond.damage) * (
                failure_strain - damage_onset
            )
        )
        _crack_fronts[front_index] = front
        return false

    var spent := minf(cost, budget)
    front.budget = budget - spent
    _crack_budget = maxf(_crack_budget - spent, 0.0)
    if (
        float(best_bond.damage) >= 0.55
        or available >= cost
        or _bond_tensile_energy(best_bond) >= cost * 0.18
    ):
        _break_bond(best_bond)
        front.index = best_other
        var next_dir := _positions[best_other] - _positions[node]
        if next_dir.length_squared() > 0.0001:
            front.direction = next_dir.normalized().lerp(dir, 0.35).normalized()
        _crack_fronts[front_index] = front
        return true

    best_bond.damage = clampf(float(best_bond.damage) + 0.32, 0.0, 1.0)
    best_bond.history = maxf(float(best_bond.history), damage_onset)
    _crack_fronts[front_index] = front
    return false


func _bond_tensile_energy(bond: Dictionary) -> float:
    var first := int(bond.a)
    var second := int(bond.b)
    var rest := maxf(float(bond.rest), 0.0001)
    var length := _positions[first].distance_to(_positions[second])
    var elastic := (length - rest) / rest - float(bond.plastic)
    var tensile := maxf(elastic, 0.0)
    var damage_scale := maxf((1.0 - float(bond.damage)) ** 2, 0.025)
    return (
        0.5
        * float(bond.stiffness)
        * tensile
        * tensile
        * rest
        * damage_scale
    )


func _cell_scale() -> float:
    var dx := span.x / maxf(float(columns - 1), 1.0)
    var dz := span.z / maxf(float(rows - 1), 1.0)
    return maxf(0.08, (absf(dx) + absf(dz)) * 0.5)


func _wendland(q: float) -> float:
    if q >= 1.0:
        return 0.0
    var x := maxf(0.0, 1.0 - q)
    return x * x * x * x * (1.0 + 4.0 * q)


func get_height_map_data() -> PackedFloat32Array:
    var data := PackedFloat32Array()
    data.resize(columns * rows)
    for row in rows:
        for column in columns:
            var index := _index(column, row)
            if is_retired(index):
                data[row * columns + column] = NAN
            else:
                data[row * columns + column] = _positions[index].y
    return data


func take_detached_fragments(
        fragment_thickness: float = 0.20,
        minimum_nodes: int = 2
) -> Array[Dictionary]:
    _refresh_topology()
    var components := _components()
    if components.size() <= 1:
        return []
    var keep_index := 0
    var keep_score := -INF
    for i in components.size():
        var score := float((components[i] as Array).size())
        var has_pin := false
        for node_index in components[i]:
            if _pinned[int(node_index)] and not _fracture_finalized:
                has_pin = true
                break
        if has_pin:
            score += 100000.0
        if score > keep_score:
            keep_score = score
            keep_index = i
    var specs: Array[Dictionary] = []
    for i in components.size():
        if i == keep_index:
            continue
        var component: Array = components[i]
        if component.size() < minimum_nodes:
            _retire_component(component)
            continue
        specs.append(_component_spec(component, fragment_thickness))
        _retire_component(component)
    if not specs.is_empty():
        _refresh_topology()
        _revision += 1
    return specs


func _retire_component(component: Array) -> void:
    for raw in component:
        var index := int(raw)
        if index < 0 or index >= _retired.size():
            continue
        _retired[index] = true
        _velocities[index] = Vector3.ZERO
        _forces[index] = Vector3.ZERO
        if index < _wave.size():
            _wave[index] = 0.0
        _pinned[index] = true
        for bond in _bonds:
            if int(bond.a) == index or int(bond.b) == index:
                if bool(bond.active):
                    _break_bond(bond)


func _components() -> Array:
    var adjacency: Array = []
    for _i in _positions.size():
        adjacency.append([])
    for bond in _bonds:
        if not bool(bond.active):
            continue
        var first := int(bond.a)
        var second := int(bond.b)
        adjacency[first].append(second)
        adjacency[second].append(first)
    var visited: Array[bool] = []
    visited.resize(_positions.size())
    for i in visited.size():
        visited[i] = false
    var result: Array = []
    for start in _positions.size():
        if visited[start] or is_retired(start):
            continue
        var component: Array[int] = []
        var queue: Array[int] = [start]
        visited[start] = true
        while not queue.is_empty():
            var current: int = queue.pop_front()
            component.append(current)
            for neighbor in adjacency[current]:
                if visited[neighbor]:
                    continue
                visited[neighbor] = true
                queue.append(neighbor)
        result.append(component)
    return result
