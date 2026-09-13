class_name MachineStability
extends RefCounted

## Whether a machine is about to go over.
##
## One law for every machine: the overturning moment about the edge of the
## support base, divided by the restoring moment its own weight provides.
## A ratio of 1 is the tipping line. What differs between machines is which
## masses and contact forces contribute, not the arithmetic.

const GRAVITY := 9.81


static func tipping_ratio(
        moment: float,
        machine_mass: float,
        half_base: float,
        brace_gain: float = 1.0
) -> float:
    var capacity := (
        maxf(machine_mass, 0.001)
        * GRAVITY
        * maxf(half_base, 0.001)
        * maxf(brace_gain, 0.05)
    )
    return moment / maxf(capacity, 1.0)


## Moment a mass held out at a horizontal offset applies about the base.
static func load_moment(mass: float, lever: float) -> float:
    return maxf(mass, 0.0) * GRAVITY * absf(lever)
