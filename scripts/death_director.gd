extends Node

const RESTART_DELAY := 2.6

var _player
var _timer := -1.0
var _announced := false

func _ready() -> void:
    set_process(true)

func _process(delta: float) -> void:
    if _player == null or not is_instance_valid(_player):
        _player = get_tree().get_first_node_in_group("player")
        _timer = -1.0
        _announced = false
        return

    var health_value: float = float(_player.get("health"))
    if health_value > 0.0:
        _timer = -1.0
        _announced = false
        return

    if _timer < 0.0:
        _timer = RESTART_DELAY
        _lock_dead_player()

    _timer -= delta
    if _player is CharacterBody3D:
        _player.velocity.x = move_toward(_player.velocity.x, 0.0, 12.0 * delta)
        _player.velocity.z = move_toward(_player.velocity.z, 0.0, 12.0 * delta)

    if _timer <= 0.0:
        get_tree().reload_current_scene()

func _lock_dead_player() -> void:
    if _player == null:
        return
    _player.set("speed", 0.0)
    _player.set("sprint_speed", 0.0)
    _player.set("traversal_lock", 999.0)
    _player.set("attack_cooldown", 999.0)
    _player.set("held_target", null)
    var scene: Node = get_tree().current_scene
    if scene == null:
        return
    var hud: Node = scene.get("hud") as Node
    if hud != null:
        if hud.has_method("set_target"):
            hud.set_target(null)
        if hud.has_method("set_context"):
            hud.set_context("DOWN // CHECKPOINT RELOAD")
        if hud.has_method("set_objective_progress"):
            hud.set_objective_progress(0.0)
