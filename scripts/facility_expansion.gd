extends Node3D

const GeomUtil = preload("res://scripts/geom.gd")

var _carts: Array[AnimatableBody3D] = []
var _cart_phase: Array[float] = []
var _yard: Node3D
var _time := 0.0

func configure(yard: Node3D) -> void:
    _yard = yard
    _remove_cramped_perimeter()
    _build_expanded_floor()
    _build_daylight_canopy()
    _build_distant_industry()
    _build_service_traffic()
    set_physics_process(true)

func _remove_cramped_perimeter() -> void:
    if _yard == null:
        return
    var stack: Array[Node] = [_yard]
    while not stack.is_empty():
        var node := stack.pop_back()
        for child in node.get_children():
            stack.append(child)
        if node == _yard:
            continue
        var n := str(node.name)
        if n.begins_with("PerimeterWall") or n.begins_with("WallButtress") or n.begins_with("NorthWall"):
            node.queue_free()

func _build_expanded_floor() -> void:
    GeomUtil.static_box(
        self,
        "ExpandedFoundryFloor",
        Vector3(0.0, -0.56, 1.0),
        Vector3(124.0, 1.10, 112.0),
        Color(0.105, 0.112, 0.108)
    )

    for lane in [-28.0, 28.0]:
        for z_i in 18:
            var dash := GeomUtil.box_mesh(Vector3(0.16, 0.018, 2.4), Color(0.82, 0.66, 0.16), 0.94, 0.0)
            dash.position = Vector3(lane, 0.014, -48.0 + float(z_i) * 5.8)
            add_child(dash)

    for x in [-57.0, 57.0]:
        for z in range(-48, 49, 8):
            var barrier := GeomUtil.static_box(
                self,
                "OuterBarrier",
                Vector3(x, 0.55, float(z)),
                Vector3(0.55, 1.10, 5.4),
                Color(0.24, 0.25, 0.23)
            )
            var marker := GeomUtil.box_mesh(Vector3(0.03, 0.22, 4.7), Color(0.86, 0.52, 0.08), 0.74, 0.04)
            marker.position = Vector3(-sign(x) * 0.29, 0.08, 0.0)
            barrier.add_child(marker)

func _build_daylight_canopy() -> void:
    var steel := Color(0.26, 0.285, 0.29)
    var dark_steel := Color(0.12, 0.14, 0.145)
    var roof_y := 20.5

    for x in [-50.0, 50.0]:
        for z in [-44.0, -22.0, 0.0, 22.0, 44.0]:
            GeomUtil.static_box(self, "CanopyColumn", Vector3(x, 10.0, z), Vector3(0.75, 20.0, 0.75), dark_steel)
            var foot := GeomUtil.box_mesh(Vector3(2.3, 0.45, 2.3), Color(0.18, 0.19, 0.18), 0.86, 0.22)
            foot.position = Vector3(x, 0.22, z)
            add_child(foot)

    for z in [-44.0, -22.0, 0.0, 22.0, 44.0]:
        var cross := GeomUtil.box_mesh(Vector3(101.0, 0.48, 0.52), steel, 0.66, 0.34)
        cross.position = Vector3(0.0, roof_y, z)
        add_child(cross)
        for x in range(-45, 46, 10):
            var brace := GeomUtil.box_mesh(Vector3(0.22, 3.4, 0.24), Color(0.52, 0.54, 0.50), 0.68, 0.24)
            brace.position = Vector3(float(x), roof_y - 1.15, z)
            brace.rotation.z = 0.72 if (x / 10) % 2 == 0 else -0.72
            add_child(brace)

    for x in [-40.0, -20.0, 0.0, 20.0, 40.0]:
        var long_beam := GeomUtil.box_mesh(Vector3(0.42, 0.42, 92.0), steel, 0.66, 0.34)
        long_beam.position = Vector3(x, roof_y + 0.05, 0.0)
        add_child(long_beam)

    var glass := GeomUtil.glass_material(Color(0.50, 0.76, 0.94, 0.115), 0.08, 0.04)
    for xi in 5:
        for zi in 5:
            if xi == 2 and zi == 2:
                continue
            var pane := GeomUtil.box_mesh(Vector3(18.4, 0.035, 17.0), Color.WHITE)
            pane.material_override = glass
            pane.position = Vector3(-40.0 + float(xi) * 20.0, roof_y + 0.28, -36.0 + float(zi) * 18.0)
            add_child(pane)

    var skylight_ring := GeomUtil.box_mesh(Vector3(20.0, 0.24, 0.32), Color(0.68, 0.69, 0.65), 0.54, 0.40)
    skylight_ring.position = Vector3(0.0, roof_y + 0.22, -9.0)
    add_child(skylight_ring)
    var skylight_ring_2 := skylight_ring.duplicate() as MeshInstance3D
    skylight_ring_2.position.z = 9.0
    add_child(skylight_ring_2)

