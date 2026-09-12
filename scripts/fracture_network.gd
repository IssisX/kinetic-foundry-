class_name FractureNetwork
extends RefCounted

## Small, deterministic bond network for game-scale deformation.
##
## Each bond owns elastic strain, plastic rest-state strain, and a
## monotone tensile damage history. Failed bonds change the connected
## component graph; fragment velocities are reconstructed from the
## solved node state so a split does not invent energy.

signal topology_changed(component_count: int)

var columns := 0
var rows := 0
var span := Vector3.ONE
var total_mass := 1.0
var yield_strain := 0.018
var damage_onset := 0.036
var failure_strain := 0.18
var hardening := 0.22
var pin_boundary := false
var pin_corners := true

var _rest_positions: Array[Vector3] = []
var _positions: Array[Vector3] = []
var _velocities: Array[Vector3] = []
var _forces: Array[Vector3] = []
var _pinned: Array[bool] = []
var _bonds: Array[Dictionary] = []
var _node_mass := 1.0
var _topology_dirty := true
var _component_count := 1
var _last_reported_components := 1
var _max_displacement := 0.0

func configure_grid(
        grid_columns: int,
        grid_rows: int,
        grid_span: Vector3,
        mass_value: float,
        toughness: float,
        boundary_pins: bool = false
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
    hardening = clampf(0.12 + toughness * 0.0003, 0.12, 0.42)
    pin_boundary = boundary_pins
    pin_corners = not boundary_pins
    _rest_positions.clear()
    _positions.clear()
    _velocities.clear()
    _forces.clear()
    _pinned.clear()
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
            _pinned.append(_is_pinned(column, row))

    for row in rows:
        for column in columns:
            var index := _index(column, row)
            if column + 1 < columns:
                _add_bond(index, _index(column + 1, row), 1.0)
            if row + 1 < rows:
                _add_bond(index, _index(column, row + 1), 0.92)
            if column + 1 < columns and row + 1 < rows:
                _add_bond(index, _index(column + 1, row + 1), 0.54)
                _add_bond(
                    _index(column + 1, row),
                    _index(column, row + 1),
                    0.54
                )
    _topology_dirty = true
    _component_count = 1
    _last_reported_components = 1

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

func _add_bond(first: int, second: int, stiffness_scale: float) -> void:
    var rest_length := _rest_positions[first].distance_to(
        _rest_positions[second]
    )
    _bonds.append({
        "a": first,
        "b": second,
        "rest": rest_length,
        "stiffness": total_mass * 18.0 * stiffness_scale,
        "plastic": 0.0,
        "history": 0.0,
        "damage": 0.0,
        "active": true
    })

func apply_force(local_point: Vector3, force: Vector3) -> void:
    if _positions.is_empty() or force.length_squared() < 0.0001:
        return
    var nearest: Array[int] = []
    var nearest_distance: Array[float] = []
    for i in _positions.size():
        var distance := _positions[i].distance_squared_to(local_point)
        var insert_at := nearest.size()
        for j in nearest_distance.size():
            if distance < nearest_distance[j]:
                insert_at = j
                break
        if insert_at < 4:
            nearest.insert(insert_at, i)
            nearest_distance.insert(insert_at, distance)
            if nearest.size() > 4:
                nearest.pop_back()
                nearest_distance.pop_back()
    var weight_sum := 0.0
    for distance in nearest_distance:
        weight_sum += 1.0 / (0.20 + sqrt(distance))
    if weight_sum <= 0.0:
        return
    for i in nearest.size():
        var weight := (
            1.0 / (0.20 + sqrt(nearest_distance[i]))
        ) / weight_sum
        _forces[nearest[i]] += force * weight

func clear_forces() -> void:
    for i in _forces.size():
        _forces[i] = Vector3.ZERO

func step(delta: float) -> void:
    if _positions.is_empty():
        return
    var safe_delta := clampf(delta, 0.002, 0.16)
    var substeps := clampi(ceili(safe_delta / 0.024), 1, 8)
    var sub_delta := safe_delta / float(substeps)
    for _i in substeps:
        _step_substep(sub_delta)
    clear_forces()
    _refresh_topology()

func _step_substep(delta: float) -> void:
    var node_forces: Array[Vector3] = []
    for force in _forces:
        node_forces.append(force)

    for bond_index in _bonds.size():
        var bond := _bonds[bond_index]
        if not bool(bond.active):
            continue
        var first: int = int(bond.a)
        var second: int = int(bond.b)
        var offset := _positions[second] - _positions[first]
        var length := offset.length()
        if length < 0.0001:
            continue
        var axis := offset / length
        var rest_length: float = float(bond.rest)
        var strain := (length - rest_length) / rest_length
        var plastic: float = float(bond.plastic)
        var elastic_strain := strain - plastic
        var yield_limit := yield_strain + hardening * absf(plastic)
        if absf(elastic_strain) > yield_limit:
            var return_amount := minf(
                absf(elastic_strain) - yield_limit,
                0.032
            )
            plastic += signf(elastic_strain) * return_amount * 0.46
            bond.plastic = plastic
            elastic_strain = strain - plastic

        var tensile_strain := maxf(0.0, strain)
        var history: float = maxf(float(bond.history), tensile_strain)
        bond.history = history
        var damage := clampf(
            (history - damage_onset)
            / maxf(failure_strain - damage_onset, 0.001),
            0.0,
            1.0
        )
        bond.damage = maxf(float(bond.damage), damage)
        if bond.damage >= 1.0:
            bond.active = false
            _topology_dirty = true
            continue

        var stiffness: float = float(bond.stiffness)
        var damping := sqrt(stiffness * _node_mass) * 0.28
        var relative_speed := (
            _velocities[second] - _velocities[first]
        ).dot(axis)
        var force_magnitude: float = (
            stiffness * elastic_strain * (1.0 - bond.damage) ** 2
            + damping * relative_speed
        )
        var force: Vector3 = axis * force_magnitude
        node_forces[first] += force
        node_forces[second] -= force

    for i in _positions.size():
        if _pinned[i]:
            _positions[i] = _rest_positions[i]
            _velocities[i] = Vector3.ZERO
            continue
        var acceleration := node_forces[i] / maxf(_node_mass, 0.001)
        _velocities[i] += acceleration * delta
        _velocities[i] *= exp(-4.8 * delta)
        _positions[i] += _velocities[i] * delta
        var displacement := _positions[i] - _rest_positions[i]
        var displacement_limit := maxf(span.length() * 0.40, 0.8)
        if displacement.length() > displacement_limit:
            _positions[i] = _rest_positions[i] + displacement.normalized() * displacement_limit
            _velocities[i] *= 0.20

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
    for i in _positions.size():
        var displacement := _positions[i] - _rest_positions[i]
        maximum = maxf(maximum, displacement.length())
        sag = maxf(sag, -displacement.y)
        average += displacement
    if not _positions.is_empty():
        average /= float(_positions.size())
    _max_displacement = maximum
    var left := 0.0
    var right := 0.0
    var front := 0.0
    var back := 0.0
    for i in _positions.size():
        var rest := _rest_positions[i]
        var displacement := _positions[i] - rest
        if rest.x < 0.0:
            left += displacement.z
        else:
            right += displacement.z
        if rest.z < 0.0:
            front += displacement.y
        else:
            back += displacement.y
    var half_count := maxf(float(_positions.size()) * 0.5, 1.0)
    return {
        "max_displacement": maximum,
        "sag": sag,
        "average": average,
        "roll": clampf((right - left) / half_count, -0.42, 0.42),
        "pitch": clampf((back - front) / half_count, -0.42, 0.42),
        "damage": _mean_damage(),
        "broken_fraction": get_broken_fraction(),
        "components": _component_count
    }

func _mean_damage() -> float:
    if _bonds.is_empty():
        return 0.0
    var total := 0.0
    for bond in _bonds:
        total += float(bond.damage)
    return total / float(_bonds.size())

func fracture_into_columns() -> void:
    for bond in _bonds:
        var first: int = int(bond.a)
        var second: int = int(bond.b)
        var first_column := first % columns
        var second_column := second % columns
        var row_delta := absi(first / columns - second / columns)
        var keep_vertical := (
            first_column == second_column
            and row_delta == 1
        )
        bond.active = keep_vertical
        if not keep_vertical:
            bond.damage = 1.0
    _topology_dirty = true
    _refresh_topology()

func get_fragment_specs(
        thickness: float = 0.20,
        minimum_nodes: int = 1
) -> Array[Dictionary]:
    _refresh_topology()
    var result: Array[Dictionary] = []
    for component in _components():
        if component.size() < minimum_nodes:
            continue
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
            inertia.x += _node_mass * (offset.y * offset.y + offset.z * offset.z)
            inertia.y += _node_mass * (offset.x * offset.x + offset.z * offset.z)
            inertia.z += _node_mass * (offset.x * offset.x + offset.y * offset.y)
        var angular_velocity := Vector3(
            angular_momentum.x / maxf(inertia.x, 0.001),
            angular_momentum.y / maxf(inertia.y, 0.001),
            angular_momentum.z / maxf(inertia.z, 0.001)
        )
        var size := Vector3(
            maxf(0.24, maximum.x - minimum.x + span.x / float(columns) * 0.52),
            maxf(thickness, maximum.y - minimum.y + thickness),
            maxf(0.24, maximum.z - minimum.z + span.z / float(rows) * 0.52)
        )
        result.append({
            "local_position": center,
            "size": size,
            "mass": _node_mass * float(component.size()),
            "linear_velocity": velocity,
            "angular_velocity": angular_velocity,
            "nodes": component
        })
    return result

func _components() -> Array:
    var adjacency: Array = []
    for _i in _positions.size():
        adjacency.append([])
    for bond in _bonds:
        if not bool(bond.active):
            continue
        var first: int = int(bond.a)
        var second: int = int(bond.b)
        adjacency[first].append(second)
        adjacency[second].append(first)
    var visited: Array[bool] = []
    visited.resize(_positions.size())
    for i in visited.size():
        visited[i] = false
    var result: Array = []
    for start in _positions.size():
        if visited[start]:
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
