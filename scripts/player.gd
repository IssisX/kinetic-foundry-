class_name FoundryPlayer
extends CharacterBody3D

const GeomUtil = preload("res://scripts/geom.gd")
const HumanoidRigScript = preload("res://scripts/humanoid_rig.gd")

signal request_machine_entry(player)

var hud
var camera_rig
var health := 180.0
var max_health := 180.0
var speed := 7.4
var sprint_speed := 10.2

# Progression-backed physical affordances.
var grab_mass_limit := 110.0
var melee_force_multiplier := 1.0
var throw_force_multiplier := 1.0
var machine_climb_range := 5.8
var damage_reduction := 0.0
var hazard_reduction := 0.0

var engaged_target
var engage_timer := 0.0
var held_target
var attack_cooldown := 0.0
var attack_anim := 0.0
var attack_duration := 0.28
var attack_mode := 0
var hit_anim := 0.0
var combo_window := 0.0
var combo_step := 0
var attack_side := 1.0
var traversal_lock := 0.0
var _rig

var machine_climb_target
var machine_climb_active := false
var machine_climb_time := 0.0
var machine_climb_duration := 0.72
var machine_climb_start := Vector3.ZERO
var machine_climb_side := -1.0
var _normal_collision_mask := 0

func _ready() -> void:
    add_to_group("player")
    collision_layer = 1
    collision_mask = 1 | 2 | 4 | 8
    _normal_collision_mask = collision_mask
    var collision: CollisionShape3D = GeomUtil.add_capsule_collision(self, 0.46, 1.82)
    collision.position.y = 0.91
    _rig = HumanoidRigScript.new()
    add_child(_rig)
    _rig.configure(true)

func configure(controls, camera) -> void:
    hud = controls
    camera_rig = camera

func receive_enemy_hit(damage: float) -> void:
    if machine_climb_active:
        _cancel_machine_climb()
    var applied: float = damage * (1.0 - clampf(damage_reduction, 0.0, 0.8))
    health = maxf(0.0, health - applied)
    hit_anim = 0.28
    if hud != null and hud.has_method("flash_damage"):
        hud.flash_damage()

func receive_hazard_hit(damage: float, impulse: Vector3) -> void:
    var hazard_scale: float = 1.0 - clampf(hazard_reduction, 0.0, 0.8)
    receive_enemy_hit(damage * hazard_scale)
    velocity += impulse * (0.55 + hazard_scale * 0.45)

func begin_machine_climb(machine) -> bool:
    if machine == null or not is_instance_valid(machine):
        return false
    if machine_climb_active or held_target != null or health <= 0.0:
        return false
    var distance: float = global_position.distance_to(machine.global_position)
    if distance > machine_climb_range:
        return false
    machine_climb_target = machine
    machine_climb_active = true
    machine_climb_time = 0.0
    machine_climb_start = global_position
    var lateral: float = (global_position - machine.global_position).dot(machine.global_basis.x)
    machine_climb_side = -1.0 if lateral <= 0.0 else 1.0
    traversal_lock = machine_climb_duration
    velocity = Vector3.ZERO
    collision_mask = 0
    if hud != null and hud.has_method("set_context"):
        hud.set_context("LATCH // CLIMB MOVING MACHINE")
    return true

func _cancel_machine_climb() -> void:
    machine_climb_active = false
    machine_climb_target = null
    machine_climb_time = 0.0
    collision_mask = _normal_collision_mask

func _update_machine_climb(delta: float) -> void:
    if not machine_climb_active:
        return
    if machine_climb_target == null or not is_instance_valid(machine_climb_target):
        _cancel_machine_climb()
        return
    if machine_climb_target.has_method("is_player_driven") and machine_climb_target.is_player_driven():
        _cancel_machine_climb()
        return

    machine_climb_time += delta
    var raw_t: float = clampf(machine_climb_time / machine_climb_duration, 0.0, 1.0)
    var t: float = raw_t * raw_t * (3.0 - 2.0 * raw_t)
    var machine = machine_climb_target
    var side_point: Vector3 = machine.global_position + machine.global_basis.x * machine_climb_side * 1.72 + machine.global_basis.z * 0.32 + Vector3.UP * 1.05
    var cab_point: Vector3 = machine.global_position - machine.global_basis.x * 0.95 + machine.global_basis.z * 0.12 + Vector3.UP * 1.72
    var mid_t: float = clampf(t * 1.8, 0.0, 1.0)
    var finish_t: float = clampf((t - 0.48) / 0.52, 0.0, 1.0)
    var approach: Vector3 = machine_climb_start.lerp(side_point, mid_t)
    var mount: Vector3 = side_point.lerp(cab_point, finish_t)
    var path: Vector3 = approach.lerp(mount, finish_t)
    path.y += sin(t * PI) * 0.72
    global_position = path

    var face: Vector3 = machine.global_position - global_position
    face.y = 0.0
    if face.length_squared() > 0.01:
        rotation.y = lerp_angle(rotation.y, atan2(-face.x, -face.z), 0.34)
    if _rig != null:
        _rig.pose_climb(t, machine_climb_side)

    if raw_t >= 1.0:
        machine_climb_active = false
        collision_mask = _normal_collision_mask
        if machine.has_method("try_enter") and machine.try_enter(self):
            machine_climb_target = null
            return
        machine_climb_target = null
        global_position = side_point

