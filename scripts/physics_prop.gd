class_name PhysicsProp
extends RigidBody3D

const GeomUtil = preload("res://scripts/geom.gd")
const ImpactFx = preload("res://scripts/impact_fx.gd")

var health := 80.0
var destroyed := false
var impact_scale := 1.0
var held := false
var impact_color := Color(0.72, 0.45, 0.12)
var source_color := Color(0.25, 0.25, 0.22)
var source_size := Vector3.ONE
var barrel_shape := false

func _ready() -> void:
    add_to_group("physics_prop")
    collision_layer = 8
    collision_mask = 1 | 2 | 4 | 8
    sleeping = true
    can_sleep = true

func configure_box(size: Vector3, color: Color, mass_value: float = 75.0, hp: float = 80.0) -> void:
    mass = mass_value
    health = hp
    source_color = color
    source_size = size
    barrel_shape = false
    impact_color = color.lightened(0.32)
    add_child(GeomUtil.box_mesh(size, color, 0.86, 0.16))
    GeomUtil.add_box_collision(self, size)

func configure_barrel(radius: float, height: float, color: Color, mass_value: float = 48.0, hp: float = 58.0) -> void:
    mass = mass_value
    health = hp
    source_color = color
    source_size = Vector3(radius * 2.0, height, radius * 2.0)
    barrel_shape = true
    impact_color = color.lightened(0.38)
    add_child(GeomUtil.cylinder_mesh(radius, height, color, 0.76, 0.22))
    GeomUtil.add_cylinder_collision(self, radius, height)
    for y in [-height * 0.32, height * 0.32]:
        var ring := GeomUtil.cylinder_mesh(radius * 1.045, 0.06, Color(0.075, 0.08, 0.075), 0.72, 0.28)
        ring.position.y = y
        add_child(ring)

func set_held(value: bool) -> void:
    held = value
    sleeping = false
    freeze = value
    if value:
        linear_velocity = Vector3.ZERO
        angular_velocity = Vector3.ZERO

func machine_hit(amount: float, direction: Vector3) -> void:
    _receive_impact(amount * 1.35, direction, 14.0)

func take_hit(force: Vector3, damage: float) -> void:
    if held:
        set_held(false)
    var dir := force
    if dir.length_squared() < 0.001:
        dir = Vector3.UP
    _receive_impact(damage, dir.normalized(), force.length())

func _receive_impact(damage: float, direction: Vector3, impulse_strength: float) -> void:
    if destroyed:
        return
    sleeping = false
    health -= damage
    var impulse := direction.normalized() * maxf(impulse_strength, damage * 0.22)
    impulse += Vector3.UP * minf(damage * 0.055, 4.2)
    apply_central_impulse(impulse * mass * 0.18 * impact_scale)
    apply_torque_impulse(Vector3(direction.z, 0.35, -direction.x) * damage * mass * 0.025)
    ImpactFx.spawn(get_parent(), global_position + Vector3.UP * 0.45, direction, impact_color, clampf(damage / 20.0, 0.7, 3.5), 7)
    if health <= 0.0:
        _destroy(direction)

func _destroy(direction: Vector3) -> void:
    destroyed = true
    linear_damp = 0.18
    angular_damp = 0.12
    ImpactFx.spawn(get_parent(), global_position + Vector3.UP * 0.35, direction, impact_color, 3.4, 13)
    _spawn_fragments(direction)
    visible = false
    collision_layer = 0
    collision_mask = 0
    freeze = true

func _spawn_fragments(direction: Vector3) -> void:
    var parent := get_parent()
    if parent == null:
        return
    var fragment_count := 5 if barrel_shape else 4
    for i in fragment_count:
        var piece := RigidBody3D.new()
        piece.global_position = global_position + Vector3(
            (float(i % 2) - 0.5) * source_size.x * 0.35,
            0.18 + float(i % 3) * 0.10,
            (float((i + 1) % 2) - 0.5) * source_size.z * 0.35
        )
        piece.mass = maxf(4.0, mass / float(fragment_count) * 0.48)
        piece.collision_layer = 8
        piece.collision_mask = 1 | 2 | 4 | 8
        parent.add_child(piece)
        var chunk_size := Vector3(
            maxf(0.18, source_size.x * (0.34 if barrel_shape else 0.42)),
            maxf(0.16, source_size.y * 0.26),
            maxf(0.18, source_size.z * (0.34 if barrel_shape else 0.42))
        )
        piece.add_child(GeomUtil.box_mesh(chunk_size, source_color.darkened(0.10 + float(i) * 0.025), 0.92, 0.22))
        GeomUtil.add_box_collision(piece, chunk_size)
        var scatter := Vector3(
            direction.x + (-0.7 + float(i) * 0.31),
            0.55 + float(i % 2) * 0.32,
            direction.z + (0.6 - float(i) * 0.22)
        ).normalized()
        piece.apply_central_impulse(scatter * piece.mass * (3.8 + float(i) * 0.45))
        piece.apply_torque_impulse(Vector3(scatter.z, 0.6, -scatter.x) * piece.mass * 1.8)
