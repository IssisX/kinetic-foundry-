class_name StructuralFrame
extends Node3D

const GeomUtil = preload("res://scripts/geom.gd")
const SupportScript = preload("res://scripts/support.gd")
const ImpactFx = preload("res://scripts/impact_fx.gd")

signal structure_collapsed

var support_health: Array[float] = [100.0, 100.0, 100.0, 100.0]
var supports: Array[StaticBody3D] = []
var support_meshes: Array[MeshInstance3D] = []
var deck: RigidBody3D
var collapsed := false
var collapse_age := 0.0
var _aftermath_spawned := false

func _ready() -> void:
    add_to_group("structure")
    _build_frame()

func _physics_process(delta: float) -> void:
    if not collapsed:
        return
    collapse_age += delta
    if collapse_age > 0.18 and not _aftermath_spawned:
        _aftermath_spawned = true
        _spawn_aftermath()

func _build_frame() -> void:
    var positions: Array[Vector3] = [
        Vector3(-3.7, 2.3, -2.2),
        Vector3(3.7, 2.3, -2.2),
        Vector3(-3.7, 2.3, 2.2),
        Vector3(3.7, 2.3, 2.2)
    ]
    for i in positions.size():
        var support: StaticBody3D = _make_support(i, positions[i])
        supports.append(support)

    deck = RigidBody3D.new()
    deck.name = "Deck"
    deck.position = Vector3(0.0, 5.05, 0.0)
    deck.mass = 950.0
    deck.freeze = true
    deck.collision_layer = 8
    deck.collision_mask = 1 | 2 | 4 | 8
    add_child(deck)
    deck.add_child(GeomUtil.box_mesh(Vector3(9.4, 0.48, 6.0), Color(0.18, 0.19, 0.175), 0.90, 0.24))
    GeomUtil.add_box_collision(deck, Vector3(9.4, 0.48, 6.0))

    for x in [-4.15, -2.05, 0.0, 2.05, 4.15]:
        var girder: MeshInstance3D = GeomUtil.box_mesh(Vector3(0.28, 0.58, 6.1), Color(0.29, 0.27, 0.20), 0.82, 0.30)
        girder.position = Vector3(float(x), -0.34, 0.0)
        deck.add_child(girder)

    for z in [-2.72, 2.72]:
        var rail_top: MeshInstance3D = GeomUtil.box_mesh(Vector3(9.4, 0.13, 0.13), Color(0.70, 0.47, 0.08), 0.78, 0.22)
        rail_top.position = Vector3(0.0, 1.06, float(z))
        deck.add_child(rail_top)
        var rail_mid: MeshInstance3D = GeomUtil.box_mesh(Vector3(9.4, 0.09, 0.09), Color(0.47, 0.48, 0.42), 0.80, 0.24)
        rail_mid.position = Vector3(0.0, 0.62, float(z))
        deck.add_child(rail_mid)
        for x in [-4.4, -2.2, 0.0, 2.2, 4.4]:
            var post: MeshInstance3D = GeomUtil.box_mesh(Vector3(0.12, 1.16, 0.12), Color(0.47, 0.48, 0.42), 0.80, 0.24)
            post.position = Vector3(float(x), 0.58, float(z))
            deck.add_child(post)

    for stripe_i in 10:
        var stripe: MeshInstance3D = GeomUtil.box_mesh(
            Vector3(0.62, 0.03, 0.40),
            Color(0.76, 0.54, 0.10) if stripe_i % 2 == 0 else Color(0.07, 0.075, 0.07),
            0.84,
            0.06
        )
        stripe.position = Vector3(-4.15 + float(stripe_i) * 0.92, 0.255, -2.80)
        stripe.rotation.y = 0.55
        deck.add_child(stripe)

    _build_cross_braces()

func _build_cross_braces() -> void:
    for z in [-2.22, 2.22]:
        for direction in [-1.0, 1.0]:
            var brace: MeshInstance3D = GeomUtil.box_mesh(Vector3(0.22, 5.45, 0.22), Color(0.33, 0.29, 0.19), 0.82, 0.25)
            brace.position = Vector3(0.0, 2.6, float(z))
            brace.rotation.z = float(direction) * 0.94
            add_child(brace)

func _make_support(index: int, pos: Vector3) -> StaticBody3D:
    var support: StaticBody3D = StaticBody3D.new()
    support.name = "Support_%d" % index
    support.position = pos
    support.collision_layer = 8
    support.collision_mask = 1 | 2 | 4
    support.set_meta("support_index", index)
    support.set_script(SupportScript)
    support.set("frame", self)
    add_child(support)

    var column: MeshInstance3D = GeomUtil.box_mesh(Vector3(0.72, 4.6, 0.72), Color(0.39, 0.33, 0.20), 0.80, 0.30)
    support.add_child(column)
    support_meshes.append(column)
    GeomUtil.add_box_collision(support, Vector3(0.72, 4.6, 0.72))

    var foot: MeshInstance3D = GeomUtil.box_mesh(Vector3(1.28, 0.32, 1.28), Color(0.20, 0.205, 0.19), 0.88, 0.24)
    foot.position.y = -2.14
    support.add_child(foot)

    for plate_y in [-1.15, 0.15, 1.45]:
        var plate: MeshInstance3D = GeomUtil.box_mesh(Vector3(0.83, 0.16, 0.83), Color(0.64, 0.43, 0.08), 0.74, 0.20)
        plate.position.y = float(plate_y)
        support.add_child(plate)
    return support

