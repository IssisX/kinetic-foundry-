class_name YardDozer
extends FoundryMachine

## Tracked bulldozer: the yard's third flagship machine.
##
## Its verbs are not the excavator's and not the crane's. An excavator
## points a rigid arm. A crane hangs a pendulum. A dozer puts a wall of
## steel in front of 9.8 tonnes and drives. The working assembly is the
## blade plane — lift, tilt, shove — and a ripper that tears what the
## blade cannot lift. Force is closing speed times machine mass.

const GeomUtil = preload("res://scripts/geom.gd")
const VisualBuilder = preload("res://scripts/dozer_visual.gd")
const EnergyPartitionScript = preload("res://scripts/energy_partition.gd")

const BLADE_LIFT_MIN := 0.0
const BLADE_LIFT_MAX := 1.0
const BLADE_TILT_LIMIT := 0.32
const CONTACT_MASK := 1 | 8

var drive_speed := 5.4
var turn_speed := 0.88
var blade_lift := 0.22
var blade_tilt := 0.0
var ripper_drop := 0.0
var hydraulic_health := 280.0
var track_health := 360.0

var _blade: Node3D
var _ripper: Node3D
var _blade_probe: CollisionShape3D
var _ripper_probe: CollisionShape3D
var _operator_view: Node3D
var _work_light: Light3D
var _engine_cover: MeshInstance3D
var _contact_targets: Array[Node] = []
var _blade_point := Vector3.ZERO
var _impact_cooldown := 0.0
var _ripper_cooldown := 0.0
var _telemetry_timer := 0.0
var _ripper_latched := false
var _ai_time := 0.0
var _ground_work_cooldown := 0.0


func _ready() -> void:
    machine_material = FoundryMaterial.PAINTED_STEEL
    machine_tint = Color(0.82, 0.62, 0.08)
    machine_mass = 9800.0
    max_chassis_health = 780.0
    chassis_health = 780.0
    super()
    var body := GeomUtil.add_box_collision(self, Vector3(3.15, 1.35, 4.70))
    body.position.y = 0.88
    var nodes := VisualBuilder.build(self)
    _blade = nodes.blade
    _ripper = nodes.ripper
    _blade_probe = nodes.blade_probe
    _ripper_probe = nodes.ripper_probe
    _operator_view = nodes.operator_view
    _work_light = nodes.work_light
    _engine_cover = nodes.engine_cover
    _apply_pose()


func machine_name() -> String:
    return "TRACKED DOZER"


func machine_entry_reach() -> float:
    return 4.1


func get_operator_view_anchor() -> Node3D:
    return _operator_view


func get_operator_fov() -> float:
    return 70.0


func get_control_profile() -> Dictionary:
    return {
        "machine_name": "TRACKED DOZER",
        "mode": "OPERATOR POV // BLADE + RIPPER",
        "primary": "DROP BLADE",
        "secondary": "RIPPER UP" if ripper_drop > 0.5 else "RIPPER DOWN",
        "tertiary": "EXIT",
        "left_hint": "TRACK / STEER",
        "right_hint": "BLADE LIFT / TILT",
        "center_hint": "SHOVE + PILE + TEAR"
    }


func get_hydraulic_ratio() -> float:
    return clampf(hydraulic_health / 280.0, 0.0, 1.0)


func get_track_ratio() -> float:
    return clampf(track_health / 360.0, 0.0, 1.0)


func get_tool_force() -> float:
    var speed := Vector3(velocity.x, 0.0, velocity.z).length()
    var cutting := 1.0 - blade_lift
    return clampf(32.0 + speed * 24.0 + cutting * 40.0, 12.0, 280.0)


func get_sustained_contact_state() -> Dictionary:
    var valid: Array[Node] = []
    for node in _contact_targets:
        if is_instance_valid(node):
            valid.append(node)
    var forward := -global_basis.z
    return {
        "active": not valid.is_empty(),
        "contacts": valid,
        "position": _blade_point,
        "direction": forward,
        "force": get_tool_force(),
        "effort": clampf(Vector3(velocity.x, 0.0, velocity.z).length() / drive_speed, 0.0, 1.0),
        "persistence": 1.0 - blade_lift,
        "reaction_ratio": clampf(float(valid.size()) * 0.22, 0.0, 1.0),
        "held_mass": 0.0,
        "stability_ratio": 0.0
    }


func _physics_process(delta: float) -> void:
    _tick_hijack(delta)
    _impact_cooldown = maxf(0.0, _impact_cooldown - delta)
    _ripper_cooldown = maxf(0.0, _ripper_cooldown - delta)
    _telemetry_timer = maxf(0.0, _telemetry_timer - delta)

    if disabled:
        velocity.x = move_toward(velocity.x, 0.0, 7.0 * delta)
        velocity.z = move_toward(velocity.z, 0.0, 7.0 * delta)
    elif player_driver != null:
        _player_control(delta)
    elif enemy_driver != null:
        _enemy_control(delta)
    else:
        velocity.x = move_toward(velocity.x, 0.0, 10.0 * delta)
        velocity.z = move_toward(velocity.z, 0.0, 10.0 * delta)

    if not is_on_floor():
        velocity.y -= 26.0 * delta
    move_and_slide()
    _shove_slide_bodies()
    _apply_pose()
    _resolve_blade_contacts()
    _resolve_ripper()
    _scrape_ground(delta)
    _update_telemetry()


