extends Node3D

const GeomUtil = preload("res://scripts/geom.gd")
const SelfScript = preload("res://scripts/impact_fx.gd")

var life := 0.0
var duration := 0.42
var velocities: Array[Vector3] = []
var fragments: Array[MeshInstance3D] = []
var gravity := 9.5

static func spawn(
        parent: Node,
        world_pos: Vector3,
        direction: Vector3,
        color: Color,
        strength: float = 1.0,
        count: int = 9
) -> void:
    var fx: Node3D = SelfScript.new()
    parent.add_child(fx)
    fx.global_position = world_pos
    fx._configure(direction, color, strength, count)

func _configure(direction: Vector3, color: Color, strength: float, count: int) -> void:
    duration = 0.34 + minf(strength * 0.045, 0.28)
    var base_dir: Vector3 = direction.normalized() if direction.length_squared() > 0.001 else Vector3.UP
    for i in count:
        var shard: MeshInstance3D = GeomUtil.box_mesh(
            Vector3(0.055, 0.055, 0.16 + float(i % 3) * 0.035) * (0.85 + strength * 0.04),
            color,
            0.42,
            0.28
        )
        shard.material_override = GeomUtil.emissive_material(color, 1.5 + strength * 0.18, 0.42, 0.18)
        shard.rotation = Vector3(float(i) * 0.71, float(i) * 1.13, float(i) * 0.37)
        add_child(shard)
        fragments.append(shard)

        var ring_angle: float = float(i) * TAU / float(maxi(count, 1))
        var lateral: Vector3 = Vector3(cos(ring_angle), 0.22 + float(i % 2) * 0.22, sin(ring_angle))
        var velocity: Vector3 = base_dir * 1.8 + lateral * (1.5 + strength * 0.42)
        velocity += Vector3.UP * (0.8 + float(i % 4) * 0.34)
        velocities.append(velocity)

func _process(delta: float) -> void:
    life += delta
    var t: float = clampf(life / duration, 0.0, 1.0)
    for i in fragments.size():
        var shard: MeshInstance3D = fragments[i]
        if not is_instance_valid(shard):
            continue
        velocities[i].y -= gravity * delta
        shard.position += velocities[i] * delta
        shard.rotation += Vector3(4.1, 6.0, 3.2) * delta * (1.0 + float(i % 3) * 0.18)
        shard.scale = Vector3.ONE * (1.0 - t * 0.78)
    if life >= duration:
        queue_free()
