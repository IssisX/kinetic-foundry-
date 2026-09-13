class_name FidelityFragmentSkin3D
extends Node3D

## Keeps fracture identity continuous: the rigid body's convex hull remains the
## collision proxy, while F2+ renders the exact solved component triangles,
## solver COLOR, and UVs that existed on the parent plate at separation.

const SteelShader = preload("res://shaders/foundry_steel.gdshader")

var _fallback_meshes: Array[MeshInstance3D] = []
var _skin: MeshInstance3D

func configure(
        body: Node3D,
        network,
        spec: Dictionary,
        plane_mode: int,
        base_color: Color,
        thickness: float
) -> bool:
    for child in body.get_children():
        if child is MeshInstance3D:
            _fallback_meshes.append(child)

    var built := _build_mesh(
        network,
        spec,
        plane_mode,
        thickness
    )
    if built == null:
        return false

    _skin = MeshInstance3D.new()
    _skin.name = "SolverFragmentSkin"
    _skin.mesh = built
    var material := ShaderMaterial.new()
    material.shader = SteelShader
    material.set_shader_parameter("base_color", Vector3(
        base_color.r,
        base_color.g,
        base_color.b
    ))
    _skin.material_override = material
    add_child(_skin)
    body.set_meta("material_id", "STRUCTURAL_STEEL")
    body.set_meta("fidelity_skin_attached", true)
    set_process(true)
    _apply_visibility()
    return true

func _process(_delta: float) -> void:
    _apply_visibility()

func _apply_visibility() -> void:
    var exact := Fidelity.keep_skin_on_debris()
    if _skin != null:
        _skin.visible = exact
    for fallback in _fallback_meshes:
        if is_instance_valid(fallback):
            fallback.visible = not exact

func _build_mesh(
        network,
        spec: Dictionary,
        plane_mode: int,
        thickness: float
) -> ArrayMesh:
    var nodes_value: Variant = spec.get("nodes", [])
    if not nodes_value is Array:
        return null
    var component: Array = nodes_value as Array
    if component.size() < 3:
        return null
    var node_set := {}
    for value in component:
        node_set[int(value)] = true

    var grid: Vector2i = network.get_grid_size()
    var center_source: Vector3 = spec.get("local_position", Vector3.ZERO)
    var center := _map_position(center_source, plane_mode)
    var normal := _default_normal(plane_mode)
    var half_t := maxf(thickness, 0.02) * 0.5
    var tool := SurfaceTool.new()
    tool.begin(Mesh.PRIMITIVE_TRIANGLES)
    var triangle_count := 0

    for row in grid.y - 1:
        for column in grid.x - 1:
            var first := row * grid.x + column
            var right := first + 1
            var down := first + grid.x
            var diagonal := down + 1
            triangle_count += _add_component_triangle(
                tool, network, node_set, [first, down, right],
                grid, center, normal * half_t, plane_mode, false
            )
            triangle_count += _add_component_triangle(
                tool, network, node_set, [right, down, diagonal],
                grid, center, normal * half_t, plane_mode, false
            )
            triangle_count += _add_component_triangle(
                tool, network, node_set, [first, right, down],
                grid, center, -normal * half_t, plane_mode, true
            )
            triangle_count += _add_component_triangle(
                tool, network, node_set, [right, diagonal, down],
                grid, center, -normal * half_t, plane_mode, true
            )

    var hull_value: Variant = spec.get("hull", PackedVector2Array())
    if hull_value is PackedVector2Array:
        var hull := hull_value as PackedVector2Array
        if hull.size() >= 3:
            var mean_damage := 0.0
            for value in component:
                mean_damage += float(network.get_node_damage(int(value)))
            mean_damage /= maxf(float(component.size()), 1.0)
            for index in hull.size():
                var next := (index + 1) % hull.size()
                var front_a := _hull_point(hull[index], half_t, plane_mode)
                var front_b := _hull_point(hull[next], half_t, plane_mode)
                var back_a := _hull_point(hull[index], -half_t, plane_mode)
                var back_b := _hull_point(hull[next], -half_t, plane_mode)
                var packed := Color(mean_damage, mean_damage * 0.45, 0.0, 1.0)
                _add_raw_triangle(tool, front_a, back_a, front_b, packed)
                _add_raw_triangle(tool, front_b, back_a, back_b, packed)
                triangle_count += 2

    if triangle_count <= 0:
        return null
    tool.generate_normals()
    return tool.commit()

func _add_component_triangle(
        tool: SurfaceTool,
        network,
        node_set: Dictionary,
        indices: Array,
        grid: Vector2i,
        center: Vector3,
        offset: Vector3,
        plane_mode: int,
        reverse: bool
) -> int:
    for raw_index in indices:
        if not node_set.has(int(raw_index)):
            return 0
    var order := [0, 1, 2]
    if reverse:
        order = [0, 2, 1]
    for local_index in order:
        var node_index := int(indices[local_index])
        var position := _map_position(
            network.get_node_position(node_index),
            plane_mode
        ) - center + offset
        var row := node_index / grid.x
        var column := node_index % grid.x
        tool.set_uv(Vector2(
            float(column) / float(grid.x - 1),
            float(row) / float(grid.y - 1)
        ))
        tool.set_color(_solver_color(network, node_index))
        tool.add_vertex(position)
    return 1

func _add_raw_triangle(
        tool: SurfaceTool,
        first: Vector3,
        second: Vector3,
        third: Vector3,
        packed: Color
) -> void:
    for vertex in [first, second, third]:
        tool.set_uv(Vector2(vertex.x, vertex.z))
        tool.set_color(packed)
        tool.add_vertex(vertex)

func _solver_color(network, index: int) -> Color:
    var damage := float(network.get_node_damage(index))
    var heat := damage
    var load := 0.0
    if network.has_method("get_node_heat"):
        heat = float(network.get_node_heat(index))
    if network.has_method("get_node_load"):
        load = float(network.get_node_load(index))
    return Color(damage, heat, load, 1.0)

func _map_position(source: Vector3, plane_mode: int) -> Vector3:
    if plane_mode == 1:
        return Vector3(source.x, source.z, source.y)
    return source

func _hull_point(point: Vector2, depth: float, plane_mode: int) -> Vector3:
    if plane_mode == 1:
        return Vector3(point.x, point.y, depth)
    return Vector3(point.x, depth, point.y)

func _default_normal(plane_mode: int) -> Vector3:
    if plane_mode == 1:
        return Vector3(0.0, 0.0, -1.0)
    return Vector3.UP
