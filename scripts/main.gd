extends Node3D

const PlayerScene = preload("res://scripts/player.gd")
const EnemyScene = preload("res://scripts/enemy.gd")
const ExcavatorScene = preload("res://scripts/excavator.gd")
const StructureScene = preload("res://scripts/structure.gd")
const CameraRigScene = preload("res://scripts/camera_rig.gd")
const HudScene = preload("res://scripts/mobile_hud.gd")
const YardScene = preload("res://scripts/industrial_yard.gd")
const HazardFieldScene = preload("res://scripts/hazard_field.gd")
const CaptureRunnerScene = preload("res://scripts/visual_capture.gd")

var hud
var camera_rig
var player
var excavator
var structure
var yard
var hazards

func _ready() -> void:
    _build_environment()
    _build_yard()
    _build_gameplay()
    if OS.get_environment("KF_CAPTURE") == "1":
        print("CAPTURE_STAGE activation")
        var capture_runner := CaptureRunnerScene.new()
        add_child(capture_runner)
        capture_runner.begin(self)

func _build_environment() -> void:
    var world := WorldEnvironment.new()
    var env := Environment.new()
    env.background_mode = Environment.BG_COLOR
    env.background_color = Color(0.028, 0.036, 0.040)
    env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
    env.ambient_light_color = Color(0.30, 0.33, 0.34)
    env.ambient_light_energy = 0.58
    env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
    env.fog_enabled = true
    env.fog_light_color = Color(0.12, 0.14, 0.145)
    env.fog_density = 0.010
    world.environment = env
    add_child(world)

    var sun := DirectionalLight3D.new()
    sun.rotation_degrees = Vector3(-52.0, -38.0, 0.0)
    sun.light_color = Color(0.91, 0.84, 0.70)
    sun.light_energy = 1.72
    sun.shadow_enabled = true
    add_child(sun)

func _build_yard() -> void:
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

    excavator = ExcavatorScene.new()
    excavator.position = Vector3(4.0, -0.17, -3.0)
    excavator.rotation.y = 0.42
    add_child(excavator)
    excavator.configure(hud, camera_rig)
    excavator.player_entered.connect(_on_machine_entered)
    excavator.player_exited.connect(_on_machine_exited)

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

func _spawn_enemy(pos: Vector3):
    var enemy = EnemyScene.new()
    enemy.position = pos
    add_child(enemy)
    enemy.set_target(player)
    return enemy

func _on_player_use(user) -> void:
    excavator.try_enter(user)

func _on_machine_entered(machine) -> void:
    camera_rig.set_target(machine)
    camera_rig.distance = 13.4
    camera_rig.height = 5.0

func _on_machine_exited(_machine) -> void:
    camera_rig.set_target(player)
    camera_rig.distance = 9.8
    camera_rig.height = 3.2
