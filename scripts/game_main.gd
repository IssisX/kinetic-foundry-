extends Node3D

const PlayerScene = preload("res://scripts/player.gd")
const EnemyScene = preload("res://scripts/enemy.gd")
const ExcavatorScene = preload("res://scripts/excavator_contact.gd")
const StructureScene = preload("res://scripts/structure.gd")
const CameraRigScene = preload("res://scripts/camera_rig.gd")
const HudScene = preload("res://scripts/mobile_hud.gd")
const YardScene = preload("res://scripts/industrial_yard.gd")
const HazardFieldScene = preload("res://scripts/hazard_field.gd")
const MissionDirectorScene = preload("res://scripts/mission_director.gd")
const CaptureRunnerScene = preload("res://scripts/visual_capture.gd")

var hud
var camera_rig
var player
var excavator
var structure
var yard
var hazards
var mission

var _reclaim_timer := 0.0
var _reclaim_cooldown := 2.5

func _ready() -> void:
    _build_environment()
    _build_world()
    _build_gameplay()
    _build_mission()
    if OS.get_environment("KF_CAPTURE") == "1":
        print("CAPTURE_STAGE activation")
        var capture_runner := CaptureRunnerScene.new()
        add_child(capture_runner)
        capture_runner.begin(self)

func _process(delta: float) -> void:
    if OS.get_environment("KF_CAPTURE") == "1":
        return
    _update_interaction_prompt()
    _reclaim_timer = maxf(0.0, _reclaim_timer - delta)
    if _reclaim_timer <= 0.0:
        _try_enemy_reclaim()
        _reclaim_timer = 0.45

func _build_environment() -> void:
    var world := WorldEnvironment.new()
    var env := Environment.new()

    var sky_mat := ProceduralSkyMaterial.new()
    sky_mat.sky_top_color = Color(0.035, 0.055, 0.075)
    sky_mat.sky_horizon_color = Color(0.22, 0.20, 0.17)
    sky_mat.ground_bottom_color = Color(0.018, 0.022, 0.024)
    sky_mat.ground_horizon_color = Color(0.11, 0.10, 0.085)
    sky_mat.sun_angle_max = 18.0
    sky_mat.sun_curve = 0.08
    var sky := Sky.new()
    sky.sky_material = sky_mat

    env.background_mode = Environment.BG_SKY
    env.sky = sky
    env.background_energy_multiplier = 0.72
    env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
    env.ambient_light_color = Color(0.40, 0.43, 0.44)
    env.ambient_light_energy = 0.78
    env.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
    env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
    env.fog_enabled = true
    env.fog_light_color = Color(0.19, 0.19, 0.175)
    env.fog_light_energy = 0.72
    env.fog_density = 0.0055
    env.fog_height = 0.0
    env.fog_height_density = 0.045
    world.environment = env
    add_child(world)

    var sun := DirectionalLight3D.new()
    sun.rotation_degrees = Vector3(-49.0, -42.0, 0.0)
    sun.light_color = Color(1.0, 0.82, 0.64)
    sun.light_energy = 2.15
    sun.shadow_enabled = true
    sun.directional_shadow_max_distance = 70.0
    add_child(sun)

    var fill := DirectionalLight3D.new()
    fill.rotation_degrees = Vector3(-28.0, 138.0, 0.0)
    fill.light_color = Color(0.34, 0.48, 0.62)
    fill.light_energy = 0.42
    fill.shadow_enabled = false
    add_child(fill)

func _build_world() -> void:
    yard = YardScene.new()
    add_child(yard)
    hazards = HazardFieldScene.new()
    add_child(hazards)

func _build_gameplay() -> void:
    hud = HudScene.new()
    add_child(hud)
    camera_rig = CameraRigScene.new()
    add_child(camera_rig)

    player = PlayerScene.new()
    player.position = Vector3(-10.0, 0.03, 13.0)
    add_child(player)
    player.configure(hud, camera_rig)
    player.request_machine_entry.connect(_on_player_use)
    camera_rig.set_target(player)
    camera_rig.distance = 8.5
    camera_rig.height = 2.8

    excavator = ExcavatorScene.new()
    excavator.position = Vector3(4.0, -0.17, -3.0)
    excavator.rotation.y = 0.42
    add_child(excavator)
    excavator.configure(hud, camera_rig)
    excavator.player_entered.connect(_on_machine_entered)
    excavator.player_exited.connect(_on_machine_exited)
    excavator.machine_disabled.connect(_on_machine_disabled)

    var operator = _spawn_enemy(Vector3(4.0, 0.03, -3.0))
    excavator.set_enemy_driver(operator)
    _spawn_enemy(Vector3(-3.0, 0.03, 5.0))
    _spawn_enemy(Vector3(1.0, 0.03, 10.0))
    _spawn_enemy(Vector3(8.0, 0.03, 7.0))
    _spawn_enemy(Vector3(-11.5, 0.03, -1.0))
    _spawn_enemy(Vector3(14.0, 0.03, 11.5))

    structure = StructureScene.new()
    structure.position = Vector3(11.0, 0.0, -14.0)
    add_child(structure)

