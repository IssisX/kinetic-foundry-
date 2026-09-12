extends Node3D

const GeomUtil = preload("res://scripts/geom.gd")
const PhysicsPropScript = preload("res://scripts/physics_prop.gd")

func _ready() -> void:
    name = "ScaffoldAndScrap"
    _build_scaffold()
    _build_scrap()
    _build_micro_detail()

func _build_scaffold() -> void:
    var base := Vector3(-13.0, 0.0, -8.0)
    for x in [-3.0, 0.0, 3.0]:
        for z in [-1.65, 1.65]:
            GeomUtil.static_box(self, "ScaffoldPost", base + Vector3(x, 2.7, z), Vector3(0.20, 5.4, 0.20), Color(0.44, 0.38, 0.18))
    for level in [1.55, 3.15, 4.75]:
        GeomUtil.static_box(self, "ScaffoldDeck", base + Vector3(0.0, level, 0.0), Vector3(6.6, 0.16, 3.5), Color(0.22, 0.23, 0.21))
        for z in [-1.68, 1.68]:
            var rail := GeomUtil.box_mesh(Vector3(6.4, 0.10, 0.10), Color(0.70, 0.48, 0.08), 0.80, 0.20)
            rail.position = base + Vector3(0.0, level + 0.80, z)
            add_child(rail)
    for bay in 2:
        for sign in [-1.0, 1.0]:
            var brace := GeomUtil.box_mesh(Vector3(0.16, 3.7, 0.16), Color(0.36, 0.31, 0.16), 0.82, 0.24)
            brace.position = base + Vector3(-1.5 + float(bay) * 3.0, 2.8, sign * 1.68)
            brace.rotation.z = 0.67 if sign > 0.0 else -0.67
            add_child(brace)
    for rung_i in 9:
        var rung := GeomUtil.box_mesh(Vector3(0.72, 0.06, 0.09), Color(0.48, 0.48, 0.43), 0.78, 0.24)
        rung.position = base + Vector3(3.18, 0.45 + float(rung_i) * 0.52, -1.62)
        add_child(rung)

func _build_scrap() -> void:
    var positions := [
        Vector3(16.0, 0.30, 16.0),
        Vector3(18.0, 0.52, 15.4),
        Vector3(20.0, 0.34, 16.8),
        Vector3(17.4, 0.28, 18.0),
        Vector3(20.3, 0.60, 18.2)
    ]
    for i in positions.size():
        var prop := PhysicsPropScript.new()
        prop.position = positions[i]
        prop.rotation.y = float(i) * 0.43
        add_child(prop)
        var size := Vector3(2.2 + float(i % 2) * 1.1, 0.28 + float(i % 3) * 0.12, 0.30 + float((i + 1) % 2) * 0.35)
        prop.configure_box(size, Color(0.22, 0.23, 0.20), 80.0 + i * 24.0, 90.0)

func _build_micro_detail() -> void:
    for i in 10:
        var pallet := Node3D.new()
        pallet.position = Vector3(-21.0 + float((i * 7) % 38), 0.10, -14.0 + float((i * 11) % 28))
        pallet.rotation.y = float(i) * 0.39
        add_child(pallet)
        for slat in 4:
            var board := GeomUtil.box_mesh(Vector3(1.65, 0.08, 0.22), Color(0.24, 0.16, 0.08), 0.96, 0.0)
            board.position = Vector3(0.0, 0.0, -0.55 + float(slat) * 0.37)
            pallet.add_child(board)
    for i in 10:
        var cone := GeomUtil.cylinder_mesh(0.18, 0.52, Color(0.86, 0.31, 0.04), 0.86, 0.02)
        cone.position = Vector3(-16.0 + float(i) * 3.1, 0.26, 20.0 + sin(float(i)) * 1.1)
        add_child(cone)
