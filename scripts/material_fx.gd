extends Node3D

const GeomUtil = preload("res://scripts/geom.gd")
const ImpactFx = preload("res://scripts/impact_fx.gd")
const SelfScript = preload("res://scripts/material_fx.gd")

var life := 0.0
var duration := 1.8
var kind := 0
var droplets: Array[MeshInstance3D] = []
var velocities: Array[Vector3] = []
var radii: Array[float] = []
var gravity := 9.81

const KIND_CONCRETE := 1
const KIND_HYDRAULIC := 2

static func steel(parent: Node, position: Vector3, direction: Vector3, strength: float) -> void:
    ImpactFx.spawn(parent, position, direction, Color(1.0, 0.48, 0.075), clampf(strength, 0.6, 6.0), clampi(6 + int(strength * 3.0), 8, 22))

static func concrete(parent: Node, position: Vector3, direction: Vector3, strength: float) -> void:
    ImpactFx.spawn(parent, position, direction, Color(0.48, 0.45, 0.39), clampf(strength * 0.70, 0.7, 5.0), clampi(7 + int(strength * 2.2), 8, 20))
    var fx: Node3D = SelfScript.new()
    parent.add_child(fx)
    fx.global_position = position
    fx._configure(KIND_CONCRETE, direction, strength)

static func hydraulic(parent: Node, position: Vector3, direction: Vector3, strength: float) -> void:
    var fx: Node3D = SelfScript.new()
    parent.add_child(fx)
    fx.global_position = position
    fx._configure(KIND_HYDRAULIC, direction, strength)

func _configure(new_kind: int, direction: Vector3, strength: float) -> void:
    kind = new_kind
    duration = 1.35 if kind == KIND_CONCRETE else 2.25
    var base := direction.normalized() if direction.length_squared() > 0.001 else Vector3.UP
    var count := clampi(8 + int(strength * 4.0), 10, 30)

    for i in count:
        var seed := float(i + 1)
        var angle := seed * 2.39996323
        var lateral := Vector3(cos(angle), 0.08 + fmod(seed * 0.23, 0.40), sin(angle)).normalized()
        var mesh: MeshInstance3D
        if kind == KIND_CONCRETE:
            var radius := 0.10 + fmod(seed * 0.043, 0.12)
            mesh = GeomUtil.sphere_mesh(radius, Color(0.50, 0.48, 0.43, 0.18))
            var mat := StandardMaterial3D.new()
            mat.albedo_color = Color(0.46, 0.45, 0.41, 0.16)
            mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
            mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
            mesh.material_override = mat
            radii.append(radius)
        else:
            var radius := 0.025 + fmod(seed * 0.012, 0.032)
            mesh = GeomUtil.sphere_mesh(radius, Color(0.20, 0.085, 0.025))
            mesh.material_override = GeomUtil.material(Color(0.20, 0.065, 0.018), 0.18, 0.0)
            radii.append(radius)
        add_child(mesh)
        droplets.append(mesh)

        var speed := (1.1 + fmod(seed * 0.41, 2.4)) * (0.85 + minf(strength, 5.0) * 0.17)
        var v := base * (0.9 + strength * 0.25) + lateral * speed
        if kind == KIND_CONCRETE:
            v += Vector3.UP * (0.45 + fmod(seed * 0.31, 0.95))
        else:
            v += Vector3.UP * (1.1 + fmod(seed * 0.29, 1.8))
        velocities.append(v)

func _process(delta: float) -> void:
    life += delta
    var t := clampf(life / duration, 0.0, 1.0)
    var space := get_world_3d().direct_space_state if get_world_3d() != null else null

    for i in droplets.size():
        var p := droplets[i]
        if not is_instance_valid(p):
            continue
        var v := velocities[i]
        v.y -= gravity * delta * (0.42 if kind == KIND_CONCRETE else 1.0)
        var old_pos := p.global_position
        var next_pos := old_pos + v * delta

        if space != null:
            var q := PhysicsRayQueryParameters3D.create(old_pos, next_pos, 1 | 2 | 4 | 8)
            q.collide_with_areas = false
            var hit := space.intersect_ray(q)
            if not hit.is_empty():
                if kind == KIND_HYDRAULIC:
                    p.global_position = hit.position + hit.normal * 0.006
                    v = Vector3.ZERO
                    p.scale = Vector3(1.45, 0.18, 1.45)
                else:
                    var n: Vector3 = hit.normal
                    p.global_position = hit.position + n * 0.012
                    v = v.bounce(n) * 0.22
            else:
                p.global_position = next_pos
        else:
            p.global_position = next_pos

        velocities[i] = v
        if kind == KIND_CONCRETE:
            var expansion := 1.0 + t * 3.2
            p.scale = Vector3.ONE * expansion
            var mat := p.material_override as StandardMaterial3D
            if mat != null:
                mat.albedo_color.a = maxf(0.0, 0.16 * (1.0 - t))
        else:
            p.scale *= 0.998

    if life >= duration:
        queue_free()
