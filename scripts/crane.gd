class_name YardCrane
extends FoundryMachine

## Crawler crane: the yard's second flagship machine.
##
## Its verbs are not the excavator's. An excavator's tool is rigid, so where
## the arm points is where the force goes. A crane hangs its load on a rope,
## so the load has its own momentum: slewing throws it wide, hoisting in
## shortens the pendulum and speeds the swing, and stopping does not stop
## what is hanging underneath. That momentum is the weapon, the lifting
## capacity, and the reason the machine can put itself on its side.
##
## Everything the crane does to the world it does through authorities the
## game already owns: the shared grip law holds the load, contacts go
## through the material resolver, and structural damage goes through the
## same machine_hit_at path the bucket uses.

const GeomUtil = preload("res://scripts/geom.gd")

const BOOM_LENGTH := 12.4
const BOOM_PIVOT := Vector3(0.0, 2.35, -0.55)
const LUFF_MIN := 0.30
const LUFF_MAX := 1.22
const ROPE_MIN := 1.8
const ROPE_MAX := 11.5
const HOOK_MASS := 240.0
const HOOK_DAMPING := 0.22
const HOOK_PROBE_RADIUS := 1.15
const TRACK_HALF_WIDTH := 1.95
const TRACK_HALF_LENGTH := 2.70
const CLAMP_FORCE := 96000.0
const CLAMP_TRAVEL := 0.34
const CLAMP_CREEP := 0.018
const SLEW_RATE := 0.62
const LUFF_RATE := 0.34
const HOIST_RATE := 2.05
const GRAB_MASS_LIMIT := 1900.0

var drive_speed := 3.4
var turn_speed := 0.72
var slew_angle := 0.0
var luff_angle := 0.86
var rope_length := 6.4
var hoist_health := 240.0

var _slew: Node3D
var _boom: Node3D
var _boom_tip: Node3D
var _hook: Node3D
var _jaw_left: MeshInstance3D
var _jaw_right: MeshInstance3D
var _rope: MeshInstance3D
var _hook_probe: Area3D
var _operator_view: Node3D
var _house_shell: MeshInstance3D

var _hook_position := Vector3.ZERO
var _hook_velocity := Vector3.ZERO
var _hook_ready := false
var _hook_grounded := false
var _clamp_closure := 0.0
var _swing_speed := 0.0
var _tipping_ratio := 0.0
var _tip_direction_local := Vector3.ZERO
var _impact_cooldown := 0.0
var _contact_targets: Array[Node] = []
var _warn_cooldown := 0.0
var _tipping_damage_bank := 0.0
var _load_path_reaction := 0.0


func _ready() -> void:
    machine_material = FoundryMaterial.PAINTED_STEEL
    machine_tint = Color(0.58, 0.42, 0.09)
    machine_mass = 4200.0
    max_chassis_health = 620.0
    chassis_health = 620.0
    super()
    var body := GeomUtil.add_box_collision(self, Vector3(3.35, 1.30, 4.85))
    body.position.y = 0.82
    _build_visual()
    _grip.travel_limit = 2.60


func machine_name() -> String:
    return "CRAWLER CRANE"


func machine_entry_reach() -> float:
    return 3.9


func get_operator_view_anchor() -> Node3D:
    return _operator_view


func get_operator_fov() -> float:
    return 76.0


func get_control_profile() -> Dictionary:
    return {
        "machine_name": "CRAWLER CRANE",
        "mode": "OPERATOR POV // ROPE + SLEW CONTROL",
        "primary": "HOIST IN",
        "secondary": "RELEASE" if _grip.is_holding() else "CLAMP",
        "tertiary": "EXIT",
        "left_hint": "TRACK / STEER",
        "right_hint": "SLEW / LUFF",
        "center_hint": "LOAD SWING + RADIUS + TIPPING"
    }


func get_hydraulic_ratio() -> float:
    return clampf(hoist_health / 240.0, 0.0, 1.0)


func get_track_ratio() -> float:
    return clampf(chassis_health / maxf(max_chassis_health, 1.0), 0.0, 1.0)


