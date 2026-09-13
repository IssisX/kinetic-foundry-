class_name FidelityCrackOverlay3D
extends MeshInstance3D

## Read-only crack projection from the same bonds as the fracture solver. F2+
## also resolves tensile constraint/opening, so cracks widen because the solved
## plate is separating rather than because a cosmetic timer advanced.

var _seen_revision := -1
var _seen_fidelity := -1
var _material: StandardMaterial3D

func _ready() -> void:
    name = "FidelityCracks"
    _material = StandardMaterial3D.new()
    _material.albedo_color = Color(0.055, 0.025, 0.012)
    _material.roughness = 0.96
    _material.emission_enabled = true
    _material.emission = Color(0.31, 0.055, 0.008)
    _material.emission_energy_multiplier = 0.55
    _material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
    material_override = _material
    set_process(true)

func _process(_delta: float) -> void:
    var skin := get_parent()
    if skin == null:
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
    _rebuild(network, int(skin.get("plane_mode")))

func _rebuild(network, plane_mode: int) -> void:
    var threshold := Fidelity.ribbon_damage()
    var vertices := PackedVector3Array()
    var colors := PackedColorArray()
    var indices := PackedInt32Array()
    var total_mass := maxf(float(network.get("total_mass")), 0.1)
    for bond in network.get_bond_visuals():
        var damage := float(bond.damage)
        var opening := float(bond.get("opening", 0.0))
        var lambda_mag := float(bond.get("lambda", 0.0))
        var lambda_signal := clampf(
            1.0 - exp(-lambda_mag / maxf(total_mass * 0.002, 0.001)),
            0.0,
            1.0
        )
        var tensile_visible := (
            Fidelity.f >= 2
            and opening > 0.0015
            and lambda_signal > 0.035
        )
        if bool(bond.active) and damage < threshold and not tensile_visible:
            continue
        var first := _map_position(
            network.get_node_position(int(bond.a)),
            plane_mode
        )
        var second := _map_position(
            network.get_node_position(int(bond.b)),
            plane_mode
        )
        var segment := second - first
        if segment.length_squared() < 0.000001:
            continue
        var tangent := segment.normalized()
        var normal := (
            Vector3(0.0, 0.0, -1.0)
            if plane_mode == 1
            else Vector3.UP
        )
        var crack_axis := normal.cross(tangent).normalized()
        if crack_axis.length_squared() < 0.0001:
            crack_axis = Vector3.RIGHT
        var midpoint := (first + second) * 0.5 + normal * 0.020
        var half_length := first.distance_to(second) * (
            0.16 + damage * 0.18 + lambda_signal * 0.08
        )
        var half_width := (
            0.010
            + damage * 0.022
            + minf(opening * 0.40, 0.055)
            + lambda_signal * 0.018
        )
        var base := vertices.size()
        vertices.append(midpoint - crack_axis * half_length - tangent * half_width)
        vertices.append(midpoint + crack_axis * half_length - tangent * half_width)
        vertices.append(midpoint + crack_axis * half_length + tangent * half_width)
        vertices.append(midpoint - crack_axis * half_length + tangent * half_width)
        for local_index in [0, 1, 2, 0, 2, 3]:
            indices.append(base + local_index)
        var signal := maxf(damage, lambda_signal)
        var color := Color(0.11, 0.025, 0.008).lerp(
            Color(1.0, 0.19, 0.018),
            signal * 0.48
        )
        for _i in 4:
            colors.append(color)
    if vertices.is_empty():
        mesh = null
        return
    var arrays := []
    arrays.resize(Mesh.ARRAY_MAX)
    arrays[Mesh.ARRAY_VERTEX] = vertices
    arrays[Mesh.ARRAY_COLOR] = colors
    arrays[Mesh.ARRAY_INDEX] = indices
    var new_mesh := ArrayMesh.new()
    new_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
    mesh = new_mesh

func _map_position(source: Vector3, plane_mode: int) -> Vector3:
    if plane_mode == 1:
        return Vector3(source.x, source.z, source.y)
    return source
