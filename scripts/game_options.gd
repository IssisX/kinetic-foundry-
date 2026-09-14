extends Node

## Yard-wide view law. Stress, deformation, and damage skin hide or show
## state the solvers already own. They do not invent a second physics.
## Fidelity stays the grid knob. Persistence is local to the device.

signal changed()

var stress_visible := true
var deformation_visible := true
var damage_visible := true

const PATH := "user://foundry_options.cfg"


func _ready() -> void:
    process_mode = Node.PROCESS_MODE_ALWAYS
    _load()


func set_stress_visible(value: bool) -> void:
    if stress_visible == value:
        return
    stress_visible = value
    _save()
    changed.emit()


func set_deformation_visible(value: bool) -> void:
    if deformation_visible == value:
        return
    deformation_visible = value
    _save()
    changed.emit()


func set_damage_visible(value: bool) -> void:
    if damage_visible == value:
        return
    damage_visible = value
    _save()
    changed.emit()


func toggle_stress() -> void:
    set_stress_visible(not stress_visible)


func toggle_deformation() -> void:
    set_deformation_visible(not deformation_visible)


func toggle_damage() -> void:
    set_damage_visible(not damage_visible)


func stress_amount() -> float:
    return 1.0 if stress_visible else 0.0


func deform_scale() -> float:
    return 1.0 if deformation_visible else 0.0


func damage_amount() -> float:
    return 1.0 if damage_visible else 0.0


func _load() -> void:
    var config := ConfigFile.new()
    if config.load(PATH) != OK:
        return
    stress_visible = bool(config.get_value("view", "stress", true))
    deformation_visible = bool(config.get_value("view", "deformation", true))
    damage_visible = bool(config.get_value("view", "damage", true))


func _save() -> void:
    var config := ConfigFile.new()
    config.set_value("view", "stress", stress_visible)
    config.set_value("view", "deformation", deformation_visible)
    config.set_value("view", "damage", damage_visible)
    config.save(PATH)