func get_tool_force() -> float:
    var bob := HOOK_MASS + _grip.load_mass()
    return clampf(bob * 0.02 + _swing_speed * 9.5, 6.0, 260.0)


func get_grip_stress() -> float:
    return _grip.stress


func set_load_path_feedback(state: Dictionary) -> void:
    _load_path_reaction = clampf(
        float(state.get("reaction_ratio", 0.0)),
        0.0,
        1.0
    )


## Radius is the horizontal distance from the slew centre to the hook. It
## is the number that decides both what the crane can lift and whether the
## crane stays upright.
func get_working_radius() -> float:
    var offset := _hook_position - global_position
    offset.y = 0.0
    return offset.length()


func get_hook_position() -> Vector3:
    return _hook_position


## Re-seat the hook directly under the boom tip, optionally with a swing
## already running. Scripted setups use this rather than posing the rope.
func place_hook(swing_velocity: Vector3 = Vector3.ZERO) -> void:
    _hook_ready = false
    _step_hook(1.0 / 60.0)
    _hook_velocity = swing_velocity


## Take a specific body into the clamp, using the same grip law the
## operator's clamp uses.
func hold_load(body) -> bool:
    if body == null or not is_instance_valid(body):
        return false
    if not _grip.grab(body, _hook, false):
        return false
    held_load = body
    _clamp_closure = 0.0
    return true


func drop_load() -> void:
    _release_load(false)


func get_sustained_contact_state() -> Dictionary:
    var valid: Array[Node] = []
    for node in _contact_targets:
        if is_instance_valid(node):
            valid.append(node)
    var direction := Vector3.DOWN
    if _hook_velocity.length_squared() > 0.04:
        direction = _hook_velocity.normalized()
    return {
        "active": not valid.is_empty(),
        "contacts": valid,
        "position": _hook_position,
        "direction": direction,
        "force": get_tool_force(),
        "effort": clampf(_swing_speed / 6.0, 0.0, 1.0),
        "persistence": _clamp_closure,
        "reaction_ratio": _grip.stress,
        "held_mass": _grip.load_mass(),
        "stability_ratio": _tipping_ratio
    }


func get_stability_state() -> Dictionary:
    return {
        "ratio": _tipping_ratio,
        "lateral": _tipping_ratio,
        "longitudinal": _tipping_ratio,
        "tip_direction_local": _tip_direction_local,
        "braced": 0.0
    }


func _physics_process(delta: float) -> void:
    _tick_hijack(delta)
    _impact_cooldown = maxf(0.0, _impact_cooldown - delta)
    _warn_cooldown = maxf(0.0, _warn_cooldown - delta)

    if disabled:
        velocity.x = move_toward(velocity.x, 0.0, 6.0 * delta)
        velocity.z = move_toward(velocity.z, 0.0, 6.0 * delta)
    elif player_driver != null:
        _player_control(delta)
    elif enemy_driver != null:
        _enemy_control(delta)
    else:
        velocity.x = move_toward(velocity.x, 0.0, 9.0 * delta)
        velocity.z = move_toward(velocity.z, 0.0, 9.0 * delta)

    if not is_on_floor():
        velocity.y -= 26.0 * delta
    move_and_slide()

    _apply_upper_pose()
    _step_hook(delta)
    _update_rope_visual()
    _update_clamp(delta)
    _update_tipping(delta)
    _resolve_hook_contacts()


