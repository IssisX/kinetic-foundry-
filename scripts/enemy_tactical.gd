class_name FoundryTacticalEnemy
extends "res://scripts/enemy.gd"

const AGGRO_RADIUS := 10.5
const LEASH_RADIUS := 13.5
const RETURN_STOP_RADIUS := 1.15
const AGGRO_MEMORY_SECONDS := 4.2

var _home_position := Vector3.ZERO
var _engagement_memory := 0.0

func _ready() -> void:
    super()
    _home_position = global_position

func take_hit(force: Vector3, damage: float) -> void:
    _engagement_memory = AGGRO_MEMORY_SECONDS
    super(force, damage)

func set_target(node: Node3D) -> void:
    # Assignment does not equal permanent pursuit. The target becomes actionable
    # only inside this enemy's territory or after a real combat interaction.
    target = node

func _physics_process(delta: float) -> void:
    _engagement_memory = maxf(0.0, _engagement_memory - delta)
    attack_cooldown = maxf(0.0, attack_cooldown - delta)
    stagger = maxf(0.0, stagger - delta)
    hit_anim = maxf(0.0, hit_anim - delta)

    if held:
        velocity = Vector3.ZERO
        _animate(delta)
        return
    if not is_on_floor():
        velocity.y -= 24.0 * delta
    if dead:
        velocity.x = move_toward(velocity.x, 0.0, 5.5 * delta)
        velocity.z = move_toward(velocity.z, 0.0, 5.5 * delta)
        move_and_slide()
        _animate(delta)
        return

    if target == null or not is_instance_valid(target):
        _return_home(delta)
        return

    var to_target := target.global_position - global_position
    to_target.y = 0.0
    var dist := to_target.length()
    var from_home := global_position - _home_position
    from_home.y = 0.0
    var home_distance := from_home.length()
    var target_from_home := target.global_position - _home_position
    target_from_home.y = 0.0

    if target_from_home.length() <= AGGRO_RADIUS and home_distance <= LEASH_RADIUS:
        _engagement_memory = maxf(_engagement_memory, 1.35)

    if home_distance > LEASH_RADIUS or _engagement_memory <= 0.0:
        attack_windup = 0.0
        attack_landed = false
        _return_home(delta)
        return

    var machine_target := target.is_in_group("machine")
    var desired_range := 2.15 if machine_target else 1.52
    var strike_range := 2.55 if machine_target else attack_reach

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
                    1.12 if machine_target and role_id == 1 else 1.0
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
        var dir := to_target.normalized()
        var tangent := Vector3(-dir.z, 0.0, dir.x) * flank_sign
        var separation := _separation_force()
        var role_flank := 0.65 if role_id == 1 else (1.30 if role_id == 2 else 1.0)
        var flank_weight := clampf(
            (dist - desired_range) / 6.0,
            0.0,
            0.42
        ) * role_flank
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
            attack_cooldown = 1.22 if role_id == 1 else (0.82 if role_id == 2 else 1.02)
            attack_windup = 0.46 if role_id == 1 else 0.34
            attack_landed = false
            flank_sign *= -1.0
            if _rig != null:
                _rig.set_attack_side(flank_sign)

    move_and_slide()
    _animate(delta)

func _return_home(delta: float) -> void:
    var home_delta := _home_position - global_position
    home_delta.y = 0.0
    var distance := home_delta.length()
    if distance <= RETURN_STOP_RADIUS:
        velocity.x = move_toward(velocity.x, 0.0, 18.0 * delta)
        velocity.z = move_toward(velocity.z, 0.0, 18.0 * delta)
    elif stagger <= 0.0:
        var dir := home_delta.normalized()
        var separation := _separation_force()
        var move_dir := (dir + separation * 0.55).normalized()
        velocity.x = move_toward(velocity.x, move_dir.x * speed * 0.78, 14.0 * delta)
        velocity.z = move_toward(velocity.z, move_dir.z * speed * 0.78, 14.0 * delta)
        rotation.y = rotate_toward(
            rotation.y,
            atan2(-dir.x, -dir.z),
            deg_to_rad(115.0) * delta
        )
    move_and_slide()
    _animate(delta)
