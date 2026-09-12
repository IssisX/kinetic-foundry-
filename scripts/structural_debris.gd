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

func get_load_profile() -> Dictionary:
    var velocity_sq := linear_velocity.length_squared()
    return {
        "mass": mass,
        "size": piece_size,
        "kinetic_energy": 0.5 * mass * velocity_sq,
        "brace_quality": _brace_quality(),
        "plastic_strain": plastic_strain,
        "source": source_tag
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
    return clampf(longest / shortest / 12.0, 0.15, 1.0)
