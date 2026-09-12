extends Node

var character_tier := 0
var equipment_tier := 0
var completed_missions := 0
var upgrade_points := 0
var _bound_missions: Dictionary = {}
var _player

const SAVE_PATH := "user://kinetic_foundry_progress.cfg"

func _ready() -> void:
    _load_state()
    get_tree().node_added.connect(_on_node_added)
    call_deferred("_scan_scene")

func _scan_scene() -> void:
    await get_tree().process_frame
    for node in get_tree().get_nodes_in_group("player"):
        _bind_player(node)
    var scene: Node = get_tree().current_scene
    if scene != null:
        _scan_for_mission(scene)

func _on_node_added(node: Node) -> void:
    call_deferred("_inspect_node", node)

func _inspect_node(node: Node) -> void:
    if not is_instance_valid(node):
        return
    if node.is_in_group("player"):
        _bind_player(node)
    if node.has_signal("mission_complete"):
        _bind_mission(node)

func _scan_for_mission(node: Node) -> void:
    if node.has_signal("mission_complete"):
        _bind_mission(node)
    for child in node.get_children():
        _scan_for_mission(child)

func _bind_player(node) -> void:
    _player = node
    _apply_player_progression()

func _bind_mission(node) -> void:
    var id: int = int(node.get_instance_id())
    if _bound_missions.has(id):
        return
    _bound_missions[id] = true
    node.mission_complete.connect(_on_mission_complete)

func _on_mission_complete() -> void:
    completed_missions += 1
    upgrade_points += 2
    if character_tier <= equipment_tier:
        character_tier += 1
    else:
        equipment_tier += 1
    _apply_player_progression()
    _save_state()
    var hud: Node = _find_hud()
    if hud != null:
        hud.set_context("UPGRADE // BODY %d // GEAR %d // NEW PHYSICAL AUTHORITY" % [character_tier, equipment_tier])

func _apply_player_progression() -> void:
    if _player == null or not is_instance_valid(_player):
        return

    _player.max_health = 180.0 + equipment_tier * 24.0 + character_tier * 8.0
    _player.health = minf(_player.health + equipment_tier * 10.0, _player.max_health)
    _player.speed = 7.4 + character_tier * 0.28
    _player.sprint_speed = 10.2 + character_tier * 0.42

    _player.grab_mass_limit = 110.0 + character_tier * 42.0
    _player.melee_force_multiplier = 1.0 + character_tier * 0.11
    _player.throw_force_multiplier = 1.0 + character_tier * 0.13
    _player.machine_climb_range = 5.8 + character_tier * 0.32

    _player.damage_reduction = clampf(equipment_tier * 0.055, 0.0, 0.42)
    _player.hazard_reduction = clampf(equipment_tier * 0.075, 0.0, 0.55)

    _player.set_meta("character_tier", character_tier)
    _player.set_meta("equipment_tier", equipment_tier)
    _player.set_meta("physical_authority", character_tier + equipment_tier)

func _find_hud() -> Node:
    var scene: Node = get_tree().current_scene
    if scene == null:
        return null
    return scene.get("hud") as Node

func _save_state() -> void:
    var cfg := ConfigFile.new()
    cfg.set_value("progress", "character_tier", character_tier)
    cfg.set_value("progress", "equipment_tier", equipment_tier)
    cfg.set_value("progress", "completed_missions", completed_missions)
    cfg.set_value("progress", "upgrade_points", upgrade_points)
    cfg.save(SAVE_PATH)

func _load_state() -> void:
    var cfg := ConfigFile.new()
    if cfg.load(SAVE_PATH) != OK:
        return
    character_tier = int(cfg.get_value("progress", "character_tier", 0))
    equipment_tier = int(cfg.get_value("progress", "equipment_tier", 0))
    completed_missions = int(cfg.get_value("progress", "completed_missions", 0))
    upgrade_points = int(cfg.get_value("progress", "upgrade_points", 0))
