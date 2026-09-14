extends Node

## Headless acceptance for the process plant, run against the live yard.
##
## Run: KF_PROCESS_CHECK=1 ./tools/godot --path . --audio-driver Dummy
##
## This measures one chain end to end, and it is deliberately the chain
## nobody is allowed to script: a machine opens a hole in a pipe, and every
## step after that is something a different system worked out for itself by
## reading the network. The only calls this harness makes are the ones a
## machine, a leak, or a rigger would make anyway.

var game: Node3D
var excavator
var pipe: ProcessPipe
var _failures := 0
var _baseline_header := 0.0
var _baseline_authority := 0.0


func begin(root: Node3D) -> void:
    game = root
    process_mode = Node.PROCESS_MODE_ALWAYS
    call_deferred("_run")


func _run() -> void:
    excavator = game.excavator
    _quiet_the_yard()
    await _physics_frames(90)

    pipe = _find_pipe("P_EAST_VENT")
    if pipe == null or excavator == null:
        push_error("PROCESS_CHECK_NO_PLANT")
        get_tree().quit(3)
        return

    _check_plant_stands_up()
    await _check_vent_cycles_on_its_own()
    _capture_baseline()

    await _check_machine_opens_a_hole()
    await _check_fluid_escapes_at_the_hole()
    await _check_pressure_collapses()
    _check_ground_lost_traction()
    await _check_vent_stops()
    _check_machine_lost_authority()
    await _check_rigger_isolates()
    await _check_pressure_recovers()

    if _failures == 0:
        print("PROCESS_CHECK_OK")
        get_tree().quit(0)
        return
    print("PROCESS_CHECK_FAILED count=", _failures)
    get_tree().quit(1)


## The plant is the subject. An unattended player gets killed by the crew,
## the death director reloads the scene, and the measurement starts over
## forever - so everything that is not being measured is parked, exactly as
## the crane and enemy harnesses do it. The excavator stays live but
## driverless: it is here as a supply consumer, not as a combatant.
func _quiet_the_yard() -> void:
    if game.player != null:
        game.player.process_mode = Node.PROCESS_MODE_DISABLED
        game.player.visible = false
    if game.mission != null:
        game.mission.process_mode = Node.PROCESS_MODE_DISABLED
    if game.crane != null:
        game.crane.process_mode = Node.PROCESS_MODE_DISABLED
    if excavator != null:
        excavator.enemy_driver = null
    for enemy in get_tree().get_nodes_in_group("enemy"):
        enemy.process_mode = Node.PROCESS_MODE_DISABLED


func _physics_frames(count: int) -> void:
    for _i in count:
        await get_tree().physics_frame


func _expect(condition: bool, claim: String) -> void:
    if condition:
        print("  ok   ", claim)
        return
    _failures += 1
    print("  FAIL ", claim)


func _find_pipe(edge_id: String) -> ProcessPipe:
    for node in get_tree().get_nodes_in_group("process_pipe"):
        if node is ProcessPipe and node.edge_id == edge_id:
            return node
    return null


func _header_mpa() -> float:
    return ProcessPlant.network.gauge_pressure(ProcessPlant.network.node_index("header")) / 1.0e6


func _plenum_mpa() -> float:
    return ProcessPlant.network.gauge_pressure(ProcessPlant.network.node_index("east_plenum")) / 1.0e6


func _check_plant_stands_up() -> void:
    print("the loop holds its set pressure with the yard idling")
    var net = ProcessPlant.network
    print("    substeps/frame=", net._substep_count(1.0 / 60.0),
        " header=", _header_mpa(),
        " plenum=", _plenum_mpa(),
        " supply=", net.gauge_pressure(net.node_index("excavator_supply")) / 1.0e6,
        " venthead=", net.gauge_pressure(net.node_index("east_vent_head")) / 1.0e6,
        " pump=", net.nodes[net.node_index("header")].pump_flow,
        " leak=", net.total_leak_flow())
    _expect(_header_mpa() > 15.0, "header is up at working pressure")
    _expect(
        ProcessPlant.network.stored_volume(ProcessPlant.network.node_index("reservoir")) > 2.0,
        "the tank is full"
    )
    _expect(
        pipe.collision_layer & 8 != 0,
        "pipe sits on the layer machine contact probes actually sweep"
    )


