class_name VisualCapture
extends Node

var game: Node3D
var capture_dir := ""

func begin(root: Node3D) -> void:
    game = root
    process_mode = Node.PROCESS_MODE_ALWAYS
    capture_dir = OS.get_environment("CAPTURE_DIR")
    if capture_dir.is_empty():
        capture_dir = ProjectSettings.globalize_path("res://captures/latest")
    DirAccess.make_dir_recursive_absolute(capture_dir)
    _freeze_gameplay()
    if game.camera_rig != null:
        game.camera_rig.collision_enabled = false
    call_deferred("_run")

func _run() -> void:
    get_tree().paused = true
    await _settle_frames(4)

    _stage_yard_overview()
    await _settle_frames(4)
    _capture("01_yard_overview.png")

    _stage_combat()
    await _settle_frames(4)
    _capture("02_grounded_combat.png")

    _stage_excavator_operator_pov()
    await _settle_frames(4)
    _capture("03_excavator_load_control.png")

    _stage_structure_damage()
    await _settle_frames(4)
    _capture("04_progressive_structure_damage.png")

    get_tree().paused = false
    _stage_structure_collapse()
    await _settle_physics_frames(58)
    await _settle_frames(4)
    get_tree().paused = true
    _capture("05_collapse_aftermath.png")

    get_tree().paused = false
    _stage_breach_gate()
    await _settle_physics_frames(24)
    await _settle_frames(4)
    get_tree().paused = true
    _capture("06_breached_route.png")

    get_tree().paused = false
    _stage_crane_load_swing()
    await _settle_physics_frames(46)
    await _settle_frames(4)
    get_tree().paused = true
    _capture("09_crane_suspended_load.png")

    get_tree().paused = false
    _stage_dozer_blade_push()
    await _settle_physics_frames(36)
    await _settle_frames(4)
    get_tree().paused = true
    _capture("10_dozer_blade_push.png")

    get_tree().paused = false
    var gait_ok: bool = await _stage_gait_observables()
    if not gait_ok:
        get_tree().quit(4)
        return

    print("CAPTURE_SUITE_OK dir=", capture_dir)
    get_tree().quit(0)

func _freeze_gameplay() -> void:
    if game.player != null:
        game.player.process_mode = Node.PROCESS_MODE_DISABLED
    if game.excavator != null:
        game.excavator.process_mode = Node.PROCESS_MODE_DISABLED
    if game.dozer != null:
        game.dozer.process_mode = Node.PROCESS_MODE_DISABLED
    if game.crane != null:
        game.crane.process_mode = Node.PROCESS_MODE_DISABLED
    if game.mission != null:
        game.mission.process_mode = Node.PROCESS_MODE_DISABLED
    for enemy in get_tree().get_nodes_in_group("enemy"):
        enemy.process_mode = Node.PROCESS_MODE_DISABLED
    for mover in get_tree().get_nodes_in_group("capture_mover"):
        mover.process_mode = Node.PROCESS_MODE_DISABLED
        mover.visible = false

func _stage_yard_overview() -> void:
    _show_all_enemies(true)
    game.player.visible = true
    game.player.global_position = Vector3(-6.0, 0.03, 10.0)
    game.excavator.global_position = Vector3(3.5, -0.17, 1.0)
    game.excavator.rotation.y = 0.34
    if game.dozer != null:
        game.dozer.visible = true
        game.dozer.global_position = Vector3(11.6, -0.12, 7.4)
        game.dozer.rotation.y = -0.72
        game.dozer.blade_lift = 0.10
        game.dozer.blade_tilt = 0.06
        game.dozer._apply_pose()
    if game.crane != null:
        game.crane.visible = true
    game.mission.stage = 0
    _clear_machine_hud()
    game.hud.set_health(0.92)
    game.hud.set_target(null)
    game.hud.set_objective("BREAK THE YARD CREW", "CUT THROUGH THE ACTIVE FOUNDRY AND EXPOSE THE MACHINE")
    game.hud.set_objective_progress(0.20)
    game.hud.set_context("POWER // COMBAT // MACHINES")
    _camera(Vector3(30.0, 20.0, 30.0), Vector3(0.0, 3.4, -4.0), 60.0)