func _physics_process(delta: float) -> void:
    if hud == null or camera_rig == null:
        return
    attack_cooldown = maxf(0.0, attack_cooldown - delta)
    attack_anim = maxf(0.0, attack_anim - delta)
    hit_anim = maxf(0.0, hit_anim - delta)
    combo_window = maxf(0.0, combo_window - delta)
    traversal_lock = maxf(0.0, traversal_lock - delta)
    engage_timer = maxf(0.0, engage_timer - delta)
    if combo_window <= 0.0:
        combo_step = 0
    if engage_timer <= 0.0 and held_target == null:
        engaged_target = null

    if machine_climb_active:
        camera_rig.apply_look(hud.consume_look())
        _update_machine_climb(delta)
        _update_hud()
        return

    var axis: Vector2 = hud.move_axis + _keyboard_axis()
    if axis.length() > 1.0:
        axis = axis.normalized()
    var forward: Vector3 = camera_rig.flat_forward()
    var right: Vector3 = camera_rig.flat_right()
    var desired: Vector3 = right * axis.x + forward * -axis.y
    var target_speed: float = speed
    if axis.length() > 0.94:
        target_speed = sprint_speed
    if attack_anim > 0.0:
        target_speed *= 0.42

    if traversal_lock <= 0.0:
        if desired.length_squared() > 0.001:
            desired = desired.normalized()
            velocity.x = move_toward(velocity.x, desired.x * target_speed, 32.0 * delta)
            velocity.z = move_toward(velocity.z, desired.z * target_speed, 32.0 * delta)
            if attack_anim <= 0.0:
                rotation.y = lerp_angle(rotation.y, atan2(-desired.x, -desired.z), 0.22)
        else:
            velocity.x = move_toward(velocity.x, 0.0, 30.0 * delta)
            velocity.z = move_toward(velocity.z, 0.0, 30.0 * delta)

    if not is_on_floor():
        velocity.y -= 26.0 * delta

    var look: Vector2 = hud.consume_look()
    camera_rig.apply_look(look)
    if hud.consume_attack() or _keyboard_attack():
        _attack()
    if hud.consume_grab() or _keyboard_grab():
        _grab_or_throw()
    if hud.consume_use() or _keyboard_use():
        if not _try_traversal():
            request_machine_entry.emit(self)

    if held_target != null and is_instance_valid(held_target):
        _update_held_target()

    move_and_slide()
    _animate(delta)
    _update_hud()

func _try_traversal() -> bool:
    if traversal_lock > 0.0 or not is_on_floor() or held_target != null:
        return false
    var space: PhysicsDirectSpaceState3D = get_world_3d().direct_space_state
    var forward: Vector3 = -global_basis.z
    var low_from: Vector3 = global_position + Vector3.UP * 0.65
    var low_to: Vector3 = low_from + forward * 1.35
    var low_query: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.create(low_from, low_to, 2 | 8)
    low_query.exclude = [self]
    var low_hit: Dictionary = space.intersect_ray(low_query)
    if low_hit.is_empty():
        return false
    var high_from: Vector3 = global_position + Vector3.UP * 1.45
    var high_to: Vector3 = high_from + forward * 1.45
    var high_query: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.create(high_from, high_to, 2 | 8)
    high_query.exclude = [self]
    var high_hit: Dictionary = space.intersect_ray(high_query)
    if high_hit.is_empty():
        velocity = forward * 8.8 + Vector3.UP * 6.8
        traversal_lock = 0.34
        if hud != null and hud.has_method("set_context"):
            hud.set_context("VAULT")
        return true
    var chest_from: Vector3 = global_position + Vector3.UP * 1.72
    var chest_to: Vector3 = chest_from + forward * 1.15
    var chest_query: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.create(chest_from, chest_to, 2 | 8)
    chest_query.exclude = [self]
    var chest_hit: Dictionary = space.intersect_ray(chest_query)
    if chest_hit.is_empty():
        velocity = forward * 5.2 + Vector3.UP * 8.2
        traversal_lock = 0.44
        if hud != null and hud.has_method("set_context"):
            hud.set_context("MANTLE")
        return true
    return false

