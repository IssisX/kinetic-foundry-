extends Node3D

const GeomUtil = preload("res://scripts/geom.gd")

func _ready() -> void:
    name = "YardSurface"
    _build_asphalt()
    _build_wear()
    _build_route_language()

func _build_asphalt() -> void:
    var surface := GeomUtil.box_mesh(
        Vector3(51.0, 0.018, 55.0),
        Color(0.145, 0.150, 0.145),
        0.97,
        0.02
    )
    surface.position = Vector3(0.0, 0.012, 0.0)
    add_child(surface)

func _build_wear() -> void:
    for i in 18:
        var sx := 2.2 + float((i * 7) % 5) * 0.72
        var sz := 1.1 + float((i * 11) % 6) * 0.48
        var patch := GeomUtil.box_mesh(
            Vector3(sx, 0.008, sz),
            Color(0.085 + float(i % 3) * 0.012, 0.090, 0.087),
            1.0,
            0.03
        )
        patch.position = Vector3(
            -21.0 + float((i * 13) % 43),
            0.024,
            -22.0 + float((i * 17) % 45)
        )
        patch.rotation.y = float(i) * 0.51
        add_child(patch)

    for i in 10:
        var stain := GeomUtil.cylinder_mesh(
            0.45 + float(i % 4) * 0.24,
            0.006,
            Color(0.045, 0.050, 0.048),
            0.72,
            0.12
        )
        stain.position = Vector3(
            -17.0 + float((i * 9) % 35),
            0.030,
            -17.0 + float((i * 7) % 33)
        )
        stain.scale.x = 1.0 + float(i % 3) * 0.55
        stain.scale.z = 0.62 + float((i + 1) % 3) * 0.31
        add_child(stain)

func _build_route_language() -> void:
    for i in 9:
        var dash := GeomUtil.box_mesh(
            Vector3(0.12, 0.009, 1.55),
            Color(0.78, 0.58, 0.16),
            0.93,
            0.0
        )
        dash.position = Vector3(1.4, 0.034, -14.0 + float(i) * 3.5)
        add_child(dash)

    for i in 7:
        var edge := GeomUtil.box_mesh(
            Vector3(1.1, 0.010, 0.16),
            Color(0.70, 0.22, 0.07),
            0.91,
            0.0
        )
        edge.position = Vector3(-10.5 + float(i) * 1.8, 0.035, 15.7)
        edge.rotation.y = -0.55
        add_child(edge)