func _stage_combat() -> void:
    game.player.visible = true
    game.player.global_position = Vector3(0.0, 0.03, 10.5)
    game.player.rotation.y = PI
    game.player.attack_anim = 0.22
    game.player.attack_duration = 0.38
    game.player.attack_mode = 1
    game.player.attack_side = 1.0
    if game.player._rig != null:
        game.player._rig.set_attack_side(1.0)
        game.player._rig.set_attack_mode(1)
        game.player._animate(0.016)

    var visible_enemies := _visible_enemies()
    var positions := [Vector3(-2.1, 0.03, 8.4), Vector3(2.2, 0.03, 8.2), Vector3(-3.5, 0.03, 11.3), Vector3(3.7, 0.03, 11.7)]
    for i in mini(visible_enemies.size(), positions.size()):
        var enemy = visible_enemies[i]
        enemy.visible = true
        enemy.global_position = positions[i]
        enemy.look_at(game.player.global_position, Vector3.UP)
        enemy.attack_windup = 0.18 if i == 0 else 0.0
        enemy.hit_anim = 0.11 if i == 1 else 0.0
        enemy._animate(0.016)
    for i in range(positions.size(), visible_enemies.size()):
        visible_enemies[i].visible = false

    game.player.engaged_target = visible_enemies[0] if not visible_enemies.is_empty() else null
    _clear_machine_hud()
    game.hud.set_health(0.76)
    game.hud.set_target(game.player.engaged_target)
    game.hud.set_objective("BREAK THE YARD CREW", "TACKLE // COMBO // KICK // GRAB // THROW")
    game.hud.set_objective_progress(0.45)
    game.hud.set_context("ANALYTIC GAIT // SIDE KICK // HEAVY FINISHER")
    _camera(Vector3(6.8, 4.8, 16.0), Vector3(0.0, 1.20, 9.7), 60.0)

func _stage_excavator_operator_pov() -> void:
    game.player.visible = false
    _show_all_enemies(false)
    game.excavator.enemy_driver = null
    game.excavator.player_driver = game.player
    game.excavator.global_position = Vector3(0.0, -0.17, 2.5)
    game.excavator.rotation.y = 0.12
    game.excavator.arm_yaw = -0.10
    game.excavator.boom_angle = -0.42
    game.excavator.stick_angle = 0.58
    game.excavator.tool_angle = -0.38
    game.excavator._apply_arm_pose()

    var load = _first_prop()
    if load != null:
        game.excavator.hold_load(load)

    game.mission.stage = 2
    if game.hud.has_method("set_machine_profile") and game.excavator.has_method("get_control_profile"):
        game.hud.set_machine_profile(game.excavator.get_control_profile())
    else:
        game.hud.set_machine_mode(true)
    game.hud.set_target(null)
    game.hud.set_objective("DROP THE TRANSFER PLATFORM", "YOU ARE THE OPERATOR // READ THE LOAD PATH THROUGH THE GLASS")
    game.hud.set_objective_progress(0.18)
    game.hud.set_machine_telemetry(0.88, 0.82, 0.91, 0.72, load != null)
    game.hud.set_context("CAB POV // HYDRAULIC THUMB // DIRECT ARM")

    var anchor: Node3D = game.excavator.get_operator_view_anchor() if game.excavator.has_method("get_operator_view_anchor") else null
    if anchor != null:
        var eye := anchor.global_position
        var look := eye - anchor.global_basis.z * 18.0 + Vector3.UP * 0.15
        _camera(eye, look, 78.0)
    else:
        _camera(game.excavator.global_position + Vector3(0.0, 2.7, -0.4), game.excavator.global_position - game.excavator.global_basis.z * 12.0 + Vector3.UP * 2.0, 78.0)

func _stage_structure_damage() -> void:
    _release_capture_load()
    var beam = _heaviest_prop()
    var support_a = game.structure.supports[0] if game.structure.supports.size() > 0 else null
    var hit_point: Vector3 = game.structure.global_position + Vector3(-3.7, 2.1, -2.2)
    if support_a != null and is_instance_valid(support_a):
        hit_point = support_a.global_position + Vector3(0.38, -0.35, 0.12)
    if beam != null and game.excavator != null:
        game.excavator.hold_load(beam)
        beam.global_position = hit_point + Vector3(0.55, 0.18, 0.08)
        game.excavator.global_position = Vector3(7.2, -0.17, -10.8)
        game.excavator.rotation.y = -0.55
        game.excavator.arm_yaw = 0.18
        game.excavator.boom_angle = -0.22
        game.excavator.stick_angle = 0.46
        game.excavator.tool_angle = -0.42
        game.excavator._apply_arm_pose()
    game.structure.damage_support(
        0,
        72.0,
        Vector3(1.0, 0.08, 0.18),
        hit_point,
        18500.0
    )
    game.structure.damage_support(2, 22.0, Vector3(0.55, 0.0, -0.28))
    game.mission.stage = 2
    _set_machine_hud()
    game.hud.set_objective("DROP THE TRANSFER PLATFORM", "HIT THE FLANGE // THE COLUMN KINKS WHERE THE BEAM LANDS")
    game.hud.set_objective_progress(0.52)
    game.hud.set_machine_telemetry(0.84, 0.76, 0.90, 0.88, true)
    game.hud.set_context("STRESS WAVE // CRACK FRONT FROM CONTACT // FLANGE KINKS AT HIT HEIGHT")
    _camera(
        hit_point + Vector3(3.6, 1.15, 2.4),
        hit_point + Vector3(-0.15, 0.05, -0.05),
        38.0
    )

