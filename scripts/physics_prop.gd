class_name PhysicsProp
extends RigidBody3D

const GeomUtil = preload("res://scripts/geom.gd")
const ImpactFx = preload("res://scripts/impact_fx.gd")
const FoundryMaterial = preload("res://scripts/foundry_material.gd")
const EnergyPartition = preload("res://scripts/energy_partition.gd")

const LIVE_SPEED := 1.35
const CONTACT_SPEED := 2.15
const WAKE_SPEED := 0.55

var health := 80.0
var destroyed := false
var impact_scale := 1.0
var held := false
var impact_color := Color(0.72, 0.45, 0.12)
var source_color := Color(0.25, 0.25, 0.22)
var source_size := Vector3.ONE
var barrel_shape := false
var machine_held := false
var _saved_linear_damp := 0.0
var _saved_angular_damp := 0.0
var _flight_time := 0.0
var _flight_source: Node
var _contact_cooldown := 0.0
var _last_contact_id := 0

func _ready() -> void:
    add_to_group("physics_prop")
    add_to_group("physical_event_listener")
    collision_layer = 8
    collision_mask = 1 | 2 | 4 | 8
    sleeping = true
    can_sleep = true
    set_physics_process(true)


## A thrown crate is a weapon. Anyone who can pick this up can launch it,
## and what it hits is decided by the mass and speed it arrives with, not
## by who threw it.
func launch(throw_velocity: Vector3, source: Node = null) -> void:
    set_held(false)
    sleeping = false
    linear_velocity = throw_velocity
    angular_velocity = Vector3(
        throw_velocity.z,
        0.9,
        -throw_velocity.x
    ) * 0.22
    _flight_source = source
    _flight_time = 2.4
    _arm_contact_sense()
    set_physics_process(true)


func _physics_process(delta: float) -> void:
    _contact_cooldown = maxf(0.0, _contact_cooldown - delta)
    if _flight_time > 0.0:
        _flight_time -= delta
        if _flight_time <= 0.0:
            _end_flight()

    if destroyed or (held and not machine_held):
        return
    if sleeping and not machine_held and _flight_time <= 0.0:
        return

    var speed := linear_velocity.length()
    if speed >= LIVE_SPEED or machine_held:
        sleeping = false
        can_sleep = false
        continuous_cd = true
        _arm_contact_sense()
    elif speed < WAKE_SPEED and not machine_held:
        continuous_cd = false
        can_sleep = true


func _arm_contact_sense() -> void:
    contact_monitor = true
    max_contacts_reported = 8
    continuous_cd = true
    if not body_entered.is_connected(_on_live_contact):
        body_entered.connect(_on_live_contact)


func _on_live_contact(body: Node) -> void:
    if destroyed or body == null or body == self or body == _flight_source:
        return
    if not is_inside_tree():
        return
    if held and not machine_held:
        return
    if machine_held and body.is_in_group("machine"):
        return
    if _contact_cooldown > 0.0 and body.get_instance_id() == _last_contact_id:
        return

    var relative := linear_velocity.length()
    if body is RigidBody3D:
        relative = (linear_velocity - (body as RigidBody3D).linear_velocity).length()
    # Yard pads and walls are StaticBody3D without a hit method. Settling
    # onto them is not a smash; dropping a beam at demolition speed is.
    if (
        body is StaticBody3D
        and not body.has_method("machine_hit")
        and not body.has_method("machine_hit_at")
        and relative < 6.5
    ):
        if _flight_time > 0.0:
            _end_flight()
        return
    if relative < CONTACT_SPEED:
        if _flight_time > 0.0:
            _end_flight()
        return

    var direction := linear_velocity
    if direction.length_squared() < 0.001:
        direction = Vector3.DOWN
    else:
        direction = direction.normalized()
    var point := _contact_point_on(body)

    var consequence := MaterialResponse.collide(
        self,
        body,
        point,
        direction,
        relative,
        {
            "tool_material": _material_id(),
            "area": 0.14,
            "novelty": 0.78
        }
    )
    var energy := float(consequence.get("energy", 0.0))
    var damage := clampf(energy / 260.0, 4.0, 90.0)
    if body.has_method("machine_hit_at"):
        body.machine_hit_at(damage, direction, point, energy)
    elif body.has_method("machine_hit"):
        body.machine_hit(damage, direction)
    elif body.has_method("take_hit"):
        body.take_hit(
            direction * minf(relative * 0.9, 16.0) + Vector3.UP * 2.2,
            damage
        )
    elif body.has_method("receive_enemy_hit"):
        body.receive_enemy_hit(damage)

    _contact_cooldown = 0.10
    _last_contact_id = body.get_instance_id()
    if _flight_time > 0.0:
        _end_flight()