func _keyboard_axis() -> Vector2:
    var axis: Vector2 = Vector2.ZERO
    if Input.is_physical_key_pressed(KEY_A): axis.x -= 1.0
    if Input.is_physical_key_pressed(KEY_D): axis.x += 1.0
    if Input.is_physical_key_pressed(KEY_W): axis.y -= 1.0
    if Input.is_physical_key_pressed(KEY_S): axis.y += 1.0
    return axis

func _keyboard_attack() -> bool:
    return Input.is_physical_key_pressed(KEY_J)

func _keyboard_grab() -> bool:
    return Input.is_physical_key_pressed(KEY_K)

func _keyboard_use() -> bool:
    return Input.is_physical_key_pressed(KEY_E)

func _attack() -> void:
    if attack_cooldown > 0.0 or traversal_lock > 0.0:
        return
    var planar_speed: float = Vector2(velocity.x, velocity.z).length()
    var target = _find_target(3.05 if planar_speed > speed * 0.92 else 2.35)
    var sprint_tackle: bool = target != null and planar_speed > speed * 0.92 and combo_step == 0

    attack_side *= -1.0
    attack_mode = 2 if sprint_tackle else (1 if combo_step == 2 else 0)
    attack_duration = 0.42 if sprint_tackle else (0.38 if attack_mode == 1 else 0.28)
    attack_anim = attack_duration
    attack_cooldown = 0.58 if sprint_tackle else (0.40 if attack_mode == 1 else 0.24)
    if _rig != null:
        _rig.set_attack_side(attack_side)
        _rig.set_attack_mode(attack_mode)

    if held_target != null and is_instance_valid(held_target):
        var throw_dir: Vector3 = -global_basis.z
        held_target.set_held(false)
        var throw_mult: float = maxf(throw_force_multiplier, 0.5)
        held_target.take_hit(throw_dir * 17.0 * throw_mult + Vector3.UP * 6.2 * throw_mult, 38.0 * throw_mult)
        held_target = null
        combo_step = 0
        combo_window = 0.0
        return

    if target != null:
        engaged_target = target
        engage_timer = 1.15
        var dir: Vector3 = target.global_position - global_position
        dir.y = 0.0
        if dir.length_squared() < 0.01:
            dir = -global_basis.z
        dir = dir.normalized()
        rotation.y = lerp_angle(rotation.y, atan2(-dir.x, -dir.z), 0.72 if sprint_tackle else 0.62)

        var strength: float = maxf(melee_force_multiplier, 0.5)
        var damage: float = (36.0 if sprint_tackle else float([24.0, 29.0, 44.0][combo_step])) * strength
        var push_strength: float = (16.0 if sprint_tackle else float([7.4, 8.8, 16.5][combo_step])) * strength
        var lift: float = (1.1 if sprint_tackle else float([1.5, 2.0, 2.6][combo_step])) * minf(strength, 1.6)
        velocity += dir * (4.7 if sprint_tackle else (3.2 if combo_step == 2 else 1.7))
        target.take_hit(dir * push_strength + Vector3.UP * lift, damage)
        if sprint_tackle:
            traversal_lock = 0.18
            combo_step = 1
            combo_window = 0.72
            if hud != null:
                hud.set_context("SHOULDER DRIVE // TARGET DISPLACED")
        else:
            combo_step = (combo_step + 1) % 3
            combo_window = 0.72
            if attack_mode == 1 and hud != null:
                hud.set_context("SIDE KICK // HEAVY FINISHER")
        return

    var prop = _find_prop(2.15)
    if prop != null:
        var prop_dir: Vector3 = prop.global_position - global_position
        prop_dir.y = 0.0
        if prop_dir.length_squared() < 0.01:
            prop_dir = -global_basis.z
        prop_dir = prop_dir.normalized()
        var strength: float = maxf(melee_force_multiplier, 0.5)
        var prop_damage: float = (34.0 if attack_mode == 1 else 19.0) * strength
        prop.take_hit(prop_dir * (12.5 if attack_mode == 1 else 9.5) * strength + Vector3.UP * 1.9, prop_damage)
        velocity += prop_dir * 0.8
    combo_step = 0
    combo_window = 0.0