func _stage_structure_collapse() -> void:
    _release_capture_load()
    var beam = _heaviest_prop()
    if beam != null and is_instance_valid(beam):
        beam.sleeping = false
        beam.freeze = false
        beam.global_position = (
            game.structure.global_position
            + Vector3(-0.8, 6.2, 0.35)
        )
        beam.linear_velocity = Vector3(1.4, -7.2, 0.2)
        beam.angular_velocity = Vector3(0.6, 0.2, -0.4)
    game.structure.damage_support(0, 55.0, Vector3(1.0, 0.0, 0.25))
    game.structure.damage_support(2, 90.0, Vector3(1.0, 0.0, -0.20))
    game.mission.stage = 3
    _clear_machine_hud()
    game.hud.set_target(null)
    game.hud.set_objective("OWN THE WRECKAGE", "420 KG FALLS WITH THE DECK // COLLAPSE BECOMES TERRAIN")
    game.hud.set_objective_progress(0.63)
    game.hud.set_context("CHAIN REACTION // MASS KEEPS MOVING")
    _camera(Vector3(22.0, 8.0, -4.5), game.structure.global_position + Vector3(0.0, 1.5, 0.0), 54.0)

func _stage_breach_gate() -> void:
    var gates := get_tree().get_nodes_in_group("breachable")
    if gates.is_empty():
        push_error("CAPTURE_BREACH_GATE_MISSING")
        return
    var gate = gates[0]
    var punch: Vector3 = gate.global_position + Vector3(-2.15, 2.35, -0.12)
    if gate.panels.size() > 0 and is_instance_valid(gate.panels[0]):
        punch = gate.panels[0].global_position + Vector3(-0.72, 0.48, -0.12)
    if gate.has_method("damage_panel_at"):
        gate.damage_panel_at(
            0,
            145.0,
            Vector3(0.18, 0.04, 1.0),
            punch,
            24000.0
        )
    else:
        gate.damage_panel(0, 145.0, Vector3(0.15, 0.05, 1.0))
    game.mission.stage = 4
    _set_machine_hud()
    game.hud.set_objective("BREACH THE NORTH ACCESS", "STAR-CRACK FROM THE BUCKET // CELLS FAIL AT THE CONTACT")
    game.hud.set_objective_progress(1.0)
    game.hud.set_machine_telemetry(0.79, 0.72, 0.86, 0.94, false)
    game.hud.set_context("GRIFFITH FRONT // WAVE ARRIVES // HOLE YOU CAN DRIVE THROUGH")
    _camera(punch + Vector3(3.8, 1.6, -4.6), punch + Vector3(0.1, -0.15, 0.0), 40.0)