func physical_event(event: Dictionary) -> void:
    if destroyed or held or not sleeping:
        return
    var event_position_value: Variant = event.get("position", global_position)
    var event_position := event_position_value as Vector3
    var radius := maxf(float(event.get("radius", 0.0)), 0.0)
    var distance := global_position.distance_to(event_position)
    if distance > radius + 2.4:
        return
    var energy := float(event.get("energy_in", 0.0))
    var kinetic := float(event.get("kinetic_energy", energy * 0.28))
    if kinetic < 35.0 and energy < 180.0:
        return
    sleeping = false
    can_sleep = false
    _arm_contact_sense()
    var falloff := 1.0 - clampf(
        distance / maxf(radius + 2.4, 0.001),
        0.0,
        1.0
    )
    if falloff < 0.08:
        return
    var away := global_position - event_position
    if away.length_squared() < 0.01:
        away = Vector3.UP
    away = away.normalized()
    away.y = maxf(away.y, 0.16)
    var impulse := EnergyPartition.kinetic_impulse(
        mass,
        kinetic * falloff * 0.32
    )
    apply_central_impulse(away.normalized() * impulse)


func _end_flight() -> void:
    _flight_time = 0.0
    _flight_source = null


func configure_box(size: Vector3, color: Color, mass_value: float = 75.0, hp: float = 80.0) -> void:
    mass = mass_value
    health = hp
    source_color = color
    source_size = size
    set_meta("load_size", size)
    set_meta("source_tag", "yard_prop")
    barrel_shape = false
    impact_color = color.lightened(0.32)
    add_child(GeomUtil.box_mesh(size, color, 0.86, 0.16 if mass_value < 200.0 else 0.72))
    GeomUtil.add_box_collision(self, size)
    _register_material()

func configure_barrel(radius: float, height: float, color: Color, mass_value: float = 48.0, hp: float = 58.0) -> void:
    mass = mass_value
    health = hp
    source_color = color
    source_size = Vector3(radius * 2.0, height, radius * 2.0)
    set_meta("load_size", source_size)
    set_meta("source_tag", "yard_prop")
    barrel_shape = true
    impact_color = color.lightened(0.38)
    add_child(GeomUtil.cylinder_mesh(radius, height, color, 0.76, 0.22))
    GeomUtil.add_cylinder_collision(self, radius, height)
    for y in [-height * 0.32, height * 0.32]:
        var ring := GeomUtil.cylinder_mesh(radius * 1.045, 0.06, Color(0.075, 0.08, 0.075), 0.72, 0.28)
        ring.position.y = y
        add_child(ring)
    _register_material()


func _register_material() -> void:
    var material_id := FoundryMaterial.TIMBER
    if mass >= 200.0:
        material_id = FoundryMaterial.STRUCTURAL_STEEL
    elif barrel_shape:
        material_id = FoundryMaterial.PAINTED_STEEL
    MaterialResponse.register(self, material_id, source_color)


func _material_id() -> int:
    return MaterialResponse.material_of(
        self,
        FoundryMaterial.STRUCTURAL_STEEL if mass >= 200.0 else FoundryMaterial.TIMBER
    )

func set_held(value: bool) -> void:
    held = value
    machine_held = false
    sleeping = false
    freeze = value
    if value:
        linear_velocity = Vector3.ZERO
        angular_velocity = Vector3.ZERO
    else:
        _restore_machine_damping()

func set_machine_held(value: bool) -> void:
    if value:
        if not machine_held:
            _saved_linear_damp = linear_damp
            _saved_angular_damp = angular_damp
        held = true
        machine_held = true
        freeze = false
        can_sleep = false
        sleeping = false
        continuous_cd = true
        _arm_contact_sense()
        linear_damp = maxf(linear_damp, 3.2)
        angular_damp = maxf(angular_damp, 3.8)
        return
    held = false
    machine_held = false
    freeze = false
    can_sleep = true
    sleeping = false
    continuous_cd = false
    _restore_machine_damping()

func _restore_machine_damping() -> void:
    linear_damp = _saved_linear_damp
    angular_damp = _saved_angular_damp

func get_load_profile() -> Dictionary:
    var longest := maxf(source_size.x, maxf(source_size.y, source_size.z))
    var shortest := maxf(
        0.08,
        minf(source_size.x, minf(source_size.y, source_size.z))
    )
    return {
        "mass": mass,
        "size": source_size,
        "kinetic_energy": EnergyPartition.against_world(
            mass,
            linear_velocity.length()
        ),
        "brace_quality": clampf(longest / shortest / 12.0, 0.15, 1.0),
        "plastic_strain": 0.0,
        "source": "yard_prop"
    }

func machine_hit(
        amount: float,
        direction: Vector3,
        world_point: Vector3 = Vector3.ZERO
) -> void:
    _receive_impact(
        amount * 1.35,
        direction,
        14.0,
        world_point
    )