func damage_support(index: int, amount: float, direction: Vector3) -> void:
    if index < 0 or index >= support_health.size():
        return
    if support_health[index] <= 0.0:
        return
    support_health[index] = maxf(0.0, support_health[index] - amount)
    var support: StaticBody3D = supports[index]
    if is_instance_valid(support):
        support.rotation.z += direction.x * amount * 0.0009
        support.rotation.x -= direction.z * amount * 0.0009
    _update_support_material(index)
    ImpactFx.spawn(
        get_parent(),
        supports[index].global_position + Vector3.UP * 1.1 if is_instance_valid(supports[index]) else global_position,
        direction,
        Color(0.92, 0.56, 0.12),
        clampf(amount / 22.0, 0.8, 3.2),
        8
    )
    if support_health[index] <= 0.0:
        _break_support(index, direction)
    _apply_pre_failure_pose()
    _evaluate_failure()

func _update_support_material(index: int) -> void:
    if index < 0 or index >= support_meshes.size():
        return
    var mesh: MeshInstance3D = support_meshes[index]
    if not is_instance_valid(mesh):
        return
    var ratio: float = support_health[index] / 100.0
    var color: Color = Color(0.39, 0.33, 0.20)
    if ratio < 0.70:
        color = Color(0.48, 0.30, 0.12)
    if ratio < 0.35:
        color = Color(0.56, 0.18, 0.07)
    mesh.material_override = GeomUtil.material(color, 0.88, 0.32)

func _apply_pre_failure_pose() -> void:
    if collapsed or deck == null:
        return
    var left_capacity: float = maxf(support_health[0], 0.0) + maxf(support_health[2], 0.0)
    var right_capacity: float = maxf(support_health[1], 0.0) + maxf(support_health[3], 0.0)
    var north_capacity: float = maxf(support_health[0], 0.0) + maxf(support_health[1], 0.0)
    var south_capacity: float = maxf(support_health[2], 0.0) + maxf(support_health[3], 0.0)
    var roll: float = clampf((right_capacity - left_capacity) / 200.0, -1.0, 1.0) * 0.075
    var pitch: float = clampf((south_capacity - north_capacity) / 200.0, -1.0, 1.0) * 0.060
    var total_capacity: float = left_capacity + right_capacity
    var sag: float = clampf((400.0 - total_capacity) / 400.0, 0.0, 1.0) * 0.18
    deck.rotation.x = pitch
    deck.rotation.z = roll
    deck.position.y = 5.05 - sag

func _break_support(index: int, direction: Vector3) -> void:
    var old: StaticBody3D = supports[index]
    if not is_instance_valid(old):
        return
    var pos: Vector3 = old.global_position
    old.queue_free()

    var debris: RigidBody3D = RigidBody3D.new()
    debris.position = to_local(pos)
    debris.mass = 180.0
    debris.collision_layer = 8
    debris.collision_mask = 1 | 2 | 4 | 8
    add_child(debris)
    debris.add_child(GeomUtil.box_mesh(Vector3(0.72, 4.6, 0.72), Color(0.31, 0.27, 0.18), 0.92, 0.30))
    GeomUtil.add_box_collision(debris, Vector3(0.72, 4.6, 0.72))
    debris.apply_central_impulse(direction.normalized() * 2200.0 + Vector3.UP * 520.0)
    debris.apply_torque_impulse(Vector3(direction.z, 0.6, -direction.x) * 900.0)

func _evaluate_failure() -> void:
    if collapsed:
        return
    var alive: int = 0
    for hp: float in support_health:
        if hp > 0.0:
            alive += 1
    if alive <= 2:
        collapsed = true
        collapse_age = 0.0
        deck.freeze = false
        deck.apply_torque_impulse(Vector3(4200.0, 900.0, -3600.0))
        deck.apply_central_impulse(Vector3(220.0, -180.0, -120.0))
        ImpactFx.spawn(get_parent(), deck.global_position, Vector3.UP, Color(0.72, 0.48, 0.20), 5.0, 18)
        structure_collapsed.emit()

func _spawn_aftermath() -> void:
    var pieces: Array = [
        [Vector3(-3.8, 4.8, -2.7), Vector3(2.8, 0.18, 0.18), 90.0],
        [Vector3(3.6, 4.9, 2.7), Vector3(3.2, 0.18, 0.18), 95.0],
        [Vector3(-1.4, 4.7, 2.6), Vector3(0.18, 0.18, 2.3), 70.0],
        [Vector3(1.9, 4.75, -2.6), Vector3(0.18, 0.18, 2.7), 72.0],
        [Vector3(-2.4, 4.4, 0.4), Vector3(1.6, 0.28, 0.42), 120.0],
        [Vector3(2.8, 4.5, -0.7), Vector3(1.9, 0.24, 0.34), 110.0]
    ]
    for i in pieces.size():
        var entry: Array = pieces[i]
        var body: RigidBody3D = RigidBody3D.new()
        body.position = entry[0] as Vector3
        body.mass = float(entry[2])
        body.collision_layer = 8
        body.collision_mask = 1 | 2 | 4 | 8
        add_child(body)
        var piece_size: Vector3 = entry[1] as Vector3
        body.add_child(GeomUtil.box_mesh(piece_size, Color(0.27, 0.25, 0.20), 0.92, 0.31))
        GeomUtil.add_box_collision(body, piece_size)
        var side: float = -1.0 if i % 2 == 0 else 1.0
        body.apply_central_impulse(Vector3(side * (120.0 + i * 18.0), 80.0 + i * 24.0, (i - 2) * 42.0))
        body.apply_torque_impulse(Vector3(180.0, side * 260.0, 140.0))
