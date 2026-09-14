class_name EnergyPartition
extends RefCounted

## The one place impact energy is divided.
##
## Every consumer reads a term from this split. None of them may take the
## whole energy a second time, and none of them may invent a second formula
## for the same joules.

const MAX_EVENT_ENERGY := 250000.0
const MAX_TICK_ENERGY := 40000.0

const FRACTURE_SHARE := 0.46
const KINETIC_SHARE := 0.28
const PLASTIC_SHARE := 0.10
const ACOUSTIC_SHARE := 0.02
const RESIDUAL_SHARE := 0.14
const IMMOVABLE_MASS := 1.0e9


static func split(energy: float) -> Dictionary:
    var total := clampf(energy, 0.0, MAX_EVENT_ENERGY)
    return {
        "input": total,
        "fracture": total * FRACTURE_SHARE,
        "kinetic": total * KINETIC_SHARE,
        "plastic": total * PLASTIC_SHARE,
        "acoustic": total * ACOUSTIC_SHARE,
        "residual": total * RESIDUAL_SHARE
    }


## Impulse that carries the kinetic term for a body of this mass, so no call
## site has to guess a newton-second figure.
static func kinetic_impulse(mass: float, energy: float) -> float:
    var kinetic := clampf(energy, 0.0, MAX_EVENT_ENERGY) * KINETIC_SHARE
    return sqrt(maxf(2.0 * maxf(mass, 0.001) * kinetic, 0.0))


## Stand-in used only where a call site genuinely has no kinematics to
## offer. It is an approximation, it lives here once, and anything that can
## supply a mass and a relative speed must use `collision_energy` instead.
static func nominal_impact_energy(
        damage_scalar: float,
        tool_force: float = 0.0,
        effort: float = 0.0
) -> float:
    var from_damage := damage_scalar * damage_scalar * 3.0
    var from_tool := (
        tool_force
        * tool_force
        * (0.30 + clampf(effort, 0.0, 1.0) * 0.65)
    )
    return maxf(from_damage, from_tool)


## Closing energy of two bodies meeting at a relative speed.
static func collision_energy(
        mass_a: float,
        mass_b: float,
        relative_speed: float
) -> float:
    var first := maxf(mass_a, 0.001)
    var second := maxf(mass_b, 0.001)
    var reduced := (first * second) / (first + second)
    return 0.5 * reduced * relative_speed * relative_speed


## Closing energy against an immovable world (ground, a locked column).
## Same formula as `collision_energy`; the second mass is just large.
static func against_world(mass: float, speed: float) -> float:
    return collision_energy(mass, IMMOVABLE_MASS, speed)
