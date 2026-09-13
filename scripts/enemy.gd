class_name FoundryEnemy
extends CharacterBody3D

## Yard crew.
##
## An archetype is a different answer to the same question - how do I get at
## that target - not a different set of numbers. The rigger answers it by
## taking a machine, the plate carrier by putting steel between itself and
## the player, the thrower by using the yard as ammunition. Each of them
## reaches for an authority the game already owns rather than carrying its
## own private mechanism.

const GeomUtil = preload("res://scripts/geom.gd")
const HumanoidRigScript = preload("res://scripts/humanoid_motion.gd")
const ImpactFx = preload("res://scripts/impact_fx.gd")

const GRUNT := 0
const HEAVY := 1
const RUNNER := 2
const RIGGER := 3
const PLATE := 4
const THROWER := 5

const PLATE_SIZE := Vector3(0.94, 1.16, 0.07)
## Plastic work the plate can absorb before it is scrap, in joules.
const PLATE_CAPACITY := 42000.0
const MACHINE_SEEK_RANGE := 34.0
const MACHINE_MOUNT_RANGE := 2.7
const THROW_RANGE_MIN := 5.5
const THROW_RANGE_MAX := 17.0
const SALVAGE_RANGE := 8.0
## A dead body is mass the coupling law says should stay relevant: gravity,
## grabbable, throwable. Not a ragdoll - the pose is not simulated, only
## the body it drags across the yard.
const CORPSE_MASS := 78.0
const CORPSE_FLIGHT_SECONDS := 2.2

var target: Node3D
var health := 100.0
var max_health := 100.0
var speed := 3.9
var attack_damage := 14.0
var attack_reach := 1.68
var archetype := GRUNT
var attack_cooldown := 0.0
var attack_windup := 0.0
var attack_landed := false
var stagger := 0.0
var hit_anim := 0.0
var held := false
var dead := false
var flank_sign := 1.0

var _rig
var _plate: MeshInstance3D
var _plate_state: SurfaceState
var _plate_work := 0.0
var _machine_goal: FoundryMachine
var _grip := MachineGrip.new()
var _carry_anchor: Node3D
var _throw_cooldown := 0.0
var _salvage_cooldown := 0.0
var _corpse_flight_time := 0.0
var _corpse_flight_source: Node


static func archetype_stats(id: int) -> Dictionary:
    match id:
        HEAVY:
            return {
                "name": "BREAKER",
                "health": 155.0,
                "speed": 3.15,
                "damage": 21.0,
                "reach": 1.82,
                "windup": 0.46,
                "cooldown": 1.22,
                "resistance": 0.72,
                "stagger": 0.24,
                "flank": 0.65
            }
        RUNNER:
            return {
                "name": "RUNNER",
                "health": 78.0,
                "speed": 4.75,
                "damage": 11.0,
                "reach": 1.62,
                "windup": 0.34,
                "cooldown": 0.82,
                "resistance": 1.0,
                "stagger": 0.32,
                "flank": 1.30
            }
        RIGGER:
            return {
                "name": "RIGGER",
                "health": 92.0,
                "speed": 4.35,
                "damage": 12.0,
                "reach": 1.66,
                "windup": 0.34,
                "cooldown": 0.96,
                "resistance": 1.0,
                "stagger": 0.34,
                "flank": 1.05
            }
        PLATE:
            return {
                "name": "PLATE CARRIER",
                "health": 130.0,
                "speed": 2.95,
                "damage": 17.0,
                "reach": 1.74,
                "windup": 0.42,
                "cooldown": 1.14,
                "resistance": 0.84,
                "stagger": 0.26,
                "flank": 0.48
            }
        THROWER:
            return {
                "name": "THROWER",
                "health": 88.0,
                "speed": 3.65,
                "damage": 10.0,
                "reach": 1.60,
                "windup": 0.34,
                "cooldown": 1.05,
                "resistance": 1.0,
                "stagger": 0.34,
                "flank": 1.15
            }
        _:
            return {
                "name": "CREW",
                "health": 100.0,
                "speed": 3.9,
                "damage": 14.0,
                "reach": 1.68,
                "windup": 0.34,
                "cooldown": 1.02,
                "resistance": 1.0,
                "stagger": 0.32,
                "flank": 1.0
            }


