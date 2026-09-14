class_name FoundryMachine
extends CharacterBody3D

const FoundryMaterial = preload("res://scripts/foundry_material.gd")
const EnergyPartition = preload("res://scripts/energy_partition.gd")

## What every heavy machine in the yard shares.
##
## Occupancy, hijacking, damage, and holding a load are not excavator
## behaviour or crane behaviour; they are machine behaviour. A new machine
## brings new verbs and new geometry, and inherits the rest, so that a
## second machine cannot quietly grow a second damage model or a second way
## of holding a load.

## A rigid body below this mass is scrap the working assembly can sweep.
## At or above it, the arm/load has to stop and spend energy.
const HARD_CONTACT_MASS := 85.0

signal player_entered(machine)
signal player_exited(machine)
signal machine_disabled(machine)

var player_driver: Node3D
var enemy_driver: Node3D
var hud
var camera_rig

var chassis_health := 500.0
var max_chassis_health := 500.0
var disabled := false
var held_load

var machine_material := FoundryMaterial.PAINTED_STEEL
var machine_tint := Color(0.68, 0.37, 0.045)
var machine_mass := 2600.0

## How fast reported actuator demand chases the real pose rate, per second.
const DEMAND_RESPONSE := 6.0

var _grip := MachineGrip.new()
var _hijack_candidate: Node3D
var _hijack_timeout := 0.0
var _supply_demand := 0.0
var work_anchor := Vector3.ZERO
var work_heading := 0.0
var _work_sign := 1.0
var _floor_exclude: Array[RID] = []


func _ready() -> void:
    add_to_group("machine")
    collision_layer = 2
    collision_mask = 1 | 4 | 8
    MaterialResponse.register(self, machine_material, machine_tint)
    var supply := process_supply_id()
    if supply != "":
        ProcessPlant.bind_machine(self, supply)
    call_deferred("_lock_work_station")


func _lock_work_station() -> void:
    work_anchor = global_position
    work_heading = rotation.y
    _collect_floor_rids()


func _collect_floor_rids() -> void:
    _floor_exclude.clear()
    if not is_inside_tree():
        return
    for node in get_tree().get_nodes_in_group("yard_substrate"):
        if node is CollisionObject3D:
            _floor_exclude.append((node as CollisionObject3D).get_rid())
    var ground := get_tree().root.find_child("Ground", true, false)
    if ground is CollisionObject3D:
        _floor_exclude.append((ground as CollisionObject3D).get_rid())


func configure(controls, camera) -> void:
    hud = controls
    camera_rig = camera


## Which supply point on the process graph feeds this machine. A machine
## that names nothing runs off its own tank and reads full supply forever,
## which is what keeps an unplumbed machine behaving exactly as before.
func process_supply_id() -> String:
    return ""


## What the branch can push. Pressure is the force limit: an actuator with
## no pressure behind it cannot exert, at any speed.
func supply_pressure_ratio() -> float:
    return clampf(
        float(ProcessPlant.machine_supply_state(self).get("pressure_ratio", 1.0)),
        0.0,
        1.0
    )


## What the branch can move. Flow is the speed limit: a starved actuator
## still holds its load, it just crawls.
func supply_flow_ratio() -> float:
    return clampf(
        float(ProcessPlant.machine_supply_state(self).get("flow_ratio", 1.0)),
        0.0,
        1.0
    )


## Actuators only draw oil while they are actually moving. Reporting the
## real pose rate means a machine working hard loads the loop and a parked
## one stops competing with the vents for flow.
##
## The demand is filtered rather than published raw, because what it feeds
## comes back as the speed limit on the very motion it was measured from: a
## starved arm would otherwise stutter between asking for everything and
## asking for nothing at frame rate. A pump compensator has exactly this
## lag for exactly this reason.
func publish_actuator_demand(pose_rate: float, reference_rate: float) -> void:
    var target := clampf(pose_rate / maxf(reference_rate, 0.001), 0.0, 1.0)
    _supply_demand = lerpf(
        _supply_demand,
        target,
        clampf(DEMAND_RESPONSE * get_physics_process_delta_time(), 0.0, 1.0)
    )
    ProcessPlant.request_machine_supply(self, _supply_demand)


## Locomotion stick. Touch owns the HUD axis; keyboard fills in when
## the stick is idle so a desktop session can still drive. A is left,
## D is right: yaw += -axis.x, forward is -Z.
func control_axis() -> Vector2:
    var axis := Vector2.ZERO
    if hud != null:
        axis = hud.move_axis
    if axis.length_squared() < 0.002:
        if Input.is_physical_key_pressed(KEY_D) or Input.is_physical_key_pressed(KEY_RIGHT):
            axis.x += 1.0
        if Input.is_physical_key_pressed(KEY_A) or Input.is_physical_key_pressed(KEY_LEFT):
            axis.x -= 1.0
        if Input.is_physical_key_pressed(KEY_W) or Input.is_physical_key_pressed(KEY_UP):
            axis.y -= 1.0
        if Input.is_physical_key_pressed(KEY_S) or Input.is_physical_key_pressed(KEY_DOWN):
            axis.y += 1.0
        axis = axis.limit_length(1.0)
    return axis


## Readable name for prompts and machine telemetry.
func machine_name() -> String:
    return "MACHINE"


## How close the player must be to climb straight into the cab.
func machine_entry_reach() -> float:
    return 3.5


func set_enemy_driver(driver: Node3D) -> void:
    enemy_driver = driver
    if driver != null:
        driver.visible = false
        driver.process_mode = Node.PROCESS_MODE_DISABLED


func is_player_driven() -> bool:
    return player_driver != null


func is_hijack_in_progress() -> bool:
    return (
        _hijack_candidate != null
        and is_instance_valid(_hijack_candidate)
        and _hijack_timeout > 0.0
    )


