extends "res://scripts/structure.gd"

const GeomUtilLocal = preload("res://scripts/geom.gd")
const StructuralDebrisLocal = preload(
    "res://scripts/structural_debris.gd"
)

const SUPPORT_HEIGHT := 4.6

var _support_segments: Array = []
var _support_segment_damage: Array = []
var _support_last_hit_world: Array[Vector3] = []
var _support_last_energy: Array[float] = []
var _support_last_direction: Array[Vector3] = []
var _support_last_wave: Array[float] = []

func _support_segment_count() -> int:
    return maxi(Fidelity.support_segments(), 3)

func _support_segment_height() -> float:
    return SUPPORT_HEIGHT / float(_support_segment_count())

func _ready() -> void:
    super()
    _build_deformable_support_skins()

func _build_deformable_support_skins() -> void:
    _support_segments.clear()
    _support_segment_damage.clear()
    _support_last_hit_world.clear()
    _support_last_energy.clear()
    _support_last_direction.clear()
    _support_last_wave.clear()

    for index: int in supports.size():
        var segment_list: Array[MeshInstance3D] = []
        var damage_list: Array[float] = []
        _support_last_hit_world.append(Vector3.ZERO)
        _support_last_energy.append(0.0)
        _support_last_direction.append(Vector3.UP)
        _support_last_wave.append(0.0)

        if index < support_meshes.size() and is_instance_valid(support_meshes[index]):
            support_meshes[index].visible = false
        if not is_instance_valid(supports[index]):
            _support_segments.append(segment_list)
            _support_segment_damage.append(damage_list)
            continue

        for segment_index: int in _support_segment_count():
            var segment := GeomUtilLocal.box_mesh(
                Vector3(
                    0.72,
                    _support_segment_height() * 0.975,
                    0.72
                ),
                Color(0.39, 0.33, 0.20),
                0.80,
                0.30
            )
            segment.name = "DeformableColumn_%d" % segment_index
            segment.position.y = (
                -SUPPORT_HEIGHT * 0.5
                + _support_segment_height() * (float(segment_index) + 0.5)
            )
            supports[index].add_child(segment)
            segment_list.append(segment)
            damage_list.append(0.0)

        _support_segments.append(segment_list)
        _support_segment_damage.append(damage_list)

func damage_support(
        index: int,
        amount: float,
        direction: Vector3,
        world_point: Vector3 = Vector3.ZERO,
        source_energy: float = -1.0
) -> void:
    var hit_pos := world_point
    if hit_pos == Vector3.ZERO:
        hit_pos = global_position
    if index >= 0 and index < supports.size() and is_instance_valid(supports[index]):
        if world_point == Vector3.ZERO:
            hit_pos = (
                supports[index].global_position + Vector3.UP * 1.05
            )
    var impact_energy := source_energy
    if impact_energy < 0.0:
        impact_energy = EnergyPartition.nominal_impact_energy(amount)
    damage_support_at(
        index,
        amount,
        direction,
        hit_pos,
        impact_energy
    )

func damage_support_at(
        index: int,
        amount: float,
        direction: Vector3,
        world_point: Vector3,
        impact_energy: float
) -> void:
    if index < 0 or index >= support_health.size():
        return
    var hp_before := support_health[index]
    if index < _support_last_hit_world.size():
        _support_last_hit_world[index] = world_point
        _support_last_energy[index] = maxf(
            _support_last_energy[index],
            impact_energy
        )
        _support_last_direction[index] = direction

    super.damage_support(
        index,
        amount,
        direction,
        world_point,
        impact_energy
    )

    var removed := maxf(0.0, hp_before - support_health[index])
    if removed <= 0.0:
        return

    _deform_support_at(
        index,
        world_point,
        direction,
        removed,
        impact_energy
    )

    MaterialResponse.impact(
        supports[index],
        world_point,
        direction,
        impact_energy,
        180.0,
        FoundryMaterial.HARDENED_STEEL,
        {
            "type": MaterialResponse.EVENT_MACHINE,
            "radius": 2.3,
            "area": 0.09,
            "fracture": clampf(
                removed / 95.0 + impact_energy / 22000.0,
                0.0,
                1.0
            ),
            "novelty": clampf(0.55 + removed / 120.0, 0.55, 1.0),
            "stiffness_ratio": (
                deck_network.get_stiffness_ratio()
                if deck_network != null
                else 1.0
            )
        }
    )

    # The column is standing on something. A hit hard enough to shift it
    # spalls the pad underneath, and the pad decides what that looks like.
    if removed > 28.0 or support_health[index] <= 0.0:
        MaterialResponse.impact_below(
            world_point,
            direction + Vector3.UP * 0.35,
            impact_energy * 0.34,
            180.0,
            {
                "reach": minf(world_point.y, 3.2) + 0.8,
                "tool_material": FoundryMaterial.STRUCTURAL_STEEL,
                "radius": 3.4
            }
        )