func _ready() -> void:
    add_to_group("enemy")
    collision_layer = 4
    collision_mask = 1 | 2 | 8
    var collision := GeomUtil.add_capsule_collision(self, 0.42, 1.70)
    collision.position.y = 0.85
    flank_sign = -1.0 if int(get_instance_id()) % 2 == 0 else 1.0
    _apply_archetype()
    _rig = HumanoidRigScript.new()
    add_child(_rig)
    _rig.configure(false)
    _rig.set_attack_side(flank_sign)

    _carry_anchor = Node3D.new()
    _carry_anchor.name = "CarryAnchor"
    _carry_anchor.position = Vector3(0.0, 1.05, -0.72)
    add_child(_carry_anchor)


func configure_archetype(id: int) -> void:
    archetype = id
    if is_inside_tree():
        _apply_archetype()


func archetype_name() -> String:
    return str(archetype_stats(archetype).get("name", "CREW"))


func _apply_archetype() -> void:
    var stats := archetype_stats(archetype)
    max_health = float(stats.health)
    health = max_health
    speed = float(stats.speed)
    attack_damage = float(stats.damage)
    attack_reach = float(stats.reach)
    if archetype == PLATE and _plate == null:
        _build_plate()


## The plate is a real surface with a real identity, so what ruins it is
## the same accumulated work that ruins any other steel in the yard.
func _build_plate() -> void:
    _plate = GeomUtil.box_mesh(
        PLATE_SIZE,
        Color(0.42, 0.36, 0.22),
        0.84,
        0.36
    )
    _plate.name = "CarriedPlate"
    _plate.position = Vector3(0.16, 1.02, -0.52)
    add_child(_plate)
    _plate_state = MaterialResponse.register(
        _plate,
        FoundryMaterial.PAINTED_STEEL,
        Color(0.42, 0.36, 0.22)
    )


func is_carrying() -> bool:
    return _grip.is_holding()


func carried_load():
    return _grip.held


func machine_goal():
    return _machine_goal


func plate_integrity() -> float:
    if _plate == null or not is_instance_valid(_plate):
        return 0.0
    return clampf(1.0 - _plate_work / PLATE_CAPACITY, 0.0, 1.0)


func set_target(node: Node3D) -> void:
    target = node


func take_hit(force: Vector3, damage: float) -> void:
    if dead:
        return
    var stats := archetype_stats(archetype)
    var incoming := damage
    var fx_dir := force.normalized() if force.length_squared() > 0.001 else Vector3.UP

    if _plate != null and is_instance_valid(_plate) and plate_integrity() > 0.0:
        var facing := -global_basis.z
        var frontal := fx_dir.dot(facing)
        # Only what arrives at the face of the plate is stopped by it.
        if frontal < -0.25:
            incoming = _absorb_with_plate(incoming, force, fx_dir)

    health -= incoming
    stagger = float(stats.stagger)
    hit_anim = 0.30
    attack_windup = 0.0
    attack_landed = false
    velocity += force * float(stats.resistance)
    ImpactFx.spawn(
        get_parent(),
        global_position + Vector3.UP * 1.15,
        fx_dir,
        Color(0.86, 0.48, 0.16),
        clampf(incoming / 18.0, 0.8, 3.0),
        8
    )
    if health <= 0.0:
        dead = true
        collision_layer = 0
        collision_mask = 1 | 8
        velocity += force * 0.75
        _drop_carried()
        ImpactFx.spawn(
            get_parent(),
            global_position + Vector3.UP * 0.9,
            fx_dir,
            Color(0.55, 0.34, 0.18),
            2.6,
            11
        )


func _absorb_with_plate(
        damage: float,
        force: Vector3,
        direction: Vector3
) -> float:
    var integrity := plate_integrity()
    var energy := 0.5 * 92.0 * force.length_squared() + damage * 180.0
    _plate_work += energy
    MaterialResponse.impact(
        _plate,
        _plate.global_position,
        direction,
        energy,
        62.0,
        FoundryMaterial.HARDENED_STEEL,
        {"area": 0.18, "radius": 2.6, "fracture": 1.0 - integrity}
    )
    if _plate_state != null:
        _plate_state.apply_to_material(
            _plate.material_override as StandardMaterial3D
        )
    var absorbed := damage * (0.20 + integrity * 0.62)
    if plate_integrity() <= 0.0:
        _shed_plate(direction)
    return maxf(damage - absorbed, damage * 0.18)


