extends Node3D

const GeomUtil = preload("res://scripts/geom.gd")
const PhysicsPropScript = preload("res://scripts/physics_prop.gd")

func _ready() -> void:
    _build_ground()
    _build_perimeter()
    _build_warehouse()
    _build_cargo_lane()
    _build_gantry()
    _build_pipe_rack()
    _build_catwalk_tower()
    _build_barriers()
    _build_ground_markings()
    _build_forklift()
    _build_loose_props()
    _build_work_lights()

func _build_ground() -> void:
    GeomUtil.static_box(
        self,
        "Ground",
        Vector3(0.0, -0.50, 0.0),
        Vector3(72.0, 1.0, 72.0),
        Color(0.078, 0.084, 0.082)
    )
    for i in 9:
        var patch := GeomUtil.box_mesh(
            Vector3(4.5 + float(i % 3), 0.012, 2.2 + float(i % 4) * 0.6),
            Color(0.055 + float(i % 2) * 0.014, 0.061, 0.060),
            0.96,
            0.02
        )
        patch.position = Vector3(
            -19.0 + float((i * 7) % 37),
            0.012,
            -18.0 + float((i * 11) % 33)
        )
        patch.rotation.y = float(i) * 0.37
        add_child(patch)

func _build_perimeter() -> void:
    for x in [-26.0, 26.0]:
        GeomUtil.static_box(
            self,
            "PerimeterWall",
            Vector3(x, 4.0, 0.0),
            Vector3(1.0, 8.0, 64.0),
            Color(0.13, 0.14, 0.135)
        )
        for z in range(-27, 28, 5):
            GeomUtil.static_box(
                self,
                "WallButtress",
                Vector3(x - sign(x) * 0.55, 2.0, float(z)),
                Vector3(0.50, 4.0, 0.72),
                Color(0.20, 0.205, 0.19)
            )
    GeomUtil.static_box(
        self,
        "NorthWall",
        Vector3(0.0, 4.0, 28.0),
        Vector3(52.0, 8.0, 1.0),
        Color(0.13, 0.14, 0.135)
    )

func _build_warehouse() -> void:
    GeomUtil.static_box(
        self,
        "WarehouseMass",
        Vector3(0.0, 6.0, -27.0),
        Vector3(34.0, 12.0, 7.0),
        Color(0.115, 0.125, 0.12)
    )
    GeomUtil.static_box(
        self,
        "WarehouseRoofLip",
        Vector3(0.0, 12.15, -25.0),
        Vector3(35.0, 0.45, 3.4),
        Color(0.20, 0.205, 0.19)
    )
    for bay in 5:
        var x := -12.0 + float(bay) * 6.0
        var door := GeomUtil.box_mesh(
            Vector3(4.65, 4.15, 0.18),
            Color(0.17, 0.18, 0.17),
            0.86,
            0.18
        )
        door.position = Vector3(x, 2.15, -23.42)
        add_child(door)
        for slat in 6:
            var line := GeomUtil.box_mesh(
                Vector3(4.45, 0.045, 0.025),
                Color(0.32, 0.31, 0.27),
                0.68,
                0.12
            )
            line.position = Vector3(x, 0.62 + float(slat) * 0.63, -23.30)
            add_child(line)
        var bay_light := OmniLight3D.new()
        bay_light.position = Vector3(x, 5.3, -22.9)
        bay_light.light_color = Color(1.0, 0.66, 0.30)
        bay_light.light_energy = 2.1
        bay_light.omni_range = 7.0
        add_child(bay_light)

    for window_i in 6:
        var window := GeomUtil.box_mesh(
            Vector3(2.4, 0.65, 0.08),
            Color(0.20, 0.31, 0.31),
            0.24,
            0.34
        )
        window.material_override = GeomUtil.emissive_material(
            Color(0.12, 0.22, 0.20),
            1.25,
            0.32,
            0.20
        )
        window.position = Vector3(-13.5 + float(window_i) * 5.4, 8.2, -23.38)
        add_child(window)

    for vent_i in 3:
        var vent := GeomUtil.cylinder_mesh(
            0.62,
            2.0,
            Color(0.18, 0.19, 0.18),
            0.82,
            0.35
        )
        vent.position = Vector3(-8.0 + float(vent_i) * 8.0, 13.0, -27.0)
        add_child(vent)

