extends Node3D

const GeomUtil = preload("res://scripts/geom.gd")
const ImpactFx = preload("res://scripts/impact_fx.gd")
const GatePanelScript = preload("res://scripts/gate_panel.gd")

var panel_health := [120.0, 120.0]
var panels: Array[StaticBody3D] = []
var breached := false

func _ready() -> void:
    add_to_group("breachable")
    _build_gate()

func _build_gate() -> void:
    for side in [-1.0, 1.0]:
        var index := 0 if side < 0.0 else 1
        var panel := StaticBody3D.new()
        panel.position = Vector3(side * 2.15, 2.05, 0.0)
        panel.collision_layer = 8
        panel.collision_mask = 1 | 2 | 4
        panel.set_meta("gate_index", index)
        panel.set_script(GatePanelScript)
        panel.set("gate_owner", self)
        add_child(panel)
        panels.append(panel)
        var frame := GeomUtil.box_mesh(Vector3(4.0, 4.0, 0.24), Color(0.17, 0.18, 0.165), 0.88, 0.26)
        panel.add_child(frame)
        GeomUtil.add_box_collision(panel, Vector3(4.0, 4.0, 0.24))
        for rib in 5:
            var rib_mesh := GeomUtil.box_mesh(Vector3(0.12, 3.55, 0.08), Color(0.40, 0.36, 0.22), 0.80, 0.28)
            rib_mesh.position = Vector3(-1.55 + float(rib) * 0.78, 0.0, -0.17)
            panel.add_child(rib_mesh)
        for stripe in 5:
            var warning := GeomUtil.box_mesh(Vector3(0.66, 0.16, 0.035), Color(0.82, 0.54, 0.08), 0.78, 0.10)
            warning.position = Vector3(-1.25 + float(stripe) * 0.62, -1.45, -0.19)
            warning.rotation.z = 0.55
            panel.add_child(warning)

    for side in [-1.0, 1.0]:
        var post := GeomUtil.static_box(self, "GatePost", Vector3(side * 4.45, 2.5, 0.0), Vector3(0.48, 5.0, 0.72), Color(0.25, 0.25, 0.22))
        var beacon := OmniLight3D.new()
        beacon.position = Vector3(0.0, 2.25, -0.5)
        beacon.light_color = Color(0.98, 0.34, 0.04)
        beacon.light_energy = 1.4
        beacon.omni_range = 4.2
        post.add_child(beacon)

func machine_hit(amount: float, direction: Vector3) -> void:
    if breached:
        return
    var closest := -1
    var best := INF
    for i in panels.size():
        if not is_instance_valid(panels[i]):
            continue
        var d := panels[i].global_position.distance_to(global_position + direction.normalized() * 0.5)
        if d < best:
            best = d
            closest = i
    if closest >= 0:
        damage_panel(closest, amount, direction)

func damage_panel(index: int, amount: float, direction: Vector3) -> void:
    if breached or index < 0 or index >= panels.size() or not is_instance_valid(panels[index]):
        return
    panel_health[index] = maxf(0.0, panel_health[index] - amount)
    var panel := panels[index]
    panel.rotation.y += direction.x * amount * 0.0018
    panel.rotation.x -= direction.y * amount * 0.0009
    ImpactFx.spawn(get_parent(), panel.global_position + Vector3.UP * 0.6, direction, Color(0.92, 0.55, 0.10), clampf(amount / 20.0, 1.0, 3.8), 10)
    if panel_health[index] <= 0.0:
        _break_panel(index, direction)
    breached = panel_health[0] <= 0.0 or panel_health[1] <= 0.0

func _break_panel(index: int, direction: Vector3) -> void:
    var old := panels[index]
    if not is_instance_valid(old):
        return
    var transform := old.global_transform
    old.queue_free()
    var debris := RigidBody3D.new()
    debris.global_transform = transform
    debris.mass = 310.0
    debris.collision_layer = 8
    debris.collision_mask = 1 | 2 | 4 | 8
    get_parent().add_child(debris)
    debris.add_child(GeomUtil.box_mesh(Vector3(4.0, 4.0, 0.24), Color(0.13, 0.14, 0.13), 0.94, 0.30))
    GeomUtil.add_box_collision(debris, Vector3(4.0, 4.0, 0.24))
    debris.apply_central_impulse(direction.normalized() * 1850.0 + Vector3.UP * 420.0)
    debris.apply_torque_impulse(Vector3(direction.z, 0.7, -direction.x) * 1250.0)