func _build_distant_industry() -> void:
    var colors := [Color(0.18, 0.20, 0.20), Color(0.22, 0.21, 0.18), Color(0.15, 0.19, 0.21)]
    for i in 9:
        var x := -48.0 + float(i) * 12.0
        var h := 5.0 + float((i * 3) % 5) * 1.4
        var building := GeomUtil.box_mesh(Vector3(7.5, h, 5.5), colors[i % colors.size()], 0.82, 0.12)
        building.position = Vector3(x, h * 0.5, -50.0)
        add_child(building)
        for w in 3:
            var window := GeomUtil.box_mesh(Vector3(1.2, 0.42, 0.05), Color(0.62, 0.80, 0.90), 0.20, 0.06)
            window.material_override = GeomUtil.emissive_material(Color(0.36, 0.63, 0.75), 0.55, 0.30, 0.0)
            window.position = building.position + Vector3(-2.2 + float(w) * 2.2, h * 0.12, 2.78)
            add_child(window)

    for x in [-42.0, 43.0]:
        var stack := GeomUtil.cylinder_mesh(1.15, 14.0, Color(0.24, 0.25, 0.24), 0.82, 0.28)
        stack.position = Vector3(x, 7.0, -45.0)
        add_child(stack)
        var cap := GeomUtil.cylinder_mesh(1.25, 0.26, Color(0.70, 0.42, 0.06), 0.66, 0.16)
        cap.position = Vector3(x, 14.1, -45.0)
        add_child(cap)

func _build_service_traffic() -> void:
    for i in 3:
        var cart := AnimatableBody3D.new()
        cart.name = "ServiceCart_%d" % i
        cart.collision_layer = 2
        cart.collision_mask = 1 | 8
        add_child(cart)
        var body := GeomUtil.box_mesh(Vector3(1.45, 0.55, 2.4), Color(0.76, 0.43, 0.055), 0.72, 0.12)
        body.position.y = 0.48
        cart.add_child(body)
        var cab := GeomUtil.box_mesh(Vector3(1.25, 0.78, 0.90), Color(0.17, 0.24, 0.23), 0.38, 0.10)
        cab.position = Vector3(0.0, 0.94, -0.45)
        cart.add_child(cab)
        GeomUtil.add_box_collision(cart, Vector3(1.45, 1.0, 2.4)).position.y = 0.50
        _carts.append(cart)
        _cart_phase.append(float(i) * 0.33)

func _physics_process(_delta: float) -> void:
    _time += _delta
    for i in _carts.size():
        var cart := _carts[i]
        if not is_instance_valid(cart):
            continue
        var t := fposmod(_time * (0.035 + float(i) * 0.006) + _cart_phase[i], 1.0)
        var z := lerpf(-44.0, 46.0, t)
        cart.position = Vector3(35.0 - float(i) * 4.0, 0.0, z)
        cart.rotation.y = PI if t < 0.5 else 0.0
