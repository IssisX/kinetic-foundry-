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
    call_deferred("_run")

func _run() -> void:
    await _settle_frames(6)
    _freeze_gameplay()

    _stage_yard_overview()
    await _settle_frames(8)
    _capture("01_yard_overview.png")

    _stage_combat()
    await _settle_frames(8)
    _capture("02_grounded_combat.png")

    _stage_excavator_load()
    await _settle_frames(8)
    _capture("03_excavator_load_control.png")

    _stage_structure_damage()
    await _settle_frames(8)
    _capture("04_progressive_structure_damage.png")

    _stage_structure_collapse()
    await _settle_physics_frames(58)
    await _settle_frames(8)
    _capture("05_collapse_aftermath.png")

    _stage_breach_gate()
    await _settle_physics_frames(24)
    await _settle_frames(8)
    _capture("06_breached_route.png")

    print("CAPTURE_SUITE_OK dir=", capture_dir)
    get_tree().quit(0)

func _freeze_gameplay() -> void:
    if game.player != null:
        game.player.process_mode = Node.PROCESS_MODE_DISABLED
    if game.excavator != null:
        game.excavator.process_mode = Node.PROCESS_MODE_DISABLED
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
    game.mission.stage = 0
    game.hud.set_machine_mode(false)
    game.hud.set_health(0.92)
    game.hud.set_target(null)
    game.hud.set_objective("BREAK THE YARD CREW", "CUT THROUGH THE WORK YARD AND EXPOSE THE MACHINE")
    game.hud.set_objective_progress(0.20)
    game.hud.set_context("POWER // COMBAT // MACHINES")
    _camera(
        Vector3(23.0, 18.0, 23.0),
        Vector3(0.0, 1.8, -4.0),
        58.0
    )

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
    var positions := [
        Vector3(-2.1, 0.03, 8.4),
        Vector3(2.2, 0.03, 8.2),
        Vector3(-3.5, 0.03, 11.3),
        Vector3(3.7, 0.03, 11.7)
    ]
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
    game.hud.set_machine_mode(false)
    game.hud.set_health(0.76)
    game.hud.set_target(game.player.engaged_target)
    game.hud.set_objective("BREAK THE YARD CREW", "TACKLE // COMBO // KICK // GRAB // THROW")
    game.hud.set_objective_progress(0.45)
    game.hud.set_context("SIDE KICK // HEAVY FINISHER")
    _camera(
        Vector3(8.4, 6.2, 18.0),
        Vector3(0.0, 1.15, 9.8),
        55.0
    )

func _stage_excavator_load() -> void:
    game.player.visible = false
    _show_all_enemies(false)
    game.excavator.enemy_driver = null
    game.excavator.player_driver = game.player
    game.excavator.global_position = Vector3(0.0, -0.17, 2.5)
    game.excavator.rotation.y = 0.12
    game.excavator.arm_yaw = -0.18
    game.excavator.boom_angle = -0.50
    game.excavator.stick_angle = 0.68
    game.excavator.tool_angle = -0.48
    game.excavator._apply_arm_pose()

    var load = _first_prop()
    if load != null:
        game.excavator.held_load = load
        load.set_held(true)
        game.excavator._apply_arm_pose()
        game.excavator._update_held_load()

    game.mission.stage = 2
    game.hud.set_machine_mode(true)
    game.hud.set_target(null)
    game.hud.set_objective("DROP THE TRANSFER PLATFORM", "LOAD CONTROL + REAL BUCKET FORCE")
    game.hud.set_objective_progress(0.18)
    game.hud.set_machine_telemetry(0.88, 0.82, 0.91, 0.72, load != null)
    game.hud.set_context("LOAD CLAMPED // HYDRAULIC THUMB // DIRECT ARM")
    _camera(
        Vector3(11.5, 7.8, 12.5),
        Vector3(0.0, 2.0, 0.2),
        52.0
    )

func _stage_structure_damage() -> void:
    _release_capture_load()
    game.structure.damage_support(0, 68.0, Vector3(1.0, 0.0, 0.22))
    game.structure.damage_support(2, 34.0, Vector3(0.72, 0.0, -0.34))
    game.mission.stage = 2
    game.hud.set_machine_mode(true)
    game.hud.set_objective("DROP THE TRANSFER PLATFORM", "LOAD PATH COMPROMISED // KEEP WORKING THE WEAK SIDE")
    game.hud.set_objective_progress(0.52)
    game.hud.set_machine_telemetry(0.84, 0.76, 0.90, 0.88, false)
    game.hud.set_context("STRUCTURE RACKING // SUPPORT 01 CRITICAL")
    _camera(
        Vector3(22.0, 10.5, -3.0),
        game.structure.global_position + Vector3(0.0, 2.5, 0.0),
        50.0
    )

func _stage_structure_collapse() -> void:
    game.structure.damage_support(0, 55.0, Vector3(1.0, 0.0, 0.25))
    game.structure.damage_support(2, 90.0, Vector3(1.0, 0.0, -0.20))
    game.mission.stage = 3
    game.hud.set_machine_mode(false)
    game.hud.set_target(null)
    game.hud.set_objective("OWN THE WRECKAGE", "COLLAPSE BECOMES TERRAIN // HOLD THE SPACE")
    game.hud.set_objective_progress(0.63)
    game.hud.set_context("PERSISTENT DEBRIS // NEW COVER // NEW ROUTE")
    _camera(
        Vector3(22.0, 8.0, -4.5),
        game.structure.global_position + Vector3(0.0, 1.5, 0.0),
        54.0
    )

func _stage_breach_gate() -> void:
    var gates := get_tree().get_nodes_in_group("breachable")
    if gates.is_empty():
        push_error("CAPTURE_BREACH_GATE_MISSING")
        return
    var gate = gates[0]
    gate.damage_panel(0, 145.0, Vector3(0.15, 0.05, 1.0))
    game.mission.stage = 4
    game.hud.set_machine_mode(true)
    game.hud.set_objective("BREACH THE NORTH ACCESS", "ROUTE CONTROL IS PHYSICAL // THE DOOR BECOMES DEBRIS")
    game.hud.set_objective_progress(1.0)
    game.hud.set_machine_telemetry(0.79, 0.72, 0.86, 0.94, false)
    game.hud.set_context("ACCESS OPEN // DEBRIS REMAINS IN WORLD")
    _camera(
        gate.global_position + Vector3(11.0, 7.0, -12.0),
        gate.global_position + Vector3(0.0, 1.6, 0.0),
        52.0
    )

func _camera(position: Vector3, target: Vector3, fov: float) -> void:
    game.camera_rig.set_capture_pose(position, target, fov)

func _release_capture_load() -> void:
    if game.excavator.held_load == null or not is_instance_valid(game.excavator.held_load):
        return
    var load = game.excavator.held_load
    game.excavator.held_load = null
    load.set_held(false)
    load.linear_velocity = Vector3.ZERO
    load.angular_velocity = Vector3.ZERO

func _first_prop():
    for prop in get_tree().get_nodes_in_group("physics_prop"):
        if is_instance_valid(prop) and prop.mass <= 110.0:
            return prop
    return null

func _show_all_enemies(value: bool) -> void:
    for enemy in get_tree().get_nodes_in_group("enemy"):
        enemy.visible = value and enemy != game.excavator.enemy_driver

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