func _stage_gait_observables() -> bool:
    _show_all_enemies(false)
    game.excavator.visible = false
    if game.dozer != null:
        game.dozer.visible = false
    if game.crane != null:
        game.crane.visible = false
    game.player.visible = true
    game.player.global_position = Vector3(-1.2, 0.03, 13.5)
    game.player.rotation = Vector3.ZERO
    game.player.attack_anim = 0.0
    game.player.hit_anim = 0.0

    var rig = game.player._rig
    if rig == null:
        push_error("CAPTURE_GAIT_RIG_MISSING")
        return false
    rig.reset_gait_state()
    rig.set_gait_debug_enabled(true)

    var walk_speed := 1.28
    var walk_velocity := Vector3(0.0, 0.0, -walk_speed)
    game.player.velocity = walk_velocity
    game.player.force_update_transform()
    await get_tree().physics_frame

    for _i in 270:
        await _advance_gait_frame(rig, walk_velocity)

    for _i in 120:
        await _advance_gait_frame(rig, walk_velocity)
        var state: Dictionary = rig.get_gait_observables()
        var swing: Dictionary = (
            state.left
            if not state.left.planted
            else state.right
        )
        if (
            not state.double_support
            and swing.swing_progress > 0.34
            and swing.swing_progress < 0.66
        ):
            break

    var focus: Vector3 = game.player.global_position
    _clear_machine_hud()
    game.hud.set_target(null)
    game.hud.set_health(1.0)
    game.hud.set_objective(
        "WORLD-SPACE WALK SOLVER",
        "SINGLE SUPPORT // SWING CLEARANCE // FORWARD KNEE POLE"
    )
    game.hud.set_objective_progress(0.72)
    game.hud.set_context(
        "PLANTED CONTACTS // COM TRANSFER // ANALYTIC IK"
    )
    _camera(
        focus + Vector3(4.8, 2.65, -3.8),
        focus + Vector3(0.0, 1.05, 0.0),
        46.0
    )
    await _settle_frames(8)
    _capture("07_walk_single_support.png")

    for _i in 120:
        await _advance_gait_frame(rig, walk_velocity)
        var state: Dictionary = rig.get_gait_observables()
        if state.double_support:
            break

    focus = game.player.global_position
    game.hud.set_objective(
        "WORLD-SPACE WALK SOLVER",
        "DOUBLE SUPPORT // HEEL STRIKE // TOE RELEASE"
    )
    game.hud.set_objective_progress(0.86)
    game.hud.set_context(
        "NO FLIGHT PHASE // SUPPORT BRIDGE // GROUNDED FEET"
    )
    _camera(
        focus + Vector3(-4.4, 2.45, -3.4),
        focus + Vector3(0.0, 1.00, 0.0),
        47.0
    )
    await _settle_frames(8)
    _capture("08_walk_double_support.png")

    var acceptance: Dictionary = (
        rig.get_gait_acceptance_window()
    )
    print("GAIT_ACCEPTANCE ", JSON.stringify(acceptance))
    var accepted := _gait_acceptance_passes(acceptance)
    rig.set_gait_debug_enabled(false)
    return accepted

func _advance_gait_frame(rig, velocity: Vector3) -> void:
    const STEP := 1.0 / 60.0
    game.player.global_position += velocity * STEP
    game.player.force_update_transform()
    rig.animate(
        STEP,
        velocity.length(),
        game.player.speed,
        0.0,
        0.0,
        false
    )
    await get_tree().physics_frame

func _gait_acceptance_passes(data: Dictionary) -> bool:
    var valid: bool = (
        data.duration >= 3.99
        and data.left_stance_fraction > 0.52
        and data.left_stance_fraction < 0.78
        and data.right_stance_fraction > 0.52
        and data.right_stance_fraction < 0.78
        and data.double_support_fraction > 0.06
        and data.double_support_fraction < 0.34
        and data.max_planted_velocity < 0.012
        and data.max_ground_error < 0.010
    )
    if not valid:
        push_error(
            "GAIT_ACCEPTANCE_FAILED %s"
            % JSON.stringify(data)
        )
    return valid

func _stage_crane_load_swing() -> void:
    game.player.visible = false
    _show_all_enemies(false)
    _release_capture_load()
    var crane = game.crane
    if crane == null:
        return
    crane.global_position = Vector3(-9.0, -0.10, 12.5)
    crane.rotation.y = 0.0
    crane.slew_angle = 0.40
    crane.luff_angle = 0.70
    crane.rope_length = 5.0
    crane.force_update_transform()
    crane._apply_upper_pose()
    crane.place_hook(Vector3(1.9, 0.0, -1.2))

    var load = _first_prop()
    if load != null:
        load.global_position = crane.get_hook_position()
        load.linear_velocity = Vector3.ZERO
        load.angular_velocity = Vector3.ZERO
        crane.hold_load(load)

    if game.hud.has_method("set_machine_profile"):
        game.hud.set_machine_profile(crane.get_control_profile())
    else:
        game.hud.set_machine_mode(true)
    game.hud.set_health(0.88)
    game.hud.set_target(null)
    game.hud.set_objective(
        "WORK THE ROPE",
        "SLEW // LUFF // HOIST // THE LOAD KEEPS ITS OWN MOMENTUM"
    )
    game.hud.set_objective_progress(0.55)
    game.hud.set_context("SUSPENDED LOAD // RADIUS DRIVES TIPPING")
    _camera(Vector3(9.0, 11.0, 26.5), Vector3(-8.0, 5.2, 8.5), 55.0)


