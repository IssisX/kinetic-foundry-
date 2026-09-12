extends Node3D

const GeomUtil = preload("res://scripts/geom.gd")

var cycle_time := 4.4
var burst_duration := 0.72
var phase_offset := 0.0
var timer := 0.0
var tick := 0.0
var area: Area3D
var warning_light: OmniLight3D
var puffs: Array[MeshInstance3D] = []

func configure(offset: float = 0.0) -> void:
    phase_offset = offset
    timer = offset

func _ready() -> void:
    _build_visual()
    _build_area()

func _build_visual() -> void:
    var base := GeomUtil.cylinder_mesh(0.46, 1.55, Color(0.17, 0.18, 0.17), 0.84, 0.30)
    base.position.y = 0.78
    add_child(base)
    var elbow := GeomUtil.cylinder_mesh(0.34, 1.45, Color(0.23, 0.24, 0.22), 0.80, 0.34)
    elbow.rotation.x = PI * 0.5
    elbow.position = Vector3(0.0, 1.34, -0.62)
    add_child(elbow)
    var nozzle := GeomUtil.cylinder_mesh(0.48, 0.34, Color(0.10, 0.11, 0.10), 0.76, 0.42)
    nozzle.rotation.x = PI * 0.5
    nozzle.position = Vector3(0.0, 1.34, -1.32)
    add_child(nozzle)
    var beacon := GeomUtil.cylinder_mesh(0.16, 0.18, Color(0.75, 0.12, 0.035), 0.38, 0.10)
    beacon.material_override = GeomUtil.emissive_material(Color(0.85, 0.10, 0.025), 2.8, 0.36, 0.04)
    beacon.position = Vector3(0.0, 1.90, 0.0)
    add_child(beacon)
    warning_light = OmniLight3D.new()
    warning_light.position = Vector3(0.0, 1.92, 0.0)
    warning_light.light_color = Color(1.0, 0.12, 0.03)
    warning_light.light_energy = 0.6
    warning_light.omni_range = 3.8
    add_child(warning_light)
    var steam_mat := StandardMaterial3D.new()
    steam_mat.albedo_color = Color(0.70, 0.78, 0.78, 0.22)
    steam_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
    steam_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
    for i in 7:
        var puff := GeomUtil.sphere_mesh(0.42 + float(i % 3) * 0.08, Color.WHITE)
        puff.material_override = steam_mat
        puff.visible = false
        add_child(puff)
        puffs.append(puff)

func _build_area() -> void:
    area = Area3D.new()
    area.collision_layer = 0
    area.collision_mask = 1 | 2 | 4 | 8
    area.monitoring = true
    add_child(area)
    var shape := BoxShape3D.new()
    shape.size = Vector3(2.2, 2.1, 5.4)
    var collision := CollisionShape3D.new()
    collision.shape = shape
    collision.position = Vector3(0.0, 1.25, -3.25)
    area.add_child(collision)

func _process(delta: float) -> void:
    timer = fmod(timer + delta, cycle_time)
    tick = maxf(0.0, tick - delta)
    var active := timer < burst_duration
    var warning_window := timer > cycle_time - 1.0
    warning_light.light_energy = 3.8 if active else (1.8 if warning_window else 0.45)
    _animate_steam(active)
    if active and tick <= 0.0:
        tick = 0.13
        _apply_blast()

func _animate_steam(active: bool) -> void:
    for i in puffs.size():
        var puff := puffs[i]
        if not active:
            puff.visible = false
            continue
        var t := fposmod(timer / burst_duration + float(i) * 0.145, 1.0)
        puff.visible = true
        puff.position = Vector3(sin(float(i) * 2.1) * 0.18 * t, 1.34 + sin(float(i) * 1.37) * 0.10 * t, -1.52 - t * 5.25)
        var s := 0.55 + t * 1.35
        puff.scale = Vector3(s * 0.82, s, s * 1.18)

func _apply_blast() -> void:
    var dir := -global_basis.z
    for body in area.get_overlapping_bodies():
        if not is_instance_valid(body):
            continue
        if body.has_method("receive_hazard_hit"):
            body.receive_hazard_hit(5.5, dir * 4.8 + Vector3.UP * 1.6)
        elif body.has_method("take_hit"):
            body.take_hit(dir * 9.0 + Vector3.UP * 2.2, 7.0)
