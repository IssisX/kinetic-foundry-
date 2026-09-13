extends Node3D

const PlayerScene = preload("res://scripts/player.gd")
const EnemyScene = preload("res://scripts/enemy.gd")
const ExcavatorScene = preload("res://scripts/excavator_contact.gd")
const CraneScene = preload("res://scripts/crane.gd")
const StructureScene = preload("res://scripts/structure_material.gd")
const CameraRigScene = preload("res://scripts/camera_rig.gd")
const HudScene = preload("res://scripts/machine_hud.gd")
const YardScene = preload("res://scripts/industrial_yard.gd")
const FacilityExpansionScene = preload("res://scripts/facility_expansion.gd")
const HazardFieldScene = preload("res://scripts/hazard_field.gd")
const MissionDirectorScene = preload("res://scripts/mission_director.gd")
const CaptureRunnerScene = preload("res://scripts/visual_capture.gd")
const CraneCheckScene = preload("res://scripts/crane_check.gd")
const EnemyCheckScene = preload("res://scripts/enemy_check.gd")
const LoadPathCouplerScene = preload(
    "res://scripts/load_path_coupler.gd"
)

var hud
var camera_rig
var player
var excavator
var crane
var structure
var yard
var facility_expansion
var hazards
var mission
var load_path_coupler

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
    elif OS.get_environment("KF_CRANE_CHECK") == "1":
        var crane_check := CraneCheckScene.new()
        add_child(crane_check)
        crane_check.begin(self)
    elif OS.get_environment("KF_ENEMY_CHECK") == "1":
        var enemy_check := EnemyCheckScene.new()
        add_child(enemy_check)
        enemy_check.begin(self)

func _process(delta: float) -> void:
    if OS.get_environment("KF_CAPTURE") == "1":
        return
    _update_interaction_prompt()
    _update_fidelity_telemetry()
    _reclaim_timer = maxf(0.0, _reclaim_timer - delta)
    if _reclaim_timer <= 0.0:
        _try_enemy_reclaim()
        _reclaim_timer = 0.45

func _build_environment() -> void:
    var world := WorldEnvironment.new()
    var env := Environment.new()

    var sky_mat := ProceduralSkyMaterial.new()
    sky_mat.sky_top_color = Color(0.16, 0.48, 0.86)
    sky_mat.sky_horizon_color = Color(0.66, 0.81, 0.96)
    sky_mat.ground_bottom_color = Color(0.15, 0.17, 0.17)
    sky_mat.ground_horizon_color = Color(0.46, 0.54, 0.58)
    sky_mat.sun_angle_max = 12.0
    sky_mat.sun_curve = 0.06
    var sky := Sky.new()
    sky.sky_material = sky_mat

    env.background_mode = Environment.BG_SKY
    env.sky = sky
    env.background_energy_multiplier = 1.08
    env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
    env.ambient_light_color = Color(0.72, 0.80, 0.88)
    env.ambient_light_energy = 0.88
    env.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
    env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
    env.fog_enabled = true
    env.fog_light_color = Color(0.72, 0.80, 0.86)
    env.fog_light_energy = 0.50
    env.fog_density = 0.0015
    env.fog_height = 0.0
    env.fog_height_density = 0.018
    world.environment = env
    add_child(world)

    var sun := DirectionalLight3D.new()
    sun.rotation_degrees = Vector3(-54.0, -34.0, 0.0)
    sun.light_color = Color(1.0, 0.94, 0.82)
    sun.light_energy = 2.55
    sun.shadow_enabled = true
    sun.directional_shadow_max_distance = 125.0
    add_child(sun)

    var sky_fill := DirectionalLight3D.new()
    sky_fill.rotation_degrees = Vector3(-32.0, 146.0, 0.0)
    sky_fill.light_color = Color(0.54, 0.72, 0.96)
    sky_fill.light_energy = 0.58
    sky_fill.shadow_enabled = false
    add_child(sky_fill)

