class_name ModalResonator
extends RefCounted

## A struck body rings and decays instead of the impact being a single
## instantaneous flash. Two to three vibration modes, integrated with the
## closed-form damped oscillator (elite-solvers spec §11.4) rather than an
## exponential "s *= 0.98" fade. One state, read by shader shimmer and (in
## future) continuous audio - not two independently-authored effects.

var _omega: Array[float] = []
var _zeta: Array[float] = []
var _coupling: Array[float] = []
var _s: Array[float] = []
var _v: Array[float] = []
var _asleep_frames := 0

const SLEEP_AMPLITUDE := 0.00003
const SLEEP_FRAMES_REQUIRED := 20


func configure(frequencies_hz: Array, damping_ratios: Array) -> void:
    _omega.clear()
    _zeta.clear()
    _coupling.clear()
    _s.clear()
    _v.clear()
    for i in frequencies_hz.size():
        _omega.append(TAU * float(frequencies_hz[i]))
        _zeta.append(
            float(damping_ratios[i]) if i < damping_ratios.size() else 0.045
        )
        # Higher modes couple more weakly to a single point excitation.
        _coupling.append(1.0 / float(i + 1))
        _s.append(0.0)
        _v.append(0.0)


## A velocity kick, not a position kick: this is the same E -> impulse
## relation used everywhere else in this game (EnergyPartition), so a hard
## hit rings harder than a soft one for a physically consistent reason.
func excite(velocity_kick: float) -> void:
    for i in _v.size():
        _v[i] += velocity_kick * _coupling[i]
    _asleep_frames = 0


func step(dt: float) -> void:
    if is_asleep() or dt <= 0.0:
        return
    for i in _s.size():
        var wn: float = _omega[i]
        if wn <= 0.0:
            continue
        var z: float = _zeta[i]
        var wd := wn * sqrt(maxf(1.0 - z * z, 1e-6))
        var x: float = _s[i]
        var v: float = _v[i]
        var e := exp(-z * wn * dt)
        var c := cos(wd * dt)
        var sn := sin(wd * dt)
        var x2 := e * (x * c + ((v + z * wn * x) / wd) * sn)
        var v2 := -z * wn * x2 + e * (-x * wd * sn + (v + z * wn * x) * c)
        _s[i] = x2
        _v[i] = v2
    if absf(amplitude()) < SLEEP_AMPLITUDE:
        _asleep_frames += 1
    else:
        _asleep_frames = 0


func is_asleep() -> bool:
    return _asleep_frames > SLEEP_FRAMES_REQUIRED


func amplitude() -> float:
    var total := 0.0
    for value in _s:
        total += value
    return total


## When a component actually fractures, its shards do not inherit the
## parent's ring (elite spec §8: "when the deck fragments, kill the modes").
func kill() -> void:
    for i in _s.size():
        _s[i] = 0.0
        _v[i] = 0.0
    _asleep_frames = SLEEP_FRAMES_REQUIRED + 1
