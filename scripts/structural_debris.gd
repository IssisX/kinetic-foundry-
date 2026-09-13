class_name StructuralDebris
extends RigidBody3D

const GeomUtil = preload("res://scripts/geom.gd")

var held := false
var surface_state: SurfaceState
var source_tag := "structure"
var piece_size := Vector3.ONE
var toughness := 180.0
var plastic_strain := 0.0
var machine_held := false
var _saved_linear_damp := 0.0
var _saved_angular_damp := 0.0

var _base_color := Color(0.27, 0.25, 0.20)
var _axis_index := 0
var _segment_length := 1.0
var _segment_meshes: Array[MeshInstance3D] = []
var _segment_collisions: Array[CollisionShape3D] = []
var _segment_centers: Array[Vector3] = []
var _segment_base_sizes: Array[Vector3] = []
var _segment_damage: Array[float] = []
var _fracturing := false

func _ready() -> void:
    add_to_group("physics_prop")
    add_to_group("reusable_debris")
    collision_layer = 8
    collision_mask = 1 | 2 | 4 | 8
    can_sleep = true

func configure(
        size: Vector3,
        color: Color,
        mass_value: float,
        hp: float,
        tag: String
) -> void:
    piece_size = size
    mass = mass_value
    toughness = hp
    source_tag = tag
    _base_color = color
    set_meta("load_size", size)
    set_meta("source_tag", tag)
    _build_segmented_body()
    _ensure_surface_state()


func configure_fragment(
        hull: PackedVector2Array,
        fragment_thickness: float,
        plane_mode: int,
        color: Color,
        mass_value: float,
        hp: float,
        tag: String
) -> void:
    if hull.size() < 3:
        configure(
            Vector3(0.5, fragment_thickness, 0.5),
            color,
            mass_value,
            hp,
            tag
        )
        return
    mass = mass_value
    toughness = hp
    source_tag = tag
    _base_color = color
    var half_thickness := maxf(fragment_thickness, 0.04) * 0.5
    var minimum := Vector2(INF, INF)
    var maximum := Vector2(-INF, -INF)
    for point in hull:
        minimum.x = minf(minimum.x, point.x)
        minimum.y = minf(minimum.y, point.y)
        maximum.x = maxf(maximum.x, point.x)
        maximum.y = maxf(maximum.y, point.y)
    piece_size = (
        Vector3(
            maximum.x - minimum.x,
            maximum.y - minimum.y,
            half_thickness * 2.0
        )
        if plane_mode == 1
        else Vector3(
            maximum.x - minimum.x,
            half_thickness * 2.0,
            maximum.y - minimum.y
        )
    )
    _axis_index = _longest_axis_index()
    set_meta("load_size", piece_size)
    set_meta("source_tag", tag)

    var tool := SurfaceTool.new()
    tool.begin(Mesh.PRIMITIVE_TRIANGLES)
    for i in range(1, hull.size() - 1):
        if plane_mode == 1:
            _add_hull_triangle(
                tool,
                _hull_vertex(hull[0], half_thickness, plane_mode),
                _hull_vertex(hull[i], half_thickness, plane_mode),
                _hull_vertex(hull[i + 1], half_thickness, plane_mode)
            )
            _add_hull_triangle(
                tool,
                _hull_vertex(hull[0], -half_thickness, plane_mode),
                _hull_vertex(hull[i + 1], -half_thickness, plane_mode),
                _hull_vertex(hull[i], -half_thickness, plane_mode)
            )
        else:
            _add_hull_triangle(
                tool,
                _hull_vertex(hull[0], half_thickness, plane_mode),
                _hull_vertex(hull[i + 1], half_thickness, plane_mode),
                _hull_vertex(hull[i], half_thickness, plane_mode)
            )
            _add_hull_triangle(
                tool,
                _hull_vertex(hull[0], -half_thickness, plane_mode),
                _hull_vertex(hull[i], -half_thickness, plane_mode),
                _hull_vertex(hull[i + 1], -half_thickness, plane_mode)
            )
    for i in hull.size():
        var next := (i + 1) % hull.size()
        var first_front := _hull_vertex(
            hull[i], half_thickness, plane_mode
        )
        var second_front := _hull_vertex(
            hull[next], half_thickness, plane_mode
        )
        var first_back := _hull_vertex(
            hull[i], -half_thickness, plane_mode
        )
        var second_back := _hull_vertex(
            hull[next], -half_thickness, plane_mode
        )
        _add_hull_triangle(
            tool,
            first_front,
            first_back,
            second_front
        )
        _add_hull_triangle(
            tool,
            second_front,
            first_back,
            second_back
        )
    tool.generate_normals()
    var mesh := MeshInstance3D.new()
    mesh.mesh = tool.commit()
    var material := GeomUtil.material(color, 0.92, 0.30)
    material.cull_mode = BaseMaterial3D.CULL_DISABLED
    mesh.material_override = material
    add_child(mesh)
    _ensure_surface_state()

    var points := PackedVector3Array()
    for point in hull:
        points.append(_hull_vertex(
            point, half_thickness, plane_mode
        ))
        points.append(_hull_vertex(
            point, -half_thickness, plane_mode
        ))
    var shape := ConvexPolygonShape3D.new()
    shape.points = points
    var collision := CollisionShape3D.new()
    collision.shape = shape
    add_child(collision)


