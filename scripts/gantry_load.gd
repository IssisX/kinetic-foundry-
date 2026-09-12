extends AnimatableBody3D

const GeomUtil = preload("res://scripts/geom.gd")

var time := 0.0
var base_z := -5.0
var travel := 7.8
var speed := 0.62
var last_position := Vector3.ZERO
var sweep_velocity := Vector3.ZERO
var hit_cooldown := 0.0
var cable: MeshInstance3D
var danger_area: Area3D

func _ready() -> void:
    add_to_group("capture_mover")
    collision_layer = 8
    collision_mask = 1 | 2 | 4 | 8
    sync_to_physics = true
    _build_visual()
    _build_danger_area()
    last_position = global_position

func _build_visual() -> void:
    var trolley := GeomUtil.box_mesh(Vector3(2.2, 0.48, 1.15), Color(0.42, 0.30, 0.075), 0.74, 0.24)
    trolley.position.y = 2.28
    add_child(trolley)
    for side in [-0.78, 0.78]:
        var wheel := GeomUtil.cylinder_mesh(0.22, 0.22, Color(0.06, 0.065, 0.06), 0.95, 0.30)
        wheel.rotation.z = PI * 0.5
        wheel.position = Vector3(side, 2.52, 0.0)
        add_child(wheel)
    cable = GeomUtil.cylinder_mesh(0.055, 3.55, Color(0.10, 0.105, 0.10), 0.88, 0.42)
    cable.position.y = 0.55
    add_child(cable)
    var hook := GeomUtil.sphere_mesh(0.28, Color(0.24, 0.25, 0.22))
    hook.position.y = -1.25
    add_child(hook)
    var load := GeomUtil.box_mesh(Vector3(2.8, 1.25, 1.75), Color(0.25, 0.17, 0.075), 0.86, 0.16)
    load.position.y = -2.05
    add_child(load)
    GeomUtil.add_box_collision(self, Vector3(2.8, 1.25, 1.75)).position.y = -2.05
    for side in [-1.12, 1.12]:
        var strap := GeomUtil.box_mesh(Vector3(0.10, 1.35, 1.80), Color(0.54, 0.42, 0.16), 0.80, 0.08)
        strap.position = Vector3(side, -2.05, 0.0)
        add_child(strap)

func _build_danger_area() -> void:
    danger_area = Area3D.new()
    danger_area.collision_layer = 0
    danger_area.collision_mask = 1 | 2 | 4 | 8
    add_child(danger_area)
    var shape := BoxShape3D.new()
    shape.size = Vector3(3.4, 1.8, 2.3)
    var collision := CollisionShape3D.new()
    collision.shape = shape
    collision.position.y = -2.05
    danger_area.add_child(collision)

func _physics_process(delta: float) -> void:
    time += delta
    hit_cooldown = maxf(0.0, hit_cooldown - delta)
    var x := sin(time * speed) * travel
    var sway := sin(time * speed * 1.85) * 0.24
    position = Vector3(x, 4.72 + sway, base_z)
    sweep_velocity = (global_position - last_position) / maxf(delta, 0.001)
    last_position = global_position
    rotation.z = sin(time * speed * 1.85) * 0.055
    if hit_cooldown <= 0.0 and sweep_velocity.length() > 1.0:
        _apply_sweep()

func _apply_sweep() -> void:
    var travel_dir := Vector3(sweep_velocity.x, 0.0, sweep_velocity.z)
    if travel_dir.length_squared() < 0.01:
        return
    travel_dir = travel_dir.normalized()
    for body in danger_area.get_overlapping_bodies():
        if not is_instance_valid(body):
            continue
        if body.has_method("receive_hazard_hit"):
            body.receive_hazard_hit(12.0, travel_dir * 5.8 + Vector3.UP * 2.2)
            hit_cooldown = 0.30
        elif body.has_method("machine_hit"):
            body.machine_hit(34.0, travel_dir)
            hit_cooldown = 0.30
        elif body.has_method("take_hit"):
            body.take_hit(travel_dir * 11.0 + Vector3.UP * 2.8, 18.0)
            hit_cooldown = 0.30