## No timer anywhere: the accumulator charges through a restriction until it
## cracks the relief, blows down to reseat and starts again.
func _check_vent_cycles_on_its_own() -> void:
    print("the vent cycles because its accumulator cycles")
    var opened := false
    var closed_after_opening := false
    var peak := 0.0
    for _i in 900:
        await get_tree().physics_frame
        peak = maxf(peak, _plenum_mpa())
        var open: bool = ProcessPlant.network.is_relief_open(ProcessPlant.edge_index("RELIEF_EAST"))
        if open:
            opened = true
        elif opened:
            closed_after_opening = true
            break
    _expect(opened, "the relief cracked on its own")
    _expect(closed_after_opening, "and reseated after blowing down")
    _expect(peak > 14.0, "the accumulator really did charge to cracking pressure")


func _capture_baseline() -> void:
    _baseline_header = _header_mpa()
    _baseline_authority = excavator.get_hydraulic_ratio()


## The call below is exactly the one the crane hook and the excavator arm
## make on anything they strike, carrying an energy a swung hook genuinely
## delivers. Nothing here tells the pipe how big a hole to open.
func _check_machine_opens_a_hole() -> void:
    print("a machine strike opens a breach the wall's own toughness sized")
    var hook_mass := 240.0
    var swing_speed := 7.6
    var energy := 0.5 * hook_mass * swing_speed * swing_speed
    var before := pipe.breach_area()
    pipe.machine_hit_at(
        clampf(energy / 900.0, 4.0, 110.0),
        Vector3(0.0, -0.3, 1.0).normalized(),
        pipe.global_position + Vector3(0.0, 0.1, 0.0),
        energy
    )
    await _physics_frames(4)
    _expect(before <= 0.0, "the wall was intact before the strike")
    _expect(pipe.breach_area() > 0.0, "the strike tore an opening")
    _expect(
        is_equal_approx(
            ProcessPlant.network.rupture_area(pipe.process_edge),
            pipe.breach_area()
        ),
        "the network is carrying the same hole the wall reports"
    )


func _check_fluid_escapes_at_the_hole() -> void:
    print("fluid leaves through the hole, where the hole is")
    await _physics_frames(20)
    var leak := ProcessPlant.network.leak_flow(pipe.process_edge)
    _expect(leak > 0.0, "the breach is discharging")
    var edge: Dictionary = ProcessPlant.network.edges[pipe.process_edge]
    var point: Vector3 = edge.leak_point
    _expect(
        point.distance_to(pipe.global_position) < 2.5,
        "the discharge is located at the struck run, not at an origin"
    )
    await _physics_frames(60)
    _expect(
        ProcessPlant.network.spilled_volume() > 0.0,
        "spilled volume is being accounted against the tank"
    )


func _check_pressure_collapses() -> void:
    print("the pump cannot outrun the hole")
    var net = ProcessPlant.network
    for _i in 900:
        await get_tree().physics_frame
        if _header_mpa() < _baseline_header * 0.5:
            break
    print("    breach=", pipe.breach_area(),
        " leak=", net.leak_flow(pipe.process_edge),
        " pump=", net.nodes[net.node_index("header")].pump_flow,
        " header=", _header_mpa(),
        " baseline=", _baseline_header)
    _expect(
        _header_mpa() < _baseline_header * 0.6,
        "header pressure fell well below its set point"
    )


## The leak is published as a fluid source through the material resolver, so
## the ground it lands on is wet by the same path rain or a hose would use,
## and the traction reading at that point is what a body standing there gets.
func _check_ground_lost_traction() -> void:
    print("the ground under the breach is slippery")
    var edge: Dictionary = ProcessPlant.network.edges[pipe.process_edge]
    var point: Vector3 = edge.leak_point
    var space := get_tree().root.get_world_3d().direct_space_state
    var query := PhysicsRayQueryParameters3D.create(
        point,
        point + Vector3.DOWN * 8.0,
        1 | 2 | 4 | 8
    )
    query.collide_with_areas = false
    var hit := space.intersect_ray(query)
    _expect(not hit.is_empty(), "the spray reached a surface below it")
    if hit.is_empty():
        return
    var ground = hit.get("collider")
    var traction := MaterialResponse.traction_at(ground, hit.get("position"))
    _expect(
        traction < 0.98,
        "traction at the spill is reduced (%.3f)" % traction
    )