func _player_control(delta: float) -> void:
    if hud == null:
        return
    var hoist_authority := maxf(get_hydraulic_ratio(), 0.22)
    # A crane close to tipping does not get to swing faster.
    var authority := clampf(1.0 - maxf(_tipping_ratio - 0.55, 0.0) * 0.85, 0.30, 1.0)

    var axis: Vector2 = control_axis()
    var forward := -global_basis.z
    var throttle := -axis.y
    velocity.x = forward.x * throttle * drive_speed * authority
    velocity.z = forward.z * throttle * drive_speed * authority
    rotation.y -= axis.x * turn_speed * authority * delta

    var look: Vector2 = hud.consume_look()
    slew_angle -= look.x * 0.0036 * authority
    luff_angle = clampf(
        luff_angle - look.y * 0.0020 * hoist_authority,
        LUFF_MIN,
        LUFF_MAX
    )

    if hud.smash_held:
        rope_length = clampf(
            rope_length - HOIST_RATE * hoist_authority * delta,
            ROPE_MIN,
            ROPE_MAX
        )
    if hud.consume_attack():
        rope_length = clampf(
            rope_length + 0.85 * hoist_authority,
            ROPE_MIN,
            ROPE_MAX
        )
    if hud.consume_grab():
        if _grip.is_holding():
            _release_load(true)
        elif not _try_clamp():
            hud.set_context("CLAMP EMPTY // PUT THE HOOK ON THE LOAD")
    if hud.consume_use() or Input.is_physical_key_pressed(KEY_E):
        exit_player()


## An enemy operator works the crane the obvious way: keep the load between
## the machine and whoever it is trying to hit, and swing.
func _enemy_control(delta: float) -> void:
    var target := _hostile_target()
    if target == null:
        velocity.x = move_toward(velocity.x, 0.0, 9.0 * delta)
        velocity.z = move_toward(velocity.z, 0.0, 9.0 * delta)
        return
    var to_target := target.global_position - global_position
    to_target.y = 0.0
    if to_target.length_squared() < 0.01:
        return
    var desired := atan2(-to_target.x, -to_target.z)
    rotation.y = rotate_toward(rotation.y, desired, turn_speed * 0.6 * delta)

    var hook_offset := _hook_position - target.global_position
    hook_offset.y = 0.0
    slew_angle += clampf(hook_offset.x * 0.04, -1.0, 1.0) * SLEW_RATE * delta
    var distance := to_target.length()
    rope_length = clampf(
        rope_length + (4.2 - _hook_position.y + target.global_position.y) * delta,
        ROPE_MIN,
        ROPE_MAX
    )
    if distance > 14.0:
        velocity.x = move_toward(velocity.x, 0.0, 9.0 * delta)
        velocity.z = move_toward(velocity.z, 0.0, 9.0 * delta)
        return
    if distance > 9.0:
        var forward := -global_basis.z
        velocity.x = forward.x * drive_speed * 0.7
        velocity.z = forward.z * drive_speed * 0.7
    else:
        velocity.x = move_toward(velocity.x, 0.0, 9.0 * delta)
        velocity.z = move_toward(velocity.z, 0.0, 9.0 * delta)


func _hostile_target() -> Node3D:
    var best: Node3D = null
    var best_distance := 26.0
    for node in get_tree().get_nodes_in_group("player"):
        if not is_instance_valid(node) or not node.visible:
            continue
        var distance: float = node.global_position.distance_to(global_position)
        if distance < best_distance:
            best_distance = distance
            best = node
    return best


func _apply_upper_pose() -> void:
    if _slew == null or _boom == null:
        return
    _slew.rotation.y = slew_angle
    # The boom lies along local -Z, so a positive pitch about X lifts the tip.
    _boom.rotation.x = luff_angle


