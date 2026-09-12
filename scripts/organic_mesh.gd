extends RefCounted

const GeomUtil = preload("res://scripts/geom.gd")

static func loft_node(rings: Array, color: Color, radial_segments: int = 14, roughness: float = 0.78) -> MeshInstance3D:
    var node := MeshInstance3D.new()
    node.mesh = loft_mesh(rings, radial_segments)
    node.material_override = GeomUtil.material(color, roughness, 0.0)
    return node

static func loft_mesh(rings: Array, radial_segments: int = 14) -> ArrayMesh:
    var st := SurfaceTool.new()
    st.begin(Mesh.PRIMITIVE_TRIANGLES)
    if rings.size() < 2:
        return st.commit()

    var segs := maxi(radial_segments, 8)
    for ring_i in rings.size() - 1:
        var a: Vector3 = rings[ring_i]
        var b: Vector3 = rings[ring_i + 1]
        for seg in segs:
            var next_seg := (seg + 1) % segs
            var angle0 := TAU * float(seg) / float(segs)
            var angle1 := TAU * float(next_seg) / float(segs)
            var p00 := Vector3(cos(angle0) * a.y, a.x, sin(angle0) * a.z)
            var p01 := Vector3(cos(angle1) * a.y, a.x, sin(angle1) * a.z)
            var p10 := Vector3(cos(angle0) * b.y, b.x, sin(angle0) * b.z)
            var p11 := Vector3(cos(angle1) * b.y, b.x, sin(angle1) * b.z)
            _triangle(st, p00, p10, p11)
            _triangle(st, p00, p11, p01)

    var bottom: Vector3 = rings[0]
    var top: Vector3 = rings[rings.size() - 1]
    var bottom_center := Vector3(0.0, bottom.x, 0.0)
    var top_center := Vector3(0.0, top.x, 0.0)
    for seg in segs:
        var next_seg := (seg + 1) % segs
        var a0 := TAU * float(seg) / float(segs)
        var a1 := TAU * float(next_seg) / float(segs)
        var b0 := Vector3(cos(a0) * bottom.y, bottom.x, sin(a0) * bottom.z)
        var b1 := Vector3(cos(a1) * bottom.y, bottom.x, sin(a1) * bottom.z)
        _triangle(st, bottom_center, b1, b0)
        var t0 := Vector3(cos(a0) * top.y, top.x, sin(a0) * top.z)
        var t1 := Vector3(cos(a1) * top.y, top.x, sin(a1) * top.z)
        _triangle(st, top_center, t0, t1)

    st.generate_normals()
    st.index()
    return st.commit()

static func _triangle(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3) -> void:
    st.add_vertex(a)
    st.add_vertex(b)
    st.add_vertex(c)
