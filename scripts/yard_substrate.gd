class_name YardSubstrate
extends StaticBody3D

## The yard floor is a load, not a backdrop.
##
## A dozer blade or excavator bucket spends the same energy partition on
## dirt that it spends on steel. Cut goes into the working face; the spoil
## piles ahead and to the sides and becomes walkable mass. Gait samples it.
## Machines rest on it. It is not a decal.

const GeomUtil = preload("res://scripts/geom.gd")

const GRID := 33
const SPAN := 32.0
const MAX_PILE := 1.35
const CELL := SPAN / float(GRID - 1)

var _heights := PackedFloat32Array()
var _scar := PackedFloat32Array()
var _visual: MeshInstance3D
var _collision: CollisionShape3D
var _shape: HeightMapShape3D
var _dirty := false
var _rebuild_cooldown := 0.0


func _ready() -> void:
    add_to_group("yard_substrate")
    collision_layer = 8
    collision_mask = 0
    _heights.resize(GRID * GRID)
    _scar.resize(GRID * GRID)
    _heights.fill(0.0)
    _scar.fill(0.0)
    _shape = HeightMapShape3D.new()
    _shape.map_width = GRID
    _shape.map_depth = GRID
    _shape.map_data = _heights
    _collision = CollisionShape3D.new()
    _collision.name = "Earth"
    _collision.shape = _shape
    _collision.position = Vector3(0.0, 0.0, 0.0)
    _collision.scale = Vector3(CELL, 1.0, CELL)
    add_child(_collision)
    _visual = MeshInstance3D.new()
    _visual.name = "Spoil"
    add_child(_visual)
    position = Vector3(0.0, 0.04, 0.0)
    _rebuild()


func _process(delta: float) -> void:
    _rebuild_cooldown = maxf(0.0, _rebuild_cooldown - delta)
    if _dirty and _rebuild_cooldown <= 0.0:
        _rebuild()


func cut_and_pile(
        world_point: Vector3,
        direction: Vector3,
        intensity: float,
        width: float = 1.6
) -> void:
    var push := direction
    push.y = 0.0
    if push.length_squared() < 0.0001:
        push = Vector3(0.0, 0.0, -1.0)
    push = push.normalized()
    var right := Vector3.UP.cross(push).normalized()
    var local := to_local(world_point)
    var strength := clampf(intensity / 90.0, 0.04, 0.55)
    var radius := clampf(width, 0.6, 4.2)
    var changed := false
    for z in GRID:
        for x in GRID:
            var cell := Vector3(
                (float(x) - float(GRID - 1) * 0.5) * CELL,
                0.0,
                (float(z) - float(GRID - 1) * 0.5) * CELL
            )
            var delta := cell - Vector3(local.x, 0.0, local.z)
            var along := delta.dot(push)
            var side := delta.dot(right)
            var falloff := _kernel(along, side, radius)
            if falloff < 0.01:
                continue
            var index := z * GRID + x
            var scar_add := falloff * strength * 0.85
            _scar[index] = clampf(_scar[index] + scar_add, 0.0, 1.0)
            # Spoil is driven forward and out, not erased. A blade does
            # not delete the yard; it relocates it.
            var pile := 0.0
            if along > -0.15:
                var ahead := clampf(along / (radius * 1.15), 0.0, 1.0)
                var berm := exp(-side * side / maxf(radius * radius * 0.55, 0.08))
                pile = falloff * strength * (0.22 + ahead * 0.55) * (0.55 + berm * 0.80)
            _heights[index] = clampf(_heights[index] + pile * 0.12, 0.0, MAX_PILE)
            changed = true
    if changed:
        _dirty = true