func get_health_ratio() -> float:
    return clampf(chassis_health / maxf(max_chassis_health, 1.0), 0.0, 1.0)


func is_holding_load() -> bool:
    return held_load != null and is_instance_valid(held_load)


func load_mass() -> float:
    if not is_holding_load():
        return 0.0
    return maxf(float(held_load.get("mass")), 0.0)


func struck_mass(body: Node) -> float:
    if body == null:
        return 900.0
    if body is RigidBody3D:
        return maxf((body as RigidBody3D).mass, 1.0)
    var value = body.get("mass")
    if value != null:
        return maxf(float(value), 1.0)
    return 900.0


func is_hard_world_contact(collider: Node) -> bool:
    if collider == null or collider == self:
        return false
    if is_holding_load() and collider == held_load:
        return false
    if collider is RigidBody3D and not (collider as RigidBody3D).freeze:
        return (collider as RigidBody3D).mass >= HARD_CONTACT_MASS
    return true


func request_hijack(player: Node3D) -> bool:
    if disabled or player == null or player_driver != null:
        return false
    var distance: float = global_position.distance_to(player.global_position)
    if distance <= machine_entry_reach():
        return try_enter(player)
    var range_value = player.get("machine_climb_range")
    var climb_range: float = float(range_value) if range_value != null else 5.8
    if distance > climb_range or not player.has_method("begin_machine_climb"):
        return false
    _hijack_candidate = player
    _hijack_timeout = 1.5
    if hud != null:
        hud.set_context("HIJACK // LATCHING ON // MACHINE CONTROL PENDING")
    var started: bool = bool(player.begin_machine_climb(self))
    if not started:
        _hijack_candidate = null
        _hijack_timeout = 0.0
    return started


func try_enter(player: Node3D) -> bool:
    if disabled or player == null or player_driver != null:
        return false
    var latched: bool = (
        _hijack_candidate == player
        or player.get("machine_climb_target") == self
    )
    if (
        not latched
        and global_position.distance_to(player.global_position) > machine_entry_reach()
    ):
        return false

    if enemy_driver != null:
        enemy_driver.visible = true
        enemy_driver.process_mode = Node.PROCESS_MODE_INHERIT
        enemy_driver.global_position = (
            global_position + global_basis.x * 2.2 + Vector3.UP * 0.22
        )
        if enemy_driver.has_method("take_hit"):
            enemy_driver.take_hit(
                global_basis.x * 8.0 + Vector3.UP * 2.5,
                40.0
            )
        enemy_driver = null

    _hijack_candidate = null
    _hijack_timeout = 0.0
    player_driver = player
    velocity.x = 0.0
    velocity.z = 0.0
    player.visible = false
    player.process_mode = Node.PROCESS_MODE_DISABLED
    if hud != null:
        hud.set_machine_mode(true)
        hud.set_context(
            "CONTROL TRANSFERRED // %s ONLINE" % machine_name()
        )
    player_entered.emit(self)
    return true


func exit_player() -> void:
    if player_driver == null:
        return
    _release_load(false)
    var player := player_driver
    player_driver = null
    player.visible = true
    player.process_mode = Node.PROCESS_MODE_INHERIT
    player.global_position = (
        global_position + global_basis.x * 2.8 + Vector3.UP * 0.22
    )
    if hud != null:
        hud.set_machine_mode(false)
        hud.set_context("POWER // COMBAT // MACHINES")
    player_exited.emit(self)


func receive_enemy_hit(damage: float) -> void:
    _apply_machine_damage(damage, Vector3.UP)


func receive_hazard_hit(damage: float, impulse: Vector3) -> void:
    velocity += impulse * 0.22
    _apply_machine_damage(
        damage * 0.72,
        impulse.normalized() if impulse.length_squared() > 0.01 else Vector3.UP
    )


func machine_hit(
        amount: float,
        direction: Vector3,
        _world_point: Vector3 = Vector3.ZERO
) -> void:
    velocity += direction.normalized() * minf(amount * 0.018, 3.8)
    _apply_machine_damage(amount * 0.58, direction)


func _apply_machine_damage(amount: float, direction: Vector3) -> void:
    if disabled:
        return
    chassis_health = maxf(0.0, chassis_health - amount)
    if chassis_health <= 0.0:
        _disable_machine()


func _disable_machine() -> void:
    if disabled:
        return
    disabled = true
    _release_load(true)
    velocity *= 0.2
    machine_disabled.emit(self)


func _tick_hijack(delta: float) -> void:
    _hijack_timeout = maxf(0.0, _hijack_timeout - delta)
    if _hijack_timeout <= 0.0:
        _hijack_candidate = null


func _release_load(_with_throw: bool) -> void:
    _grip.release(Vector3.ZERO, false)
    held_load = null


## The yard floor is a load the working assembly can spend energy on.
func work_ground(
        world_point: Vector3,
        direction: Vector3,
        intensity: float,
        width: float = 1.6
) -> void:
    if not is_inside_tree() or intensity < 0.5:
        return
    var nodes := get_tree().get_nodes_in_group("yard_substrate")
    if nodes.is_empty():
        return
    var ground: Node = nodes[0]
    if ground.has_method("cut_and_pile"):
        ground.cut_and_pile(world_point, direction, intensity, width)


func work_gouge(
        world_point: Vector3,
        direction: Vector3,
        intensity: float
) -> void:
    if not is_inside_tree() or intensity < 0.5:
        return
    var nodes := get_tree().get_nodes_in_group("yard_substrate")
    if nodes.is_empty():
        return
    var ground: Node = nodes[0]
    if ground.has_method("gouge"):
        ground.gouge(world_point, direction, intensity)

