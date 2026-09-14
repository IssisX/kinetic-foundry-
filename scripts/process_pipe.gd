class_name ProcessPipe
extends StaticBody3D

## One physical run of pressurised line, and the edge of the process graph
## it carries.
##
## A breach here is not a health bar reaching zero. Delivered impact energy
## is partitioned by the same EnergyPartition every other collision in this
## game uses, and the fracture share is spent tearing wall: opening a hole
## of radius r through wall of thickness t costs the tearing energy of its
## own perimeter. That makes hole area grow with the square of the energy
## that has been put into the wall, so a tap weeps and a swung hook opens
## something the pump cannot keep up with.

const GeomUtil = preload("res://scripts/geom.gd")

const WALL_THICKNESS := 0.008
## Dynamic tearing energy of the wall per square metre of torn section,
## referenced to structural steel's catalog toughness. A pipe rolled from a
## more brittle alloy gives way for less.
const BASE_TEAR_ENERGY := 2.4e7
const REFERENCE_TOUGHNESS := 180.0
## A line already carrying hoop stress is part-way to failing before
## anything hits it. Isolating a run before you smash it really does make
## it harder to open.
const PRESSURE_EMBRITTLEMENT := 0.35
const SKIN_REFRESH_INTERVAL := 0.5

var edge_id := ""
var process_edge := -1
var material_id := FoundryMaterial.STRUCTURAL_STEEL
var pipe_radius := 0.16

var _axis := Vector3.FORWARD
var _length := 1.0
var _tear_energy := 0.0
var _surface_state: SurfaceState
var _mesh: MeshInstance3D
var _skin_clock := 0.0
var _seen_surface_revision := -1


func configure(
        from_point: Vector3,
        to_point: Vector3,
        radius: float,
        id: String
) -> void:
    edge_id = id
    pipe_radius = maxf(radius, 0.04)
    var span := to_point - from_point
    _length = maxf(span.length(), 0.2)
    _axis = span / _length
    position = (from_point + to_point) * 0.5
    _orient_to_axis()

    collision_layer = 8
    collision_mask = 0
    add_to_group("process_pipe")

    _mesh = GeomUtil.cylinder_mesh(
        pipe_radius,
        _length,
        Color(0.26, 0.29, 0.27),
        0.74,
        0.36
    )
    add_child(_mesh)
    GeomUtil.add_cylinder_collision(self, pipe_radius * 1.15, _length)

    for flange_offset in [-_length * 0.5 + 0.12, _length * 0.5 - 0.12]:
        var flange := GeomUtil.cylinder_mesh(
            pipe_radius * 1.45,
            0.1,
            Color(0.17, 0.18, 0.17),
            0.82,
            0.30
        )
        flange.position.y = flange_offset
        add_child(flange)

    _surface_state = MaterialResponse.register(
        self,
        material_id,
        Color(0.26, 0.29, 0.27)
    )
    process_edge = ProcessPlant.register_pipe_body(edge_id, self)


## The mesh and collider are built along local Y, so the body is rotated to
## put local Y on the run's real axis rather than rebuilding the geometry.
func _orient_to_axis() -> void:
    var up := Vector3.UP
    if absf(_axis.dot(up)) > 0.999:
        up = Vector3.FORWARD
    var side := up.cross(_axis).normalized()
    var forward := _axis.cross(side).normalized()
    basis = Basis(side, _axis, forward)


func _process(delta: float) -> void:
    _skin_clock += delta
    if _skin_clock < SKIN_REFRESH_INTERVAL:
        return
    _skin_clock = 0.0
    _refresh_skin()


func _refresh_skin() -> void:
    if _surface_state == null or _mesh == null:
        return
    if _surface_state.revision == _seen_surface_revision:
        return
    _seen_surface_revision = _surface_state.revision
    var surface := _mesh.material_override as StandardMaterial3D
    if surface == null:
        return
    _surface_state.apply_to_material(surface)


