class_name HumanoidGaitDebug
extends Node3D

const GeomUtil = preload("res://scripts/geom.gd")

var _world: Node3D
var _left: MeshInstance3D
var _right: MeshInstance3D
var _com: MeshInstance3D
var _support: MeshInstance3D
var _left_normal: MeshInstance3D
var _right_normal: MeshInstance3D
var _left_reach: MeshInstance3D
var _right_reach: MeshInstance3D
var _label: Label3D

func _ready() -> void:
    _world = Node3D.new()
    _world.top_level = true
    add_child(_world)

    _left = _marker(Color(0.18, 0.95, 0.34))
    _right = _marker(Color(0.18, 0.95, 0.34))
    _com = _marker(Color(0.15, 0.82, 1.0), 0.055)
    _support = _line(Color(0.25, 0.92, 0.88))
    _left_normal = _line(Color(0.28, 0.78, 1.0))
    _right_normal = _line(Color(0.28, 0.78, 1.0))
    _left_reach = _line(Color(0.96, 0.72, 0.12))
    _right_reach = _line(Color(0.96, 0.72, 0.12))

    _label = Label3D.new()
    _label.font_size = 20
    _label.outline_size = 5
    _label.pixel_size = 0.0025
    _label.modulate = Color(0.92, 0.97, 1.0)
    _label.no_depth_test = true
    _label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
    _world.add_child(_label)

func present(data: Dictionary) -> void:
    if not visible or _world == null:
        return
    var left: Dictionary = data.left
    var right: Dictionary = data.right
    var left_contact: Vector3 = left.contact
    var right_contact: Vector3 = right.contact
    var com: Vector3 = data.com

    _left.global_position = left_contact
    _right.global_position = right_contact
    _com.global_position = com
    _set_color(
        _left,
        Color(0.18, 0.95, 0.34)
        if left.planted
        else Color(1.0, 0.78, 0.12)
    )
    _set_color(
        _right,
        Color(0.18, 0.95, 0.34)
        if right.planted
        else Color(1.0, 0.78, 0.12)
    )

    _segment(
        _left_normal,
        left_contact,
        left_contact + left.normal * 0.34
    )
    _segment(
        _right_normal,
        right_contact,
        right_contact + right.normal * 0.34
    )
    _segment(_left_reach, left.hip, left_contact)
    _segment(_right_reach, right.hip, right_contact)
    _support.visible = data.double_support
    if _support.visible:
        _segment(
            _support,
            left_contact + Vector3.UP * 0.025,
            right_contact + Vector3.UP * 0.025
        )

    _label.global_position = com + Vector3.UP * 1.22
    _label.text = (
        "%s  phi %.3f  DS %s\n"
        + "L %s  R %s\n"
        + "plant v %.3f / %.3f  reach %.2f / %.2f"
    ) % [
        data.mode,
        data.phase,
        "YES" if data.double_support else "NO",
        left.state,
        right.state,
        left.planted_velocity,
        right.planted_velocity,
        left.reach,
        right.reach
    ]

func _marker(
        color: Color,
        radius: float = 0.045
) -> MeshInstance3D:
    var node := GeomUtil.sphere_mesh(radius, color)
    _world.add_child(node)
    return node

func _line(color: Color) -> MeshInstance3D:
    var node := GeomUtil.cylinder_mesh(
        0.012,
        1.0,
        color,
        0.80,
        0.0
    )
    _world.add_child(node)
    return node

func _segment(
        node: MeshInstance3D,
        start: Vector3,
        finish: Vector3
) -> void:
    var vector := finish - start
    var length := vector.length()
    if length < 0.001:
        node.visible = false
        return
    node.visible = true
    node.global_position = (start + finish) * 0.5
    node.global_basis = Basis(
        Quaternion(Vector3.UP, vector / length)
    ).scaled(Vector3(1.0, length, 1.0))

func _set_color(node: MeshInstance3D, color: Color) -> void:
    var material := node.material_override
    if material is StandardMaterial3D:
        material.albedo_color = color
