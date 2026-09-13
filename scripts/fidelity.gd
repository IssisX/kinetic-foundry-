extends Node

## One fidelity authority for the existing physical world. Live changes retune
## legitimate representation/solver knobs in-place. Topology changes require an
## explicit scene rebuild so no cracked low-resolution plate is upsampled into
## invented high-resolution history.

signal live_changed(f: int)
signal rebuild_requested(f: int)

const Overlay = preload("res://scripts/fidelity_overlay.gd")
const CrackOverlay = preload("res://scripts/fidelity_crack_overlay.gd")
const BaseNetwork = preload("res://scripts/fidelity_fracture_network.gd")
const PrecisionNetwork = preload("res://scripts/fidelity_precision_fracture_network.gd")

var f := 1
var topology_f := 1
var telemetry_nodes := 0
var telemetry_bonds := 0
var telemetry_shards := 0
var telemetry_last_shards := 0
var telemetry_ms_phys := 0.0

var _scene_id := 0
var _bound_scene: Node
var _overlay: Control
var _scan_timer := 0.0
var _last_debris_count := 0
var _pending_fracture_sample := 0.0
var _fracture_baseline := 0

func _ready() -> void:
    process_mode = Node.PROCESS_MODE_ALWAYS
    add_to_group("physical_event_listener")
    set_process(true)

func _process(delta: float) -> void:
    var scene := get_tree().current_scene
    if scene != null and scene.get_instance_id() != _scene_id:
        _scene_id = scene.get_instance_id()
        _bound_scene = scene
        call_deferred("_bind_scene", scene)

    _scan_timer -= delta
    if _scan_timer <= 0.0:
        _scan_timer = 0.40
        _apply_live_knobs()
        _ensure_crack_overlays()
        _update_topology_counts()

    telemetry_ms_phys = (
        float(Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS))
        * 1000.0
    )
    telemetry_shards = get_tree().get_nodes_in_group("reusable_debris").size()
    if _pending_fracture_sample > 0.0:
        _pending_fracture_sample -= delta
        telemetry_last_shards = maxi(
            telemetry_last_shards,
            telemetry_shards - _fracture_baseline
        )
    _last_debris_count = telemetry_shards

func set_live_f(value: int) -> void:
    var next := clampi(value, 0, 3)
    if next == f:
        return
    f = next
    _apply_live_knobs()
    _ensure_crack_overlays(true)
    live_changed.emit(f)

func request_rebuild() -> void:
    topology_f = f
    rebuild_requested.emit(f)
    call_deferred("_reload_scene")

func _reload_scene() -> void:
    get_tree().reload_current_scene()

func deck_grid() -> Vector2i:
    return [
        Vector2i(4, 3),
        Vector2i(5, 4),
        Vector2i(8, 6),
        Vector2i(12, 8)
    ][f]

func gate_grid() -> int:
    return [5, 7, 9, 11][f]

func iterations() -> int:
    return [3, 5, 5, 5][f]

func use_bend() -> bool:
    return f >= 2

func use_area() -> bool:
    return f >= 3

func ribbon_damage() -> float:
    return [1.1, 0.55, 0.42, 0.42][f]

func keep_skin_on_debris() -> bool:
    return f >= 2

func max_shards() -> int:
    return [6, 8, 14, 24][f]

func physical_event(event: Dictionary) -> void:
    if String(event.get("type", "")) != "fracture":
        return
    _fracture_baseline = _last_debris_count
    telemetry_last_shards = 0
    _pending_fracture_sample = 0.42

func _bind_scene(scene: Node) -> void:
    if scene == null or not is_instance_valid(scene):
        return
    topology_f = f
    _replace_scene_networks()
    _apply_live_knobs()
    _ensure_crack_overlays(true)
    _update_topology_counts()
    if _overlay != null and is_instance_valid(_overlay):
        _overlay.queue_free()
    _overlay = Overlay.new()
    _overlay.name = "FidelityOverlay"
    scene.add_child(_overlay)
    _last_debris_count = get_tree().get_nodes_in_group("reusable_debris").size()

