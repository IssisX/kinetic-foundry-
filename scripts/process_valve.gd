class_name ProcessValve
extends StaticBody3D

## A hand-operated isolation valve on one edge of the process graph.
##
## The only thing this does is move an aperture. Everything that follows -
## a branch going dead, a breach stopping, a vent losing its charge - is the
## network's answer to that aperture, not something this node arranges. The
## player and the yard crew both turn it through the same call.

const GeomUtil = preload("res://scripts/geom.gd")

## Turning a big gate valve takes real seconds, and the flow transient
## while it closes is part of what the network sees.
const SLEW_RATE := 0.75
const OPERATE_REACH := 2.8

var edge_id := ""
var process_edge := -1
var label := "LINE"

var _aperture := 1.0
var _target_aperture := 1.0
var _wheel: Node3D
var _indicator: MeshInstance3D
var _indicator_material: StandardMaterial3D


func configure(site_position: Vector3, id: String, readable_label: String) -> void:
    position = site_position
    edge_id = id
    label = readable_label
    collision_layer = 8
    collision_mask = 0
    add_to_group("process_valve")

    var body := GeomUtil.cylinder_mesh(
        0.24,
        0.42,
        Color(0.20, 0.21, 0.19),
        0.78,
        0.34
    )
    add_child(body)
    GeomUtil.add_cylinder_collision(self, 0.30, 0.62)

    var bonnet := GeomUtil.cylinder_mesh(
        0.11,
        0.34,
        Color(0.32, 0.33, 0.30),
        0.62,
        0.48
    )
    bonnet.position.y = 0.36
    add_child(bonnet)

    _wheel = Node3D.new()
    _wheel.position.y = 0.54
    add_child(_wheel)
    var rim := GeomUtil.cylinder_mesh(
        0.30,
        0.045,
        Color(0.62, 0.24, 0.06),
        0.72,
        0.20
    )
    _wheel.add_child(rim)
    for spoke_i in 4:
        var spoke := GeomUtil.box_mesh(
            Vector3(0.046, 0.046, 0.56),
            Color(0.58, 0.22, 0.05),
            0.72,
            0.20
        )
        spoke.rotation.y = float(spoke_i) * PI * 0.5
        _wheel.add_child(spoke)

    _indicator = GeomUtil.cylinder_mesh(0.07, 0.08, Color.WHITE, 0.4, 0.1)
    _indicator_material = GeomUtil.emissive_material(
        Color(0.15, 0.92, 0.32),
        2.4,
        0.36,
        0.05
    )
    _indicator.material_override = _indicator_material
    _indicator.position = Vector3(0.0, 0.74, 0.0)
    add_child(_indicator)

    process_edge = ProcessPlant.register_valve_body(edge_id, self)
    _aperture = ProcessPlant.valve_aperture(process_edge)
    _target_aperture = _aperture
    _apply_visual()


func _process(delta: float) -> void:
    if is_equal_approx(_aperture, _target_aperture):
        return
    _aperture = move_toward(_aperture, _target_aperture, SLEW_RATE * delta)
    ProcessPlant.set_valve(process_edge, _aperture)
    _apply_visual()


func _apply_visual() -> void:
    if _wheel != null:
        _wheel.rotation.y = (1.0 - _aperture) * TAU * 1.5
    if _indicator_material != null:
        var tint := Color(0.92, 0.12, 0.06).lerp(
            Color(0.15, 0.92, 0.32),
            _aperture
        )
        _indicator_material.albedo_color = tint
        _indicator_material.emission = tint


## Returns the aperture this valve is now heading for, so a caller can say
## what it just did without asking again.
func operate(_actor: Node = null) -> float:
    _target_aperture = 0.0 if _target_aperture > 0.5 else 1.0
    return _target_aperture


func set_target_aperture(value: float) -> void:
    _target_aperture = clampf(value, 0.0, 1.0)


func is_open() -> bool:
    return _target_aperture > 0.5


func aperture() -> float:
    return _aperture


func operate_reach() -> float:
    return OPERATE_REACH


func status_text() -> String:
    return "%s // %s" % [
        label,
        "OPEN" if is_open() else "CLOSED"
    ]
