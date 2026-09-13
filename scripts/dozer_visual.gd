extends RefCounted

const GeomUtil = preload("res://scripts/geom.gd")

const YELLOW := Color(0.82, 0.62, 0.08)
const YELLOW_DARK := Color(0.62, 0.44, 0.05)
const IRON := Color(0.11, 0.12, 0.11)
const STEEL := Color(0.22, 0.23, 0.21)
const GROUSER := Color(0.16, 0.17, 0.155)


static func build(root: Node3D) -> Dictionary:
    var nodes := {}
    var yellow := YELLOW
    var iron := IRON

    for side in [-1.0, 1.0]:
        var track := GeomUtil.box_mesh(Vector3(0.78, 0.92, 4.55), iron, 0.96, 0.22)
        track.position = Vector3(side * 1.52, 0.52, 0.08)
        root.add_child(track)
        for shoe_i in 11:
            var shoe := GeomUtil.box_mesh(Vector3(0.88, 0.10, 0.32), GROUSER, 0.94, 0.30)
            shoe.position = Vector3(side * 1.52, 0.08, -1.95 + float(shoe_i) * 0.40)
            root.add_child(shoe)
        for roller_i in 5:
            var roller := GeomUtil.cylinder_mesh(0.28, 0.62, STEEL, 0.88, 0.36)
            roller.rotation.z = PI * 0.5
            roller.position = Vector3(side * 1.52, 0.46, -1.40 + float(roller_i) * 0.70)
            root.add_child(roller)
        var idler := GeomUtil.cylinder_mesh(0.42, 0.70, STEEL, 0.86, 0.40)
        idler.rotation.z = PI * 0.5
        idler.position = Vector3(side * 1.52, 0.50, -2.18)
        root.add_child(idler)
        var sprocket := GeomUtil.cylinder_mesh(0.46, 0.70, Color(0.18, 0.19, 0.17), 0.84, 0.42)
        sprocket.rotation.z = PI * 0.5
        sprocket.position = Vector3(side * 1.52, 0.54, 2.22)
        root.add_child(sprocket)

    var hull := GeomUtil.box_mesh(Vector3(2.55, 1.18, 3.85), yellow, 0.62, 0.14)
    hull.position = Vector3(0.0, 1.22, 0.12)
    root.add_child(hull)
    var belly := GeomUtil.box_mesh(Vector3(2.20, 0.32, 3.40), iron, 0.90, 0.28)
    belly.position = Vector3(0.0, 0.58, 0.10)
    root.add_child(belly)

    var engine := GeomUtil.box_mesh(Vector3(1.85, 1.05, 1.55), YELLOW_DARK, 0.70, 0.16)
    engine.position = Vector3(0.18, 1.92, 1.05)
    root.add_child(engine)
    nodes.engine_cover = engine
    var stack := GeomUtil.cylinder_mesh(0.11, 1.15, STEEL, 0.72, 0.34)
    stack.position = Vector3(0.62, 2.95, 1.28)
    root.add_child(stack)
    var cap := GeomUtil.cylinder_mesh(0.16, 0.10, iron, 0.80, 0.20)
    cap.position = Vector3(0.62, 3.55, 1.28)
    root.add_child(cap)

    _build_cab(root, nodes)

    var work := GeomUtil.work_spot(
        root,
        Vector3(-0.72, 3.28, -1.05),
        Vector3(-0.72, 1.2, -4.6),
        Color(1.0, 0.78, 0.46),
        5.4,
        12.0,
        36.0,
        false
    )
    nodes.work_light = work

    var blade := Node3D.new()
    blade.name = "Blade"
    blade.position = Vector3(0.0, 1.12, -2.55)
    root.add_child(blade)
    nodes.blade = blade

    var arm_l := GeomUtil.box_mesh(Vector3(0.22, 0.28, 1.55), yellow, 0.68, 0.18)
    arm_l.position = Vector3(-1.42, 0.05, 0.55)
    blade.add_child(arm_l)
    var arm_r := GeomUtil.box_mesh(Vector3(0.22, 0.28, 1.55), yellow, 0.68, 0.18)
    arm_r.position = Vector3(1.42, 0.05, 0.55)
    blade.add_child(arm_r)

    var plate := GeomUtil.box_mesh(Vector3(3.62, 1.22, 0.22), STEEL, 0.88, 0.38)
    plate.position = Vector3(0.0, 0.12, -0.72)
    blade.add_child(plate)
    var lip := GeomUtil.box_mesh(Vector3(3.62, 0.16, 0.38), GROUSER, 0.92, 0.44)
    lip.position = Vector3(0.0, -0.48, -0.88)
    blade.add_child(lip)
    for edge in [-1.0, 1.0]:
        var cheek := GeomUtil.box_mesh(Vector3(0.16, 1.18, 0.55), STEEL, 0.86, 0.36)
        cheek.position = Vector3(edge * 1.78, 0.10, -0.62)
        blade.add_child(cheek)
    for tooth_i in 7:
        var tooth := GeomUtil.box_mesh(Vector3(0.28, 0.14, 0.32), iron, 0.94, 0.48)
        tooth.position = Vector3(-1.50 + float(tooth_i) * 0.50, -0.58, -1.05)
        blade.add_child(tooth)

    var blade_body := CollisionShape3D.new()
    var blade_box := BoxShape3D.new()
    blade_box.size = Vector3(3.70, 1.28, 0.46)
    blade_body.shape = blade_box
    blade_body.position = Vector3(0.0, 0.06, -0.74)
    blade.add_child(blade_body)
    nodes.blade_collision = blade_body
    nodes.blade_probe = _probe(blade, Vector3(3.72, 1.32, 0.58), Vector3(0.0, 0.06, -0.74))

    var ripper := Node3D.new()
    ripper.name = "Ripper"
    ripper.position = Vector3(0.0, 1.05, 2.35)
    root.add_child(ripper)
    nodes.ripper = ripper
    var shank := GeomUtil.box_mesh(Vector3(0.22, 1.35, 0.28), STEEL, 0.82, 0.36)
    shank.position = Vector3(0.0, -0.20, 0.35)
    ripper.add_child(shank)
    var point := GeomUtil.box_mesh(Vector3(0.16, 0.42, 0.42), iron, 0.90, 0.48)
    point.position = Vector3(0.0, -0.92, 0.48)
    point.rotation.x = 0.55
    ripper.add_child(point)
    var ripper_beam := GeomUtil.box_mesh(Vector3(1.15, 0.22, 0.22), yellow, 0.70, 0.18)
    ripper_beam.position = Vector3(0.0, 0.35, 0.05)
    ripper.add_child(ripper_beam)
    nodes.ripper_probe = _probe(ripper, Vector3(0.42, 0.70, 0.55), Vector3(0.0, -0.85, 0.42))

    return nodes


