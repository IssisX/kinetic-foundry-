class_name GateDeformationView3D
extends Node

## Read-only presentation bridge for the breach gate's authoritative
## fracture networks. It adds no forces, damage, collision, or fracture state.

const DeformationSkin = preload("res://scripts/deformation_skin.gd")

var gate: Node
var _skins: Array[Node] = []

func bind(source: Node) -> void:
    gate = source
    call_deferred("_attach")

func _process(_delta: float) -> void:
    for skin in _skins:
        if is_instance_valid(skin):
            skin.refresh()

func _attach() -> void:
    if gate == null or not is_instance_valid(gate):
        return

    var panels_value: Variant = gate.get("panels")
    var networks_value: Variant = gate.get("panel_networks")
    var cells_value: Variant = gate.get("panel_cells")
    if not panels_value is Array or not networks_value is Array:
        return

    var panels: Array = panels_value as Array
    var networks: Array = networks_value as Array
    var cell_sets: Array = cells_value as Array if cells_value is Array else []
    var count := mini(panels.size(), networks.size())

    for index in count:
        var panel = panels[index]
        var network = networks[index]
        if panel == null or network == null or not is_instance_valid(panel):
            continue

        if index < cell_sets.size():
            var cells = cell_sets[index]
            if cells is Array:
                for cell in cells:
                    if is_instance_valid(cell):
                        cell.visible = false

        var skin := DeformationSkin.new()
        skin.name = "SolvedGateSkin_%d" % index
        panel.add_child(skin)
        skin.configure(
            network,
            DeformationSkin.MODE_VERTICAL,
            Color(0.17, 0.18, 0.165)
        )
        _skins.append(skin)
