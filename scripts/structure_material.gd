extends "res://scripts/structure.gd"

const MaterialFx = preload("res://scripts/material_fx.gd")
const GeomUtilLocal = preload("res://scripts/geom.gd")
const StructuralDebrisLocal = preload(
    "res://scripts/structural_debris.gd"
)

const SUPPORT_HEIGHT := 4.6
const SUPPORT_SEGMENTS := 6
const SUPPORT_SEGMENT_HEIGHT := SUPPORT_HEIGHT / float(SUPPORT_SEGMENTS)

var _support_segments: Array = []
var _support_segment_damage: Array = []
var _support_last_hit_world: Array[Vector3] = []
var _support_last_energy: Array[float] = []
var _support_last_direction: Array[Vector3] = []

func _ready() -> void:
    super()
    _build_deformable_support_skins()

func _build_deformable_support_skins() -> void:
    _support_segments.clear()
    _support_segment_damage.clear()
    _support_last_hit_world.clear()
    _support_last_energy.clear()
    _support_last_direction.clear()

    for index: int in supports.size():
        var segment_list: Array[MeshInstance3D] = []
        var damage_list: Array[float] = []
        _support_last_hit_world.append(Vector3.ZERO)
        _support_last_energy.append(0.0)
        _support_last_direction.append(Vector3.UP)

        if index < support_meshes.size() and is_instance_valid(support_meshes[index]):
            support_meshes[index].visible = false
        if not is_instance_valid(supports[index]):
            _support_segments.append(segment_list)
            _support_segment_damage.append(damage_list)
            continue

        for segment_index: int in SUPPORT_SEGMENTS:
            var segment := GeomUtilLocal.box_mesh(
                Vector3(
                    0.72,
                    SUPPORT_SEGMENT_HEIGHT * 0.975,
                    0.72
                ),
                Color(0.39, 0.33, 0.20),
                0.80,
                0.30
            )
            segment.name = "DeformableColumn_%d" % segment_index
            segment.position.y = (
                -SUPPORT_HEIGHT * 0.5
                + SUPPORT_SEGMENT_HEIGHT * (float(segment_index) + 0.5)
            )
            supports[index].add_child(segment)
            segment_list.append(segment)
            damage_list.append(0.0)

        _support_segments.append(segment_list)
        _support_segment_damage.append(damage_list)

func damage_support(index: int, amount: float, direction: Vector3) -> void:
    var hit_pos := global_position
    if index >= 0 and index < supports.size() and is_instance_valid(supports[index]):
        hit_pos = supports[index].global_position + Vector3.UP * 1.05
    damage_support_at(
        index,
        amount,
        direction,
        hit_pos,
        amount * amount * 3.0
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

    super.damage_support(index, amount, direction)

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

    MaterialFx.steel(
        get_parent(),
        world_point,
        direction,
        clampf(maxf(removed / 20.0, impact_energy / 6000.0), 0.55, 5.2)
    )

    get_tree().call_group(
        "physical_event_listener",
        "physical_event",
        {
            "type": "machine_contact",
            "position": world_point,
            "impulse": sqrt(maxf(2.0 * 180.0 * impact_energy, 0.0)),
            "mass": 180.0,
            "fracture": clampf(
                removed / 95.0 + impact_energy / 22000.0,
                0.0,
                1.0
            ),
            "radius": 2.3,
            "novelty": clampf(0.55 + removed / 120.0, 0.55, 1.0),
            "material": "steel"
        }
    )

    if removed > 28.0 or support_health[index] <= 0.0:
        MaterialFx.concrete(
            get_parent(),
            world_point - Vector3.UP * minf(world_point.y, 2.8),
            direction + Vector3.UP * 0.35,
            clampf(removed / 24.0, 0.8, 4.2)
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
    var sigma := SUPPORT_SEGMENT_HEIGHT * (0.65 + energy_ratio * 0.34)

    for segment_index: int in segment_list.size():
        var segment := segment_list[segment_index] as MeshInstance3D
        if segment == null or not is_instance_valid(segment):
            continue
        var base_y := (
            -SUPPORT_HEIGHT * 0.5
            + SUPPORT_SEGMENT_HEIGHT * (float(segment_index) + 0.5)
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
        var heat := clampf(
            (1.0 - support_health[index] / 100.0) * 0.55
            + local_damage * 0.55,
            0.0,
            1.0
        )
        segment.material_override = GeomUtilLocal.material(
            Color(0.39, 0.33, 0.20).lerp(
                Color(0.57, 0.18, 0.055),
                heat
            ),
            0.84,
            0.30
        )

    _support_segment_damage[index] = damage_list

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

    get_tree().call_group(
        "physical_event_listener",
        "physical_event",
        {
            "type": "fracture",
            "position": hit_world,
            "impulse": sqrt(maxf(2.0 * 180.0 * event_energy, 0.0)),
            "mass": 180.0,
            "fracture": 1.0,
            "radius": 4.6,
            "novelty": 0.92,
            "material": "steel"
        }
    )

func _evaluate_failure() -> void:
    var was_collapsed := collapsed
    super()
    if was_collapsed or not collapsed:
        return
    var event_position := global_position + Vector3.UP * 3.4
    var event_mass := 950.0
    if deck != null and is_instance_valid(deck):
        event_position = deck.global_position
        event_mass = deck.mass
    get_tree().call_group(
        "physical_event_listener",
        "physical_event",
        {
            "type": "collapse",
            "position": event_position,
            "impulse": event_mass * 12.5,
            "mass": event_mass,
            "fracture": 1.0,
            "radius": 11.0,
            "novelty": 1.0,
            "material": "steel"
        }
    )