## The rope is treated as an inextensible link between the boom tip and the
## hook block: the hook is integrated freely under gravity and the load it
## carries, then projected back onto the rope length. Slew the upper works
## and the tip moves while the hook does not, which is the swing.
func _step_hook(delta: float) -> void:
    if _boom_tip == null or _hook == null:
        return
    var tip := _boom_tip.global_position
    if not _hook_ready:
        _hook_position = tip + Vector3.DOWN * rope_length
        _hook_velocity = Vector3.ZERO
        _hook_ready = true

    var bob_mass := HOOK_MASS + _grip.load_mass()
    _hook_velocity.y -= MachineStability.GRAVITY * delta
    if _grip.is_holding():
        # The load hangs on the hook, so what the grip does to the load is
        # done back to the hook.
        _hook_velocity -= _grip.force / maxf(bob_mass, 1.0) * delta
    _hook_velocity *= exp(-HOOK_DAMPING * delta)
    _hook_position += _hook_velocity * delta

    var offset := _hook_position - tip
    var distance := offset.length()
    if distance < 0.0001:
        offset = Vector3.DOWN * rope_length
        distance = rope_length
    var radial := offset / distance
    _hook_position = tip + radial * rope_length
    var radial_speed := _hook_velocity.dot(radial)
    _hook_velocity -= radial * radial_speed

    # Rope pays out onto the ground rather than through it. A landed hook
    # is a real state: the rope goes slack and the pendulum stops.
    var floor_limit := _ground_height_at(_hook_position) + 0.46
    _hook_grounded = _hook_position.y < floor_limit
    if _hook_grounded:
        _hook_position.y = floor_limit
        _hook_velocity.y = maxf(_hook_velocity.y, 0.0)
        _hook_velocity.x *= 0.86
        _hook_velocity.z *= 0.86

    _hook.global_position = _hook_position
    _swing_speed = _hook_velocity.length()

    var reaction := _grip.update(_hook, _hook_velocity)
    held_load = _grip.held
    if _grip.slipped and hud != null and player_driver != null:
        hud.set_context("LOAD LOST // THE CLAMP COULD NOT HOLD IT")
    velocity -= reaction * (delta / 9000.0)


func is_hook_grounded() -> bool:
    return _hook_grounded


func _ground_height_at(point: Vector3) -> float:
    var world := get_world_3d()
    if world == null:
        return -1000.0
    var query := PhysicsRayQueryParameters3D.create(
        point + Vector3.UP * 3.0,
        point + Vector3.DOWN * 40.0,
        8
    )
    query.collide_with_areas = false
    query.exclude = [get_rid()]
    var hit := world.direct_space_state.intersect_ray(query)
    if hit.is_empty():
        return -1000.0
    return float((hit.position as Vector3).y)


func _update_rope_visual() -> void:
    if _rope == null or _boom_tip == null:
        return
    var tip := _boom_tip.global_position
    var span := _hook_position - tip
    var length := span.length()
    if length < 0.01:
        _rope.visible = false
        return
    _rope.visible = true
    _rope.global_position = tip + span * 0.5
    var up := span.normalized()
    var side := up.cross(Vector3.FORWARD)
    if side.length_squared() < 0.001:
        side = up.cross(Vector3.RIGHT)
    side = side.normalized()
    # Stretch the local Y column, not the parent frame: the rope has to grow
    # along its own length, whatever direction it is hanging in.
    _rope.global_basis = Basis(side, up * length, side.cross(up))


func _try_clamp() -> bool:
    if _hook_probe == null:
        return false
    var best = null
    var best_distance := INF
    for body in _hook_probe.get_overlapping_bodies():
        if body == self or body is CharacterBody3D:
            continue
        if not (body is RigidBody3D) or body.mass > GRAB_MASS_LIMIT:
            continue
        var distance: float = body.global_position.distance_to(_hook_position)
        if distance < best_distance:
            best_distance = distance
            best = body
    if best == null:
        return false
    if not _grip.grab(best, _hook, false):
        return false
    held_load = best
    _clamp_closure = 0.0
    if hud != null and player_driver != null:
        hud.set_context("CLAMPED // %d KG ON THE ROPE" % int(best.mass))
    return true


