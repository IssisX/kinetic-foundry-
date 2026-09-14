extends RefCounted

const GeomUtil = preload("res://scripts/geom.gd")

static func build(root: Node3D) -> Dictionary:
    var nodes := {}
    var arm_shapes: Array[CollisionShape3D] = []

    var undercarriage := GeomUtil.box_mesh(Vector3(3.25, 0.46, 4.45), Color(0.09, 0.095, 0.085), 0.94, 0.18)
    undercarriage.position.y = 0.62
    root.add_child(undercarriage)

    for side in [-1.0, 1.0]:
        var track := GeomUtil.box_mesh(Vector3(0.68, 0.82, 4.55), Color(0.055, 0.06, 0.055), 0.98, 0.22)
        track.position = Vector3(side * 1.43, 0.58, 0.0)
        root.add_child(track)
        for shoe_i in 10:
            var shoe := GeomUtil.box_mesh(Vector3(0.78, 0.08, 0.39), Color(0.17, 0.18, 0.16), 0.94, 0.30)
            shoe.position = Vector3(side * 1.43, 1.02, -1.78 + float(shoe_i) * 0.40)
            root.add_child(shoe)
        for roller_i in 5:
            var roller := GeomUtil.cylinder_mesh(0.32, 0.52, Color(0.12, 0.13, 0.12), 0.90, 0.34)
            roller.rotation.z = PI * 0.5
            roller.position = Vector3(side * 1.43, 0.56, -1.45 + float(roller_i) * 0.72)
            root.add_child(roller)

    var turntable := GeomUtil.cylinder_mesh(1.15, 0.44, Color(0.18, 0.19, 0.17), 0.84, 0.30)
    turntable.position.y = 1.10
    root.add_child(turntable)

    var chassis := GeomUtil.box_mesh(Vector3(2.85, 1.16, 3.30), Color(0.80, 0.47, 0.055), 0.66, 0.16)
    chassis.position = Vector3(0.0, 1.65, -0.05)
    root.add_child(chassis)

    var counterweight := GeomUtil.cylinder_mesh(1.36, 1.34, Color(0.74, 0.40, 0.045), 0.72, 0.18)
    counterweight.scale = Vector3(1.0, 1.0, 0.54)
    counterweight.position = Vector3(0.0, 1.82, 1.42)
    root.add_child(counterweight)

    var engine_cover := GeomUtil.box_mesh(Vector3(1.18, 1.18, 1.65), Color(0.68, 0.37, 0.045), 0.70, 0.14)
    engine_cover.position = Vector3(0.70, 2.15, 0.44)
    root.add_child(engine_cover)
    nodes.engine_cover = engine_cover

    for grille_i in 6:
        var grille := GeomUtil.box_mesh(Vector3(0.035, 0.72, 0.11), Color(0.11, 0.12, 0.105), 0.86, 0.24)
        grille.position = Vector3(1.305, 1.92, -0.30 + float(grille_i) * 0.23)
        root.add_child(grille)

    _build_cab(root, nodes)

    var work_light := GeomUtil.work_spot(
        root,
        Vector3(-0.74, 3.52, -0.72),
        Vector3(-0.74, 1.10, -6.4),
        Color(1.0, 0.78, 0.46),
        7.2,
        16.0,
        36.0,
        false
    )
    nodes.work_light = work_light

    var beacon := GeomUtil.cylinder_mesh(0.12, 0.18, Color(0.98, 0.43, 0.05), 0.34, 0.05)
    beacon.material_override = GeomUtil.emissive_material(Color(0.98, 0.43, 0.05), 2.4, 0.34, 0.05)
    beacon.position = Vector3(-0.70, 3.62, 0.88)
    root.add_child(beacon)

    var boom := Node3D.new()
    boom.position = Vector3(0.62, 2.37, -0.88)
    root.add_child(boom)
    nodes.boom = boom
    var boom_hub := GeomUtil.cylinder_mesh(0.43, 0.72, Color(0.18, 0.19, 0.17), 0.76, 0.42)
    boom_hub.rotation.z = PI * 0.5
    boom.add_child(boom_hub)
    var boom_mesh := GeomUtil.box_mesh(Vector3(0.58, 0.66, 4.72), Color(0.84, 0.49, 0.055), 0.61, 0.14)
    boom_mesh.position.z = -2.15
    boom.add_child(boom_mesh)
    for plate_side in [-1.0, 1.0]:
        var side_plate := GeomUtil.box_mesh(Vector3(0.07, 0.79, 4.48), Color(0.70, 0.38, 0.038), 0.68, 0.24)
        side_plate.position = Vector3(plate_side * 0.31, 0.0, -2.15)
        boom.add_child(side_plate)
    var boom_barrel := GeomUtil.capsule_mesh(0.13, 2.10, Color(0.22, 0.23, 0.21))
    boom_barrel.rotation.x = PI * 0.5
    boom_barrel.position = Vector3(0.42, 0.20, -0.82)
    boom.add_child(boom_barrel)
    var boom_rod := GeomUtil.capsule_mesh(0.075, 2.25, Color(0.74, 0.75, 0.70))
    boom_rod.rotation.x = PI * 0.5
    boom_rod.position = Vector3(0.42, 0.20, -2.45)
    boom.add_child(boom_rod)
    arm_shapes.append(_make_arm_probe(boom, Vector3(0.72, 0.82, 4.55), Vector3(0.0, 0.0, -2.15)))

    var stick := Node3D.new()
    stick.position = Vector3(0.0, 0.0, -4.28)
    boom.add_child(stick)
    nodes.stick = stick
    var stick_hub := GeomUtil.cylinder_mesh(0.35, 0.64, Color(0.18, 0.19, 0.17), 0.76, 0.42)
    stick_hub.rotation.z = PI * 0.5
    stick.add_child(stick_hub)
    var stick_mesh := GeomUtil.box_mesh(Vector3(0.46, 0.54, 3.58), Color(0.84, 0.49, 0.055), 0.61, 0.14)
    stick_mesh.position.z = -1.65
    stick.add_child(stick_mesh)
    var stick_barrel := GeomUtil.capsule_mesh(0.11, 1.62, Color(0.22, 0.23, 0.21))
    stick_barrel.rotation.x = PI * 0.5
    stick_barrel.position = Vector3(-0.34, 0.18, -0.64)
    stick.add_child(stick_barrel)
    var stick_rod := GeomUtil.capsule_mesh(0.065, 1.74, Color(0.74, 0.75, 0.70))
    stick_rod.rotation.x = PI * 0.5
    stick_rod.position = Vector3(-0.34, 0.18, -1.92)
    stick.add_child(stick_rod)
    arm_shapes.append(_make_arm_probe(stick, Vector3(0.60, 0.70, 3.45), Vector3(0.0, 0.0, -1.65)))

    var tool := Node3D.new()
    tool.position = Vector3(0.0, 0.0, -3.28)
    stick.add_child(tool)
    nodes.tool = tool

    var bucket_back := GeomUtil.box_mesh(Vector3(1.86, 0.92, 0.30), Color(0.24, 0.25, 0.225), 0.90, 0.38)
    bucket_back.position = Vector3(0.0, -0.06, -0.22)
    bucket_back.rotation.x = -0.16
    tool.add_child(bucket_back)
    var bucket_floor := GeomUtil.box_mesh(Vector3(1.86, 0.22, 1.18), Color(0.21, 0.22, 0.20), 0.92, 0.42)
    bucket_floor.position = Vector3(0.0, -0.50, -0.62)
    bucket_floor.rotation.x = -0.12
    tool.add_child(bucket_floor)
    for side in [-1.0, 1.0]:
        var cheek := GeomUtil.box_mesh(Vector3(0.12, 1.08, 1.22), Color(0.19, 0.20, 0.18), 0.92, 0.40)
        cheek.position = Vector3(side * 0.88, -0.16, -0.56)
        cheek.rotation.x = -0.10
        tool.add_child(cheek)
    for tooth_i in 5:
        var tooth := GeomUtil.box_mesh(Vector3(0.18, 0.20, 0.58), Color(0.15, 0.16, 0.145), 0.94, 0.46)
        tooth.position = Vector3(-0.72 + float(tooth_i) * 0.36, -0.56, -1.15)
        tooth.rotation.x = -0.28
        tool.add_child(tooth)
    arm_shapes.append(_make_arm_probe(tool, Vector3(1.92, 1.20, 1.48), Vector3(0.0, -0.14, -0.58)))

    var thumb := Node3D.new()
    thumb.position = Vector3(0.0, 0.38, -0.62)
    tool.add_child(thumb)
    nodes.thumb = thumb
    for side in [-0.56, 0.56]:
        var jaw := GeomUtil.box_mesh(Vector3(0.18, 0.18, 1.10), Color(0.15, 0.16, 0.145), 0.90, 0.40)
        jaw.position = Vector3(side, 0.0, -0.45)
        jaw.rotation.x = 0.42
        thumb.add_child(jaw)

    var grip_anchor := Node3D.new()
    grip_anchor.position = Vector3(0.0, -0.10, -0.82)
    tool.add_child(grip_anchor)
    nodes.grip_anchor = grip_anchor

    var impact_probe := Area3D.new()
    impact_probe.collision_layer = 0
    impact_probe.collision_mask = 1 | 4 | 8
    tool.add_child(impact_probe)
    var shape := BoxShape3D.new()
    shape.size = Vector3(2.05, 1.62, 2.00)
    var impact_collision := CollisionShape3D.new()
    impact_collision.shape = shape
    impact_collision.position = Vector3(0.0, -0.10, -0.60)
    impact_probe.add_child(impact_collision)
    nodes.impact_probe = impact_probe
    nodes.arm_shapes = arm_shapes

    return nodes