func _hull_vertex(
        point: Vector2,
        depth: float,
        plane_mode: int
) -> Vector3:
    if plane_mode == 1:
        return Vector3(point.x, point.y, depth)
    return Vector3(point.x, depth, point.y)


func _add_hull_triangle(
        tool: SurfaceTool,
        first: Vector3,
        second: Vector3,
        third: Vector3
) -> void:
    tool.set_uv(Vector2(first.x, first.z))
    tool.add_vertex(first)
    tool.set_uv(Vector2(second.x, second.z))
    tool.add_vertex(second)
    tool.set_uv(Vector2(third.x, third.z))
    tool.add_vertex(third)

func _build_segmented_body() -> void:
    for mesh in _segment_meshes:
        if is_instance_valid(mesh):
            mesh.queue_free()
    for collision in _segment_collisions:
        if is_instance_valid(collision):
            collision.queue_free()
    _segment_meshes.clear()
    _segment_collisions.clear()
    _segment_centers.clear()
    _segment_base_sizes.clear()
    _segment_damage.clear()

    _axis_index = _longest_axis_index()
    var longest := _axis_value(piece_size, _axis_index)
    var segment_count := clampi(ceili(longest / 0.68), 3, 7)
    _segment_length = longest / float(segment_count)

    for i in segment_count:
        var size := _set_axis_value(
            piece_size,
            _axis_index,
            _segment_length * 0.975
        )
        var offset_value := (
            -longest * 0.5
            + _segment_length * (float(i) + 0.5)
        )
        var center := _axis_vector(_axis_index) * offset_value
        var mesh := GeomUtil.box_mesh(
            size,
            _base_color,
            0.92,
            0.30
        )
        mesh.position = center
        add_child(mesh)
        var collision := GeomUtil.add_box_collision(self, size)
        collision.position = center

        _segment_meshes.append(mesh)
        _segment_collisions.append(collision)
        _segment_centers.append(center)
        _segment_base_sizes.append(size)
        _segment_damage.append(0.0)

func set_held(value: bool) -> void:
    held = value
    machine_held = false
    freeze = value
    sleeping = false
    if value:
        linear_velocity = Vector3.ZERO
        angular_velocity = Vector3.ZERO
    else:
        _restore_machine_damping()

func set_machine_held(value: bool) -> void:
    if value:
        if not machine_held:
            _saved_linear_damp = linear_damp
            _saved_angular_damp = angular_damp
        held = true
        machine_held = true
        freeze = false
        can_sleep = false
        sleeping = false
        linear_damp = maxf(linear_damp, 3.6)
        angular_damp = maxf(angular_damp, 4.2)
        return
    held = false
    machine_held = false
    freeze = false
    can_sleep = true
    sleeping = false
    _restore_machine_damping()

func _restore_machine_damping() -> void:
    linear_damp = _saved_linear_damp
    angular_damp = _saved_angular_damp

func machine_hit(amount: float, direction: Vector3) -> void:
    machine_hit_at(
        amount,
        direction,
        global_position,
        amount * mass * 0.08
    )