func _build_world() -> void:
    yard = YardScene.new()
    add_child(yard)

    facility_expansion = FacilityExpansionScene.new()
    add_child(facility_expansion)
    facility_expansion.configure(yard)

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
    camera_rig.set_on_foot_profile(8.60, 1.72, 74.0)

    excavator = ExcavatorScene.new()
    excavator.position = Vector3(4.0, -0.17, -3.0)
    excavator.rotation.y = 0.42
    add_child(excavator)
    excavator.configure(hud, camera_rig)
    excavator.player_entered.connect(_on_machine_entered)
    excavator.player_exited.connect(_on_machine_exited)
    excavator.machine_disabled.connect(_on_machine_disabled)

    crane = CraneScene.new()
    crane.position = Vector3(-6.5, -0.10, -12.0)
    crane.rotation.y = -0.85
    add_child(crane)
    crane.configure(hud, camera_rig)
    crane.player_entered.connect(_on_machine_entered)
    crane.player_exited.connect(_on_machine_exited)
    crane.machine_disabled.connect(_on_machine_disabled)

    var operator = _spawn_enemy(Vector3(4.0, 0.03, -3.0), EnemyScene.RIGGER)
    excavator.set_enemy_driver(operator)
    _spawn_enemy(Vector3(-3.0, 0.03, 5.0), EnemyScene.GRUNT)
    _spawn_enemy(Vector3(1.0, 0.03, 10.0), EnemyScene.PLATE)
    _spawn_enemy(Vector3(8.0, 0.03, 7.0), EnemyScene.THROWER)
    _spawn_enemy(Vector3(-11.5, 0.03, -1.0), EnemyScene.HEAVY)
    _spawn_enemy(Vector3(14.0, 0.03, 11.5), EnemyScene.RUNNER)
    _spawn_enemy(Vector3(-4.0, 0.03, -9.5), EnemyScene.RIGGER)

    structure = StructureScene.new()
    structure.position = Vector3(11.0, 0.0, -14.0)
    add_child(structure)
    structure.structure_collapsed.connect(_on_structure_collapsed_camera)

    load_path_coupler = LoadPathCouplerScene.new()
    add_child(load_path_coupler)
    load_path_coupler.configure(structure, excavator)

func _build_mission() -> void:
    mission = MissionDirectorScene.new()
    add_child(mission)
    mission.configure(player, excavator, structure, hud)

func _spawn_enemy(pos: Vector3, archetype: int = EnemyScene.GRUNT):
    var enemy = EnemyScene.new()
    enemy.archetype = archetype
    enemy.position = pos
    add_child(enemy)
    enemy.set_target(player)
    return enemy

func _retarget_enemies(target_node) -> void:
    for enemy in get_tree().get_nodes_in_group("enemy"):
        if is_instance_valid(enemy) and not enemy.dead:
            enemy.set_target(target_node)

func _on_player_use(user) -> void:
    var machine = _nearest_machine(user.global_position)
    if machine != null and machine.request_hijack(user):
        return
    if hud != null and hud.has_method("set_interaction_hint"):
        hud.set_interaction_hint("MOVE CLOSER // USE WHEN A MACHINE IS WITHIN REACH")


## Machines are interchangeable to everything outside them: whichever one
## the player is standing next to is the one they take.
func _nearest_machine(from: Vector3, max_distance: float = 12.0):
    var best = null
    var best_distance := max_distance
    for machine in get_tree().get_nodes_in_group("machine"):
        if not is_instance_valid(machine) or machine.disabled:
            continue
        if machine.player_driver != null:
            continue
        var distance: float = machine.global_position.distance_to(from)
        if distance < best_distance:
            best_distance = distance
            best = machine
    return best

func _on_machine_entered(machine) -> void:
    camera_rig.enter_machine_view(machine)
    _retarget_enemies(machine)
    _reclaim_cooldown = 4.0
    if hud != null:
        if machine.has_method("get_control_profile") and hud.has_method("set_machine_profile"):
            hud.set_machine_profile(machine.get_control_profile())
        elif hud.has_method("set_machine_mode"):
            hud.set_machine_mode(true)
        if hud.has_method("set_interaction_hint"):
            hud.set_interaction_hint("DRIVE / STEER    |    WORKING ASSEMBLY DIRECT CONTROL    |    EXIT TO DISMOUNT")