func _build_cargo_lane() -> void:
    var cargo_colors := [
        Color(0.20, 0.24, 0.22),
        Color(0.30, 0.17, 0.09),
        Color(0.14, 0.22, 0.24),
        Color(0.28, 0.24, 0.12)
    ]
    for i in 8:
        var x := -18.0 + float(i % 4) * 6.0
        var z := -19.0 + float(i / 4) * 7.0
        var body := GeomUtil.static_box(
            self,
            "Cargo_%d" % i,
            Vector3(x, 1.1, z),
            Vector3(4.4, 2.2, 2.4),
            cargo_colors[i % cargo_colors.size()]
        )
        for rib_i in 5:
            var rib := GeomUtil.box_mesh(
                Vector3(0.055, 1.82, 2.43),
                Color(0.055, 0.06, 0.055),
                0.84,
                0.16
            )
            rib.position.x = -1.76 + float(rib_i) * 0.88
            body.add_child(rib)
        var label_plate := GeomUtil.box_mesh(
            Vector3(1.15, 0.34, 0.035),
            Color(0.60, 0.53, 0.30),
            0.72,
            0.05
        )
        label_plate.position = Vector3(0.92, 0.32, 1.23)
        body.add_child(label_plate)

func _build_gantry() -> void:
    for x in [-10.5, 10.5]:
        GeomUtil.static_box(
            self,
            "GantryColumn",
            Vector3(x, 3.6, -5.0),
            Vector3(0.78, 7.2, 0.78),
            Color(0.25, 0.255, 0.23)
        )
        GeomUtil.static_box(
            self,
            "GantryFoot",
            Vector3(x, 0.30, -5.0),
            Vector3(1.9, 0.60, 1.9),
            Color(0.19, 0.195, 0.18)
        )
    GeomUtil.static_box(
        self,
        "GantryTop",
        Vector3(0.0, 7.0, -5.0),
        Vector3(22.0, 0.72, 0.82),
        Color(0.29, 0.285, 0.23)
    )
    for x in [-7.0, -3.5, 0.0, 3.5, 7.0]:
        var brace := GeomUtil.box_mesh(
            Vector3(0.20, 2.0, 0.24),
            Color(0.58, 0.37, 0.06),
            0.77,
            0.18
        )
        brace.position = Vector3(x, 6.25, -5.0)
        brace.rotation.z = 0.72 if int(x * 10.0) % 2 == 0 else -0.72
        add_child(brace)

func _build_pipe_rack() -> void:
    for z in [-12.0, 0.0, 12.0]:
        for x in [-21.0, -16.5]:
            GeomUtil.static_box(
                self,
                "PipeRackPost",
                Vector3(x, 2.4, z),
                Vector3(0.36, 4.8, 0.36),
                Color(0.19, 0.195, 0.18)
            )
        GeomUtil.static_box(
            self,
            "PipeRackBeam",
            Vector3(-18.75, 4.45, z),
            Vector3(5.0, 0.30, 0.36),
            Color(0.24, 0.245, 0.22)
        )

    var pipe_colors := [
        Color(0.36, 0.18, 0.07),
        Color(0.18, 0.28, 0.30),
        Color(0.31, 0.29, 0.18)
    ]
    for pipe_i in 3:
        var pipe := GeomUtil.cylinder_mesh(
            0.18 + float(pipe_i) * 0.03,
            25.0,
            pipe_colors[pipe_i],
            0.74,
            0.24
        )
        pipe.rotation.x = PI * 0.5
        pipe.position = Vector3(-18.75 + float(pipe_i) * 0.65, 3.0 + float(pipe_i) * 0.60, 0.0)
        add_child(pipe)

