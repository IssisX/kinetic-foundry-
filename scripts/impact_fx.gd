extends Node3D

const GeomUtil = preload("res://scripts/geom.gd")
const SelfScript = preload("res://scripts/impact_fx.gd")

var life := 0.0
var duration := 0.72
var velocities: Array[Vector3] = []
var angular_velocities: Array[Vector3] = []
var fragments: Array[MeshInstance3D] = []
var settled: Array[bool] = []
var gravity := 9.81
var drag := 0.34
var restitution := 0.34
var friction := 0.66
var _flash: OmniLight3D
var _strength := 1.0

static func spawn(
        parent: Node,
        world_pos: Vector3,
        direction: Vector3,
        color: Color,
        strength: float = 1.0,
        count: int = 9
) -> void:
    if parent == null:
        return
    var fx: Node3D = SelfScript.new()
    parent.add_child(fx)
    fx.global_position = world_pos
    fx._configure(direction, color, strength, clampi(count, 4, 24))

func _configure(direction: Vector3, color: Color, strength: float, count: int) -> void:
    _strength = maxf(strength, 0.15)
    duration = 0.46 + minf(_strength * 0.085, 0.62)
    restitution = clampf(0.26 + _strength * 0.018, 0.26, 0.48)
    var base_dir: Vector3 = direction.normalized() if direction.length_squared() > 0.001 else Vector3.UP
    var is_hot := color.r > color.b * 1.25 or color.g > color.b * 1.4

    for i in count:
        var seed := float(i + 1)
        var size_scale := 0.72 + fmod(seed * 0.6180339, 0.58)
        var shard_size := Vector3(
            0.035 + fmod(seed * 0.037, 0.045),
            0.025 + fmod(seed * 0.053, 0.040),
            0.095 + fmod(seed * 0.071, 0.130)
        ) * size_scale * (0.88 + _strength * 0.035)
        var shard: MeshInstance3D = GeomUtil.box_mesh(shard_size, color, 0.34 if is_hot else 0.72, 0.42 if is_hot else 0.16)
        if is_hot and i % 3 != 0:
            shard.material_override = GeomUtil.emissive_material(color, 2.0 + _strength * 0.28, 0.28, 0.22)
        shard.rotation = Vector3(seed * 0.71, seed * 1.13, seed * 0.37)
        add_child(shard)
        fragments.append(shard)

        var ring_angle: float = seed * 2.39996323
        var lateral := Vector3(cos(ring_angle), 0.14 + fmod(seed * 0.31, 0.48), sin(ring_angle))
        var speed := 1.9 + _strength * 0.72 + fmod(seed * 0.47, 1.9)
        var velocity := base_dir * (1.2 + _strength * 0.34) + lateral.normalized() * speed
        velocity += Vector3.UP * (0.55 + fmod(seed * 0.67, 1.45))
        velocities.append(velocity)
        angular_velocities.append(Vector3(4.0 + seed * 0.37, 5.2 + seed * 0.29, 3.1 + seed * 0.43))
        settled.append(false)

    if _strength >= 1.35:
        _flash = OmniLight3D.new()
        _flash.light_color = color.lightened(0.22)
        _flash.light_energy = minf(2.0 + _strength * 0.92, 8.5)
        _flash.omni_range = minf(2.4 + _strength * 0.85, 8.0)
        _flash.shadow_enabled = false
        add_child(_flash)

func _process(delta: float) -> void:
    life += delta
    var t: float = clampf(life / duration, 0.0, 1.0)
    var space := get_world_3d().direct_space_state if get_world_3d() != null else null

    if _flash != null:
        var flash_decay := maxf(0.0, 1.0 - t)
        _flash.light_energy *= exp(-13.0 * delta)
        _flash.omni_range = maxf(0.4, _flash.omni_range * (0.985 - t * 0.01))
        if flash_decay <= 0.02:
            _flash.visible = false

    for i in fragments.size():
        var shard := fragments[i]
        if not is_instance_valid(shard):
            continue

        if settled[i]:
            shard.scale = Vector3.ONE * maxf(0.0, 1.0 - maxf(0.0, t - 0.58) * 2.15)
            continue

        var velocity := velocities[i]
        velocity.y -= gravity * delta
        velocity *= exp(-drag * delta)

        var old_world := shard.global_position
        var proposed_world := old_world + velocity * delta
        var collided := false

        if space != null and old_world.distance_squared_to(proposed_world) > 0.000001:
            var query := PhysicsRayQueryParameters3D.create(old_world, proposed_world, 1 | 2 | 4 | 8)
            query.collide_with_areas = false
            var hit := space.intersect_ray(query)
            if not hit.is_empty():
                collided = true
                var normal: Vector3 = hit.normal
                shard.global_position = hit.position + normal * 0.012
                var normal_speed := velocity.dot(normal)
                var normal_component := normal * normal_speed
                var tangent_component := velocity - normal_component
                velocity = (-normal_component * restitution) + tangent_component * friction
                angular_velocities[i] *= 0.68
                if velocity.length() < 1.05 or life > duration * 0.62:
                    settled[i] = true
                    velocity = Vector3.ZERO
            
        if not collided:
            shard.global_position = proposed_world

        velocities[i] = velocity
        shard.rotation += angular_velocities[i] * delta
        if not settled[i]:
            shard.scale = Vector3.ONE * (1.0 - t * 0.38)

    if life >= duration:
        queue_free()
