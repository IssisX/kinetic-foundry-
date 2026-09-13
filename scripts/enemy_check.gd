extends Node

## Headless acceptance for the yard crew archetypes, run against the live
## yard.
##
## Run: KF_ENEMY_CHECK=1 ./tools/godot --path . --audio-driver Dummy
##
## An archetype is only worth having if it behaves differently, not if it
## only has different numbers. Each check below is something the old single
## enemy could not do at all.

const EnemyScript = preload("res://scripts/enemy.gd")
const PropScript = preload("res://scripts/physics_prop.gd")

var game: Node3D
var _failures := 0
var _spawned: Array[Node] = []


func begin(root: Node3D) -> void:
    game = root
    process_mode = Node.PROCESS_MODE_ALWAYS
    call_deferred("_run")


func _run() -> void:
    _quiet_the_yard()
    await _physics_frames(4)

    await _check_plate_stops_what_hits_its_face()
    await _check_plate_fails_into_debris()
    await _check_rigger_goes_for_a_machine()
    await _check_thrower_uses_the_yard_as_ammunition()
    await _check_thrown_mass_hurts()

    for node in _spawned:
        if is_instance_valid(node):
            node.queue_free()

    if _failures == 0:
        print("ENEMY_CHECK_OK")
        get_tree().quit(0)
        return
    print("ENEMY_CHECK_FAILED count=", _failures)
    get_tree().quit(1)


## Park everything the yard spawned so the only actors are the ones each
## check makes on purpose.
func _quiet_the_yard() -> void:
    if game.player != null:
        game.player.process_mode = Node.PROCESS_MODE_DISABLED
        game.player.global_position = Vector3(0.0, 0.03, 0.0)
    if game.mission != null:
        game.mission.process_mode = Node.PROCESS_MODE_DISABLED
    if game.excavator != null:
        game.excavator.process_mode = Node.PROCESS_MODE_DISABLED
        game.excavator.global_position = Vector3(120.0, 0.0, 120.0)
    for enemy in get_tree().get_nodes_in_group("enemy"):
        enemy.process_mode = Node.PROCESS_MODE_DISABLED
        enemy.visible = false
        enemy.global_position = Vector3(200.0, 0.0, 200.0)


func _physics_frames(count: int) -> void:
    for _i in count:
        await get_tree().physics_frame


func _expect(condition: bool, claim: String) -> void:
    if condition:
        print("  ok   ", claim)
        return
    _failures += 1
    print("  FAIL ", claim)


func _spawn(archetype: int, at: Vector3) -> FoundryEnemy:
    var enemy: FoundryEnemy = EnemyScript.new()
    enemy.archetype = archetype
    enemy.position = at
    game.add_child(enemy)
    enemy.set_target(game.player)
    _spawned.append(enemy)
    return enemy


## Position before the body joins the tree: the physics server owns a rigid
## body's transform once it is simulating.
func _spawn_crate(at: Vector3, crate_mass: float = 70.0) -> RigidBody3D:
    var crate: RigidBody3D = PropScript.new()
    crate.position = at
    game.add_child(crate)
    crate.configure_box(Vector3(0.7, 0.7, 0.7), Color(0.5, 0.42, 0.2), crate_mass, 90.0)
    _spawned.append(crate)
    return crate


## A blow that lands on the plate is not the same as a blow that lands on
## the body behind it.
func _check_plate_stops_what_hits_its_face() -> void:
    print("the plate is worth carrying")
    var attacker := Vector3(0.0, 0.03, -6.0)
    var front := _spawn(EnemyScript.PLATE, Vector3(-4.0, 0.03, -10.0))
    var back := _spawn(EnemyScript.PLATE, Vector3(4.0, 0.03, -10.0))
    await _physics_frames(4)

    for enemy in [front, back]:
        enemy.look_at(attacker + Vector3(enemy.global_position.x, 0.0, 0.0), Vector3.UP)
    front.rotation.y = 0.0
    back.rotation.y = 0.0
    await _physics_frames(2)

    # Facing is -Z, so a frontal blow drives the body along +Z.
    var blow := Vector3(0.0, 0.0, 1.0) * 9.0
    front.take_hit(blow, 40.0)
    back.take_hit(-blow, 40.0)

    _expect(
        front.health > back.health,
        "a hit on the plate costs less health than the same hit from behind"
    )
    _expect(
        front.plate_integrity() < 1.0,
        "and the plate itself is what took the difference"
    )
    _expect(
        back.plate_integrity() >= 1.0,
        "a hit from behind never touches the plate"
    )


