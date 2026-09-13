class_name MachineGrip
extends RefCounted

## How any machine holds a physical load.
##
## A grip is a force law, not a parent-child attachment: the load stays a
## rigid body with its own mass and momentum, pulled toward an anchor by a
## capped spring and damper. Exceeding the travel limit is the grip losing
## the load, which is why a clamp can be torn open by something heavier than
## it can hold. Every machine uses this one law.

const TRAVEL_LIMIT := 3.75
const STIFFNESS := 78.0
const DAMPING := 17.5
const ALIGNMENT := 31.0
const MAX_ACCEL := 118.0
const MAX_TORQUE_PER_KG := 18.0

var held
var force := Vector3.ZERO
var stress := 0.0
var slipped := false

var travel_limit := TRAVEL_LIMIT
var stiffness := STIFFNESS
var damping := DAMPING
var alignment := ALIGNMENT
var max_accel := MAX_ACCEL
var max_torque_per_kg := MAX_TORQUE_PER_KG


func is_holding() -> bool:
    return held != null and is_instance_valid(held)


func load_mass() -> float:
    if not is_holding():
        return 0.0
    return float(held.get("mass"))


func grab(body, anchor: Node3D, snap: bool = true) -> bool:
    if body == null or not is_instance_valid(body) or anchor == null:
        return false
    held = body
    slipped = false
    if snap:
        held.global_position = anchor.global_position
        held.global_basis = anchor.global_basis
    _set_machine_hold(held, true)
    return true


func release(throw_velocity: Vector3, with_throw: bool) -> Node:
    if not is_holding():
        held = null
        return null
    var load = held
    held = null
    force = Vector3.ZERO
    stress = 0.0
    _set_machine_hold(load, false)
    if with_throw and load is RigidBody3D:
        load.linear_velocity = throw_velocity
        load.angular_velocity = Vector3(
            throw_velocity.z,
            0.8,
            -throw_velocity.x
        ) * 0.16
    return load


## Returns the reaction the machine itself has to carry.
func update(anchor: Node3D, anchor_velocity: Vector3) -> Vector3:
    slipped = false
    if not is_holding():
        held = null
        force = Vector3.ZERO
        stress = 0.0
        return Vector3.ZERO
    if not (held is RigidBody3D) or anchor == null:
        release(Vector3.ZERO, false)
        return Vector3.ZERO

    var load: RigidBody3D = held
    var displacement := anchor.global_position - load.global_position
    if displacement.length() > travel_limit:
        release(Vector3.ZERO, false)
        slipped = true
        return Vector3.ZERO

    var relative_velocity := anchor_velocity - load.linear_velocity
    var grip_force := (
        displacement * load.mass * stiffness
        + relative_velocity * load.mass * damping
    )
    grip_force = _limit(grip_force, load.mass * max_accel)
    load.apply_central_force(grip_force)

    var align_axis := load.global_basis.z.cross(anchor.global_basis.z)
    var torque := (
        align_axis * load.mass * alignment
        - load.angular_velocity * load.mass * 4.5
    )
    load.apply_torque(_limit(torque, load.mass * max_torque_per_kg))

    force = grip_force
    stress = clampf(
        grip_force.length() / maxf(load.mass * max_accel, 1.0),
        0.0,
        1.0
    )
    return Vector3(grip_force.x, 0.0, grip_force.z)


func _limit(value: Vector3, max_length: float) -> Vector3:
    if value.length_squared() <= max_length * max_length:
        return value
    return value.normalized() * max_length


func _set_machine_hold(load, value: bool) -> void:
    if load == null or not is_instance_valid(load):
        return
    if load.has_method("set_machine_held"):
        load.set_machine_held(value)
    elif load.has_method("set_held"):
        load.set_held(value)
