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

    var cab_frame := GeomUtil.box_mesh(Vector3(1.46, 1.90, 1.72), Color(0.085, 0.095, 0.09), 0.56, 0.28)
    cab_frame.position = Vector3(-0.66, 2.48, 0.24)
    root.add_child(cab_frame)

    var windshield := GeomUtil.box_mesh(Vector3(1.08, 1.34, 0.055), Color(0.10, 0.20, 0.22), 0.22, 0.40)
    windshield.position = Vector3(-0.66, 2.53, -0.65)
    root.add_child(windshield)
    var side_window := GeomUtil.box_mesh(Vector3(0.055, 1.28, 1.04), Color(0.10, 0.20, 0.22), 0.22, 0.40)
    side_window.position = Vector3(-1.42, 2.54, 0.08)
    root.add_child(side_window)

    var work_light := OmniLight3D.new()
    work_light.position = Vector3(-0.74, 3.47, -0.66)
    work_light.light_color = Color(1.0, 0.72, 0.38)
    work_light.light_energy = 1.8
    work_light.omni_range = 7.5
    root.add_child(work_light)
    nodes.work_light = work_light

    var beacon := GeomUtil.cylinder_mesh(0.12, 0.18, Color(0.98, 0.43, 0.05), 0.34, 0.05)
    beacon.material_override = GeomUtil.emissive_material(Color(0.98, 0.43, 0.05), 2.4, 0.34, 0.05)
    beacon.position = Vector3(-0.70, 3.52, 0.88)
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
    impact_probe.collision_mask = 4 | 8
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

static func _make_arm_probe(parent: Node3D, size: Vector3, local_position: Vector3) -> CollisionShape3D:
    var area := Area3D.new()
    area.collision_layer = 0
    area.collision_mask = 8
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
