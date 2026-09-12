extends Node3D

const GeomUtil = preload("res://scripts/geom.gd")

func _ready() -> void:
    name = "UtilityZone"
    _build_transformers()
    _build_pipe_manifold()

func _build_transformers() -> void:
    var base := Vector3(-18.0, 0.0, 16.0)
    for unit_i in 2:
        var unit := Node3D.new()
        unit.position = base + Vector3(float(unit_i) * 5.2, 0.0, 0.0)
        add_child(unit)
        var block := GeomUtil.static_box(unit, "Transformer", Vector3(0.0, 1.4, 0.0), Vector3(3.5, 2.8, 2.5), Color(0.19, 0.23, 0.20))
        for fin_i in 6:
            var fin := GeomUtil.box_mesh(Vector3(0.10, 2.25, 1.85), Color(0.10, 0.12, 0.105), 0.82, 0.24)
            fin.position = Vector3(-1.55 + float(fin_i) * 0.62, 0.0, -1.31)
            block.add_child(fin)
        for bushing_i in 3:
            var x := -0.9 + float(bushing_i) * 0.9
            var stem := GeomUtil.cylinder_mesh(0.13, 0.78, Color(0.30, 0.23, 0.16), 0.46, 0.08)
            stem.position = Vector3(x, 3.20, 0.0)
            unit.add_child(stem)
            for ring_i in 3:
                var ring := GeomUtil.cylinder_mesh(0.22, 0.06, Color(0.42, 0.32, 0.22), 0.48, 0.06)
                ring.position = Vector3(x, 2.92 + float(ring_i) * 0.24, 0.0)
                unit.add_child(ring)
        var warning := GeomUtil.box_mesh(Vector3(0.68, 0.56, 0.04), Color(0.82, 0.63, 0.09), 0.84, 0.02)
        warning.position = Vector3(0.0, 1.55, -1.28)
        unit.add_child(warning)

func _build_pipe_manifold() -> void:
    var base := Vector3(-20.0, 0.0, -2.0)
    for i in 4:
        var y := 0.65 + float(i) * 0.78
        var pipe := GeomUtil.cylinder_mesh(0.14 + float(i) * 0.025, 9.0, Color(0.22 + i * 0.025, 0.24, 0.20), 0.72, 0.30)
        pipe.rotation.x = PI * 0.5
        pipe.position = base + Vector3(float(i) * 0.42, y, 0.0)
        add_child(pipe)
        var valve := Node3D.new()
        valve.position = base + Vector3(float(i) * 0.42, y, 2.2 - float(i) * 1.2)
        add_child(valve)
        var hub := GeomUtil.cylinder_mesh(0.22, 0.16, Color(0.18, 0.19, 0.17), 0.75, 0.30)
        hub.rotation.x = PI * 0.5
        valve.add_child(hub)
        for spoke_i in 6:
            var spoke := GeomUtil.box_mesh(Vector3(0.05, 0.70, 0.05), Color(0.66, 0.24, 0.055), 0.72, 0.20)
            spoke.position.y = 0.30
            spoke.rotation.z = float(spoke_i) * TAU / 6.0
            valve.add_child(spoke)