func _grab_or_throw() -> void:
    if traversal_lock > 0.0:
        return
    if held_target != null and is_instance_valid(held_target):
        var dir: Vector3 = -global_basis.z
        var throw_mult: float = maxf(throw_force_multiplier, 0.5)
        held_target.set_held(false)
        held_target.take_hit(dir * 13.5 * throw_mult + Vector3.UP * 5.2 * throw_mult, 24.0 * throw_mult)
        held_target = null
        return
    var target = _find_grabbable(1.90)
    if target == null:
        return
    held_target = target
    if target.is_in_group("enemy"):
        engaged_target = target
        engage_timer = 2.0
    target.set_held(true)

func _update_held_target() -> void:
    var hold_height: float = 1.20
    if held_target.is_in_group("physics_prop"):
        hold_height = 1.40
    var hold_pos: Vector3 = global_position - global_basis.z * 1.12 + Vector3.UP * hold_height
    held_target.global_position = held_target.global_position.lerp(hold_pos, 0.52)
    held_target.rotation.y = rotation.y

func _find_grabbable(radius: float):
    var best = null
    var best_score: float = -9999.0
    var forward: Vector3 = -global_basis.z
    var candidates: Array = []
    candidates.append_array(get_tree().get_nodes_in_group("enemy"))
    candidates.append_array(get_tree().get_nodes_in_group("physics_prop"))
    for node in candidates:
        if not is_instance_valid(node):
            continue
        if node.is_in_group("enemy") and node.dead:
            continue
        if node.is_in_group("physics_prop") and node.mass > grab_mass_limit:
            continue
        var offset: Vector3 = node.global_position - global_position
        var dist: float = offset.length()
        if dist > radius:
            continue
        var dir: Vector3 = offset.normalized()
        var score: float = forward.dot(dir) * 2.2 - dist * 0.60
        if score > best_score:
            best_score = score
            best = node
    return best

func _find_prop(radius: float):
    var best = null
    var best_score: float = -9999.0
    var forward: Vector3 = -global_basis.z
    for prop in get_tree().get_nodes_in_group("physics_prop"):
        if not is_instance_valid(prop):
            continue
        var offset: Vector3 = prop.global_position - global_position
        var dist: float = offset.length()
        if dist > radius:
            continue
        var dir: Vector3 = offset.normalized()
        var score: float = forward.dot(dir) * 2.0 - dist * 0.55
        if score > best_score:
            best_score = score
            best = prop
    return best

func _find_target(radius: float):
    if engaged_target != null and is_instance_valid(engaged_target):
        var d: float = global_position.distance_to(engaged_target.global_position)
        if d <= radius * 1.30:
            return engaged_target
    var best = null
    var best_score: float = -9999.0
    var forward: Vector3 = -global_basis.z
    for enemy in get_tree().get_nodes_in_group("enemy"):
        if not enemy.visible or enemy.dead:
            continue
        var offset: Vector3 = enemy.global_position - global_position
        var dist: float = offset.length()
        if dist > radius:
            continue
        var dir: Vector3 = offset.normalized()
        var facing: float = forward.dot(dir)
        var score: float = facing * 2.0 - dist * 0.55
        if score > best_score:
            best_score = score
            best = enemy
    return best

func _animate(delta: float) -> void:
    if _rig == null:
        return
    var planar: float = Vector2(velocity.x, velocity.z).length()
    var attack_amount: float = attack_anim / maxf(attack_duration, 0.01) if attack_anim > 0.0 else 0.0
    var hit_amount: float = hit_anim / 0.28 if hit_anim > 0.0 else 0.0
    _rig.animate(delta, planar, speed, attack_amount, hit_amount, health <= 0.0)

func _update_hud() -> void:
    if hud == null:
        return
    if hud.has_method("set_health"):
        hud.set_health(health / max_health)
    if hud.has_method("set_target"):
        hud.set_target(engaged_target)
    if machine_climb_active:
        hud.set_context("LATCHED // CLIMBING MACHINE")
    elif held_target != null and is_instance_valid(held_target):
        if held_target.is_in_group("enemy"):
            hud.set_context("GRAPPLE // HIT TO THROW")
        elif held_target.is_in_group("physics_prop"):
            hud.set_context("LOAD HELD // HIT TO LAUNCH")
    elif traversal_lock <= 0.0 and engage_timer <= 0.0:
        hud.set_context("POWER // COMBAT // MACHINES")
