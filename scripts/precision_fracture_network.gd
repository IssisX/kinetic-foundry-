class_name PrecisionFractureNetwork
extends "res://scripts/fracture_network.gd"

## Localized impact/fracture extension for player-visible material response.
## Direct impacts use a compact Wendland kernel around the true contact point;
## sustained loads should continue to use the base apply_force() path.

var last_impact_point := Vector3.ZERO
var last_impact_energy := 0.0
var last_impact_radius := 0.0

func apply_impact(
        local_point: Vector3,
        impulse: Vector3,
        impact_energy: float
) -> Dictionary:
    if _positions.is_empty():
        return {}
    last_impact_point = local_point
    last_impact_energy = maxf(impact_energy, 0.0)

    var cell := _cell_scale()
    var energy_ratio := clampf(
        last_impact_energy / maxf(total_mass * 18.0, 1.0),
        0.0,
        4.0
    )
    var radius := cell * clampf(
        0.92 + sqrt(energy_ratio) * 0.92,
        0.92,
        3.25
    )
    last_impact_radius = radius

    var impulse_direction := impulse.normalized()
    if impulse_direction.length_squared() < 0.001:
        impulse_direction = Vector3(0.0, 1.0, 0.0)

    var weights: Array[float] = []
    weights.resize(_positions.size())
    var weight_sum := 0.0
    for i in _positions.size():
        var distance := _rest_positions[i].distance_to(local_point)
        var weight := _wendland(distance / maxf(radius, 0.001))
        weights[i] = weight
        weight_sum += weight

    if weight_sum <= 0.0001:
        return get_deformation_state()

    var impulse_scale := clampf(
        impulse.length() / maxf(total_mass * 9.0, 1.0),
        0.0,
        3.0
    )
    for i in _positions.size():
        if _pinned[i] or weights[i] <= 0.0:
            continue
        var normalized_weight := weights[i] / weight_sum
        var local_weight := weights[i]
        var dent := (
            cell
            * (0.035 + energy_ratio * 0.050)
            * local_weight
        )
        _positions[i] += impulse_direction * dent
        _velocities[i] += (
            impulse
            * normalized_weight
            / maxf(_node_mass, 0.001)
            * 0.020
        )

    for bond_index in _bonds.size():
        var bond: Dictionary = _bonds[bond_index]
        if not bool(bond.active):
            continue
        var first := int(bond.a)
        var second := int(bond.b)
        var midpoint := (
            _rest_positions[first] + _rest_positions[second]
        ) * 0.5
        var weight := _wendland(
            midpoint.distance_to(local_point) / maxf(radius, 0.001)
        )
        if weight <= 0.0:
            continue
        var axis := (
            _rest_positions[second] - _rest_positions[first]
        ).normalized()
        var directional_shear := (
            1.0 - absf(axis.dot(impulse_direction))
        )
        var damage_increment := (
            weight
            * energy_ratio
            * (0.18 + directional_shear * 0.18)
        )
        bond.damage = clampf(
            maxf(float(bond.damage), float(bond.damage) + damage_increment),
            0.0,
            1.0
        )
        var plastic_increment := (
            weight
            * energy_ratio
            * (0.004 + directional_shear * 0.008)
        )
        bond.plastic = clampf(
            float(bond.plastic)
            + signf(axis.dot(impulse_direction)) * plastic_increment,
            -0.22,
            0.22
        )
        if float(bond.damage) >= 1.0:
            bond.active = false
            _topology_dirty = true

    var settle_steps := clampi(2 + int(energy_ratio * 2.0), 2, 8)
    for _i in settle_steps:
        step(1.0 / 120.0)
    return get_deformation_state()