static func _build_cab(root: Node3D, nodes: Dictionary) -> void:
    var frame := Color(0.075, 0.085, 0.080)
    var interior := Color(0.05, 0.055, 0.052)
    var cab_x := -0.55

    var floor := GeomUtil.box_mesh(Vector3(1.42, 0.14, 1.58), frame, 0.86, 0.28)
    floor.position = Vector3(cab_x, 1.72, -0.35)
    root.add_child(floor)
    var roof := GeomUtil.box_mesh(Vector3(1.46, 0.12, 1.62), frame, 0.76, 0.32)
    roof.position = Vector3(cab_x, 3.38, -0.35)
    root.add_child(roof)
    for x in [cab_x - 0.66, cab_x + 0.66]:
        for z in [-1.08, 0.38]:
            var pillar := GeomUtil.box_mesh(Vector3(0.10, 1.55, 0.10), frame, 0.72, 0.38)
            pillar.position = Vector3(x, 2.52, z)
            root.add_child(pillar)
    var back := GeomUtil.box_mesh(Vector3(1.32, 1.05, 0.10), interior, 0.86, 0.18)
    back.position = Vector3(cab_x, 2.28, 0.42)
    root.add_child(back)

    var glass := GeomUtil.glass_material(Color(0.30, 0.58, 0.66, 0.16), 0.10, 0.10)
    var windshield := GeomUtil.box_mesh(Vector3(1.22, 1.28, 0.034), Color.WHITE)
    windshield.material_override = glass
    windshield.position = Vector3(cab_x, 2.58, -1.12)
    root.add_child(windshield)
    for x in [cab_x - 0.70, cab_x + 0.70]:
        var side := GeomUtil.box_mesh(Vector3(0.034, 1.22, 1.28), Color.WHITE)
        side.material_override = glass
        side.position = Vector3(x, 2.56, -0.34)
        root.add_child(side)

    var seat := GeomUtil.box_mesh(Vector3(0.52, 0.16, 0.52), interior, 0.94, 0.0)
    seat.position = Vector3(cab_x, 1.96, -0.18)
    root.add_child(seat)
    var backrest := GeomUtil.box_mesh(Vector3(0.52, 0.62, 0.14), interior, 0.94, 0.0)
    backrest.position = Vector3(cab_x, 2.28, 0.10)
    root.add_child(backrest)
    var dash := GeomUtil.box_mesh(Vector3(1.10, 0.22, 0.28), STEEL, 0.78, 0.16)
    dash.position = Vector3(cab_x, 2.08, -0.88)
    root.add_child(dash)

    var operator_view := Node3D.new()
    operator_view.name = "OperatorView"
    operator_view.position = Vector3(cab_x, 2.72, -0.42)
    operator_view.rotation_degrees = Vector3(-4.0, 0.0, 0.0)
    root.add_child(operator_view)
    nodes.operator_view = operator_view


static func _probe(parent: Node3D, size: Vector3, local_position: Vector3) -> CollisionShape3D:
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