## When the plate finally gives, it becomes debris carrying every mark the
## fight put on it.
func _shed_plate(direction: Vector3) -> void:
    if _plate == null or not is_instance_valid(_plate):
        return
    var origin := _plate.global_position
    var parent := get_parent()
    _plate.queue_free()
    _plate = null
    if parent == null:
        return

    var scrap := StructuralDebris.new()
    parent.add_child(scrap)
    scrap.global_position = origin
    scrap.configure(
        PLATE_SIZE,
        Color(0.38, 0.33, 0.20),
        58.0,
        70.0,
        "plate"
    )
    scrap.bind_surface_state(
        MaterialResponse.adopt_fragment(scrap, _plate_state, 0.25)
    )
    scrap.apply_central_impulse(
        direction.normalized() * 130.0 + Vector3.UP * 90.0
    )
    _plate_state = null


func receive_hazard_hit(damage: float, impulse: Vector3) -> void:
    take_hit(impulse, damage)


func set_held(value: bool) -> void:
    held = value
    if held:
        velocity = Vector3.ZERO
        attack_windup = 0.0
        _corpse_flight_time = 0.0


## Thrown, not carried: the corpse becomes a projectile with its own
## momentum and does real damage to whatever it hits, the same way a
## thrown crate does.
func launch(throw_velocity: Vector3, source: Node = null) -> void:
    if not dead:
        return
    held = false
    velocity = throw_velocity
    _corpse_flight_source = source
    _corpse_flight_time = CORPSE_FLIGHT_SECONDS


func _physics_process(delta: float) -> void:
    attack_cooldown = maxf(0.0, attack_cooldown - delta)
    stagger = maxf(0.0, stagger - delta)
    hit_anim = maxf(0.0, hit_anim - delta)
    _throw_cooldown = maxf(0.0, _throw_cooldown - delta)
    _salvage_cooldown = maxf(0.0, _salvage_cooldown - delta)

    if held:
        velocity = Vector3.ZERO
        _animate(delta)
        return
    if not is_on_floor():
        velocity.y -= 24.0 * delta
    if dead:
        var in_flight := _corpse_flight_time > 0.0
        if in_flight:
            _corpse_flight_time -= delta
        else:
            velocity.x = move_toward(velocity.x, 0.0, 5.5 * delta)
            velocity.z = move_toward(velocity.z, 0.0, 5.5 * delta)
        move_and_slide()
        if in_flight:
            _resolve_corpse_impact()
        _animate(delta)
        return
    if target == null or not is_instance_valid(target):
        move_and_slide()
        _animate(delta)
        return

    if _pursue_archetype_goal(delta):
        move_and_slide()
        _animate(delta)
        return

    var to_target: Vector3 = target.global_position - global_position
    to_target.y = 0.0
    var dist: float = to_target.length()
    var machine_target := target.is_in_group("machine")
    var desired_range := 2.15 if machine_target else 1.52
    var strike_range := 2.55 if machine_target else attack_reach
    var stats := archetype_stats(archetype)

    if attack_windup > 0.0:
        var previous := attack_windup
        attack_windup = maxf(0.0, attack_windup - delta)
        velocity.x = move_toward(velocity.x, 0.0, 24.0 * delta)
        velocity.z = move_toward(velocity.z, 0.0, 24.0 * delta)
        if to_target.length_squared() > 0.01:
            var attack_dir := to_target.normalized()
            rotation.y = lerp_angle(
                rotation.y,
                atan2(-attack_dir.x, -attack_dir.z),
                0.34
            )
        if previous > 0.17 and attack_windup <= 0.17 and not attack_landed:
            attack_landed = true
            if dist <= strike_range and target.has_method("receive_enemy_hit"):
                var damage := attack_damage * (
                    1.12 if machine_target and archetype == HEAVY else 1.0
                )
                target.receive_enemy_hit(damage)
                if target is CharacterBody3D:
                    target.velocity += to_target.normalized() * (
                        1.4 if machine_target else 2.4
                    )
        move_and_slide()
        _animate(delta)
        return

    if dist > desired_range and stagger <= 0.0:
        var dir: Vector3 = to_target.normalized()
        var tangent := Vector3(-dir.z, 0.0, dir.x) * flank_sign
        var separation := _separation_force()
        var flank_weight := clampf(
            (dist - desired_range) / 6.0,
            0.0,
            0.42
        ) * float(stats.flank)
        var move_dir := (
            dir + tangent * flank_weight + separation * 0.85
        ).normalized()
        velocity.x = move_toward(velocity.x, move_dir.x * speed, 18.0 * delta)
        velocity.z = move_toward(velocity.z, move_dir.z * speed, 18.0 * delta)
        rotation.y = rotate_toward(
            rotation.y,
            atan2(-dir.x, -dir.z),
            deg_to_rad(138.0) * delta
        )
    else:
        velocity.x = move_toward(velocity.x, 0.0, 20.0 * delta)
        velocity.z = move_toward(velocity.z, 0.0, 20.0 * delta)
        if dist <= strike_range and attack_cooldown <= 0.0 and stagger <= 0.0:
            attack_cooldown = float(stats.cooldown)
            attack_windup = float(stats.windup)
            attack_landed = false
            flank_sign *= -1.0
            if _rig != null:
                _rig.set_attack_side(flank_sign)

    move_and_slide()
    _animate(delta)


