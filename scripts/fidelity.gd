extends Node

## The fidelity slider.
##
## Not a graphics-quality preset. F retunes the same structures the game
## already owns (deck grid, gate grid, solver iterations, ribbon threshold,
## shard cap) so mechanics and graphics move together because they are the
## same grid. If dragging F does not change a node count, a bond count, or
## a shard count, the slider is fake.
##
## Two kinds of knob:
## - live knobs (iterations, ribbon threshold, shard cap) apply this frame.
## - topology knobs (grid size) destroy node identity, so they only apply
##   on an explicit rebuild, which resets that structure to intact.

signal live_changed(f: int)
signal rebuild_requested(f: int)

var f: int = 1

const DECK_GRIDS: Array[Vector2i] = [
    Vector2i(4, 3), Vector2i(5, 4), Vector2i(8, 6), Vector2i(12, 8)
]
const GATE_GRIDS: Array[int] = [5, 7, 9, 11]
const SOLVER_ITERATIONS: Array[int] = [3, 5, 5, 5]
const RIBBON_DAMAGE: Array[float] = [1.1, 0.55, 0.42, 0.42]
const MAX_SHARDS: Array[int] = [6, 8, 14, 24]
const SUPPORT_VISUAL_SEGMENTS: Array[int] = [3, 6, 6, 8]


func deck_grid() -> Vector2i:
    return DECK_GRIDS[f]


func gate_grid() -> int:
    return GATE_GRIDS[f]


func iterations() -> int:
    return SOLVER_ITERATIONS[f]


func use_bend() -> bool:
    return f >= 2


func use_area() -> bool:
    return f >= 3


func ribbon_damage() -> float:
    return RIBBON_DAMAGE[f]


func keep_skin_on_debris() -> bool:
    return f >= 2


func max_shards() -> int:
    return MAX_SHARDS[f]


func support_segments() -> int:
    return SUPPORT_VISUAL_SEGMENTS[f]


## Iterations, ribbon threshold and shard cap take effect immediately.
## Grid size does not change: changing it here would silently invent
## damage on a wounded structure.
func set_live(value: int) -> void:
    var clamped := clampi(value, 0, 3)
    if clamped == f:
        return
    f = clamped
    live_changed.emit(f)


## Grid size changes now. Structures listening for this reset to intact
## at the new grid and say so; they do not lerp a cracked mesh onto a
## different topology.
func request_rebuild(value: int = f) -> void:
    f = clampi(value, 0, 3)
    live_changed.emit(f)
    rebuild_requested.emit(f)