func _deform_support_at(
        index: int,
        world_point: Vector3,
        direction: Vector3,
        damage: float,
        impact_energy: float
) -> void:
    if (
        index < 0
        or index >= supports.size()
        or index >= _support_segments.size()
        or not is_instance_valid(supports[index])
    ):
        return
    var segment_list: Array = _support_segments[index]
    var damage_list: Array = _support_segment_damage[index]
    var local_point := supports[index].to_local(world_point)
    var local_direction := (
        supports[index].global_basis.inverse()
        * direction.normalized()
    )
    if local_direction.length_squared() < 0.001:
        local_direction = Vector3.RIGHT
    var energy_ratio := clampf(
        impact_energy / 18000.0,
        0.0,
        2.2
    )
    var sigma := _support_segment_height() * (0.65 + energy_ratio * 0.34)

    for segment_index: int in segment_list.size():
        var segment := segment_list[segment_index] as MeshInstance3D
        if segment == null or not is_instance_valid(segment):
            continue
        var base_y := (
            -SUPPORT_HEIGHT * 0.5
            + _support_segment_height() * (float(segment_index) + 0.5)
        )
        var normalized := absf(base_y - local_point.y) / maxf(sigma, 0.01)
        var weight := exp(-0.5 * normalized * normalized)
        if weight < 0.012:
            continue

        damage_list[segment_index] = clampf(
            float(damage_list[segment_index])
            + weight * (damage / 115.0 + energy_ratio * 0.16),
            0.0,
            0.92
        )
        var local_damage := float(damage_list[segment_index])
        var lateral := Vector3(local_direction.x, 0.0, local_direction.z)
        if lateral.length_squared() < 0.001:
            lateral = Vector3.RIGHT
        lateral = lateral.normalized()
        var dent := weight * minf(
            0.34,
            damage * 0.0042 + energy_ratio * 0.085
        )
        var center := Vector3(
            lateral.x * dent,
            base_y,
            lateral.z * dent
        )
        var bend_axis := Vector3(-lateral.z, 0.0, lateral.x)
        var side_sign := signf(base_y - local_point.y)
        if absf(side_sign) < 0.5:
            side_sign = 1.0
        var bend_angle := clampf(
            local_damage * 0.20 * side_sign,
            -0.22,
            0.22
        )
        segment.transform = Transform3D(
            Basis(bend_axis, bend_angle),
            center
        )
        segment.scale = Vector3(
            1.0 + local_damage * 0.10,
            1.0 - local_damage * 0.19,
            1.0 + local_damage * 0.10
        )
        _shade_segment(segment, index, local_damage)

    _support_segment_damage[index] = damage_list


## The body owns what the column is made of and what has happened to it.
## The segment only contributes how torn this particular band is.
func _shade_segment(
        segment: MeshInstance3D,
        index: int,
        local_damage: float
) -> void:
    if index < 0 or index >= supports.size() or not is_instance_valid(supports[index]):
        return
    var state := MaterialResponse.state_for(
        supports[index],
        FoundryMaterial.PAINTED_STEEL
    )
    if state == null:
        return
    var surface := segment.material_override as StandardMaterial3D
    if surface == null:
        surface = GeomUtilLocal.material(state.composite_albedo(), 0.84, 0.30)
        segment.material_override = surface
    state.apply_to_material(surface)
    var torn: Color = state.profile().get(
        "fracture_face",
        surface.albedo_color
    )
    surface.albedo_color = surface.albedo_color.lerp(
        torn.darkened(0.55),
        clampf(local_damage, 0.0, 1.0) * 0.62
    )
    surface.roughness = clampf(
        surface.roughness + local_damage * 0.10,
        0.04,
        1.0
    )


func _transmit_wave_to_supports() -> void:
    if collapsed or deck == null or deck_network == null:
        return
    if not deck_network.has_method("get_node_wave"):
        return
    if not deck_network.has_method("nearest_node_index"):
        return
    for index in supports.size():
        if not is_instance_valid(supports[index]):
            continue
        if index >= support_health.size() or support_health[index] <= 0.0:
            continue
        var local_point := deck.to_local(supports[index].global_position)
        local_point.y = 0.0
        var node_index := int(deck_network.nearest_node_index(local_point))
        if node_index < 0:
            continue
        var wave := float(deck_network.get_node_wave(node_index))
        var previous := 0.0
        if index < _support_last_wave.size():
            previous = float(_support_last_wave[index])
        else:
            _support_last_wave.append(0.0)
        if index < _support_last_wave.size():
            _support_last_wave[index] = wave
        if wave < previous + 0.10 or wave < 0.28:
            continue
        var flange := supports[index].global_position + Vector3.UP * 2.05
        var incoming := Vector3.DOWN
        if index < _support_last_direction.size():
            incoming = _support_last_direction[index]
        _deform_support_at(
            index,
            flange,
            incoming + Vector3.DOWN * 0.35,
            wave * 14.0,
            wave * 9000.0
        )