func _on_machine_exited(_machine) -> void:
    camera_rig.exit_machine_view(player)
    camera_rig.set_on_foot_profile(8.60, 1.72, 74.0)
    _retarget_enemies(player)
    _reclaim_cooldown = 2.8
    if hud != null:
        if hud.has_method("clear_machine_profile"):
            hud.clear_machine_profile()
        elif hud.has_method("set_machine_mode"):
            hud.set_machine_mode(false)
        if hud.has_method("set_interaction_hint"):
            hud.set_interaction_hint("")

func _on_machine_disabled(machine) -> void:
    if machine.player_driver != null:
        machine.exit_player()
    hud.set_context(
        "%s DISABLED // RETURN TO FOOT CONTROL" % machine.machine_name()
    )
    _retarget_enemies(player)

func _on_structure_collapsed_camera() -> void:
    # Structural collapse now publishes one authoritative physical event;
    # camera and audio both consume that event instead of receiving bespoke calls.
    pass

func _update_fidelity_telemetry() -> void:
    if hud == null or not hud.has_method("set_fidelity_telemetry"):
        return
    if structure == null or structure.deck_network == null:
        return
    var network = structure.deck_network
    hud.set_fidelity_telemetry(
        network.get_node_count(),
        network.get_bond_count(),
        int(network.get_energy_state().get("components", 1)),
        Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0
    )


func _update_interaction_prompt() -> void:
    if hud == null or not hud.has_method("set_interaction_hint") or player == null:
        return
    for machine in get_tree().get_nodes_in_group("machine"):
        if is_instance_valid(machine) and machine.player_driver != null:
            return
    if not player.visible or player.health <= 0.0:
        hud.set_interaction_hint("")
        return

    var target = _nearest_machine(player.global_position)
    if target == null:
        if excavator != null and excavator.disabled:
            var wreck_distance: float = player.global_position.distance_to(
                excavator.global_position
            )
            if wreck_distance < 6.5:
                hud.set_interaction_hint(
                    "EXCAVATOR DISABLED // WRECKAGE REMAINS PHYSICAL"
                )
                return
        hud.set_interaction_hint("")
        return

    var distance: float = player.global_position.distance_to(
        target.global_position
    )
    var climb_range: float = float(player.get("machine_climb_range")) if player.get("machine_climb_range") != null else 5.8
    if distance <= target.machine_entry_reach():
        hud.set_interaction_hint(
            "USE  //  HIJACK %s // ENTER OPERATOR POV" % target.machine_name()
        )
    elif distance <= climb_range:
        hud.set_interaction_hint("USE  //  LATCH + CLIMB TO CAB")
    elif mission != null and int(mission.get("stage")) == 1:
        hud.set_interaction_hint("FOLLOW THE ORANGE MARKER // CLOSE ON THE EXCAVATOR")
    else:
        hud.set_interaction_hint("")

## Any machine the player is not sitting in is a machine the yard crew can
## walk over and take back.
func _try_enemy_reclaim() -> void:
    _reclaim_cooldown = maxf(0.0, _reclaim_cooldown - 0.45)
    if _reclaim_cooldown > 0.0:
        return
    for machine in get_tree().get_nodes_in_group("machine"):
        if not is_instance_valid(machine) or machine.disabled:
            continue
        if (
            machine.player_driver != null
            or machine.enemy_driver != null
            or machine.is_hijack_in_progress()
        ):
            continue
        if _reclaim_machine(machine):
            return


func _reclaim_machine(machine) -> bool:
    var best = null
    var best_distance := 9999.0
    for enemy in get_tree().get_nodes_in_group("enemy"):
        if not is_instance_valid(enemy) or enemy.dead or not enemy.visible:
            continue
        var d: float = enemy.global_position.distance_to(machine.global_position)
        if d < best_distance:
            best_distance = d
            best = enemy
    if best == null:
        return false
    if best_distance <= 2.8:
        machine.set_enemy_driver(best)
        _retarget_enemies(player)
        hud.set_context(
            "HOSTILE CREW RECLAIMED THE %s" % machine.machine_name()
        )
        _reclaim_cooldown = 6.0
        return true
    if best.has_method("set_target") and best_distance < 15.0:
        best.set_target(machine)
    return false