func _build_catwalk_tower() -> void:
    var base := Vector3(17.5, 0.0, 8.0)
    for x in [-2.2, 2.2]:
        for z in [-1.8, 1.8]:
            GeomUtil.static_box(
                self,
                "TowerPost",
                base + Vector3(x, 3.2, z),
                Vector3(0.36, 6.4, 0.36),
                Color(0.24, 0.245, 0.22)
            )
    GeomUtil.static_box(
        self,
        "TowerDeck",
        base + Vector3(0.0, 5.6, 0.0),
        Vector3(5.3, 0.34, 4.5),
        Color(0.22, 0.225, 0.205)
    )
    for z in [-2.1, 2.1]:
        var rail := GeomUtil.box_mesh(
            Vector3(5.2, 0.14, 0.14),
            Color(0.72, 0.47, 0.08),
            0.74,
            0.12
        )
        rail.position = base + Vector3(0.0, 6.45, z)
        add_child(rail)
    for rung_i in 9:
        var rung := GeomUtil.box_mesh(
            Vector3(0.78, 0.08, 0.10),
            Color(0.47, 0.48, 0.43),
            0.72,
            0.20
        )
        rung.position = base + Vector3(-2.52, 0.55 + float(rung_i) * 0.56, -1.55)
        add_child(rung)

func _build_barriers() -> void:
    for i in 6:
        var x := -11.0 + float(i) * 2.1
        var barrier := GeomUtil.static_box(
            self,
            "Barrier_%d" % i,
            Vector3(x, 0.48, 18.0),
            Vector3(1.7, 0.96, 0.52),
            Color(0.42, 0.31, 0.10)
        )
        var stripe := GeomUtil.box_mesh(
            Vector3(1.72, 0.17, 0.03),
            Color(0.82, 0.68, 0.23),
            0.70,
            0.06
        )
        stripe.position = Vector3(0.0, 0.13, -0.275)
        barrier.add_child(stripe)

    for i in 7:
        var bollard := GeomUtil.cylinder_mesh(
            0.15,
            0.95,
            Color(0.72, 0.43, 0.055),
            0.82,
            0.08
        )
        bollard.position = Vector3(10.5 + float(i) * 1.25, 0.47, 15.0)
        add_child(bollard)

func _build_ground_markings() -> void:
    for lane_i in 12:
        var stripe := GeomUtil.box_mesh(
            Vector3(0.16, 0.018, 2.4),
            Color(0.70, 0.57, 0.20),
            0.92,
            0.0
        )
        stripe.position = Vector3(-6.0, 0.022, -14.0 + float(lane_i) * 3.0)
        add_child(stripe)
    for cross_i in 7:
        var cross := GeomUtil.box_mesh(
            Vector3(1.6, 0.019, 0.28),
            Color(0.70, 0.57, 0.20),
            0.92,
            0.0
        )
        cross.position = Vector3(-15.0 + float(cross_i) * 2.0, 0.023, 12.5)
        add_child(cross)

func _build_forklift() -> void:
    var root := Node3D.new()
    root.name = "ParkedForklift"
    root.position = Vector3(14.0, 0.0, -2.0)
    root.rotation.y = -0.46
    add_child(root)
    var body := GeomUtil.box_mesh(
        Vector3(1.55, 1.05, 2.35),
        Color(0.72, 0.42, 0.045),
        0.70,
        0.14
    )
    body.position.y = 0.82
    root.add_child(body)
    var counter := GeomUtil.box_mesh(
        Vector3(1.58, 1.20, 0.78),
        Color(0.59, 0.31, 0.035),
        0.75,
        0.16
    )
    counter.position = Vector3(0.0, 1.0, 0.88)
    root.add_child(counter)
    for side in [-1.0, 1.0]:
        for z in [-0.75, 0.78]:
            var wheel := GeomUtil.cylinder_mesh(
                0.37,
                0.28,
                Color(0.045, 0.05, 0.045),
                0.98,
                0.12
            )
            wheel.rotation.z = PI * 0.5
            wheel.position = Vector3(side * 0.82, 0.38, z)
            root.add_child(wheel)
    for side in [-0.52, 0.52]:
        var mast := GeomUtil.box_mesh(
            Vector3(0.16, 2.75, 0.18),
            Color(0.12, 0.13, 0.12),
            0.88,
            0.25
        )
        mast.position = Vector3(side, 1.85, -1.18)
        root.add_child(mast)
        var fork := GeomUtil.box_mesh(
            Vector3(0.16, 0.10, 1.55),
            Color(0.17, 0.18, 0.16),
            0.90,
            0.34
        )
        fork.position = Vector3(side, 0.23, -1.90)
        root.add_child(fork)