func _replace_scene_networks() -> void:
    var deck_shape := deck_grid()
    for structure in get_tree().get_nodes_in_group("structure"):
        if structure == null or not is_instance_valid(structure):
            continue
        var old = structure.get("deck_network")
        if old == null:
            continue
        var replacement = BaseNetwork.new()
        _configure_like(replacement, old, deck_shape.x, deck_shape.y)
        structure.set("deck_network", replacement)
        var skin = structure.get("deck_skin")
        if skin != null and is_instance_valid(skin):
            skin.set("network", replacement)
            skin.call("refresh", true)

    var gate_size := gate_grid()
    for gate in get_tree().get_nodes_in_group("breachable"):
        if gate == null or not is_instance_valid(gate):
            continue
        var networks_value: Variant = gate.get("panel_networks")
        if not networks_value is Array:
            continue
        var networks: Array = networks_value as Array
        for index in networks.size():
            var old = networks[index]
            if old == null:
                continue
            var replacement = PrecisionNetwork.new()
            _configure_like(replacement, old, gate_size, gate_size)
            networks[index] = replacement
        gate.set("panel_networks", networks)
        _retarget_gate_skins(gate, networks)

func _configure_like(replacement, old, columns: int, rows: int) -> void:
    var old_yield := float(old.get("yield_strain"))
    var toughness := clampf(old_yield / 0.0001, 100.0, 320.0)
    replacement.configure_grid(
        columns,
        rows,
        old.get("span") as Vector3,
        float(old.get("total_mass")),
        toughness,
        bool(old.get("pin_boundary")),
        float(old.get("thickness")),
        float(old.get("fracture_energy_density"))
    )
    replacement.solver_iterations = iterations()

func _retarget_gate_skins(gate: Node, networks: Array) -> void:
    var panels_value: Variant = gate.get("panels")
    if not panels_value is Array:
        return
    var panels: Array = panels_value as Array
    for index in mini(panels.size(), networks.size()):
        var panel = panels[index]
        if panel == null or not is_instance_valid(panel):
            continue
        for child in panel.get_children():
            if child is DeformationSkin3D:
                child.set("network", networks[index])
                child.call("refresh", true)

func _apply_live_knobs() -> void:
    for network in _collect_networks():
        if network != null:
            network.set("solver_iterations", iterations())

func _collect_networks() -> Array:
    var networks: Array = []
    for structure in get_tree().get_nodes_in_group("structure"):
        if structure != null and is_instance_valid(structure):
            var deck_network = structure.get("deck_network")
            if deck_network != null:
                networks.append(deck_network)
    for gate in get_tree().get_nodes_in_group("breachable"):
        if gate == null or not is_instance_valid(gate):
            continue
        var value: Variant = gate.get("panel_networks")
        if value is Array:
            for network in value as Array:
                if network != null:
                    networks.append(network)
    return networks

func _ensure_crack_overlays(force_refresh: bool = false) -> void:
    var scene := get_tree().current_scene
    if scene == null:
        return
    _scan_skin_node(scene, force_refresh)

func _scan_skin_node(node: Node, force_refresh: bool) -> void:
    for child in node.get_children():
        if child is DeformationSkin3D:
            var default_cracks := child.get_node_or_null("SolvedCracks")
            if default_cracks != null:
                default_cracks.visible = false
            var overlay := child.get_node_or_null("FidelityCracks")
            if overlay == null:
                overlay = CrackOverlay.new()
                child.add_child(overlay)
            elif force_refresh:
                overlay.set("_seen_revision", -1)
        _scan_skin_node(child, force_refresh)

func _update_topology_counts() -> void:
    telemetry_nodes = 0
    telemetry_bonds = 0
    for network in _collect_networks():
        if network == null:
            continue
        var grid: Vector2i = network.get_grid_size()
        telemetry_nodes += grid.x * grid.y
        telemetry_bonds += network.get_bond_visuals().size()