func _player_control(delta: float) -> void:
    if hud == null:
        return
    var track := maxf(get_track_ratio(), 0.20)
    var hydro := maxf(get_hydraulic_ratio(), 0.22)
    var axis := control_axis()
    var forward := -global_basis.z
    var throttle := -axis.y
    velocity.x = forward.x * throttle * drive_speed * track
    velocity.z = forward.z * throttle * drive_speed * track
    rotation.y -= axis.x * turn_speed * track * delta

    var look: Vector2 = hud.consume_look()
    blade_lift = clampf(blade_lift - look.y * 0.0028 * hydro, BLADE_LIFT_MIN, BLADE_LIFT_MAX)
    blade_tilt = clampf(blade_tilt + look.x * 0.0024 * hydro, -BLADE_TILT_LIMIT, BLADE_TILT_LIMIT)
    if Input.is_physical_key_pressed(KEY_R):
        blade_lift = clampf(blade_lift + 0.90 * hydro * delta, BLADE_LIFT_MIN, BLADE_LIFT_MAX)
    if Input.is_physical_key_pressed(KEY_F):
        blade_lift = clampf(blade_lift - 0.90 * hydro * delta, BLADE_LIFT_MIN, BLADE_LIFT_MAX)

    var drop: bool = hud.smash_held or Input.is_physical_key_pressed(KEY_J)
    if drop:
        blade_lift = move_toward(blade_lift, 0.0, 1.45 * hydro * delta)
    if hud.consume_attack():
        blade_lift = move_toward(blade_lift, 0.0, 0.28)

    var ripper_tap: bool = bool(hud.consume_grab())
    var ripper_key := Input.is_physical_key_pressed(KEY_K)
    if ripper_key:
        if not _ripper_latched:
            ripper_tap = true
        _ripper_latched = true
    else:
        _ripper_latched = false
    if ripper_tap:
        ripper_drop = 0.0 if ripper_drop > 0.5 else 1.0

    if hud.consume_use() or Input.is_physical_key_pressed(KEY_E):
        exit_player()


func _enemy_control(delta: float) -> void:
    if is_hijack_in_progress():
        velocity.x = move_toward(velocity.x, 0.0, 16.0 * delta)
        velocity.z = move_toward(velocity.z, 0.0, 16.0 * delta)
        return
    _ai_time += delta
    var target := get_tree().get_first_node_in_group("player")
    if target == null:
        return
    var to_target: Vector3 = target.global_position - global_position
    to_target.y = 0.0
    if to_target.length() > 0.1:
        var desired: float = atan2(-to_target.x, -to_target.z)
        rotation.y = lerp_angle(rotation.y, desired, 0.016)
    var forward := -global_basis.z
    var throttle := 1.0 if to_target.length() > 6.0 else 0.35
    var track := maxf(get_track_ratio(), 0.22)
    velocity.x = forward.x * throttle * drive_speed * 0.42 * track
    velocity.z = forward.z * throttle * drive_speed * 0.42 * track
    blade_lift = 0.08 + 0.10 * sin(_ai_time * 0.55)
    blade_tilt = 0.08 * sin(_ai_time * 0.40)


func _apply_pose() -> void:
    if _blade != null:
        _blade.position = Vector3(0.0, 0.72 + blade_lift * 1.18, -2.55)
        _blade.rotation.x = lerpf(0.10, -0.46, blade_lift)
        _blade.rotation.z = blade_tilt
    if _ripper != null:
        _ripper.rotation.x = lerpf(-0.12, 0.78, ripper_drop)
    if _blade != null:
        _blade_point = _blade.to_global(Vector3(0.0, 0.0, -0.80))


func _scrape_ground(delta: float) -> void:
    _ground_work_cooldown = maxf(0.0, _ground_work_cooldown - delta)
    var speed := Vector3(velocity.x, 0.0, velocity.z).length()
    if _ground_work_cooldown > 0.0:
        return
    var forward := -global_basis.z
    if blade_lift < 0.28 and speed > 0.35:
        var cutting := 1.0 - blade_lift
        work_ground(
            _blade_point,
            forward,
            speed * 28.0 * cutting,
            2.6
        )
        var drag := cutting * 2.4 * delta
        velocity.x = move_toward(velocity.x, 0.0, drag)
        velocity.z = move_toward(velocity.z, 0.0, drag)
        _ground_work_cooldown = 0.10
        if hud != null and player_driver != null:
            hud.set_context("BLADE // CUT AND PILE")
    if ripper_drop > 0.55 and speed > 0.25 and _ripper != null:
        work_gouge(
            _ripper.global_position,
            global_basis.z * 0.65 + Vector3(0.0, -0.35, 0.0),
            speed * 22.0
        )
        _ground_work_cooldown = 0.10


