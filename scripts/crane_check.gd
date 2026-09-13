extends Node

## Headless acceptance for the crawler crane, run against the live yard.
##
## Run: KF_CRANE_CHECK=1 ./tools/godot --path . --audio-driver Dummy
##
## The crane only earns its place if the rope behaves like a rope: the load
## has to lag the machine, keep its momentum after the operator stops, swing
## faster when it is hoisted in, and cost the crane its stability at radius.
## None of that is visible in a screenshot, so it is measured.

var game: Node3D
var crane
var _failures := 0


func begin(root: Node3D) -> void:
    game = root
    process_mode = Node.PROCESS_MODE_ALWAYS
    call_deferred("_run")


func _run() -> void:
    crane = game.crane
    if crane == null:
        push_error("CRANE_CHECK_NO_CRANE")
        get_tree().quit(3)
        return

    _quiet_the_yard()
    crane.global_position = Vector3(-16.0, 0.0, 16.0)
    crane.rotation.y = 0.0
    crane.slew_angle = 0.0
    crane.luff_angle = 0.75
    crane.rope_length = 8.0
    crane.place_hook()
    await _physics_frames(40)

    await _check_rope_hangs()
    var swing := await _check_swing_developed()
    await _check_momentum_outlives_the_input()
    await _check_hoisting_in_speeds_the_swing(float(swing))
    await _check_radius_drives_tipping()
    _check_shared_authorities()

    if _failures == 0:
        print("CRANE_CHECK_OK")
        get_tree().quit(0)
        return
    print("CRANE_CHECK_FAILED count=", _failures)
    get_tree().quit(1)


## The crane is the subject; everything else in the yard would only add
## contacts to the measurement.
func _quiet_the_yard() -> void:
    if game.player != null:
        game.player.process_mode = Node.PROCESS_MODE_DISABLED
        game.player.visible = false
    if game.excavator != null:
        game.excavator.process_mode = Node.PROCESS_MODE_DISABLED
    if game.mission != null:
        game.mission.process_mode = Node.PROCESS_MODE_DISABLED
    for enemy in get_tree().get_nodes_in_group("enemy"):
        enemy.process_mode = Node.PROCESS_MODE_DISABLED
        enemy.visible = false


func _physics_frames(count: int) -> void:
    for _i in count:
        await get_tree().physics_frame


func _expect(condition: bool, claim: String) -> void:
    if condition:
        print("  ok   ", claim)
        return
    _failures += 1
    print("  FAIL ", claim)


func _tip() -> Vector3:
    return crane._boom_tip.global_position


func _rope_offset() -> Vector3:
    return crane.get_hook_position() - _tip()


func _check_rope_hangs() -> void:
    print("the rope holds the hook at its length, under the tip")
    var offset := _rope_offset()
    _expect(
        absf(offset.length() - crane.rope_length) < 0.06,
        "hook sits at the rope length from the boom tip"
    )
    _expect(
        offset.y < -0.9 * crane.rope_length,
        "at rest it hangs straight down"
    )
    _expect(
        _tip().y > crane.global_position.y + 4.0,
        "a luffed boom puts its tip well above the machine"
    )


func _check_swing_developed() -> float:
    print("slewing throws the load wide instead of carrying it rigidly")
    for _i in 45:
        crane.slew_angle += 0.030
        await get_tree().physics_frame
    var offset := _rope_offset()
    var horizontal := Vector2(offset.x, offset.z).length()
    var speed: float = crane._hook_velocity.length()
    _expect(
        horizontal > 0.25,
        "the hook trails out from under the tip while the crane slews"
    )
    _expect(
        absf(offset.length() - crane.rope_length) < 0.06,
        "the rope does not stretch to let that happen"
    )
    _expect(speed > 0.3, "the load is actually moving")
    return speed / maxf(crane.rope_length, 0.001)


func _check_momentum_outlives_the_input() -> void:
    print("the load keeps its own momentum")
    await _physics_frames(8)
    _expect(
        crane._hook_velocity.length() > 0.2,
        "the load is still swinging after the operator stops slewing"
    )
    _expect(
        crane.get_working_radius() > 1.0,
        "and it is still out at radius"
    )


func _check_hoisting_in_speeds_the_swing(previous_rate: float) -> void:
    print("hoisting in shortens the pendulum")
    for _i in 40:
        crane.rope_length = maxf(2.4, crane.rope_length - 0.14)
        await get_tree().physics_frame
    var offset := _rope_offset()
    _expect(
        absf(offset.length() - crane.rope_length) < 0.08,
        "the hook follows the rope in as it is reeled"
    )
    var rate: float = crane._hook_velocity.length() / maxf(crane.rope_length, 0.001)
    _expect(
        rate > previous_rate,
        "a shorter rope swings faster than a long one"
    )


## Same load, same rope, two boom angles: the only thing that changed is
## how far out the weight is hanging.
func _check_radius_drives_tipping() -> void:
    print("radius is what threatens to put the crane over")
    crane.luff_angle = 1.05
    crane.rope_length = 4.0
    crane.place_hook()
    await _physics_frames(60)
    var near_radius: float = crane.get_working_radius()
    var near_ratio: float = crane._tipping_ratio

    crane.luff_angle = crane.LUFF_MIN
    crane.place_hook()
    await _physics_frames(60)

    _expect(
        crane.get_working_radius() > near_radius + 1.0,
        "dropping the boom pushes the hook further out"
    )
    _expect(
        crane._tipping_ratio > near_ratio,
        "and that radius costs the crane its stability margin"
    )
    _expect(
        not crane.is_hook_grounded(),
        "the hook is still hanging, so this compares like with like"
    )
    _expect(
        MachineStability.tipping_ratio(
            MachineStability.load_moment(2000.0, 9.0),
            4200.0,
            1.95
        ) > 1.0,
        "two tonnes at nine metres is past this machine's tipping line"
    )


## The point of the machine is that it brought verbs, not subsystems.
func _check_shared_authorities() -> void:
    print("the crane runs on the authorities the yard already owned")
    _expect(
        MaterialResponse.material_of(crane) == FoundryMaterial.PAINTED_STEEL,
        "it has an identity in the shared material catalog"
    )
    _expect(
        crane is FoundryMachine,
        "it is a machine, so occupancy and damage are not reimplemented"
    )
    _expect(
        crane.get_control_profile().has("machine_name"),
        "it presents the same control profile contract the HUD reads"
    )
    _expect(
        crane.has_method("get_sustained_contact_state"),
        "it reports contact state the way the audio and structure layers expect"
    )