## Returns true when the archetype is doing something other than closing on
## the target, and has already set its own velocity this tick.
func _pursue_archetype_goal(delta: float) -> bool:
    match archetype:
        RIGGER:
            return _work_toward_machine(delta)
        THROWER:
            return _work_the_scrap_pile(delta)
        _:
            return false


## The rigger's answer to a fight is to go and get a machine - but only when
## the target is far enough away to be worth the walk. Up close it fights.
func _work_toward_machine(delta: float) -> bool:
    if not is_instance_valid(_machine_goal) or not _machine_claimable(_machine_goal):
        _machine_goal = null
        var reach: Vector3 = target.global_position - global_position
        reach.y = 0.0
        if reach.length() > 7.0:
            _machine_goal = _find_claimable_machine()
    if _machine_goal == null:
        return false

    var to_machine: Vector3 = _machine_goal.global_position - global_position
    to_machine.y = 0.0
    var distance := to_machine.length()
    if distance <= MACHINE_MOUNT_RANGE:
        _machine_goal.set_enemy_driver(self)
        if _machine_goal.has_method("set_target"):
            _machine_goal.set_target(target)
        _machine_goal = null
        return true

    var dir := to_machine.normalized()
    velocity.x = move_toward(velocity.x, dir.x * speed, 18.0 * delta)
    velocity.z = move_toward(velocity.z, dir.z * speed, 18.0 * delta)
    rotation.y = rotate_toward(
        rotation.y,
        atan2(-dir.x, -dir.z),
        deg_to_rad(150.0) * delta
    )
    return true


func _machine_claimable(machine: FoundryMachine) -> bool:
    if machine == null or not is_instance_valid(machine):
        return false
    if machine.disabled or machine.player_driver != null:
        return false
    return machine.enemy_driver == null


func _find_claimable_machine() -> FoundryMachine:
    var best: FoundryMachine = null
    var best_distance := MACHINE_SEEK_RANGE
    for node in get_tree().get_nodes_in_group("machine"):
        var machine := node as FoundryMachine
        if not _machine_claimable(machine):
            continue
        var distance := machine.global_position.distance_to(global_position)
        if distance < best_distance:
            best_distance = distance
            best = machine
    return best


## The thrower's answer is that the yard is full of ammunition.
func _work_the_scrap_pile(delta: float) -> bool:
    var to_target: Vector3 = target.global_position - global_position
    to_target.y = 0.0
    var distance := to_target.length()

    if _grip.is_holding():
        _grip.update(_carry_anchor, velocity)
        if (
            distance >= THROW_RANGE_MIN
            and distance <= THROW_RANGE_MAX
            and _throw_cooldown <= 0.0
        ):
            _throw_at_target(to_target, distance)
            return true
        if distance < THROW_RANGE_MIN:
            var away := -to_target.normalized()
            velocity.x = move_toward(velocity.x, away.x * speed, 16.0 * delta)
            velocity.z = move_toward(velocity.z, away.z * speed, 16.0 * delta)
            rotation.y = rotate_toward(
                rotation.y,
                atan2(to_target.x, to_target.z),
                deg_to_rad(140.0) * delta
            )
            return true
        return false

    if _salvage_cooldown > 0.0:
        return false
    var salvage := _find_salvage()
    if salvage == null:
        _salvage_cooldown = 1.4
        return false

    var to_salvage: Vector3 = salvage.global_position - global_position
    to_salvage.y = 0.0
    if to_salvage.length() <= 1.6:
        if _grip.grab(salvage, _carry_anchor, false):
            _throw_cooldown = 0.55
        else:
            _salvage_cooldown = 1.0
        return true

    var dir := to_salvage.normalized()
    velocity.x = move_toward(velocity.x, dir.x * speed, 16.0 * delta)
    velocity.z = move_toward(velocity.z, dir.z * speed, 16.0 * delta)
    rotation.y = rotate_toward(
        rotation.y,
        atan2(-dir.x, -dir.z),
        deg_to_rad(140.0) * delta
    )
    return true