func gouge(world_point: Vector3, direction: Vector3, intensity: float) -> void:
    var push := direction
    if push.length_squared() < 0.0001:
        push = Vector3(0.0, -1.0, 0.0)
    push = push.normalized()
    var local := to_local(world_point)
    var strength := clampf(intensity / 70.0, 0.05, 0.70)
    var radius := 0.55
    for z in GRID:
        for x in GRID:
            var cell := Vector3(
                (float(x) - float(GRID - 1) * 0.5) * CELL,
                0.0,
                (float(z) - float(GRID - 1) * 0.5) * CELL
            )
            var delta := cell - Vector3(local.x, 0.0, local.z)
            var planar := Vector3(push.x, 0.0, push.z)
            var along := delta.dot(planar.normalized()) if planar.length_squared() > 0.001 else 0.0
            var dist := Vector2(delta.x, delta.z).length()
            var falloff := exp(-dist * dist / maxf(radius * radius * 1.4, 0.04))
            if falloff < 0.02:
                continue
            var index := z * GRID + x
            _scar[index] = clampf(_scar[index] + falloff * strength, 0.0, 1.0)
            var spoil := falloff * strength * 0.10
            if along > 0.0:
                spoil *= 1.55
            _heights[index] = clampf(_heights[index] + spoil, 0.0, MAX_PILE)
    _dirty = true


func rebuild() -> void:
    _rebuild()


func machine_hit_at(
        _amount: float,
        direction: Vector3,
        world_point: Vector3,
        impact_energy: float
) -> void:
    cut_and_pile(world_point, direction, clampf(impact_energy / 140.0, 8.0, 220.0), 1.8)


func _kernel(along: float, side: float, radius: float) -> float:
    var ahead := clampf(1.0 - absf(along) / (radius * 1.35), 0.0, 1.0)
    if along < -radius * 0.45:
        return 0.0
    var lateral := exp(-side * side / maxf(radius * radius * 0.42, 0.05))
    return ahead * lateral


func _rebuild() -> void:
    _dirty = false
    _rebuild_cooldown = 0.12
    var data := _heights.duplicate()
    _shape.map_data = data
    var st := SurfaceTool.new()
    st.begin(Mesh.PRIMITIVE_TRIANGLES)
    var asphalt := Color(0.19, 0.175, 0.155)
    var earth := Color(0.38, 0.28, 0.16)
    var has_mesh := false
    for z in GRID - 1:
        for x in GRID - 1:
            var i00 := z * GRID + x
            var i10 := i00 + 1
            var i01 := i00 + GRID
            var i11 := i01 + 1
            var h00 := _heights[i00]
            var h10 := _heights[i10]
            var h01 := _heights[i01]
            var h11 := _heights[i11]
            var scar := (
                _scar[i00] + _scar[i10] + _scar[i01] + _scar[i11]
            ) * 0.25
            if h00 < 0.012 and h10 < 0.012 and h01 < 0.012 and h11 < 0.012 and scar < 0.08:
                continue
            has_mesh = true
            var p00 := _vertex(x, z, h00)
            var p10 := _vertex(x + 1, z, h10)
            var p01 := _vertex(x, z + 1, h01)
            var p11 := _vertex(x + 1, z + 1, h11)
            var color := asphalt.lerp(earth, clampf(scar * 0.75 + maxf(h00, h11) * 0.55, 0.0, 1.0))
            _quad(st, p00, p10, p11, p01, color)
    if not has_mesh:
        _visual.mesh = null
        return
    st.generate_normals()
    st.index()
    var mesh := st.commit()
    _visual.mesh = mesh
    var mat := GeomUtil.material(Color(0.30, 0.24, 0.16), 0.94, 0.0)
    mat.vertex_color_use_as_albedo = true
    _visual.material_override = mat


func _vertex(x: int, z: int, height: float) -> Vector3:
    return Vector3(
        (float(x) - float(GRID - 1) * 0.5) * CELL,
        height,
        (float(z) - float(GRID - 1) * 0.5) * CELL
    )


func _quad(
        st: SurfaceTool,
        a: Vector3,
        b: Vector3,
        c: Vector3,
        d: Vector3,
        color: Color
) -> void:
    st.set_color(color)
    st.add_vertex(a)
    st.set_color(color)
    st.add_vertex(b)
    st.set_color(color)
    st.add_vertex(c)
    st.set_color(color)
    st.add_vertex(a)
    st.set_color(color)
    st.add_vertex(c)
    st.set_color(color)
    st.add_vertex(d)