## Closing the jaws is work done on the load. It is the same crushing path
## an excavator bucket uses, so the surface marks, deforms and eventually
## fails through the authorities that already own those things.
func _update_clamp(delta: float) -> void:
    if not _grip.is_holding():
        _clamp_closure = move_toward(_clamp_closure, 0.0, delta * 2.0)
        _apply_jaw_pose()
        return

    var previous := _clamp_closure
    _clamp_closure = minf(1.0, _clamp_closure + delta * 0.85)
    _apply_jaw_pose()

    var closing := maxf(0.0, _clamp_closure - previous)
    var work := CLAMP_FORCE * CLAMP_TRAVEL * closing
    work += CLAMP_FORCE * CLAMP_CREEP * _clamp_closure * delta
    if work <= 0.0:
        return

    var load: RigidBody3D = _grip.held
    var jaw_point := _hook_position + Vector3.DOWN * 0.5
    var squeeze: Vector3 = load.global_position - _hook_position
    squeeze = (
        squeeze.normalized()
        if squeeze.length_squared() > 0.001
        else Vector3.DOWN
    )

    MaterialResponse.impact(
        load,
        jaw_point,
        squeeze,
        work,
        maxf(load.mass, 1.0),
        FoundryMaterial.HARDENED_STEEL,
        {
            "type": MaterialResponse.EVENT_MACHINE,
            "area": 0.16,
            "radius": 3.6,
            "fracture": clampf(_clamp_closure * 0.5, 0.0, 1.0),
            "novelty": 0.72
        }
    )
    if load.has_method("machine_hit_at"):
        load.machine_hit_at(
            work / 2600.0,
            squeeze,
            jaw_point,
            work
        )


func _apply_jaw_pose() -> void:
    if _jaw_left == null or _jaw_right == null:
        return
    var open := lerpf(0.42, 0.10, _clamp_closure)
    _jaw_left.position.x = -open
    _jaw_right.position.x = open
    _jaw_left.rotation.z = -0.30 * (1.0 - _clamp_closure)
    _jaw_right.rotation.z = 0.30 * (1.0 - _clamp_closure)


## A suspended load out at radius is an overturning moment. Swing it wide
## and the crane skids, then starts wrecking its own tracks.
func _update_tipping(delta: float) -> void:
    var radius := get_working_radius()
    var bob_mass := HOOK_MASS + _grip.load_mass()
    var moment := MachineStability.load_moment(bob_mass, radius)
    # Momentum in the swing adds to what the machine has to resist.
    moment += bob_mass * _swing_speed * _swing_speed * 0.5
    var half_base := lerpf(
        TRACK_HALF_WIDTH,
        TRACK_HALF_LENGTH,
        absf(cos(slew_angle))
    )
    var target := MachineStability.tipping_ratio(
        moment,
        machine_mass,
        half_base
    )
    if _grip.is_holding():
        target += _load_path_reaction * 0.16
    _tipping_ratio = move_toward(_tipping_ratio, target, delta * 2.4)

    var lever := _hook_position - global_position
    lever.y = 0.0
    _tip_direction_local = (
        (global_basis.inverse() * lever).normalized()
        if lever.length_squared() > 0.001
        else Vector3.ZERO
    )

    if _tipping_ratio <= 0.92:
        _tipping_damage_bank = maxf(0.0, _tipping_damage_bank - delta * 0.7)
        return

    var excess := clampf((_tipping_ratio - 0.92) / 0.5, 0.0, 1.5)
    if lever.length_squared() > 0.001:
        var skid := lever.normalized()
        velocity.x += skid.x * excess * 0.9
        velocity.z += skid.z * excess * 0.9

    _tipping_damage_bank += maxf(_tipping_ratio - 1.0, 0.0) ** 2 * delta * 16.0
    if _tipping_damage_bank >= 1.0:
        var damage := minf(_tipping_damage_bank, 3.0)
        _tipping_damage_bank -= damage
        hoist_health = maxf(0.0, hoist_health - damage * 0.9)
        _apply_machine_damage(damage * 0.5, Vector3.UP)

    if player_driver != null and _warn_cooldown <= 0.0 and hud != null:
        hud.set_context("RADIUS TOO GREAT // HOIST IN OR SLEW BACK")
        _warn_cooldown = 0.9