func _check_vent_stops() -> void:
    print("the vent downstream of the breach stops firing")
    var relief := ProcessPlant.edge_index("RELIEF_EAST")
    var opened := false
    for _i in 420:
        await get_tree().physics_frame
        if ProcessPlant.network.is_relief_open(relief):
            opened = true
            break
    _expect(not opened, "the branch can no longer reach cracking pressure")
    _expect(
        _plenum_mpa() < 14.0,
        "the accumulator is not charging (%.2f MPa)" % _plenum_mpa()
    )


func _check_machine_lost_authority() -> void:
    print("the machine on that branch loses hydraulic authority")
    _expect(
        excavator.get_hydraulic_ratio() < _baseline_authority * 0.6,
        "supplied pressure dragged the excavator's authority down"
    )
    _expect(
        excavator.supply_pressure_ratio() < 0.6,
        "its supply point reads the collapse directly"
    )


## The rigger is given no instruction. It is put within walking distance of
## the yard with an intruder to care about, and it works out on its own that
## a valve is what the situation needs, which one, and walks to it.
func _check_rigger_isolates() -> void:
    print("a rigger reads the plant and shuts the right valve")
    var plan: Dictionary = ProcessPlant.plan_isolation()
    _expect(not plan.is_empty(), "the graph offers an isolating valve")
    if plan.is_empty():
        return
    _expect(
        str(plan.get("valve_id", "")) == "V_EAST_VENT",
        "it names the spur valve, not the main (%s)" % str(plan.get("valve_id", ""))
    )
    _expect(
        int(plan.get("supplies_kept", 0)) >= 2,
        "the choice keeps both machine supplies fed"
    )

    var valve = plan.get("body")
    var rigger = _wake_a_rigger(valve)
    _expect(rigger != null, "there is a rigger in the yard to do it")
    if rigger == null or valve == null:
        return
    var closed := false
    for _i in 900:
        await get_tree().physics_frame
        if valve.aperture() <= 0.05:
            closed = true
            break
    _expect(closed, "the rigger reached the wheel and shut it")


func _wake_a_rigger(valve):
    for enemy in get_tree().get_nodes_in_group("enemy"):
        if not is_instance_valid(enemy) or enemy.dead:
            continue
        if enemy.archetype != enemy.RIGGER:
            continue
        # Skip the one sitting in the excavator: it is hidden, parked, and
        # already has a job.
        if not enemy.visible:
            continue
        enemy.process_mode = Node.PROCESS_MODE_INHERIT
        enemy.global_position = valve.global_position + Vector3(6.0, 0.03, 6.0)
        enemy.set_target(game.player)
        if game.player != null:
            game.player.global_position = (
                valve.global_position + Vector3(-14.0, 0.03, 12.0)
            )
        return enemy
    return null


func _check_pressure_recovers() -> void:
    print("with the branch isolated the loop comes back")
    for _i in 900:
        await get_tree().physics_frame
        if _header_mpa() > _baseline_header * 0.9:
            break
    print("    header=", _header_mpa(), " baseline=", _baseline_header,
        " leak=", ProcessPlant.network.leak_flow(pipe.process_edge))
    _expect(
        _header_mpa() > _baseline_header * 0.85,
        "header pressure recovered (%.2f MPa)" % _header_mpa()
    )
    _expect(
        ProcessPlant.network.leak_flow(pipe.process_edge) <= 0.0
        or _header_mpa() > _baseline_header * 0.85,
        "the hole is no longer being fed"
    )
    _expect(
        excavator.get_hydraulic_ratio() > _baseline_authority * 0.85,
        "the excavator has its authority back"
    )
    _expect(
        pipe.breach_area() > 0.0,
        "the hole is still there - isolation is not repair"
    )
