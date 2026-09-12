extends Node

const YardSurface = preload("res://scripts/yard_surface.gd")
const StorageVessels = preload("res://scripts/world_storage_vessels.gd")
const UtilityZone = preload("res://scripts/world_utility_zone.gd")
const ScaffoldZone = preload("res://scripts/world_scaffold_zone.gd")
const BreachZone = preload("res://scripts/world_breach_zone.gd")

func _ready() -> void:
    call_deferred("_attach")

func _attach() -> void:
    await get_tree().process_frame
    var scene := get_tree().current_scene
    if scene == null:
        return
    for script in [YardSurface, StorageVessels, UtilityZone, ScaffoldZone, BreachZone]:
        var node := Node3D.new()
        node.set_script(script)
        scene.add_child(node)