## The hook block, and anything clamped in it, carries the swing energy into
## whatever it meets. That energy is measured, not authored.
func _resolve_hook_contacts() -> void:
    _contact_targets.clear()
    if _hook_probe == null or _impact_cooldown > 0.0:
        return
    if _swing_speed < 1.2:
        return
    var bob_mass := HOOK_MASS + _grip.load_mass()
    var direction := _hook_velocity.normalized()
    var struck := false

    for body in _hook_probe.get_overlapping_bodies():
        if body == self or body == _grip.held:
            continue
        _contact_targets.append(body)
        var energy := EnergyPartition.collision_energy(
            bob_mass,
            _body_mass(body),
            _swing_speed
        )
        if body.has_method("machine_hit_at"):
            body.machine_hit_at(
                clampf(energy / 900.0, 4.0, 110.0),
                direction,
                _hook_position,
                energy
            )
            struck = true
        elif body.has_method("take_hit"):
            body.take_hit(
                direction * minf(_swing_speed * 3.4, 28.0) + Vector3.UP * 3.0,
                clampf(energy / 320.0, 12.0, 95.0)
            )
            struck = true
        elif body is RigidBody3D and not body.freeze:
            MaterialResponse.impact(
                body,
                _hook_position,
                direction,
                energy,
                body.mass,
                FoundryMaterial.HARDENED_STEEL,
                {"area": 0.14, "radius": 3.2}
            )
            body.apply_impulse(
                direction * minf(bob_mass * _swing_speed * 0.35, 4200.0),
                body.to_local(_hook_position)
            )
            struck = true

    if not struck:
        return
    _impact_cooldown = 0.22
    # The rope takes the reaction: a hook that just hit something stops.
    _hook_velocity *= 0.28
    if camera_rig != null and camera_rig.has_method("add_machine_impulse"):
        camera_rig.add_machine_impulse(
            clampf(0.014 + _swing_speed * 0.0035, 0.014, 0.055),
            direction
        )


func _body_mass(body: Node) -> float:
    if body is RigidBody3D:
        return maxf((body as RigidBody3D).mass, 1.0)
    var value = body.get("mass")
    if value != null:
        return maxf(float(value), 1.0)
    return 900.0


func _release_load(with_throw: bool) -> void:
    var had_load := _grip.is_holding()
    _grip.release(_hook_velocity, with_throw)
    held_load = null
    _clamp_closure = 0.0
    _apply_jaw_pose()
    if had_load and hud != null and player_driver != null:
        hud.set_context("LOAD RELEASED // ROPE FREE")


