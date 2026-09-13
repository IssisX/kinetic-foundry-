class_name DeformationSkin3D
extends Node3D

## Read-only visual projection of a FractureNetwork.
## Collision remains coarse until separation; the rendered sheet, heat tint,
## and crack paths all come directly from solved node and bond state.

const SURFACE_SHADER = preload(
    "res://shaders/foundry_surface.gdshader"
)

const MODE_HORIZONTAL := 0
const MODE_VERTICAL := 1

var network
var plane_mode := MODE_HORIZONTAL
var base_color := Color(0.28, 0.29, 0.27)
var material_id := FoundryMaterial.STRUCTURAL_STEEL
var surface_state: SurfaceState
## The body whose resonance drives shimmer. Not necessarily the same object
## the surface_state is bound to (it usually is), kept separate so a skin
## can shimmer with a body's ring without also inheriting its paint.
var resonance_source: Object
var _surface: MeshInstance3D
var _cracks: MeshInstance3D
var _surface_material: ShaderMaterial
var _crack_material: StandardMaterial3D
var _seen_revision := -1
var _seen_surface_revision := -1


func configure(
        source,
        mode: int,
        color: Color,
        local_offset: Vector3 = Vector3.ZERO,
        identity: int = FoundryMaterial.STRUCTURAL_STEEL
) -> void:
    network = source
    plane_mode = mode
    base_color = color
    material_id = identity
    position = local_offset
    _surface = MeshInstance3D.new()
    _surface.name = "SolvedSurface"
    add_child(_surface)
    _cracks = MeshInstance3D.new()
    _cracks.name = "SolvedCracks"
    add_child(_cracks)

    var data := FoundryMaterial.of(material_id)
    _surface_material = ShaderMaterial.new()
    _surface_material.shader = SURFACE_SHADER
    _surface_material.set_shader_parameter("base_color", color)
    _surface_material.set_shader_parameter(
        "substrate_color",
        data.get("substrate", color)
    )
    _surface_material.set_shader_parameter("oxide_color", data.get("oxide", color))
    _surface_material.set_shader_parameter(
        "metallic_base",
        float(data.get("metallic", 0.34))
    )
    _surface_material.set_shader_parameter(
        "roughness_base",
        float(data.get("roughness", 0.86))
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


func bind_surface_state(state: SurfaceState) -> void:
    surface_state = state
    if state != null:
        material_id = state.material_id
    _seen_surface_revision = -1
    _push_surface_uniforms()


## Defaults to the surface_state's own body the first time it is bound, so
## callers that only ever had one body to give (the common case) do not
## need a second call.
func bind_resonance_source(body: Object) -> void:
    resonance_source = body


func refresh(force: bool = false) -> void:
    if network == null or _surface == null:
        return
    _push_surface_uniforms()
    _push_resonance_uniform()
    var revision: int = network.get_revision()
    if not force and revision == _seen_revision:
        return
    _seen_revision = revision
    _rebuild_surface()
    _rebuild_cracks()


## Unconditional every call: a ringing plate's amplitude changes every
## frame with no new damage/exposure event, so it cannot wait on the
## surface_state revision guard the way paint/oxidation can.
func _push_resonance_uniform() -> void:
    if resonance_source == null or _surface_material == null:
        return
    _surface_material.set_shader_parameter(
        "shimmer_m",
        MaterialResponse.resonance_shimmer(resonance_source)
    )


func _push_surface_uniforms() -> void:
    if surface_state == null or _surface_material == null:
        return
    if surface_state.revision == _seen_surface_revision:
        return
    _seen_surface_revision = surface_state.revision
    _surface_material.set_shader_parameter("exposure_level", surface_state.exposure)
    _surface_material.set_shader_parameter("oxidation_level", surface_state.oxidation)
    _surface_material.set_shader_parameter("film_amount", surface_state.film_amount())
    _surface_material.set_shader_parameter("film_color", surface_state.film_color())
    _surface_material.set_shader_parameter("film_gloss", surface_state.film_gloss())
    _surface_material.set_shader_parameter(
        "thermal_emission",
        surface_state.emission_energy() * 0.35
    )


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
            colors.append(Color(
                clampf(network.get_node_damage(index), 0.0, 1.0),
                clampf(network.get_node_heat(index), 0.0, 1.0),
                clampf(network.get_node_load(index), 0.0, 1.0),
                1.0
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
    var ribbon_threshold := Fidelity.ribbon_damage()
    for bond in network.get_bond_visuals():
        var damage := float(bond.damage)
        if bool(bond.active) and damage < ribbon_threshold:
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
        # Tension pulls a bond apart and shows as an opening. Compression
        # does not: a crushed brace goes plastic, it does not smile.
        var tension := maxf(0.0, -float(bond.get("lambda", 0.0)))
        var opening := tension / (1.0 + tension * 40.0)
        var half_width := 0.010 + damage * 0.022 + opening
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
