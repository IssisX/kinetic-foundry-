extends Node3D

## A relief vent on the process loop.
##
## Nothing here keeps time. The vent blows when its accumulator has reached
## cracking pressure and stops when it has blown down to reseat, which is a
## relaxation cycle the network runs, not a timer this node owns. A branch
## that can no longer reach cracking pressure - because a breach upstream is
## outflowing the pump, or because somebody shut its valve - simply never
## fires again, and how hard it hits is the discharge power it actually has.

const GeomUtil = preload("res://scripts/geom.gd")

## Pressure times volumetric flow is the power leaving the orifice. This is
## the reference an intact loop delivers; the blast scales against it.
const REFERENCE_BLAST_POWER := 1.15e5
const BLAST_INTERVAL := 0.13
const BASE_BLAST_DAMAGE := 5.5

var plenum_id := "east_plenum"
var relief_id := "RELIEF_EAST"

var tick := 0.0
var area: Area3D
var warning_light: OmniLight3D
var puffs: Array[MeshInstance3D] = []

var _burst_phase := 0.0
var _intensity := 0.0
var _open := false

func configure(plenum: String, relief: String) -> void:
    plenum_id = plenum
    relief_id = relief

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
    var state := ProcessPlant.vent_state(plenum_id, relief_id)
    _open = bool(state.get("open", false))
    _intensity = clampf(
        float(state.get("pressure", 0.0)) * float(state.get("flow", 0.0))
        / REFERENCE_BLAST_POWER,
        0.0,
        1.4
    )
    tick = maxf(0.0, tick - delta)

    # The beacon reads the charge the accumulator has built, so a dead
    # branch shows a dead lamp rather than a countdown to nothing.
    var charge := float(state.get("charge", 0.0))
    if _open:
        warning_light.light_energy = 1.2 + _intensity * 3.2
        _burst_phase += delta
    else:
        warning_light.light_energy = 0.28 + charge * charge * 1.6
        _burst_phase = 0.0

    _animate_steam(_open)
    if _open and _intensity > 0.05 and tick <= 0.0:
        tick = BLAST_INTERVAL
        _apply_blast()

func _animate_steam(active: bool) -> void:
    for i in puffs.size():
        var puff := puffs[i]
        if not active or _intensity <= 0.02:
            puff.visible = false
            continue
        var t := fposmod(_burst_phase * 1.35 + float(i) * 0.145, 1.0)
        puff.visible = true
        var reach := 5.25 * clampf(_intensity, 0.25, 1.4)
        puff.position = Vector3(
            sin(float(i) * 2.1) * 0.18 * t,
            1.34 + sin(float(i) * 1.37) * 0.10 * t,
            -1.52 - t * reach
        )
        var s := (0.55 + t * 1.35) * clampf(_intensity, 0.35, 1.3)
        puff.scale = Vector3(s * 0.82, s, s * 1.18)

func _apply_blast() -> void:
    var dir := -global_basis.z
    var scale := _intensity
    for body in area.get_overlapping_bodies():
        if not is_instance_valid(body):
            continue
        if body.has_method("receive_hazard_hit"):
            body.receive_hazard_hit(
                BASE_BLAST_DAMAGE * scale,
                (dir * 4.8 + Vector3.UP * 1.6) * scale
            )
        elif body.has_method("take_hit"):
            body.take_hit(
                (dir * 9.0 + Vector3.UP * 2.2) * scale,
                7.0 * scale
            )

func vent_intensity() -> float:
    return _intensity

func is_blowing() -> bool:
    return _open
