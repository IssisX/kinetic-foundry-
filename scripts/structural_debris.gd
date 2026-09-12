class_name StructuralDebris
extends RigidBody3D

const GeomUtil = preload("res://scripts/geom.gd")
const MaterialFx = preload("res://scripts/material_fx.gd")

var held := false
var source_tag := "structure"
var piece_size := Vector3.ONE
var toughness := 180.0
var plastic_strain := 0.0
var _mesh: MeshInstance3D
var machine_held := false
var _saved_linear_damp := 0.0
var _saved_angular_damp := 0.0

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
    set_meta("load_size", size)
    set_meta("source_tag", tag)
    _mesh = GeomUtil.box_mesh(
        size,
        color,
        0.92,
        0.30
    )
    add_child(_mesh)
    GeomUtil.add_box_collision(self, size)

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
    _receive_energy(amount, direction, amount * mass * 0.08)

func take_hit(force: Vector3, damage: float) -> void:
    if held:
        set_held(false)
    var direction := force.normalized()
    if direction.length_squared() < 0.001:
        direction = Vector3.UP
    _receive_energy(damage, direction, force.length())

func _receive_energy(
        damage: float,
        direction: Vector3,
        impulse: float
) -> void:
    var plastic_before := plastic_strain
    toughness = maxf(0.0, toughness - damage)
    plastic_strain = clampf(
        plastic_strain + damage / 900.0,
        0.0,
        0.22
    )
    if _mesh != null:
        _mesh.scale = Vector3(
            1.0 + plastic_strain * 0.35,
            1.0 - plastic_strain * 0.45,
            1.0 + plastic_strain * 0.12
        )
    if not held:
        apply_central_impulse(
            direction * minf(impulse, mass * 18.0)
        )
        apply_torque_impulse(
            Vector3(direction.z, 0.35, -direction.x)
            * minf(impulse * 0.38, mass * 8.0)
        )
    MaterialFx.steel(
        get_parent(),
        global_position,
        direction,
        clampf(damage / 24.0, 0.5, 3.4)
    )
    _emit_physical_event(
        impulse,
        damage,
        plastic_strain - plastic_before
    )

func _emit_physical_event(
        impulse: float,
        damage: float,
        plastic_delta: float
) -> void:
    if not is_inside_tree():
        return
    var extent := maxf(
        piece_size.x,
        maxf(piece_size.y, piece_size.z)
    )
    get_tree().call_group(
        "physical_event_listener",
        "physical_event",
        {
            "type": "debris_impact",
            "position": global_position,
            "impulse": maxf(impulse, damage * mass * 0.05),
            "mass": mass,
            "fracture": clampf(
                plastic_delta * 8.0 + damage / 180.0,
                0.0,
                1.0
            ),
            "radius": extent,
            "novelty": clampf(0.55 + damage / 120.0, 0.55, 1.0)
        }
    )

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
    var local_axis := Vector3.RIGHT
    if (
        piece_size.y >= piece_size.x
        and piece_size.y >= piece_size.z
    ):
        local_axis = Vector3.UP
    elif (
        piece_size.z >= piece_size.x
        and piece_size.z >= piece_size.y
    ):
        local_axis = Vector3.BACK
    return (global_basis * local_axis).normalized()

func _settled_factor() -> float:
    if held or machine_held:
        return 0.12
    var motion := (
        linear_velocity.length() / 2.6
        + angular_velocity.length() / 4.2
    )
    return clampf(1.0 - motion, 0.12, 1.0)
