extends Node

## Presentation consumer for Fidelity. It never creates damage or fracture
## state; it projects existing solver state into steel shading and preserves
## that same surface identity when components become rigid debris.

const SurfaceOverlay = preload("res://scripts/fidelity_surface_overlay.gd")
const FragmentSkin = preload("res://scripts/fidelity_fragment_skin.gd")

var _scene_id := 0
var _scan_timer := 0.0
var _fragment_scan_timer := 0.0
var _fragment_scan_passes := 0

func _ready() -> void:
    process_mode = Node.PROCESS_MODE_ALWAYS
    add_to_group("physical_event_listener")
    Fidelity.live_changed.connect(_on_fidelity_changed)
    set_process(true)

func _process(delta: float) -> void:
    var scene: Node = get_tree().current_scene
    if scene != null and scene.get_instance_id() != _scene_id:
        _scene_id = scene.get_instance_id()
        _scan_timer = 0.0
        _fragment_scan_passes = 4
        _fragment_scan_timer = 0.02

    _scan_timer -= delta
    if _scan_timer <= 0.0:
        _scan_timer = 0.35
        if scene != null:
            _scan_for_surfaces(scene)

    if _fragment_scan_passes > 0:
        _fragment_scan_timer -= delta
        if _fragment_scan_timer <= 0.0:
            _fragment_scan_timer = 0.09
            _fragment_scan_passes -= 1
            if Fidelity.keep_skin_on_debris():
                _attach_fragment_skins()

func physical_event(event: Dictionary) -> void:
    var kind: String = String(event.get("type", ""))
    if kind != "fracture" and kind != "collapse":
        return
    if not Fidelity.keep_skin_on_debris():
        return
    _fragment_scan_passes = 4
    _fragment_scan_timer = 0.0
    _attach_fragment_skins()

func _on_fidelity_changed(_value: int) -> void:
    if Fidelity.keep_skin_on_debris():
        _fragment_scan_passes = 3
        _fragment_scan_timer = 0.0

func _scan_for_surfaces(node: Node) -> void:
    for child in node.get_children():
        if child is DeformationSkin3D:
            if child.get_node_or_null("FidelitySurface") == null:
                var overlay: Node = SurfaceOverlay.new()
                child.add_child(overlay)
        _scan_for_surfaces(child)

func _attach_fragment_skins() -> void:
    _attach_structure_fragments()
    _attach_gate_fragments()

func _attach_structure_fragments() -> void:
    for structure in get_tree().get_nodes_in_group("structure"):
        if structure == null or not is_instance_valid(structure):
            continue
        var network = structure.get("deck_network")
        var deck = structure.get("deck")
        if network == null or deck == null or not is_instance_valid(deck):
            continue
        if not network.has_method("has_fractured") or not bool(network.has_fractured()):
            continue
        var specs: Array = network.get_fragment_specs(0.34, 1)
        _match_and_attach(
            network,
            specs,
            deck.global_transform,
            0,
            "platform",
            Color(0.27, 0.25, 0.20),
            0.34
        )

func _attach_gate_fragments() -> void:
    for gate in get_tree().get_nodes_in_group("breachable"):
        if gate == null or not is_instance_valid(gate):
            continue
        var networks_value: Variant = gate.get("panel_networks")
        var panels_value: Variant = gate.get("panels")
        if not networks_value is Array or not panels_value is Array:
            continue
        var networks: Array = networks_value as Array
        var panels: Array = panels_value as Array
        for index in mini(networks.size(), panels.size()):
            var network = networks[index]
            var panel = panels[index]
            if network == null or panel == null or not is_instance_valid(panel):
                continue
            if not network.has_method("has_fractured") or not bool(network.has_fractured()):
                continue
            var specs: Array = network.get_fragment_specs(0.24, 1)
            _match_and_attach(
                network,
                specs,
                panel.global_transform,
                1,
                "gate_panel",
                Color(0.13, 0.14, 0.13),
                0.24
            )

func _match_and_attach(
        network,
        specs: Array,
        source_transform: Transform3D,
        plane_mode: int,
        source_tag: String,
        base_color: Color,
        thickness: float
) -> void:
    var candidates: Array = []
    for body in get_tree().get_nodes_in_group("reusable_debris"):
        if body == null or not is_instance_valid(body):
            continue
        if bool(body.get_meta("fidelity_skin_attached", false)):
            continue
        var tag_value: Variant = body.get("source_tag")
        if tag_value == null or String(tag_value) != source_tag:
            continue
        candidates.append(body)

    for spec_value in specs:
        if candidates.is_empty():
            return
        var spec: Dictionary = spec_value as Dictionary
        var source_center: Vector3 = spec.get("local_position", Vector3.ZERO)
        var mapped_center: Vector3 = _map_position(source_center, plane_mode)
        var target_world: Vector3 = source_transform * mapped_center
        var target_mass: float = maxf(float(spec.get("mass", 0.1)), 0.1)
        var best: Node3D = null
        var best_score: float = INF
        for candidate_value in candidates:
            var candidate: Node3D = candidate_value as Node3D
            if candidate == null:
                continue
            var distance: float = candidate.global_position.distance_to(target_world)
            var candidate_mass: float = maxf(float(candidate.get("mass")), 0.1)
            var mass_error: float = absf(candidate_mass - target_mass) / target_mass
            var score: float = distance + mass_error * 0.65
            if score < best_score:
                best_score = score
                best = candidate
        var size_value: Variant = spec.get("size", Vector3.ONE)
        var size := Vector3.ONE
        if size_value is Vector3:
            size = size_value
        var tolerance: float = maxf(1.0, size.length() * 0.52)
        if best == null or best.global_position.distance_to(target_world) > tolerance:
            continue
        var controller: Node = FragmentSkin.new()
        controller.name = "FidelityFragmentSkin"
        best.add_child(controller)
        if bool(controller.call(
            "configure",
            best,
            network,
            spec,
            plane_mode,
            base_color,
            thickness
        )):
            candidates.erase(best)
        else:
            controller.queue_free()

func _map_position(source: Vector3, plane_mode: int) -> Vector3:
    if plane_mode == 1:
        return Vector3(source.x, source.z, source.y)
    return source