func machine_hit_at(
        amount: float,
        direction: Vector3,
        world_point: Vector3,
        impact_energy: float
) -> void:
    _receive_impact(
        amount * 1.35,
        direction,
        sqrt(maxf(impact_energy, 0.0)),
        world_point
    )

func take_hit(force: Vector3, damage: float) -> void:
    if held:
        set_held(false)
    var dir := force
    if dir.length_squared() < 0.001:
        dir = Vector3.UP
    _receive_impact(
        damage,
        dir.normalized(),
        force.length(),
        global_position
    )

func _receive_impact(
        damage: float,
        direction: Vector3,
        impulse_strength: float,
        world_point: Vector3
) -> void:
    if destroyed:
        return
    sleeping = false
    _arm_contact_sense()
    health -= damage
    var impulse := direction.normalized() * maxf(impulse_strength, damage * 0.22)
    impulse += Vector3.UP * minf(damage * 0.055, 4.2)
    var point := world_point
    if point == Vector3.ZERO:
        point = global_position
    apply_impulse(
        impulse * mass * 0.18 * impact_scale,
        to_local(point)
    )
    ImpactFx.spawn(get_parent(), point, direction, impact_color, clampf(damage / 20.0, 0.7, 3.5), 7)
    set_meta("last_hit_point", point)
    if health <= 0.0:
        _destroy(direction)

func _contact_point_on(body: Node) -> Vector3:
    if not (body is Node3D) or not is_inside_tree():
        return global_position
    var other := body as Node3D
    var space := get_world_3d().direct_space_state if get_world_3d() != null else null
    if space == null:
        return global_position.lerp(other.global_position, 0.5)
    var toward := other.global_position - global_position
    if toward.length_squared() < 0.0001:
        toward = linear_velocity
    if toward.length_squared() < 0.0001:
        toward = Vector3.DOWN
    var query := PhysicsRayQueryParameters3D.create(
        global_position,
        global_position + toward.normalized() * maxf(toward.length(), 0.6),
        collision_mask
    )
    query.exclude = [get_rid()]
    var hit := space.intersect_ray(query)
    if hit.is_empty():
        return global_position.lerp(other.global_position, 0.35)
    return hit.position as Vector3


func _destroy(direction: Vector3) -> void:
    destroyed = true
    linear_damp = 0.18
    angular_damp = 0.12
    var origin := global_position
    if has_meta("last_hit_point"):
        origin = get_meta("last_hit_point") as Vector3
    ImpactFx.spawn(get_parent(), origin, direction, impact_color, 3.4, 13)
    _spawn_fragments(direction, origin)
    MaterialResponse.forget(self)
    visible = false
    collision_layer = 0
    collision_mask = 0
    freeze = true
    queue_free()

func _spawn_fragments(direction: Vector3, origin: Vector3 = Vector3.ZERO) -> void:
    var parent := get_parent()
    if parent == null:
        return
    var blast := origin
    if blast == Vector3.ZERO:
        blast = global_position
    var parent_state := MaterialResponse.state_for(self, _material_id())
    var fragment_count := 5 if barrel_shape else 4
    var leftover := float(
        EnergyPartition.split(
            EnergyPartition.against_world(
                mass,
                maxf(linear_velocity.length(), 3.5)
            )
        ).kinetic
    )
    for i in fragment_count:
        var piece := PhysicsProp.new()
        parent.add_child(piece)
        var scatter_dir := Vector3(
            direction.x + (-0.7 + float(i) * 0.31),
            0.55 + float(i % 2) * 0.32,
            direction.z + (0.6 - float(i) * 0.22)
        )
        if scatter_dir.length_squared() < 0.001:
            scatter_dir = Vector3.UP
        scatter_dir = scatter_dir.normalized()
        piece.global_position = blast + scatter_dir * (0.12 + float(i) * 0.05)
        var piece_mass := mass / float(fragment_count)
        var chunk_size := Vector3(
            maxf(0.18, source_size.x * (0.34 if barrel_shape else 0.42)),
            maxf(0.16, source_size.y * 0.26),
            maxf(0.18, source_size.z * (0.34 if barrel_shape else 0.42))
        )
        piece.configure_box(
            chunk_size,
            source_color.darkened(0.10 + float(i) * 0.025),
            piece_mass,
            maxf(18.0, health * 0.28)
        )
        MaterialResponse.adopt_fragment(piece, parent_state, 0.55)
        piece._arm_contact_sense()
        var share := leftover / float(fragment_count)
        var speed := sqrt(2.0 * share / maxf(piece.mass, 0.001))
        piece.linear_velocity = scatter_dir * speed + linear_velocity * 0.35
        piece.angular_velocity = scatter_dir.cross(Vector3.UP) * (4.0 + float(i))