func machine_hit_at(
        amount: float,
        direction: Vector3,
        world_point: Vector3,
        impact_energy: float
) -> void:
    _receive_energy(
        amount,
        direction,
        maxf(amount * mass * 0.08, sqrt(maxf(impact_energy, 0.0))),
        world_point,
        impact_energy
    )

func take_hit(force: Vector3, damage: float) -> void:
    if held:
        set_held(false)
    var direction := force.normalized()
    if direction.length_squared() < 0.001:
        direction = Vector3.UP
    _receive_energy(
        damage,
        direction,
        force.length(),
        global_position,
        0.5 * mass * force.length_squared() / maxf(mass * mass, 1.0)
    )

func _receive_energy(
        damage: float,
        direction: Vector3,
        impulse: float,
        world_point: Vector3,
        impact_energy: float
) -> void:
    if _fracturing:
        return
    var plastic_before := plastic_strain
    toughness = maxf(0.0, toughness - damage)
    var energy_ratio := clampf(
        impact_energy / maxf(mass * 48.0, 1.0),
        0.0,
        2.5
    )
    plastic_strain = clampf(
        plastic_strain + damage / 1100.0 + energy_ratio * 0.010,
        0.0,
        0.28
    )

    _deform_at(world_point, direction, damage, impact_energy)

    if not held:
        var local_offset := to_local(world_point)
        apply_impulse(
            direction * minf(impulse, mass * 18.0),
            local_offset
        )
        apply_torque_impulse(
            Vector3(direction.z, 0.35, -direction.x)
            * minf(impulse * 0.30, mass * 8.0)
        )

    _emit_physical_event(
        world_point,
        impulse,
        damage,
        plastic_strain - plastic_before,
        impact_energy
    )
    _apply_surface_state()

    var longest := _axis_value(piece_size, _axis_index)
    var fracture_threshold := mass * 58.0
    if (
        longest > 0.92
        and not held
        and not machine_held
        and (
            toughness <= 0.0
            or impact_energy > fracture_threshold
            or energy_ratio > 1.35
        )
    ):
        _fracture_at(world_point, direction, impact_energy)

func _deform_at(
        world_point: Vector3,
        direction: Vector3,
        damage: float,
        impact_energy: float
) -> void:
    if _segment_meshes.is_empty():
        return
    var local_point := to_local(world_point)
    var local_direction := global_basis.inverse() * direction.normalized()
    if local_direction.length_squared() < 0.001:
        local_direction = Vector3.UP
    var hit_coordinate := _axis_value(local_point, _axis_index)
    var energy_ratio := clampf(
        impact_energy / maxf(mass * 52.0, 1.0),
        0.0,
        2.8
    )
    var sigma := _segment_length * (0.72 + minf(energy_ratio, 1.8) * 0.34)

    for i in _segment_meshes.size():
        var center_coordinate := _axis_value(
            _segment_centers[i],
            _axis_index
        )
        var distance := absf(center_coordinate - hit_coordinate)
        var normalized := distance / maxf(sigma, 0.001)
        var weight := exp(-0.5 * normalized * normalized)
        if weight < 0.015:
            continue

        _segment_damage[i] = clampf(
            _segment_damage[i]
            + weight * (damage / 180.0 + energy_ratio * 0.12),
            0.0,
            0.75
        )
        var local_damage := _segment_damage[i]
        var dent := (
            minf(0.20, damage * 0.0022 + energy_ratio * 0.045)
            * weight
        )
        var center := _segment_centers[i] + local_direction * dent
        var bend_axis := Vector3(
            local_direction.z,
            0.0,
            -local_direction.x
        )
        if bend_axis.length_squared() < 0.001:
            bend_axis = Vector3.RIGHT
        bend_axis = bend_axis.normalized()
        var bend_angle := clampf(
            local_damage * 0.12 * signf(center_coordinate - hit_coordinate),
            -0.16,
            0.16
        )
        var basis := Basis(bend_axis, bend_angle)

        var base_size := _segment_base_sizes[i]
        var deformed_size := _deformed_segment_size(
            base_size,
            local_direction,
            local_damage
        )
        var mesh := _segment_meshes[i]
        var collision := _segment_collisions[i]
        mesh.transform = Transform3D(basis, center)
        collision.transform = Transform3D(basis, center)
        mesh.scale = Vector3(
            deformed_size.x / maxf(base_size.x, 0.001),
            deformed_size.y / maxf(base_size.y, 0.001),
            deformed_size.z / maxf(base_size.z, 0.001)
        )
        if collision.shape is BoxShape3D:
            var box := collision.shape as BoxShape3D
            box.size = deformed_size