static func _build_cab(root: Node3D, nodes: Dictionary) -> void:
    var frame_color := Color(0.075, 0.085, 0.080)
    var interior_color := Color(0.055, 0.062, 0.060)
    var steel_color := Color(0.16, 0.17, 0.16)

    var cab_floor := GeomUtil.box_mesh(Vector3(1.50, 0.16, 1.72), frame_color, 0.86, 0.28)
    cab_floor.position = Vector3(-0.66, 1.62, 0.24)
    root.add_child(cab_floor)
    var cab_roof := GeomUtil.box_mesh(Vector3(1.52, 0.15, 1.76), frame_color, 0.76, 0.32)
    cab_roof.position = Vector3(-0.66, 3.45, 0.24)
    root.add_child(cab_roof)

    for x in [-1.36, 0.04]:
        for z in [-0.58, 1.02]:
            var pillar := GeomUtil.box_mesh(Vector3(0.11, 1.78, 0.11), frame_color, 0.72, 0.38)
            pillar.position = Vector3(x, 2.53, z)
            root.add_child(pillar)

    var back_panel := GeomUtil.box_mesh(Vector3(1.40, 1.15, 0.12), interior_color, 0.86, 0.20)
    back_panel.position = Vector3(-0.66, 2.25, 1.00)
    root.add_child(back_panel)

    var windshield := GeomUtil.box_mesh(Vector3(1.27, 1.48, 0.035), Color.WHITE)
    windshield.material_override = GeomUtil.glass_material(Color(0.32, 0.60, 0.68, 0.17), 0.10, 0.10)
    windshield.position = Vector3(-0.66, 2.58, -0.595)
    root.add_child(windshield)

    for x in [-1.375, 0.055]:
        var side_window := GeomUtil.box_mesh(Vector3(0.035, 1.44, 1.36), Color.WHITE)
        side_window.material_override = GeomUtil.glass_material(Color(0.28, 0.56, 0.64, 0.15), 0.11, 0.08)
        side_window.position = Vector3(x, 2.58, 0.22)
        root.add_child(side_window)

    var seat_base := GeomUtil.box_mesh(Vector3(0.58, 0.18, 0.58), interior_color, 0.95, 0.0)
    seat_base.position = Vector3(-0.68, 1.92, 0.46)
    root.add_child(seat_base)
    var seat_back := GeomUtil.box_mesh(Vector3(0.58, 0.72, 0.16), interior_color, 0.94, 0.0)
    seat_back.position = Vector3(-0.68, 2.24, 0.71)
    seat_back.rotation.x = -0.12
    root.add_child(seat_back)

    var dashboard := GeomUtil.box_mesh(Vector3(1.18, 0.28, 0.34), steel_color, 0.78, 0.18)
    dashboard.position = Vector3(-0.66, 2.04, -0.38)
    dashboard.rotation.x = -0.12
    root.add_child(dashboard)
    for i in 4:
        var gauge := GeomUtil.cylinder_mesh(0.075, 0.018, Color(0.08, 0.12, 0.10), 0.32, 0.12)
        gauge.rotation.x = PI * 0.5
        gauge.position = Vector3(-1.03 + float(i) * 0.25, 2.13, -0.545)
        root.add_child(gauge)
        var glow := GeomUtil.sphere_mesh(0.022, Color(0.20, 0.95, 0.45))
        glow.material_override = GeomUtil.emissive_material(Color(0.20, 0.95, 0.45), 1.8, 0.2, 0.0)
        glow.position = gauge.position + Vector3(0.0, 0.0, -0.025)
        root.add_child(glow)

    for side in [-1.0, 1.0]:
        var console := GeomUtil.box_mesh(Vector3(0.22, 0.18, 0.58), interior_color, 0.88, 0.12)
        console.position = Vector3(-0.66 + side * 0.48, 1.97, 0.20)
        root.add_child(console)
        var joystick := GeomUtil.capsule_mesh(0.045, 0.34, Color(0.12, 0.13, 0.12))
        joystick.position = console.position + Vector3(0.0, 0.24, -0.06)
        joystick.rotation.z = side * 0.08
        root.add_child(joystick)

    var operator_view := Node3D.new()
    operator_view.name = "OperatorView"
    operator_view.position = Vector3(-0.66, 2.72, -0.34)
    operator_view.rotation_degrees = Vector3(-5.0, 0.0, 0.0)
    root.add_child(operator_view)
    nodes.operator_view = operator_view

static func _make_arm_probe(parent: Node3D, size: Vector3, local_position: Vector3) -> CollisionShape3D:
    var area := Area3D.new()
    area.collision_layer = 0
    area.collision_mask = 1 | 8
    area.monitoring = false
    area.monitorable = false
    parent.add_child(area)
    var shape := BoxShape3D.new()
    shape.size = size
    var collision := CollisionShape3D.new()
    collision.shape = shape
    collision.position = local_position
    area.add_child(collision)
    return collision
