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
            * (
                0.025
                + energy_ratio * 0.046
                + impulse_scale * 0.015
            )
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
        var damage_drive := (
            energy_ratio * 0.27
            + impulse_scale * 0.11
        )
        var damage_increment := (
            weight
            * damage_drive
            * (0.70 + directional_shear * 0.55)
        )
        bond.damage = clampf(
            float(bond.damage) + damage_increment,
            0.0,
            1.0
        )
        var plastic_increment := (
            weight
            * (energy_ratio * 0.006 + impulse_scale * 0.003)
            * (0.72 + directional_shear * 0.55)
        )
        var direction_sign := signf(axis.dot(impulse_direction))
        if absf(direction_sign) < 0.5:
            direction_sign = 1.0
        bond.plastic = clampf(
            float(bond.plastic)
            + direction_sign * plastic_increment,
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
        0.12 + energy_ratio * 0.045,
        0.12,
        0.36
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

    var target_components := clampi(
        2 + int(floor(sqrt(energy_ratio) * 1.55)),
        2,
        6
    )
    var crack_count := clampi(
        target_components + (1 if energy_ratio > 2.8 else 0),
        2,
        7
    )
    var crack_length := maxf(span.x, span.z) * 1.45
    var ray_ends: Array[Vector3] = []
    for crack_index in crack_count:
        var phase := float(crack_index) / float(crack_count)
        var angle := (
            base_angle
            + phase * TAU
            + sin(float(crack_index) * 2.37 + base_angle) * 0.22
        )
        ray_ends.append(
            local_point
            + Vector3(cos(angle), 0.0, sin(angle)) * crack_length
        )

    _cut_ray_family(
        local_point,
        ray_ends,
        core_radius,
        crack_width,
        energy_ratio
    )
    _refresh_topology()

    # A visible fracture must change connectivity, not only bond shading. If the
    # first radial family still leaves alternate diagonal load paths, add
    # deterministic contact-origin cuts until the energy-derived target is met.
    var reinforcement_pass := 0
    while _component_count < target_components and reinforcement_pass < 4:
        var extra_angle := (
            base_angle
            + (float(reinforcement_pass) + 0.5)
            * TAU / float(maxi(target_components, 2))
            + 0.31
        )
        var extra_end := (
            local_point
            + Vector3(cos(extra_angle), 0.0, sin(extra_angle))
            * crack_length
        )
        _cut_single_ray(
            local_point,
            extra_end,
            crack_width * (1.10 + float(reinforcement_pass) * 0.08),
            energy_ratio
        )
        _refresh_topology()
        reinforcement_pass += 1

    # High-energy local spall detaches a bounded patch around the strike point.
    # This is intentionally local: it avoids the old whole-panel column breakup.
    if _component_count < target_components and energy_ratio >= 1.10:
        _cut_spall_ring(
            local_point,
            cell * clampf(0.72 + energy_ratio * 0.18, 0.82, 1.60),
            crack_width
        )
        _refresh_topology()

func _cut_ray_family(
        origin: Vector3,
        ray_ends: Array[Vector3],
        core_radius: float,
        crack_width: float,
        energy_ratio: float
) -> void:
    for bond_index in _bonds.size():
        var bond: Dictionary = _bonds[bond_index]
        if not bool(bond.active):
            continue
        var first := int(bond.a)
        var second := int(bond.b)
        var first_position := _rest_positions[first]
        var second_position := _rest_positions[second]
        var midpoint := (first_position + second_position) * 0.5
        var radial_distance := midpoint.distance_to(origin)
        var crack_proximity := INF
        var crosses_crack := false
        for ray_end in ray_ends:
            crack_proximity = minf(
                crack_proximity,
                _distance_to_segment_xz(midpoint, origin, ray_end)
            )
            if _segments_intersect_xz(
                    first_position,
                    second_position,
                    origin,
                    ray_end
            ):
                crosses_crack = true

        var core_weight := _wendland(
            radial_distance / maxf(core_radius, 0.001)
        )
        var proximity_weight := clampf(
            1.0 - crack_proximity / maxf(crack_width, 0.001),
            0.0,
            1.0
        )
        var crack_weight := maxf(
            proximity_weight,
            1.0 if crosses_crack else 0.0
        )
        var break_score := (
            core_weight * energy_ratio * 0.58
            + crack_weight * (0.74 + energy_ratio * 0.18)
        )
        if break_score >= 0.78:
            bond.damage = 1.0
            bond.active = false
            _topology_dirty = true
        elif break_score > 0.12:
            bond.damage = clampf(
                float(bond.damage) + break_score * 0.34,
                0.0,
                1.0
            )

func _cut_single_ray(
        origin: Vector3,
        ray_end: Vector3,
        crack_width: float,
        energy_ratio: float
) -> void:
    for bond_index in _bonds.size():
        var bond: Dictionary = _bonds[bond_index]
        if not bool(bond.active):
            continue
        var first := int(bond.a)
        var second := int(bond.b)
        var first_position := _rest_positions[first]
        var second_position := _rest_positions[second]
        var midpoint := (first_position + second_position) * 0.5
        var crosses := _segments_intersect_xz(
            first_position,
            second_position,
            origin,
            ray_end
        )
        var proximity := _distance_to_segment_xz(
            midpoint,
            origin,
            ray_end
        )
        var proximity_weight := clampf(
            1.0 - proximity / maxf(crack_width, 0.001),
            0.0,
            1.0
        )
        if not crosses and proximity_weight < 0.72:
            continue
        var cut_strength := maxf(
            proximity_weight,
            1.0 if crosses else 0.0
        ) * (0.78 + energy_ratio * 0.12)
        if cut_strength >= 0.72:
            bond.damage = 1.0
            bond.active = false
            _topology_dirty = true

func _cut_spall_ring(
        origin: Vector3,
        ring_radius: float,
        crack_width: float
) -> void:
    for bond_index in _bonds.size():
        var bond: Dictionary = _bonds[bond_index]
        if not bool(bond.active):
            continue
        var first := int(bond.a)
        var second := int(bond.b)
        var first_distance := _rest_positions[first].distance_to(origin)
        var second_distance := _rest_positions[second].distance_to(origin)
        var crosses_ring := (
            (first_distance - ring_radius)
            * (second_distance - ring_radius)
            <= 0.0
        )
        var midpoint := (
            _rest_positions[first] + _rest_positions[second]
        ) * 0.5
        var ring_error := absf(midpoint.distance_to(origin) - ring_radius)
        if crosses_ring or ring_error <= crack_width * 0.62:
            bond.damage = 1.0
            bond.active = false
            _topology_dirty = true

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

func _segments_intersect_xz(
        first_a: Vector3,
        first_b: Vector3,
        second_a: Vector3,
        second_b: Vector3
) -> bool:
    var a := Vector2(first_a.x, first_a.z)
    var b := Vector2(first_b.x, first_b.z)
    var c := Vector2(second_a.x, second_a.z)
    var d := Vector2(second_b.x, second_b.z)
    var ab := b - a
    var cd := d - c
    var denominator := ab.cross(cd)
    if absf(denominator) <= 0.000001:
        return false
    var ac := c - a
    var t := ac.cross(cd) / denominator
    var u := ac.cross(ab) / denominator
    return t >= 0.0 and t <= 1.0 and u >= 0.0 and u <= 1.0