func _deformed_segment_size(
        base_size: Vector3,
        local_direction: Vector3,
        damage_value: float
) -> Vector3:
    var compression := clampf(damage_value * 0.22, 0.0, 0.18)
    var bulge := clampf(damage_value * 0.12, 0.0, 0.12)
    var x_weight := absf(local_direction.x)
    var y_weight := absf(local_direction.y)
    var z_weight := absf(local_direction.z)
    return Vector3(
        base_size.x * (1.0 - compression * x_weight + bulge * (1.0 - x_weight)),
        base_size.y * (1.0 - compression * y_weight + bulge * (1.0 - y_weight)),
        base_size.z * (1.0 - compression * z_weight + bulge * (1.0 - z_weight))
    )

func _fracture_at(
        world_point: Vector3,
        direction: Vector3,
        impact_energy: float
) -> void:
    if _fracturing or get_parent() == null:
        return
    _fracturing = true
    if held or machine_held:
        set_machine_held(false)

    var longest := _axis_value(piece_size, _axis_index)
    var local_hit := to_local(world_point)
    var split_fraction := clampf(
        (_axis_value(local_hit, _axis_index) + longest * 0.5)
        / maxf(longest, 0.001),
        0.24,
        0.76
    )
    var first_length := longest * split_fraction
    var second_length := longest - first_length
    if minf(first_length, second_length) < 0.34:
        _fracturing = false
        return

    var parent_node := get_parent()
    var lengths: Array[float] = [first_length, second_length]
    var offsets: Array[float] = [
        -longest * 0.5 + first_length * 0.5,
        -longest * 0.5 + first_length + second_length * 0.5
    ]
    var energy_ratio := clampf(
        impact_energy / maxf(mass * 60.0, 1.0),
        0.6,
        2.5
    )

    for i in 2:
        var child = get_script().new()
        parent_node.add_child(child)
        child.global_transform = global_transform
        var local_offset := _axis_vector(_axis_index) * offsets[i]
        child.global_position = to_global(local_offset)
        var child_size := _set_axis_value(
            piece_size,
            _axis_index,
            lengths[i]
        )
        var child_mass := maxf(
            8.0,
            mass * lengths[i] / maxf(longest, 0.001)
        )
        child.configure(
            child_size,
            _base_color,
            child_mass,
            maxf(35.0, toughness * 0.72 + 55.0),
            source_tag
        )
        child.bind_surface_state(
            MaterialResponse.adopt_fragment(
                child,
                surface_state,
                clampf(lengths[i] / maxf(longest, 0.001), 0.0, 1.0) * 0.6
            )
        )
        var side := -1.0 if i == 0 else 1.0
        child.linear_velocity = (
            linear_velocity
            + direction.normalized() * energy_ratio * 1.8
            + _axis_vector(_axis_index) * side * energy_ratio * 1.2
        )
        child.angular_velocity = (
            angular_velocity
            + Vector3(direction.z, side * 0.7, -direction.x)
            * energy_ratio
        )

    MaterialResponse.fracture(
        self,
        world_point,
        direction,
        impact_energy,
        mass,
        {
            "material": material_identity(),
            "radius": maxf(1.0, longest * 0.55),
            "novelty": 0.94
        }
    )
    queue_free()

func _emit_physical_event(
        world_point: Vector3,
        _impulse: float,
        damage: float,
        plastic_delta: float,
        impact_energy: float
) -> void:
    if not is_inside_tree():
        return
    var extent := maxf(
        piece_size.x,
        maxf(piece_size.y, piece_size.z)
    )
    MaterialResponse.impact(
        self,
        world_point,
        direction_from_impulse(world_point),
        impact_energy,
        mass,
        FoundryMaterial.HARDENED_STEEL,
        {
            "type": "debris_impact",
            "material": material_identity(),
            "radius": extent,
            "area": clampf(extent * 0.18, 0.01, 1.2),
            "fracture": clampf(
                plastic_delta * 8.0
                + damage / 180.0
                + impact_energy / maxf(mass * 260.0, 1.0),
                0.0,
                1.0
            ),
            "novelty": clampf(0.55 + damage / 120.0, 0.55, 1.0)
        }
    )