func _build_visual() -> void:
    var track_colour := Color(0.13, 0.13, 0.14)
    for side in [-1.0, 1.0]:
        var track := GeomUtil.box_mesh(
            Vector3(0.86, 0.92, 4.85),
            track_colour,
            0.96,
            0.04
        )
        track.position = Vector3(1.18 * side, 0.46, 0.0)
        add_child(track)
        for shoe_index in 7:
            var shoe := GeomUtil.box_mesh(
                Vector3(0.94, 0.14, 0.42),
                Color(0.19, 0.19, 0.20),
                0.92,
                0.18
            )
            shoe.position = Vector3(
                1.18 * side,
                0.05,
                -2.1 + float(shoe_index) * 0.70
            )
            add_child(shoe)

    var deck := GeomUtil.box_mesh(
        Vector3(3.05, 0.46, 4.20),
        Color(0.30, 0.31, 0.29),
        0.86,
        0.34
    )
    deck.position.y = 1.10
    add_child(deck)

    _slew = Node3D.new()
    _slew.name = "SlewRing"
    _slew.position.y = 1.36
    add_child(_slew)

    _house_shell = GeomUtil.box_mesh(
        Vector3(2.55, 1.70, 3.10),
        machine_tint,
        0.74,
        0.22
    )
    _house_shell.position = Vector3(0.0, 0.90, 0.95)
    _slew.add_child(_house_shell)

    var counterweight := GeomUtil.box_mesh(
        Vector3(2.70, 1.05, 0.95),
        Color(0.17, 0.17, 0.18),
        0.92,
        0.26
    )
    counterweight.position = Vector3(0.0, 0.62, 2.35)
    _slew.add_child(counterweight)

    var cab := GeomUtil.box_mesh(
        Vector3(1.05, 1.20, 1.25),
        Color(0.22, 0.24, 0.26),
        0.66,
        0.20
    )
    cab.position = Vector3(-1.30, 1.05, -0.35)
    _slew.add_child(cab)

    var glass := GeomUtil.box_mesh(
        Vector3(0.06, 0.78, 0.96),
        Color(0.42, 0.60, 0.68),
        0.16,
        0.10
    )
    glass.position = Vector3(-1.83, 1.18, -0.35)
    _slew.add_child(glass)

    _operator_view = Node3D.new()
    _operator_view.name = "OperatorView"
    _operator_view.position = Vector3(-1.30, 1.55, -0.60)
    _slew.add_child(_operator_view)

    _boom = Node3D.new()
    _boom.name = "Boom"
    _boom.position = BOOM_PIVOT
    _slew.add_child(_boom)

    var chord_offsets := [
        Vector3(-0.34, 0.30, 0.0),
        Vector3(0.34, 0.30, 0.0),
        Vector3(0.0, -0.34, 0.0)
    ]
    for chord_offset in chord_offsets:
        var chord := GeomUtil.box_mesh(
            Vector3(0.12, 0.12, BOOM_LENGTH),
            Color(0.56, 0.40, 0.08),
            0.78,
            0.30
        )
        chord.position = (chord_offset as Vector3) - Vector3(
            0.0,
            0.0,
            BOOM_LENGTH * 0.5
        )
        _boom.add_child(chord)

    for lace_index in 9:
        var lace := GeomUtil.box_mesh(
            Vector3(0.70, 0.07, 0.07),
            Color(0.48, 0.35, 0.09),
            0.82,
            0.28
        )
        lace.position = Vector3(
            0.0,
            0.0,
            -0.6 - float(lace_index) * (BOOM_LENGTH - 1.2) / 8.0
        )
        lace.rotation.z = 0.62 if lace_index % 2 == 0 else -0.62
        _boom.add_child(lace)

    _boom_tip = Node3D.new()
    _boom_tip.name = "BoomTip"
    _boom_tip.position = Vector3(0.0, 0.0, -BOOM_LENGTH)
    _boom.add_child(_boom_tip)

    var sheave := GeomUtil.cylinder_mesh(
        0.30,
        0.16,
        Color(0.24, 0.25, 0.26),
        0.62,
        0.52
    )
    sheave.rotation.z = PI * 0.5
    _boom_tip.add_child(sheave)

    _rope = GeomUtil.cylinder_mesh(
        0.035,
        1.0,
        Color(0.16, 0.16, 0.17),
        0.90,
        0.30
    )
    _rope.name = "HoistRope"
    _rope.top_level = true
    add_child(_rope)

    _hook = Node3D.new()
    _hook.name = "HookBlock"
    _hook.top_level = true
    add_child(_hook)

    var block := GeomUtil.box_mesh(
        Vector3(0.72, 0.54, 0.48),
        Color(0.45, 0.33, 0.07),
        0.80,
        0.34
    )
    _hook.add_child(block)

    _jaw_left = GeomUtil.box_mesh(
        Vector3(0.16, 0.86, 0.44),
        Color(0.29, 0.30, 0.31),
        0.66,
        0.56
    )
    _jaw_left.position = Vector3(-0.42, -0.62, 0.0)
    _hook.add_child(_jaw_left)

    _jaw_right = GeomUtil.box_mesh(
        Vector3(0.16, 0.86, 0.44),
        Color(0.29, 0.30, 0.31),
        0.66,
        0.56
    )
    _jaw_right.position = Vector3(0.42, -0.62, 0.0)
    _hook.add_child(_jaw_right)

    _hook_probe = Area3D.new()
    _hook_probe.name = "HookProbe"
    _hook_probe.collision_layer = 0
    _hook_probe.collision_mask = 1 | 4 | 8
    _hook.add_child(_hook_probe)
    var probe_shape := SphereShape3D.new()
    probe_shape.radius = HOOK_PROBE_RADIUS
    var probe_collision := CollisionShape3D.new()
    probe_collision.shape = probe_shape
    probe_collision.position.y = -0.5
    _hook_probe.add_child(probe_collision)

    _apply_jaw_pose()