## The plate does not have a hit counter. It fails because of the work put
## into it, and what is left is debris that remembers the fight.
func _check_plate_fails_into_debris() -> void:
    print("the plate fails into wreckage that remembers the fight")
    var carrier := _spawn(EnemyScript.PLATE, Vector3(-12.0, 0.03, -10.0))
    carrier.rotation.y = 0.0
    await _physics_frames(4)

    var before := _count_debris()
    var plate_node: Node = carrier.get_node_or_null("CarriedPlate")
    _expect(plate_node != null, "the carrier is actually carrying a plate")
    var plate_state: SurfaceState = MaterialResponse.state_for(
        plate_node,
        FoundryMaterial.PAINTED_STEEL
    )

    var swings := 0
    while carrier.plate_integrity() > 0.0 and swings < 40:
        carrier.health = carrier.max_health
        carrier.take_hit(Vector3(0.0, 0.0, 1.0) * 9.0, 30.0)
        swings += 1
        await get_tree().physics_frame

    _expect(swings > 1, "the plate survives more than one hit")
    _expect(
        carrier.plate_integrity() <= 0.0,
        "but sustained work does destroy it"
    )
    _expect(
        plate_state != null and plate_state.plasticity > 0.0,
        "the work was recorded as permanent set, not a hit count"
    )
    await _physics_frames(2)
    _expect(
        _count_debris() > before,
        "what is left of it is physical debris in the yard"
    )


## The rigger's distinguishing behaviour: it walks away from the fight to
## go and get a machine.
func _check_rigger_goes_for_a_machine() -> void:
    print("the rigger goes and gets a machine")
    var crane = game.crane
    _expect(crane != null, "there is a machine in the yard to take")
    if crane == null:
        return
    crane.enemy_driver = null
    crane.player_driver = null
    crane.global_position = Vector3(-30.0, 0.0, -30.0)
    await _physics_frames(2)

    var rigger := _spawn(EnemyScript.RIGGER, Vector3(-22.0, 0.03, -22.0))
    var grunt := _spawn(EnemyScript.GRUNT, Vector3(-22.0, 0.03, -21.0))
    await _physics_frames(4)

    var rigger_start: float = rigger.global_position.distance_to(crane.global_position)
    var grunt_start: float = grunt.global_position.distance_to(crane.global_position)
    await _physics_frames(90)

    var rigger_now: float = rigger.global_position.distance_to(crane.global_position)
    var grunt_now: float = grunt.global_position.distance_to(crane.global_position)
    _expect(
        rigger_now < rigger_start - 1.0 or crane.enemy_driver == rigger,
        "the rigger closes on the machine"
    )
    _expect(
        grunt_now >= grunt_start - 0.5,
        "the grunt does not: it is still going for the target"
    )

    await _physics_frames(150)
    _expect(
        crane.enemy_driver != null,
        "and given time it is in the seat"
    )
    if crane.enemy_driver != null:
        crane.enemy_driver = null
        crane.process_mode = Node.PROCESS_MODE_DISABLED


## The thrower turns loose yard mass into a weapon, using the same grip law
## machines use to hold a load.
func _check_thrower_uses_the_yard_as_ammunition() -> void:
    print("the thrower uses the yard as ammunition")
    game.player.global_position = Vector3(40.0, 0.03, 0.0)
    var thrower := _spawn(EnemyScript.THROWER, Vector3(28.0, 0.03, 0.0))
    var crate := _spawn_crate(Vector3(27.0, 0.5, 0.6))
    await _physics_frames(4)

    var picked_up := false
    for _i in 180:
        await get_tree().physics_frame
        if thrower.is_carrying():
            picked_up = true
            break
    _expect(picked_up, "it picks up loose mass rather than closing empty handed")

    var launched := false
    for _i in 260:
        await get_tree().physics_frame
        if not thrower.is_carrying() and crate.linear_velocity.length() > 4.0:
            launched = true
            break
    _expect(launched, "and throws it")
    if launched:
        var toward: float = crate.linear_velocity.normalized().dot(
            (game.player.global_position - crate.global_position).normalized()
        )
        _expect(toward > 0.2, "it throws it at the target, not away")


## Improvised weapons were a verb the design called for and nothing
## implemented: a thrown crate used to be scenery in flight.
func _check_thrown_mass_hurts() -> void:
    print("thrown mass actually hurts what it hits")
    # Everything spawned so far stands down, so the only thing in the lane
    # is the crate and what it is aimed at.
    for node in _spawned:
        if is_instance_valid(node) and node is FoundryEnemy:
            (node as FoundryEnemy).set_target(null)

    var victim := _spawn(EnemyScript.GRUNT, Vector3(38.0, 0.03, 0.0))
    victim.set_target(null)
    var crate := _spawn_crate(Vector3(34.0, 1.05, 0.0), 80.0)
    await _physics_frames(10)

    var space := game.get_world_3d().direct_space_state
    var query := PhysicsRayQueryParameters3D.create(
        crate.global_position,
        victim.global_position + Vector3.UP * 0.9,
        1 | 2 | 4 | 8
    )
    query.exclude = [crate.get_rid()]
    var sighting := space.intersect_ray(query)
    _expect(
        sighting.get("collider") == victim,
        "the lane to the target is clear, so the measurement means something"
    )

    var before: float = victim.health
    crate.launch(Vector3(14.0, 0.6, 0.0), null)
    var struck := false
    for _i in 90:
        await get_tree().physics_frame
        if victim.health < before:
            struck = true
            break
    _expect(struck, "a crate thrown into a body damages it")
    _expect(
        MaterialResponse.state_for(victim, FoundryMaterial.STRUCTURAL_STEEL) != null,
        "and the impact went through the shared material resolver"
    )


func _count_debris() -> int:
    var count := 0
    for node in get_tree().get_nodes_in_group("reusable_debris"):
        if is_instance_valid(node):
            count += 1
    return count