func _build_mission() -> void:
    mission = MissionDirectorScene.new()
    add_child(mission)
    mission.configure(player, excavator, structure, hud)

func _spawn_enemy(pos: Vector3):
    var enemy = EnemyScene.new()
    enemy.position = pos
    add_child(enemy)
    enemy.set_target(player)
    return enemy

func _retarget_enemies(target_node) -> void:
    for enemy in get_tree().get_nodes_in_group("enemy"):
        if is_instance_valid(enemy) and not enemy.dead:
            enemy.set_target(target_node)

func _on_player_use(user) -> void:
    if excavator.request_hijack(user):
        return
    if hud != null and hud.has_method("set_interaction_hint"):
        hud.set_interaction_hint("MOVE CLOSER // USE WHEN THE EXCAVATOR IS WITHIN REACH")

func _on_machine_entered(machine) -> void:
    camera_rig.set_target(machine)
    camera_rig.distance = 12.2
    camera_rig.height = 4.4
    _retarget_enemies(machine)
    _reclaim_cooldown = 4.0
    if hud != null and hud.has_method("set_interaction_hint"):
        hud.set_interaction_hint("LEFT: DRIVE + STEER    RIGHT: SWING + BOOM    CURL / CLAMP / EXIT")

func _on_machine_exited(_machine) -> void:
    camera_rig.set_target(player)
    camera_rig.distance = 8.5
    camera_rig.height = 2.8
    _retarget_enemies(player)
    _reclaim_cooldown = 2.8
    if hud != null and hud.has_method("set_interaction_hint"):
        hud.set_interaction_hint("")

func _on_machine_disabled(machine) -> void:
    if machine.player_driver != null:
        machine.exit_player()
    hud.set_context("EXCAVATOR DISABLED // RETURN TO FOOT CONTROL")
    _retarget_enemies(player)

func _update_interaction_prompt() -> void:
    if hud == null or not hud.has_method("set_interaction_hint") or player == null or excavator == null:
        return
    if excavator.player_driver != null:
        hud.set_interaction_hint("LEFT: DRIVE + STEER    RIGHT: SWING + BOOM    CURL / CLAMP / EXIT")
        return
    if not player.visible or player.health <= 0.0:
        hud.set_interaction_hint("")
        return
    if excavator.disabled:
        var disabled_dist: float = player.global_position.distance_to(excavator.global_position)
        hud.set_interaction_hint("EXCAVATOR DISABLED // WRECKAGE REMAINS PHYSICAL") if disabled_dist < 6.5 else hud.set_interaction_hint("")
        return

    var distance: float = player.global_position.distance_to(excavator.global_position)
    var climb_range: float = float(player.get("machine_climb_range")) if player.get("machine_climb_range") != null else 5.8
    if distance <= 3.5:
        hud.set_interaction_hint("USE  //  HIJACK EXCAVATOR")
    elif distance <= climb_range:
        hud.set_interaction_hint("USE  //  LATCH + CLIMB EXCAVATOR")
    elif mission != null and int(mission.get("stage")) == 1:
        hud.set_interaction_hint("FOLLOW THE ORANGE MARKER // CLOSE ON THE EXCAVATOR")
    else:
        hud.set_interaction_hint("")

func _try_enemy_reclaim() -> void:
    if excavator == null or excavator.disabled:
        return
    if excavator.player_driver != null or excavator.enemy_driver != null or excavator.is_hijack_in_progress():
        return
    _reclaim_cooldown = maxf(0.0, _reclaim_cooldown - 0.45)
    if _reclaim_cooldown > 0.0:
        return
    var best = null
    var best_distance := 9999.0
    for enemy in get_tree().get_nodes_in_group("enemy"):
        if not is_instance_valid(enemy) or enemy.dead or not enemy.visible:
            continue
        var d: float = enemy.global_position.distance_to(excavator.global_position)
        if d < best_distance:
            best_distance = d
            best = enemy
    if best == null:
        return
    if best_distance <= 2.8:
        excavator.set_enemy_driver(best)
        _retarget_enemies(player)
        hud.set_context("HOSTILE CREW RECLAIMED THE EXCAVATOR")
        _reclaim_cooldown = 6.0
    elif best.has_method("set_target") and best_distance < 15.0:
        best.set_target(excavator)
