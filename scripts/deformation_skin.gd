class_name DeformationSkin3D
extends Node3D

## Read-only visual projection of a FractureNetwork.
## Collision remains coarse until separation; the rendered sheet, heat tint,
## and crack paths all come directly from solved node and bond state.

const MODE_HORIZONTAL := 0
const MODE_VERTICAL := 1

var network
var plane_mode := MODE_HORIZONTAL
var base_color := Color(0.28, 0.29, 0.27)
var _surface: MeshInstance3D
var _cracks: MeshInstance3D
var _surface_material: StandardMaterial3D
var _crack_material: StandardMaterial3D
var _seen_revision := -1


func configure(
        source,
        mode: int,
        color: Color,
        local_offset: Vector3 = Vector3.ZERO
) -> void:
    network = source
    plane_mode = mode
    base_color = color
    position = local_offset
    _surface = MeshInstance3D.new()
    _surface.name = "SolvedSurface"
    add_child(_surface)
    _cracks = MeshInstance3D.new()
    _cracks.name = "SolvedCracks"
    add_child(_cracks)

    _surface_material = StandardMaterial3D.new()
    _surface_material.albedo_color = Color.WHITE
    _surface_material.roughness = 0.88
    _surface_material.metallic = 0.34
    _surface_material.vertex_color_use_as_albedo = true
    _surface_material.cull_mode = BaseMaterial3D.CULL_DISABLED
    _surface_material.shading_mode = (
        BaseMaterial3D.SHADING_MODE_PER_PIXEL
    )
    _surface.material_override = _surface_material

    _crack_material = StandardMaterial3D.new()
    _crack_material.albedo_color = Color(0.055, 0.025, 0.012)
    _crack_material.roughness = 0.96
    _crack_material.emission_enabled = true
    _crack_material.emission = Color(0.31, 0.055, 0.008)
    _crack_material.emission_energy_multiplier = 0.55
    _crack_material.shading_mode = (
        BaseMaterial3D.SHADING_MODE_UNSHADED
    )
    _cracks.material_override = _crack_material
    refresh(true)


func refresh(force: bool = false) -> void:
    if network == null or _surface == null:
        return
    var revision: int = network.get_revision()
    if not force and revision == _seen_revision:
        return
    _seen_revision = revision
    _rebuild_surface()
    _rebuild_cracks()


func _rebuild_surface() -> void:
    var grid: Vector2i = network.get_grid_size()
    if grid.x < 2 or grid.y < 2:
        return
    var vertices := PackedVector3Array()
    var colors := PackedColorArray()
    var uvs := PackedVector2Array()
    var normals: Array[Vector3] = []
    for row in grid.y:
        for column in grid.x:
            var index := row * grid.x + column
            vertices.append(_map_position(
                network.get_node_position(index)
            ))
            var damage: float = network.get_node_damage(index)
            var heat := Color(0.92, 0.20, 0.025)
            colors.append(base_color.lerp(
                heat,
                smoothstep(0.24, 1.0, damage) * 0.82
            ))
            uvs.append(Vector2(
                float(column) / float(grid.x - 1),
                float(row) / float(grid.y - 1)
            ))
            normals.append(Vector3.ZERO)

    var indices := PackedInt32Array()
    for row in grid.y - 1:
        for column in grid.x - 1:
            var first := row * grid.x + column
            var right := first + 1
            var down := first + grid.x
            var diagonal := down + 1
            _append_triangle(
                indices,
                normals,
                vertices,
                first,
                down,
                right
            )
            _append_triangle(
                indices,
                normals,
                vertices,
                right,
                down,
                diagonal
            )
    var packed_normals := PackedVector3Array()
    for normal in normals:
        packed_normals.append(
            normal.normalized()
            if normal.length_squared() > 0.0001
            else _default_normal()
        )
    var arrays := []
    arrays.resize(Mesh.ARRAY_MAX)
    arrays[Mesh.ARRAY_VERTEX] = vertices
    arrays[Mesh.ARRAY_NORMAL] = packed_normals
    arrays[Mesh.ARRAY_COLOR] = colors
    arrays[Mesh.ARRAY_TEX_UV] = uvs
    arrays[Mesh.ARRAY_INDEX] = indices
    var mesh := ArrayMesh.new()
    mesh.add_surface_from_arrays(
        Mesh.PRIMITIVE_TRIANGLES,
        arrays
    )
    _surface.mesh = mesh


func _append_triangle(
        indices: PackedInt32Array,
        normals: Array[Vector3],
        vertices: PackedVector3Array,
        first: int,
        second: int,
        third: int
) -> void:
    indices.append(first)
    indices.append(second)
    indices.append(third)
    var normal := (
        vertices[second] - vertices[first]
    ).cross(vertices[third] - vertices[first])
    normals[first] += normal
    normals[second] += normal
    normals[third] += normal


func _rebuild_cracks() -> void:
    var vertices := PackedVector3Array()
    var colors := PackedColorArray()
    var indices := PackedInt32Array()
    for bond in network.get_bond_visuals():
        var damage := float(bond.damage)
        if bool(bond.active) and damage < 0.42:
            continue
        var first := _map_position(
            network.get_node_position(int(bond.a))
        )
        var second := _map_position(
            network.get_node_position(int(bond.b))
        )
        var tangent := (second - first).normalized()
        var normal := _default_normal()
        var crack_axis := normal.cross(tangent).normalized()
        var midpoint := (first + second) * 0.5 + normal * 0.020
        var half_length := first.distance_to(second) * (
            0.16 + damage * 0.18
        )
        var half_width := 0.010 + damage * 0.022
        var base := vertices.size()
        vertices.append(
            midpoint - crack_axis * half_length - tangent * half_width
        )
        vertices.append(
            midpoint + crack_axis * half_length - tangent * half_width
        )
        vertices.append(
            midpoint + crack_axis * half_length + tangent * half_width
        )
        vertices.append(
            midpoint - crack_axis * half_length + tangent * half_width
        )
        for index in [0, 1, 2, 0, 2, 3]:
            indices.append(base + index)
        var color := Color(0.11, 0.025, 0.008).lerp(
            Color(1.0, 0.19, 0.018),
            damage * 0.48
        )
        for _i in 4:
            colors.append(color)
    if vertices.is_empty():
        _cracks.mesh = null
        return
    var arrays := []
    arrays.resize(Mesh.ARRAY_MAX)
    arrays[Mesh.ARRAY_VERTEX] = vertices
    arrays[Mesh.ARRAY_COLOR] = colors
    arrays[Mesh.ARRAY_INDEX] = indices
    var mesh := ArrayMesh.new()
    mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
    _cracks.mesh = mesh


func _map_position(source: Vector3) -> Vector3:
    if plane_mode == MODE_VERTICAL:
        return Vector3(source.x, source.z, source.y)
    return source


func _default_normal() -> Vector3:
    if plane_mode == MODE_VERTICAL:
        return Vector3(0.0, 0.0, -1.0)
    return Vector3.UP
