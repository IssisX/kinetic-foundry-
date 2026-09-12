extends Node3D

const GeomUtil = preload("res://scripts/geom.gd")

func _ready() -> void:
    name = "StorageVessels"
    var base := Vector3(18.0, 0.0, -17.0)
    for i in 3:
        _build_vessel(base + Vector3(float(i) * 4.3, 0.0, float(i % 2) * 1.4), i)
    var header := GeomUtil.cylinder_mesh(0.22, 9.0, Color(0.20, 0.24, 0.23), 0.72, 0.34)
    header.rotation.z = PI * 0.5
    header.position = Vector3(22.2, 1.0, -18.6)
    add_child(header)
    _build_pump_skid(Vector3(21.4, 0.0, -12.8))

func _build_vessel(pos: Vector3, index: int) -> void:
    var root := Node3D.new()
    root.position = pos
    add_child(root)
    var shell := GeomUtil.cylinder_mesh(1.45, 5.2, Color(0.28, 0.30, 0.285), 0.72, 0.34)
    shell.position.y = 2.6
    root.add_child(shell)
    for band_y in [0.85, 2.6, 4.35]:
        var band := GeomUtil.cylinder_mesh(1.50, 0.11, Color(0.12, 0.13, 0.12), 0.80, 0.42)
        band.position.y = band_y
        root.add_child(band)
    var cap := GeomUtil.cylinder_mesh(0.42, 0.45, Color(0.18, 0.19, 0.18), 0.80, 0.32)
    cap.position.y = 5.42
    root.add_child(cap)
    for leg_side in [-0.92, 0.92]:
        var leg := GeomUtil.static_box(root, "VesselLeg", Vector3(leg_side, 0.55, 0.0), Vector3(0.28, 1.1, 0.32), Color(0.16, 0.17, 0.16))
        leg.rotation.z = leg_side * 0.08
    var gauge := GeomUtil.cylinder_mesh(0.20, 0.12, Color(0.78, 0.74, 0.58), 0.36, 0.18)
    gauge.rotation.x = PI * 0.5
    gauge.position = Vector3(-1.47, 2.9, 0.0)
    root.add_child(gauge)
    for rung_i in 9:
        var rung := GeomUtil.box_mesh(Vector3(0.54, 0.055, 0.07), Color(0.34, 0.35, 0.32), 0.82, 0.34)
        rung.position = Vector3(-1.52, 0.72 + float(rung_i) * 0.48, 0.0)
        root.add_child(rung)
    if index == 1:
        var lamp := OmniLight3D.new()
        lamp.position = Vector3(0.0, 5.9, 0.0)
        lamp.light_color = Color(1.0, 0.50, 0.12)
        lamp.light_energy = 2.1
        lamp.omni_range = 6.0
        root.add_child(lamp)

func _build_pump_skid(pos: Vector3) -> void:
    var root := Node3D.new()
    root.position = pos
    add_child(root)
    GeomUtil.static_box(root, "PumpBase", Vector3(0.0, 0.16, 0.0), Vector3(5.2, 0.32, 2.5), Color(0.15, 0.16, 0.15))
    for side in [-1.0, 1.0]:
        var motor := GeomUtil.cylinder_mesh(0.62, 1.8, Color(0.16, 0.27, 0.23), 0.68, 0.26)
        motor.rotation.z = PI * 0.5
        motor.position = Vector3(side * 1.45, 0.75, 0.0)
        root.add_child(motor)
        var shaft := GeomUtil.cylinder_mesh(0.13, 0.85, Color(0.48, 0.49, 0.45), 0.44, 0.62)
        shaft.rotation.z = PI * 0.5
        shaft.position = Vector3(side * 0.47, 0.75, 0.0)
        root.add_child(shaft)
