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
    var energy_state := super.apply_impact(
        local_point,
        impulse,
        impact_energy
    )
    var impulse_direction := impulse.normalized()
    if impulse_direction.length_squared() < 0.001:
        impulse_direction = Vector3(0.0, 1.0, 0.0)

    # The base solver owns energy, impulse, wave injection, and Griffith
    # crack fronts. This compact kernel only supplies a permanent local dent
    # and a directional bias so the fronts prefer star-cracks from the
    # true contact, not the object's average.
    for i in _positions.size():
        if is_retired(i) or _pinned[i]:
            continue
        var distance := _rest_positions[i].distance_to(local_point)
        var weight := _wendland(distance / maxf(radius, 0.001))
        if weight <= 0.0:
            continue
        var dent := (
            cell
            * (0.012 + energy_ratio * 0.022)
            * weight
        )
        _positions[i] += impulse_direction * dent

    if energy_ratio >= 0.45:
        var ray_count := clampi(3 + int(energy_ratio), 3, 7)
        var ray_length := radius * (1.35 + energy_ratio * 0.55)
        var ray_ends: Array[Vector3] = []
        var seed := local_point.x * 12.9898 + local_point.z * 78.233
        var spin := fmod(absf(seed) * 0.17, TAU)
        for ray_index in ray_count:
            var angle := spin + TAU * float(ray_index) / float(ray_count)
            ray_ends.append(
                local_point
                + Vector3(cos(angle), 0.0, sin(angle)) * ray_length
            )
        _bias_ray_family(
            local_point,
            ray_ends,
            radius * 0.42,
            cell * (0.42 + energy_ratio * 0.12),
            energy_ratio
        )

    _revision += 1
    var settle_steps := clampi(4 + int(energy_ratio * 2.0), 4, 10)
    for _i in settle_steps:
        step(1.0 / 120.0)
    if energy_ratio >= 1.45:
        _cut_spall_ring(
            local_point,
            radius * 0.68,
            cell * 0.38
        )
        step(1.0 / 120.0)
    var deformation := get_deformation_state()
    deformation["impact_energy"] = energy_state
    return deformation

func fracture_localized(
        local_point: Vector3,
        impact_energy: float,
        impact_direction: Vector3
) -> void:
    fracture_by_energy(
        local_point,
        impact_direction,
        impact_energy,
        Fidelity.max_shards()
    )

func _bias_ray_family(
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
        if crack_weight < 0.08 and core_weight < 0.08:
            continue
        var score := (
            core_weight * energy_ratio * 0.40
            + crack_weight * (0.42 + energy_ratio * 0.16)
        )
        bond.history = maxf(
            float(bond.history),
            damage_onset + score * (failure_strain - damage_onset)
        )
        bond.damage = clampf(
            maxf(float(bond.damage), score * 0.38),
            0.0,
            0.92
        )
        # Fronts own topology. Bias never severs a bond on its own.

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

func get_grid_node_position(column: int, row: int) -> Vector3:
    if columns <= 0 or rows <= 0:
        return Vector3.ZERO
    var safe_column := clampi(column, 0, columns - 1)
    var safe_row := clampi(row, 0, rows - 1)
    return _positions[_index(safe_column, safe_row)]

func get_cell_state(column: int, row: int) -> Dictionary:
    if column < 0 or row < 0 or column + 1 >= columns or row + 1 >= rows:
        return {}
    var p00 := get_grid_node_position(column, row)
    var p10 := get_grid_node_position(column + 1, row)
    var p01 := get_grid_node_position(column, row + 1)
    var p11 := get_grid_node_position(column + 1, row + 1)
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
    var first := _index(column, row)
    var second := _index(column + 1, row)
    var third := _index(column, row + 1)
    var fourth := _index(column + 1, row + 1)
    var damage := (
        get_node_damage(first)
        + get_node_damage(second)
        + get_node_damage(third)
        + get_node_damage(fourth)
    ) * 0.25
    return {
        "center": center,
        "axis_x": axis_x,
        "axis_z": axis_z,
        "normal": normal,
        "width": width,
        "height": height_value,
        "damage": damage
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