func machine_hit_at(
        amount: float,
        direction: Vector3,
        world_point: Vector3,
        impact_energy: float
) -> void:
    _absorb(
        maxf(impact_energy, EnergyPartition.nominal_impact_energy(amount)),
        direction,
        world_point
    )


func machine_hit(
        amount: float,
        direction: Vector3,
        world_point: Vector3 = Vector3.ZERO
) -> void:
    var point := world_point
    if point == Vector3.ZERO:
        point = global_position
    machine_hit_at(
        amount,
        direction,
        point,
        EnergyPartition.nominal_impact_energy(amount)
    )


## Deliberately no take_hit or receive_hazard_hit. What opens a pipe wall is
## concentrated contact - a hook, a bucket, a falling girder - carrying real
## kinetic energy into a small area. A pressure blast is a distributed load
## and steel pipe shrugs it off, which is also why a relief vent does not
## shred the line feeding it every time it fires.


## The contact is resolved by the shared material resolver first - this wall
## marks, heats and sparks exactly like any other struck steel - and only
## the fracture share of that same partition is allowed to tear it open.
func _absorb(
        impact_energy: float,
        direction: Vector3,
        world_point: Vector3
) -> void:
    if impact_energy <= 0.0:
        return
    var consequence := MaterialResponse.impact(
        self,
        world_point,
        direction,
        impact_energy,
        240.0,
        FoundryMaterial.HARDENED_STEEL,
        {
            "material": material_id,
            "area": 0.05,
            "radius": 3.4,
            "fracture": clampf(breach_fraction(), 0.0, 1.0)
        }
    )
    _tear_energy += maxf(float(consequence.get("surface", 0.0)), 0.0)
    _update_breach(direction, world_point)


func breach_fraction() -> float:
    var bore := PI * pipe_radius * pipe_radius
    return clampf(_breach_area() / maxf(bore, 0.0001), 0.0, 1.0)


func _tear_energy_per_area() -> float:
    var data := FoundryMaterial.of(material_id)
    var toughness := float(data.get("toughness", REFERENCE_TOUGHNESS))
    var scale := maxf(toughness / REFERENCE_TOUGHNESS, 0.1)
    var pressure_ratio := 0.0
    if process_edge >= 0 and ProcessPlant.network != null:
        var edge: Dictionary = ProcessPlant.network.edges[process_edge]
        var gauge := maxf(
            ProcessPlant.network.gauge_pressure(int(edge.a)),
            ProcessPlant.network.gauge_pressure(int(edge.b))
        )
        pressure_ratio = clampf(gauge / ProcessPlant.PUMP_SET_PRESSURE, 0.0, 1.0)
    return maxf(
        BASE_TEAR_ENERGY * scale * (1.0 - PRESSURE_EMBRITTLEMENT * pressure_ratio),
        1.0
    )


## Griffith on a circular breach: the energy paid buys the torn perimeter of
## the hole through the wall, so r = E / (2*pi*gamma*t) and the escaping
## area goes with r squared.
func _breach_area() -> float:
    if _tear_energy <= 0.0:
        return 0.0
    var radius := _tear_energy / maxf(
        TAU * _tear_energy_per_area() * WALL_THICKNESS,
        0.0001
    )
    var bore := PI * pipe_radius * pipe_radius
    return minf(PI * radius * radius, bore)


func _update_breach(direction: Vector3, world_point: Vector3) -> void:
    if process_edge < 0:
        return
    var area := _breach_area()
    if area <= 0.0:
        return
    var offset := world_point - global_position
    var along := offset.dot(_axis)
    var surface_point := (
        global_position
        + _axis * clampf(along, -_length * 0.5, _length * 0.5)
    )
    var radial := offset - _axis * along
    if radial.length_squared() < 0.0001:
        radial = -direction
        radial -= _axis * radial.dot(_axis)
    if radial.length_squared() < 0.0001:
        radial = Vector3.UP
    radial = radial.normalized()
    ProcessPlant.report_rupture(
        process_edge,
        area,
        surface_point + radial * pipe_radius,
        radial
    )


func breach_area() -> float:
    return _breach_area()