func _throw_at_target(to_target: Vector3, distance: float) -> void:
    var load: RigidBody3D = _grip.held
    if load == null or not is_instance_valid(load):
        _grip.release(Vector3.ZERO, false)
        return
    # Lob it: enough arc to arrive rather than skid along the ground.
    var flat := to_target.normalized()
    var launch_speed := clampf(9.0 + distance * 0.55, 9.0, 17.0)
    var throw_velocity := (
        flat * launch_speed
        + Vector3.UP * clampf(2.6 + distance * 0.16, 2.6, 6.0)
    )
    _grip.release(Vector3.ZERO, false)
    if load.has_method("launch"):
        load.launch(throw_velocity, self)
    elif load is RigidBody3D:
        load.linear_velocity = throw_velocity
    _throw_cooldown = 2.6
    attack_windup = 0.0
    rotation.y = atan2(-flat.x, -flat.z)


func _find_salvage() -> RigidBody3D:
    var best: RigidBody3D = null
    var best_distance := SALVAGE_RANGE
    for node in get_tree().get_nodes_in_group("physics_prop"):
        var prop := node as RigidBody3D
        if prop == null or not is_instance_valid(prop):
            continue
        if not prop.has_method("launch"):
            continue
        if bool(prop.get("held")) or prop.mass > 120.0:
            continue
        var distance := prop.global_position.distance_to(global_position)
        if distance < best_distance:
            best_distance = distance
            best = prop
    return best


func _drop_carried() -> void:
    if _grip.is_holding():
        _grip.release(Vector3.ZERO, false)


## What a thrown body hits takes real damage. No material record is kept
## on the surface it struck: a body is not part of the closed material
## catalog, and inventing a soft-tissue identity for it would be exactly
## the "browse until it looks cool" the catalog is closed against.
func _resolve_corpse_impact() -> void:
    var speed := velocity.length()
    if speed < 2.5:
        _corpse_flight_time = 0.0
        return
    var direction := velocity.normalized() if speed > 0.0001 else Vector3.UP
    for i in get_slide_collision_count():
        var collision := get_slide_collision(i)
        var body: Object = collision.get_collider()
        if body == null or body == self or body == _corpse_flight_source:
            continue
        var energy := EnergyPartition.collision_energy(
            CORPSE_MASS,
            _collided_mass(body),
            speed
        )
        var damage := clampf(energy / 300.0, 6.0, 60.0)
        var point: Vector3 = collision.get_position()
        if body.has_method("machine_hit_at"):
            body.machine_hit_at(damage, direction, point, energy)
        elif body.has_method("machine_hit"):
            body.machine_hit(damage, direction, point)
        elif body.has_method("take_hit"):
            body.take_hit(
                direction * minf(speed * 0.8, 14.0) + Vector3.UP * 2.0,
                damage
            )
        elif body.has_method("receive_enemy_hit"):
            body.receive_enemy_hit(damage)
        _corpse_flight_time = 0.0
        return


func _collided_mass(body: Object) -> float:
    if body is RigidBody3D:
        return maxf((body as RigidBody3D).mass, 1.0)
    if body is CharacterBody3D:
        return 90.0
    return 900.0


func _separation_force() -> Vector3:
    var force := Vector3.ZERO
    for other in get_tree().get_nodes_in_group("enemy"):
        if other == self or not is_instance_valid(other) or other.dead:
            continue
        var away: Vector3 = global_position - other.global_position
        away.y = 0.0
        var d := away.length()
        if d > 0.01 and d < 2.15:
            force += away.normalized() * (1.0 - d / 2.15)
    return force


func _animate(delta: float) -> void:
    if _rig == null:
        return
    var planar := Vector2(velocity.x, velocity.z).length()
    var windup_total := float(archetype_stats(archetype).windup)
    var attack_amount := (
        attack_windup / windup_total if attack_windup > 0.0 else 0.0
    )
    var hit_amount := hit_anim / 0.30 if hit_anim > 0.0 else 0.0
    _rig.animate(delta, planar, speed, attack_amount, hit_amount, dead)
