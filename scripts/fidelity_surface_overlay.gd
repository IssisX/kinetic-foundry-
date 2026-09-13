class_name FidelitySurfaceOverlay3D
extends MeshInstance3D

## Solver-driven steel presentation. F0 leaves the legacy vertex-color skin
## visible; F1+ renders the same solved vertices with packed D/heat/load COLOR.

const SteelShader = preload("res://shaders/foundry_steel.gdshader")

var _seen_revision := -1
var _seen_fidelity := -1
var _material: ShaderMaterial

func _ready() -> void:
    name = "FidelitySurface"
    _material = ShaderMaterial.new()
    _material.shader = SteelShader
    material_override = _material
    set_process(true)

func _process(_delta: float) -> void:
    var skin := get_parent()
    if skin == null:
        return
    var fallback := skin.get_node_or_null("SolvedSurface")
    var use_solver_surface := Fidelity.f >= 1
    visible = use_solver_surface
    if fallback != null:
        fallback.visible = not use_solver_surface
    if not use_solver_surface:
        return

    var network = skin.get("network")
    if network == null or not network.has_method("get_revision"):
        mesh = null
        return
    var revision := int(network.get_revision())
    if revision == _seen_revision and Fidelity.f == _seen_fidelity:
        return
    _seen_revision = revision
    _seen_fidelity = Fidelity.f
    var color_value: Variant = skin.get("base_color")
    var base_color := Color(0.24, 0.25, 0.23)
    if color_value is Color:
        base_color = color_value
    _material.set_shader_parameter("base_color", Vector3(
        base_color.r,
        base_color.g,
        base_color.b
    ))
    _rebuild(network, int(skin.get("plane_mode")))

func _rebuild(network, plane_mode: int) -> void:
    var grid: Vector2i = network.get_grid_size()
    if grid.x < 2 or grid.y < 2:
        mesh = null
        return
    var vertices := PackedVector3Array()
    var colors := PackedColorArray()
    var uvs := PackedVector2Array()
    var normals: Array[Vector3] = []
    for row in grid.y:
        for column in grid.x:
            var index := row * grid.x + column
            vertices.append(_map_position(
                network.get_node_position(index),
                plane_mode
            ))
            var damage := float(network.get_node_damage(index))
            var heat := damage
            var load := 0.0
            if network.has_method("get_node_heat"):
                heat = float(network.get_node_heat(index))
            if network.has_method("get_node_load"):
                load = float(network.get_node_load(index))
            colors.append(Color(damage, heat, load, 1.0))
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
            _append_triangle(indices, normals, vertices, first, down, right)
            _append_triangle(indices, normals, vertices, right, down, diagonal)

    var packed_normals := PackedVector3Array()
    for normal in normals:
        packed_normals.append(
            normal.normalized()
            if normal.length_squared() > 0.0001
            else _default_normal(plane_mode)
        )
    var arrays := []
    arrays.resize(Mesh.ARRAY_MAX)
    arrays[Mesh.ARRAY_VERTEX] = vertices
    arrays[Mesh.ARRAY_NORMAL] = packed_normals
    arrays[Mesh.ARRAY_COLOR] = colors
    arrays[Mesh.ARRAY_TEX_UV] = uvs
    arrays[Mesh.ARRAY_INDEX] = indices
    var new_mesh := ArrayMesh.new()
    new_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
    mesh = new_mesh

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

func _map_position(source: Vector3, plane_mode: int) -> Vector3:
    if plane_mode == 1:
        return Vector3(source.x, source.z, source.y)
    return source

func _default_normal(plane_mode: int) -> Vector3:
    if plane_mode == 1:
        return Vector3(0.0, 0.0, -1.0)
    return Vector3.UP
