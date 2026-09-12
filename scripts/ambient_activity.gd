extends Node

const GeomUtil = preload("res://scripts/geom.gd")
const ImpactFx = preload("res://scripts/impact_fx.gd")

var smoke_nodes: Array[MeshInstance3D] = []
var smoke_origins: Array[Vector3] = []
var smoke_phase: Array[float] = []
var beacons: Array[OmniLight3D] = []
var time := 0.0
var spark_timer := 1.6
var scene_root

func _ready() -> void:
    call_deferred("_attach")
    set_process(true)

func _attach() -> void:
    await get_tree().process_frame
    scene_root = get_tree().current_scene
    if scene_root == null:
        return
    _build_smoke()
    _build_beacons()

func _build_smoke() -> void:
    var material := StandardMaterial3D.new()
    material.albedo_color = Color(0.14, 0.16, 0.16, 0.18)
    material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
    material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
    var stacks := [Vector3(-8.0, 14.2, -27.0), Vector3(0.0, 14.0, -27.0), Vector3(8.0, 14.3, -27.0)]
    for stack_i in stacks.size():
        for puff_i in 5:
            var puff := GeomUtil.sphere_mesh(0.42 + float(puff_i) * 0.05, Color.WHITE)
            puff.material_override = material
            scene_root.add_child(puff)
            smoke_nodes.append(puff)
            smoke_origins.append(stacks[stack_i])
            smoke_phase.append(float(puff_i) * 0.19 + float(stack_i) * 0.31)

func _build_beacons() -> void:
    for pos in [Vector3(-10.5, 7.8, -5.0), Vector3(10.5, 7.8, -5.0), Vector3(17.5, 7.2, 8.0)]:
        var light := OmniLight3D.new()
        light.position = pos
        light.light_color = Color(1.0, 0.16, 0.035)
        light.light_energy = 0.8
        light.omni_range = 4.8
        scene_root.add_child(light)
        beacons.append(light)

func _process(delta: float) -> void:
    if scene_root == null:
        return
    time += delta
    spark_timer -= delta
    for i in smoke_nodes.size():
        if not is_instance_valid(smoke_nodes[i]):
            continue
        var t := fposmod(time * 0.085 + smoke_phase[i], 1.0)
        var origin := smoke_origins[i]
        smoke_nodes[i].position = origin + Vector3(sin(t * 5.6 + i) * 0.55, t * 5.8, cos(t * 4.1 + i) * 0.34)
        var s := 0.65 + t * 1.8
        smoke_nodes[i].scale = Vector3(s * 1.18, s, s * 1.18)
        var mat := smoke_nodes[i].material_override as StandardMaterial3D
        if mat != null:
            mat.albedo_color.a = (1.0 - t) * 0.18
    for i in beacons.size():
        beacons[i].light_energy = 2.4 if fmod(time + float(i) * 0.37, 1.25) < 0.16 else 0.18
    if spark_timer <= 0.0:
        spark_timer = 2.6 + fmod(time * 0.47, 1.8)
        var spark_pos := Vector3(-12.0 + fmod(time * 3.1, 24.0), 2.3, -22.6)
        ImpactFx.spawn(scene_root, spark_pos, Vector3(0.1, 0.7, 0.2), Color(1.0, 0.56, 0.10), 1.5, 8)
