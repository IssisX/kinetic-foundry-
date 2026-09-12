extends Node

const GeomUtil = preload("res://scripts/geom.gd")

var marker_root: Node3D
var ring_a: MeshInstance3D
var ring_b: MeshInstance3D
var beam: MeshInstance3D
var light: OmniLight3D
var time := 0.0
var scene: Node

func _ready() -> void:
    call_deferred("_attach")
    set_process(true)

func _attach() -> void:
    await get_tree().process_frame
    scene = get_tree().current_scene
    if scene == null:
        return
    marker_root = Node3D.new()
    marker_root.name = "ObjectiveMarker"
    scene.add_child(marker_root)
    ring_a = _ring(1.15, Color(0.95, 0.55, 0.08, 0.80))
    ring_b = _ring(1.48, Color(0.22, 0.62, 0.64, 0.52))
    marker_root.add_child(ring_a)
    marker_root.add_child(ring_b)
    beam = GeomUtil.cylinder_mesh(0.055, 3.4, Color(0.90, 0.48, 0.06), 0.32, 0.06)
    beam.material_override = GeomUtil.emissive_material(Color(0.92, 0.42, 0.045), 2.0, 0.28, 0.04)
    beam.position.y = 1.75
    marker_root.add_child(beam)
    light = OmniLight3D.new()
    light.light_color = Color(1.0, 0.54, 0.12)
    light.light_energy = 1.4
    light.omni_range = 5.0
    light.position.y = 0.5
    marker_root.add_child(light)

func _ring(radius: float, color: Color) -> MeshInstance3D:
    var torus: TorusMesh = TorusMesh.new()
    torus.inner_radius = radius - 0.055
    torus.outer_radius = radius + 0.055
    torus.rings = 32
    torus.ring_segments = 8
    var mesh: MeshInstance3D = MeshInstance3D.new()
    mesh.mesh = torus
    var mat: StandardMaterial3D = GeomUtil.emissive_material(Color(color.r, color.g, color.b), 1.7, 0.30, 0.04)
    mat.albedo_color.a = color.a
    mesh.material_override = mat
    return mesh

func _process(delta: float) -> void:
    if marker_root == null or scene == null:
        return
    time += delta
    var mission = scene.get("mission")
    var player = scene.get("player")
    var machine = scene.get("excavator")
    var structure = scene.get("structure")
    if mission == null or mission.get("_complete") == true:
        marker_root.visible = false
        return

    marker_root.visible = true
    var stage: int = int(mission.get("stage"))
    var target_pos: Vector3 = Vector3.ZERO
    if stage == 0:
        target_pos = _nearest_live_enemy(player)
    elif stage == 1:
        target_pos = machine.global_position if machine != null else Vector3.ZERO
    elif stage == 2 or stage == 3:
        target_pos = structure.global_position if structure != null else Vector3.ZERO
    elif stage == 4:
        var gates: Array[Node] = get_tree().get_nodes_in_group("breachable")
        target_pos = gates[0].global_position if not gates.is_empty() else Vector3.ZERO

    marker_root.global_position = target_pos + Vector3.UP * 0.06
    ring_a.rotation.y += delta * 1.45
    ring_b.rotation.y -= delta * 0.95
    var pulse: float = 0.85 + sin(time * 3.8) * 0.12
    ring_a.scale = Vector3(pulse, pulse, pulse)
    ring_b.scale = Vector3(1.0 / pulse, 1.0, 1.0 / pulse)
    beam.visible = stage > 0
    light.light_energy = 1.0 + absf(sin(time * 3.1)) * 1.1

func _nearest_live_enemy(player) -> Vector3:
    var best: Node3D = null
    var best_dist: float = INF
    for enemy in get_tree().get_nodes_in_group("enemy"):
        if not is_instance_valid(enemy) or enemy.dead or not enemy.visible:
            continue
        var d: float = player.global_position.distance_to(enemy.global_position) if player != null else 0.0
        if d < best_dist:
            best_dist = d
            best = enemy as Node3D
    return best.global_position if best != null else Vector3.ZERO
