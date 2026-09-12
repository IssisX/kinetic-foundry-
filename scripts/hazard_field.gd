extends Node3D

const PressureVentScript = preload("res://scripts/pressure_vent.gd")
const GantryLoadScript = preload("res://scripts/gantry_load.gd")
const GeomUtil = preload("res://scripts/geom.gd")

var rotors: Array[Node3D] = []

func _ready() -> void:
    _spawn_pressure_vent(Vector3(-15.3, 0.0, 5.5), -0.34, 0.0)
    _spawn_pressure_vent(Vector3(7.8, 0.0, -10.8), 2.45, 2.1)
    _build_exhaust_fans()
    _build_gantry_load()

func _spawn_pressure_vent(pos: Vector3, yaw: float, offset: float) -> void:
    var vent := PressureVentScript.new()
    vent.position = pos
    vent.rotation.y = yaw
    add_child(vent)
    vent.configure(offset)

func _build_gantry_load() -> void:
    var load := GantryLoadScript.new()
    load.position = Vector3(0.0, 4.72, -5.0)
    add_child(load)

func _build_exhaust_fans() -> void:
    for i in 3:
        var root := Node3D.new()
        root.position = Vector3(-6.0 + float(i) * 6.0, 9.2, -23.0)
        add_child(root)
        var housing := GeomUtil.cylinder_mesh(0.92, 0.30, Color(0.13, 0.145, 0.14), 0.78, 0.32)
        housing.rotation.x = PI * 0.5
        root.add_child(housing)
        var rotor := Node3D.new()
        rotor.position.z = -0.20
        root.add_child(rotor)
        rotors.append(rotor)
        for blade_i in 5:
            var blade := GeomUtil.box_mesh(Vector3(0.12, 1.10, 0.06), Color(0.28, 0.30, 0.28), 0.70, 0.34)
            blade.position.y = 0.46
            blade.rotation.z = float(blade_i) * TAU / 5.0
            rotor.add_child(blade)
        var hub := GeomUtil.cylinder_mesh(0.18, 0.22, Color(0.42, 0.43, 0.39), 0.60, 0.45)
        hub.rotation.x = PI * 0.5
        rotor.add_child(hub)

func _process(delta: float) -> void:
    for i in rotors.size():
        rotors[i].rotation.z += delta * (2.1 + float(i) * 0.55)