func fracture_localized(
        local_point: Vector3,
        impact_energy: float,
        impact_direction: Vector3
) -> void:
    if _bonds.is_empty():
        return
    var cell := _cell_scale()
    var energy_ratio := clampf(
        impact_energy / maxf(total_mass * 16.0, 1.0),
        0.55,
        5.0
    )
    var core_radius := cell * clampf(
        0.52 + sqrt(energy_ratio) * 0.42,
        0.65,
        2.10
    )
    var crack_width := cell * clampf(
        0.10 + energy_ratio * 0.035,
        0.10,
        0.30
    )

    var planar := Vector2(impact_direction.x, impact_direction.z)
    var base_angle := 0.0
    if planar.length_squared() > 0.001:
        base_angle = atan2(planar.y, planar.x)
    else:
        base_angle = (
            local_point.x * 0.73
            + local_point.z * 1.17
            + impact_energy * 0.00013
        )

    var crack_count := clampi(2 + int(energy_ratio * 0.75), 2, 5)
    var crack_length := maxf(span.x, span.z) * 1.35
    var ray_ends: Array[Vector3] = []
    for crack_index in crack_count:
        var phase := float(crack_index) / float(crack_count)
        var angle := (
            base_angle
            + phase * TAU
            + sin(float(crack_index) * 2.37 + base_angle) * 0.28
        )
        ray_ends.append(
            local_point
            + Vector3(cos(angle), 0.0, sin(angle)) * crack_length
        )

    for bond_index in _bonds.size():
        var bond: Dictionary = _bonds[bond_index]
        if not bool(bond.active):
            continue
        var first := int(bond.a)
        var second := int(bond.b)
        var midpoint := (
            _rest_positions[first] + _rest_positions[second]
        ) * 0.5
        var radial_distance := midpoint.distance_to(local_point)
        var crack_proximity := INF
        for ray_end in ray_ends:
            crack_proximity = minf(
                crack_proximity,
                _distance_to_segment_xz(
                    midpoint,
                    local_point,
                    ray_end
                )
            )
        var core_weight := _wendland(
            radial_distance / maxf(core_radius, 0.001)
        )
        var crack_weight := clampf(
            1.0 - crack_proximity / maxf(crack_width, 0.001),
            0.0,
            1.0
        )
        var break_score := (
            core_weight * energy_ratio * 0.62
            + crack_weight * energy_ratio * 0.54
        )
        if break_score >= 0.78:
            bond.damage = 1.0
            bond.active = false
            _topology_dirty = true
        elif break_score > 0.12:
            bond.damage = clampf(
                float(bond.damage) + break_score * 0.36,
                0.0,
                1.0
            )

    _refresh_topology()

func get_node_position(column: int, row: int) -> Vector3:
    if columns <= 0 or rows <= 0:
        return Vector3.ZERO
    var safe_column := clampi(column, 0, columns - 1)
    var safe_row := clampi(row, 0, rows - 1)
    return _positions[_index(safe_column, safe_row)]

func get_cell_state(column: int, row: int) -> Dictionary:
    if column < 0 or row < 0 or column + 1 >= columns or row + 1 >= rows:
        return {}
    var p00 := get_node_position(column, row)
    var p10 := get_node_position(column + 1, row)
    var p01 := get_node_position(column, row + 1)
    var p11 := get_node_position(column + 1, row + 1)
    var center := (p00 + p10 + p01 + p11) * 0.25
    var axis_x := ((p10 + p11) - (p00 + p01)) * 0.5
    var axis_z := ((p01 + p11) - (p00 + p10)) * 0.5
    var width := maxf(axis_x.length(), 0.05)
    var height_value := maxf(axis_z.length(), 0.05)
    axis_x = axis_x.normalized()
    axis_z = axis_z.normalized()
    var normal := axis_z.cross(axis_x).normalized()
    if normal.y < 0.0:
        normal = -normal
    return {
        "center": center,
        "axis_x": axis_x,
        "axis_z": axis_z,
        "normal": normal,
        "width": width,
        "height": height_value
    }

func _cell_scale() -> float:
    var dx := span.x / maxf(float(columns - 1), 1.0)
    var dz := span.z / maxf(float(rows - 1), 1.0)
    return maxf(0.08, (absf(dx) + absf(dz)) * 0.5)

func _wendland(q: float) -> float:
    if q >= 1.0:
        return 0.0
    var x := maxf(0.0, 1.0 - q)
    return x * x * x * x * (1.0 + 4.0 * q)

func _distance_to_segment_xz(
        point: Vector3,
        start: Vector3,
        end: Vector3
) -> float:
    var p := Vector2(point.x, point.z)
    var a := Vector2(start.x, start.z)
    var b := Vector2(end.x, end.z)
    var ab := b - a
    var denominator := ab.length_squared()
    if denominator <= 0.000001:
        return p.distance_to(a)
    var t := clampf((p - a).dot(ab) / denominator, 0.0, 1.0)
    return p.distance_to(a + ab * t)