func direction_from_impulse(world_point: Vector3) -> Vector3:
    var away := world_point - global_position
    if away.length_squared() < 0.0001:
        return Vector3.UP
    return away.normalized()

func get_load_profile() -> Dictionary:
    var velocity_sq := linear_velocity.length_squared()
    var long_axis := _long_axis_world()
    var vertical_alignment := absf(long_axis.dot(Vector3.UP))
    var settled := _settled_factor()
    return {
        "mass": mass,
        "size": piece_size,
        "kinetic_energy": 0.5 * mass * velocity_sq,
        "brace_quality": _brace_quality(),
        "plastic_strain": plastic_strain,
        "source": source_tag,
        "long_axis": long_axis,
        "vertical_alignment": vertical_alignment,
        "settled_factor": settled
    }

func _brace_quality() -> float:
    var longest := maxf(
        piece_size.x,
        maxf(piece_size.y, piece_size.z)
    )
    var shortest := maxf(
        0.08,
        minf(piece_size.x, minf(piece_size.y, piece_size.z))
    )
    var slenderness := clampf(
        longest / shortest / 12.0,
        0.15,
        1.0
    )
    var vertical := absf(_long_axis_world().dot(Vector3.UP))
    var diagonal := sin(
        acos(clampf(vertical, 0.0, 1.0)) * 2.0
    )
    diagonal = absf(diagonal)
    var orientation_quality := clampf(
        0.34 + diagonal * 0.66,
        0.34,
        1.0
    )
    var strain_quality := clampf(
        1.0 - plastic_strain * 2.4,
        0.42,
        1.0
    )
    return clampf(
        slenderness
        * orientation_quality
        * _settled_factor()
        * strain_quality,
        0.05,
        1.0
    )

func _long_axis_world() -> Vector3:
    return (global_basis * _axis_vector(_axis_index)).normalized()

func _settled_factor() -> float:
    if held or machine_held:
        return 0.12
    var motion := (
        linear_velocity.length() / 2.6
        + angular_velocity.length() / 4.2
    )
    return clampf(1.0 - motion, 0.12, 1.0)

func _longest_axis_index() -> int:
    if piece_size.y >= piece_size.x and piece_size.y >= piece_size.z:
        return 1
    if piece_size.z >= piece_size.x and piece_size.z >= piece_size.y:
        return 2
    return 0

func _axis_vector(axis: int) -> Vector3:
    if axis == 1:
        return Vector3.UP
    if axis == 2:
        return Vector3.BACK
    return Vector3.RIGHT

func _axis_value(value: Vector3, axis: int) -> float:
    if axis == 1:
        return value.y
    if axis == 2:
        return value.z
    return value.x

func _set_axis_value(value: Vector3, axis: int, amount: float) -> Vector3:
    if axis == 1:
        return Vector3(value.x, amount, value.z)
    if axis == 2:
        return Vector3(value.x, value.y, amount)
    return Vector3(amount, value.y, value.z)

func _material_tag() -> String:
    return "concrete" if source_tag.contains("concrete") else "steel"


func material_identity() -> int:
    if surface_state != null:
        return surface_state.material_id
    return FoundryMaterial.id_from_legacy(_material_tag())


func _ensure_surface_state() -> void:
    if surface_state != null:
        return
    bind_surface_state(
        MaterialResponse.register(
            self,
            FoundryMaterial.id_from_legacy(_material_tag()),
            _base_color
        )
    )


## A piece arrives already carrying what happened to the thing it came off.
func bind_surface_state(state) -> void:
    surface_state = state as SurfaceState
    _apply_surface_state()


func _apply_surface_state() -> void:
    if surface_state == null:
        return
    for child in get_children():
        var mesh := child as MeshInstance3D
        if mesh == null:
            continue
        var surface := mesh.material_override as StandardMaterial3D
        if surface == null:
            continue
        surface_state.apply_to_material(surface)