func _break_support(index: int, direction: Vector3) -> void:
    if index < 0 or index >= supports.size():
        return
    var old: StaticBody3D = supports[index]
    if not is_instance_valid(old):
        return

    var old_transform := old.global_transform
    var hit_world := old.global_position
    var event_energy := 7200.0
    var event_direction := direction
    if index < _support_last_hit_world.size():
        if _support_last_hit_world[index] != Vector3.ZERO:
            hit_world = _support_last_hit_world[index]
        event_energy = maxf(_support_last_energy[index], event_energy)
        event_direction = _support_last_direction[index]
    var hit_local := old.to_local(hit_world)
    var hit_y := clampf(
        hit_local.y,
        -SUPPORT_HEIGHT * 0.5 + 0.28,
        SUPPORT_HEIGHT * 0.5 - 0.28
    )
    var column_state := MaterialResponse.state_for(
        old,
        FoundryMaterial.PAINTED_STEEL
    )
    MaterialResponse.fracture(
        old,
        hit_world,
        event_direction,
        event_energy,
        180.0,
        {
            "radius": 4.6,
            "novelty": 0.92,
            "tool_material": FoundryMaterial.HARDENED_STEEL
        }
    )
    old.queue_free()

    var energy_ratio := clampf(
        event_energy / 16000.0,
        0.45,
        2.4
    )
    var boundaries: Array[float] = [
        -SUPPORT_HEIGHT * 0.5,
        SUPPORT_HEIGHT * 0.5
    ]
    boundaries.append(hit_y)
    if energy_ratio > 0.82:
        boundaries.append(clampf(hit_y - 0.42, -2.05, 2.05))
        boundaries.append(clampf(hit_y + 0.42, -2.05, 2.05))
    if energy_ratio > 1.45:
        boundaries.append(clampf(hit_y - 0.82, -2.05, 2.05))
        boundaries.append(clampf(hit_y + 0.82, -2.05, 2.05))
    boundaries.sort()

    var clean_boundaries: Array[float] = []
    for value: float in boundaries:
        if clean_boundaries.is_empty() or absf(value - clean_boundaries[-1]) > 0.24:
            clean_boundaries.append(value)
    if clean_boundaries[-1] < SUPPORT_HEIGHT * 0.5 - 0.01:
        clean_boundaries.append(SUPPORT_HEIGHT * 0.5)

    for piece_index: int in clean_boundaries.size() - 1:
        var low := clean_boundaries[piece_index]
        var high := clean_boundaries[piece_index + 1]
        var piece_height := high - low
        if piece_height < 0.20:
            continue
        var center_y := (low + high) * 0.5
        var debris := StructuralDebrisLocal.new()
        get_parent().add_child(debris)
        debris.global_transform = old_transform
        debris.global_position = old_transform * Vector3(0.0, center_y, 0.0)
        var piece_mass := maxf(
            12.0,
            180.0 * piece_height / SUPPORT_HEIGHT
        )
        debris.configure(
            Vector3(0.72, piece_height * 0.97, 0.72),
            Color(0.31, 0.27, 0.18),
            piece_mass,
            maxf(80.0, 220.0 - energy_ratio * 38.0),
            "support"
        )
        var interior := clampf(0.34 + piece_height / SUPPORT_HEIGHT, 0.0, 1.0)
        var inherited := MaterialResponse.adopt_fragment(
            debris,
            column_state,
            interior
        )
        if debris.has_method("bind_surface_state"):
            debris.bind_surface_state(inherited)
        var radial := debris.global_position - hit_world
        radial.y *= 0.35
        if radial.length_squared() < 0.001:
            radial = Vector3.RIGHT * (-1.0 if piece_index % 2 == 0 else 1.0)
        radial = radial.normalized()
        var impulse_scale := clampf(
            sqrt(maxf(event_energy, 1.0)) / 95.0,
            0.70,
            2.40
        )
        debris.apply_central_impulse(
            event_direction.normalized() * piece_mass * impulse_scale * 1.55
            + radial * piece_mass * impulse_scale * 0.82
            + Vector3.UP * piece_mass * 0.36
        )
        debris.apply_torque_impulse(
            radial.cross(event_direction.normalized())
            * piece_mass * impulse_scale * 0.74
        )

func _evaluate_failure() -> void:
    var was_collapsed := collapsed
    super()
    if was_collapsed or not collapsed:
        return
    var event_position := global_position + Vector3.UP * 3.4
    var event_mass := 950.0
    var drop_height := 3.4
    if deck != null and is_instance_valid(deck):
        event_position = deck.global_position
        event_mass = deck.mass
        drop_height = maxf(deck.global_position.y - global_position.y, 0.5)
    MaterialResponse.impact(
        deck,
        event_position,
        Vector3.DOWN,
        event_mass * 9.81 * drop_height,
        event_mass,
        FoundryMaterial.STRUCTURAL_STEEL,
        {
            "type": MaterialResponse.EVENT_COLLAPSE,
            "radius": 11.0,
            "novelty": 1.0,
            "area": 12.0,
            "fracture": 1.0
        }
    )
