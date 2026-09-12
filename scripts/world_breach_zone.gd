extends Node3D

const GeomUtil = preload("res://scripts/geom.gd")
const BreakableGateScript = preload("res://scripts/breakable_gate.gd")

func _ready() -> void:
    name = "BreachLane"
    var gate := BreakableGateScript.new()
    gate.position = Vector3(0.0, 0.0, 23.5)
    add_child(gate)
    for x in [-5.4, 5.4]:
        GeomUtil.static_box(self, "BreachWall", Vector3(x, 2.6, 23.5), Vector3(2.0, 5.2, 0.75), Color(0.16, 0.17, 0.16))
    for stripe_i in 8:
        var marker := GeomUtil.box_mesh(Vector3(0.45, 0.02, 1.6), Color(0.80, 0.55, 0.09), 0.88, 0.04)
        marker.position = Vector3(-3.5 + float(stripe_i), 0.025, 20.5)
        marker.rotation.y = -0.45
        add_child(marker)
    for side in [-1.0, 1.0]:
        var tower := Node3D.new()
        tower.position = Vector3(side * 7.2, 0.0, 23.5)
        add_child(tower)
        GeomUtil.static_box(tower, "ControlPost", Vector3(0.0, 1.45, 0.0), Vector3(1.3, 2.9, 1.1), Color(0.20, 0.21, 0.19))
        var screen := GeomUtil.box_mesh(Vector3(0.72, 0.46, 0.035), Color(0.15, 0.37, 0.34), 0.28, 0.22)
        screen.material_override = GeomUtil.emissive_material(Color(0.09, 0.30, 0.26), 1.8, 0.26, 0.16)
        screen.position = Vector3(0.0, 1.65, -0.57)
        tower.add_child(screen)
