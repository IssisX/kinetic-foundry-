extends Node

## Headless acceptance for "does anything actually attack the player."
##
## Run: KF_COMBAT_CHECK=1 ./tools/godot --path . --audio-driver Dummy
##
## The user reported enemies and the excavator closing distance and then
## never doing anything - not a vibe, a measurable claim: does the
## player's own health ever move. This puts one of each archetype, and
## the excavator under enemy control, alone with the player and gives
## each a generous window to land a single hit. No archetype gets an
## exception; a silent one is the bug.

const EnemyScene = preload("res://scripts/enemy.gd")

var game: Node3D
var player
var _failures := 0


func begin(root: Node3D) -> void:
    game = root
    process_mode = Node.PROCESS_MODE_ALWAYS
    call_deferred("_run")


func _run() -> void:
    player = game.player
    await _physics_frames(30)
    _quiet_the_yard()

    for archetype in [
        EnemyScene.GRUNT,
        EnemyScene.HEAVY,
        EnemyScene.RUNNER,
        EnemyScene.PLATE,
        EnemyScene.THROWER,
        EnemyScene.RIGGER
    ]:
        await _check_archetype_attacks(archetype)

    await _check_excavator_attacks()

    if _failures == 0:
        print("COMBAT_CHECK_OK")
        get_tree().quit(0)
        return
    print("COMBAT_CHECK_FAILED count=", _failures)
    get_tree().quit(1)


func _quiet_the_yard() -> void:
    for enemy in get_tree().get_nodes_in_group("enemy"):
        enemy.process_mode = Node.PROCESS_MODE_DISABLED
        enemy.queue_free()
    if game.mission != null:
        game.mission.process_mode = Node.PROCESS_MODE_DISABLED
    if game.crane != null:
        game.crane.process_mode = Node.PROCESS_MODE_DISABLED
    if game.excavator != null:
        game.excavator.enemy_driver = null


func _physics_frames(count: int) -> void:
    for _i in count:
        await get_tree().physics_frame


func _expect(condition: bool, claim: String) -> void:
    if condition:
        print("  ok   ", claim)
        return
    _failures += 1
    print("  FAIL ", claim)


func _archetype_name(id: int) -> String:
    return str(EnemyScene.archetype_stats(id).get("name", str(id)))


## Placed at melee range from the start: this is not testing whether it
## can navigate to the player, only whether being there is enough to make
## it actually swing.
func _check_archetype_attacks(archetype: int) -> void:
    var name := _archetype_name(archetype)
    print("archetype ", name, " lands a hit when it is already on top of the player")
    player.global_position = Vector3(0.0, 0.03, 0.0)
    player.health = 180.0
    player.visible = true
    player.process_mode = Node.PROCESS_MODE_INHERIT

    var enemy := EnemyScene.new()
    enemy.archetype = archetype
    enemy.global_position = Vector3(1.1, 0.03, 0.0)
    game.add_child(enemy)
    enemy.set_target(player)
    await _physics_frames(4)

    var landed := false
    var starting_health: float = player.health
    for _i in 420:
        await get_tree().physics_frame
        if player.health < starting_health:
            landed = true
            break
    _expect(landed, "%s damaged the player within 7s at melee range" % name)

    enemy.queue_free()
    await _physics_frames(2)


## The excavator's enemy control drives at the player and, per the report,
## does nothing else once it arrives. Same bar: put it at melee range and
## see whether the player's health ever moves.
func _check_excavator_attacks() -> void:
    print("enemy-driven excavator lands a hit when it is already on top of the player")
    var excavator = game.excavator
    if excavator == null:
        _expect(false, "there is an excavator to test")
        return
    player.global_position = Vector3(0.0, 0.03, 0.0)
    player.health = 180.0
    player.visible = true
    player.process_mode = Node.PROCESS_MODE_INHERIT

    var driver := EnemyScene.new()
    driver.archetype = EnemyScene.RIGGER
    driver.global_position = excavator.global_position + Vector3(2.0, 0.03, 0.0)
    game.add_child(driver)
    await _physics_frames(4)
    excavator.set_enemy_driver(driver)
    excavator.global_position = Vector3(3.5, -0.17, 0.0)
    excavator.rotation.y = 0.0
    await _physics_frames(4)

    var landed := false
    var starting_health: float = player.health
    for _i in 480:
        await get_tree().physics_frame
        if player.health < starting_health:
            landed = true
            break
    _expect(landed, "excavator damaged the player within 8s at close range")