func _shove_slide_bodies() -> void:
    var speed := Vector3(velocity.x, 0.0, velocity.z).length()
    if speed < 0.15:
        return
    var forward := -global_basis.z
    for i in get_slide_collision_count():
        var col := get_slide_collision(i)
        var collider = col.get_collider()
        if not (collider is RigidBody3D):
            continue
        var body := collider as RigidBody3D
        var closing := maxf(0.0, velocity.dot(-col.get_normal()))
        var impulse := forward * (closing * machine_mass * 0.011) * (1.15 - blade_lift)
        var offset: Vector3 = col.get_position() - body.global_position
        body.apply_impulse(impulse, offset)


func _resolve_blade_contacts() -> void:
    _contact_targets.clear()
    if _blade_probe == null or get_world_3d() == null:
        return
    var hits := _query_probe(_blade_probe)
    var forward := -global_basis.z
    var force := get_tool_force()
    var speed := Vector3(velocity.x, 0.0, velocity.z).length()
    for hit in hits:
        var collider = hit.get("collider")
        if not is_hard_world_contact(collider):
            continue
        if not _contact_targets.has(collider):
            _contact_targets.append(collider)
        if _impact_cooldown > 0.0:
            continue
        var point_value: Variant = hit.get("point", _blade_point)
        var point := point_value as Vector3 if point_value is Vector3 else _blade_point
        _deliver_hit(collider, force, forward, point, speed)
    if not _contact_targets.is_empty():
        _impact_cooldown = 0.10
        velocity -= forward * minf(force * 0.006, 1.1)
        if hud != null and player_driver != null:
            hud.set_context("BLADE CONTACT // MASS IS THE TOOL")


func _resolve_ripper() -> void:
    if ripper_drop < 0.55 or _ripper_probe == null or _ripper_cooldown > 0.0:
        return
    var hits := _query_probe(_ripper_probe)
    var down := Vector3(0.0, -0.35, 0.0) + global_basis.z * 0.65
    var force := get_tool_force() * 0.72
    var speed := Vector3(velocity.x, 0.0, velocity.z).length()
    var tore := false
    for hit in hits:
        var collider = hit.get("collider")
        if not is_hard_world_contact(collider):
            continue
        var point_value: Variant = hit.get("point", _ripper.global_position)
        var point := point_value as Vector3 if point_value is Vector3 else _ripper.global_position
        _deliver_hit(collider, force, down.normalized(), point, speed)
        tore = true
    if tore:
        _ripper_cooldown = 0.16
        if hud != null and player_driver != null:
            hud.set_context("RIPPER // TEARING THE LOAD PATH")


func _query_probe(probe: CollisionShape3D) -> Array:
    if probe == null or probe.shape == null or get_world_3d() == null:
        return []
    var query := PhysicsShapeQueryParameters3D.new()
    query.shape = probe.shape
    query.transform = probe.global_transform
    query.collision_mask = CONTACT_MASK
    query.collide_with_bodies = true
    query.collide_with_areas = false
    query.exclude = [get_rid()]
    return get_world_3d().direct_space_state.intersect_shape(query, 18)


func _deliver_hit(
        body: Node,
        amount: float,
        direction: Vector3,
        world_point: Vector3,
        relative_speed: float
) -> void:
    var kinematic := EnergyPartitionScript.collision_energy(
        machine_mass * 0.18,
        struck_mass(body),
        relative_speed
    )
    var hydraulic := EnergyPartitionScript.nominal_impact_energy(
        amount,
        get_tool_force(),
        clampf(relative_speed / 6.0, 0.0, 1.0)
    )
    var impact_energy := maxf(kinematic, hydraulic)
    if body.has_method("machine_hit_at"):
        body.machine_hit_at(amount, direction, world_point, impact_energy)
    elif body.has_method("machine_hit"):
        body.machine_hit(amount, direction)


func _apply_machine_damage(amount: float, direction: Vector3) -> void:
    if disabled:
        return
    var side := absf(direction.dot(global_basis.x))
    track_health = maxf(0.0, track_health - amount * (0.16 + side * 0.34))
    hydraulic_health = maxf(0.0, hydraulic_health - amount * (0.10 + absf(direction.y) * 0.22))
    super(amount, direction)


func _disable_machine() -> void:
    if disabled:
        return
    super()
    if _work_light != null:
        _work_light.light_energy = 0.0


func _update_telemetry() -> void:
    if hud == null or player_driver == null or _telemetry_timer > 0.0:
        return
    _telemetry_timer = 0.12
    hud.set_machine_telemetry(
        get_health_ratio(),
        get_hydraulic_ratio(),
        get_track_ratio(),
        clampf(get_tool_force() / 220.0, 0.0, 1.0),
        false
    )
    if hud.has_method("set_machine_profile"):
        hud.set_machine_profile(get_control_profile())