func _stage_dozer_blade_push() -> void:
    game.player.visible = false
    _show_all_enemies(false)
    _release_capture_load()
    if game.crane != null and game.crane.has_method("drop_load") and game.crane.is_holding_load():
        game.crane.drop_load()
    if game.excavator != null:
        game.excavator.visible = true
    var dozer = game.dozer
    if dozer == null:
        return
    dozer.visible = true
    dozer.global_position = Vector3(12.4, -0.12, 7.1)
    dozer.rotation.y = 0.32
    dozer.blade_lift = 0.05
    dozer.blade_tilt = 0.10
    dozer.ripper_drop = 0.15
    dozer.force_update_transform()
    dozer._apply_pose()
    var forward: Vector3 = -dozer.global_basis.z
    var right: Vector3 = dozer.global_basis.x
    var blade: Vector3 = dozer._blade_point
    var offsets := [
        Vector3(0.0, 0.12, 0.0),
        Vector3(1.05, 0.08, 0.15),
        Vector3(-0.95, 0.10, 0.20),
        Vector3(0.45, 0.22, -0.55),
        Vector3(-0.40, 0.18, -0.70)
    ]
    var shove: Vector3 = forward * 2.2
    var index := 0
    for prop in get_tree().get_nodes_in_group("physics_prop"):
        if index >= offsets.size():
            break
        if not is_instance_valid(prop):
            continue
        if float(prop.get("mass")) > 200.0:
            continue
        var lateral: Vector3 = right * offsets[index].x + Vector3.UP * offsets[index].y + forward * (0.95 + offsets[index].z)
        prop.global_position = blade + lateral
        prop.linear_velocity = shove
        prop.angular_velocity = Vector3(0.4, 0.8, 0.2)
        prop.sleeping = false
        index += 1
    if game.hud.has_method("set_machine_profile"):
        game.hud.set_machine_profile(dozer.get_control_profile())
    else:
        game.hud.set_machine_mode(true)
    game.hud.set_health(0.90)
    game.hud.set_target(null)
    game.hud.set_objective(
        "SHOVE THE YARD",
        "9.8 TONNES ON TRACKS // THE BLADE IS A WALL"
    )
    game.hud.set_objective_progress(0.42)
    game.hud.set_machine_telemetry(0.92, 0.86, 0.94, 0.82, false)
    game.hud.set_context("BLADE CONTACT // MASS IS THE TOOL")
    _camera(
        blade + Vector3(5.6, 3.4, 4.8),
        blade + Vector3(-0.2, 0.35, 0.2),
        46.0
    )


func _set_machine_hud() -> void:
    if game.hud.has_method("set_machine_profile") and game.excavator.has_method("get_control_profile"):
        game.hud.set_machine_profile(game.excavator.get_control_profile())
    else:
        game.hud.set_machine_mode(true)

func _clear_machine_hud() -> void:
    if game.hud.has_method("clear_machine_profile"):
        game.hud.clear_machine_profile()
    else:
        game.hud.set_machine_mode(false)

func _camera(position: Vector3, target: Vector3, fov: float) -> void:
    game.camera_rig.set_capture_pose(position, target, fov)

func _release_capture_load() -> void:
    var load = game.excavator.held_load
    if load == null or not is_instance_valid(load):
        return
    game.excavator.drop_load()
    load.linear_velocity = Vector3.ZERO
    load.angular_velocity = Vector3.ZERO

func _first_prop():
    for prop in get_tree().get_nodes_in_group("physics_prop"):
        if is_instance_valid(prop) and prop.mass <= 110.0:
            return prop
    return null

func _heaviest_prop():
    var best = null
    var best_mass := 0.0
    for prop in get_tree().get_nodes_in_group("physics_prop"):
        if not is_instance_valid(prop):
            continue
        var prop_mass := float(prop.get("mass"))
        if prop_mass > best_mass:
            best_mass = prop_mass
            best = prop
    return best

func _show_all_enemies(value: bool) -> void:
    for enemy in get_tree().get_nodes_in_group("enemy"):
        var occupied := false
        if game.excavator != null and enemy == game.excavator.enemy_driver:
            occupied = true
        if game.dozer != null and enemy == game.dozer.enemy_driver:
            occupied = true
        if game.crane != null and enemy == game.crane.enemy_driver:
            occupied = true
        enemy.visible = value and not occupied

func _visible_enemies() -> Array[Node]:
    var result: Array[Node] = []
    for enemy in get_tree().get_nodes_in_group("enemy"):
        if enemy.visible:
            result.append(enemy)
    return result

func _settle_frames(count: int) -> void:
    for _i in count:
        await get_tree().process_frame

func _settle_physics_frames(count: int) -> void:
    for _i in count:
        await get_tree().physics_frame

func _capture(filename: String) -> void:
    var image := get_viewport().get_texture().get_image()
    var path := capture_dir.path_join(filename)
    var err := image.save_png(path)
    if err != OK:
        push_error("CAPTURE_FAILED %s err=%s" % [path, err])
        get_tree().quit(2)
        return
    print("CAPTURE_OK ", path, " ", image.get_width(), "x", image.get_height())