func _build_loose_props() -> void:
    _spawn_barrel(Vector3(-4.0, 0.60, -9.5), Color(0.42, 0.18, 0.06))
    _spawn_barrel(Vector3(-3.0, 0.60, -9.0), Color(0.16, 0.30, 0.31))
    _spawn_barrel(Vector3(-2.2, 0.60, -9.8), Color(0.34, 0.30, 0.12))
    _spawn_barrel(Vector3(9.0, 0.60, 4.5), Color(0.42, 0.18, 0.06))
    _spawn_barrel(Vector3(9.8, 0.60, 5.0), Color(0.16, 0.30, 0.31))

    _spawn_box_prop(Vector3(-10.5, 0.55, 5.0), Vector3(1.1, 1.1, 1.1), Color(0.25, 0.19, 0.10), 55.0)
    _spawn_box_prop(Vector3(-9.1, 0.42, 5.2), Vector3(0.84, 0.84, 0.84), Color(0.23, 0.17, 0.09), 38.0)
    _spawn_box_prop(Vector3(6.5, 0.38, 11.5), Vector3(2.8, 0.30, 0.32), Color(0.24, 0.25, 0.23), 88.0)
    _spawn_box_prop(Vector3(6.6, 0.72, 11.1), Vector3(2.6, 0.30, 0.32), Color(0.24, 0.25, 0.23), 88.0)

func _spawn_barrel(pos: Vector3, color: Color) -> void:
    var prop := PhysicsPropScript.new()
    prop.position = pos
    add_child(prop)
    prop.configure_barrel(0.38, 1.18, color, 46.0, 54.0)

func _spawn_box_prop(pos: Vector3, size: Vector3, color: Color, mass_value: float) -> void:
    var prop := PhysicsPropScript.new()
    prop.position = pos
    add_child(prop)
    prop.configure_box(size, color, mass_value, 72.0)

func _build_work_lights() -> void:
    _yard_light(Vector3(-14.0, 7.3, 4.0), Color(1.0, 0.60, 0.25), 4.2, 17.0)
    _yard_light(Vector3(3.0, 8.2, -7.0), Color(1.0, 0.69, 0.32), 4.7, 19.0)
    _yard_light(Vector3(17.0, 7.0, 10.0), Color(0.50, 0.68, 0.75), 3.4, 14.0)

func _yard_light(pos: Vector3, color: Color, energy: float, range_value: float) -> void:
    var pole := GeomUtil.cylinder_mesh(
        0.11,
        pos.y,
        Color(0.15, 0.16, 0.15),
        0.82,
        0.28
    )
    pole.position = Vector3(pos.x, pos.y * 0.5, pos.z)
    add_child(pole)
    var head := GeomUtil.box_mesh(
        Vector3(0.72, 0.22, 0.42),
        Color(0.76, 0.66, 0.38),
        0.42,
        0.14
    )
    head.material_override = GeomUtil.emissive_material(color * 0.75, 1.8, 0.35, 0.10)
    head.position = pos
    add_child(head)
    var light := OmniLight3D.new()
    light.position = pos + Vector3(0.0, -0.18, 0.0)
    light.light_color = color
    light.light_energy = energy
    light.omni_range = range_value
    light.shadow_enabled = false
    add_child(light)
