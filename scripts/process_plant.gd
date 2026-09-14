extends Node

## The yard's fluid infrastructure, as one authoritative running system.
##
## ProcessNetwork owns the numbers; this node owns the plant those numbers
## describe: which run of pipe is which edge, where a breach actually is in
## the world, which machine draws from which supply, and how escaped fluid
## reaches the material substrate. Nothing here decides what a machine may
## do - it publishes pressure and flow, and the machines read them.

const ProcessNetworkScript = preload("res://scripts/process_network.gd")

## Working pressures for a yard service loop, in pascals absolute. The pump
## set point sits above the vent cracking pressure so an intact loop cycles
## its vents; a loop that cannot hold 16 MPa cannot crack them at all.
const PUMP_SET_PRESSURE := 21.0e6
const PUMP_MAX_FLOW := 0.0034
const RESERVOIR_VOLUME := 2.4

const VENT_CRACK_PRESSURE := 16.0e6
const VENT_RESEAT_PRESSURE := 11.0e6
## Sized so one blowdown lasts about a second and the recharge behind it
## takes a few, and - the part that matters - so that two vents charging at
## once still sit inside what the pump can move. A vent branch that could
## outrun its own supply would collapse the header just by working.
const VENT_ORIFICE_AREA := 2.1e-5
## A gas-backed bladder accumulator: the fluid is still oil, but the gas
## behind the bladder is what gives the vent branch a slow enough blowdown
## to be a blast rather than a click.
const VENT_ACCUMULATOR_CAPACITANCE := 4.0e-10
const VENT_CHARGE_CONDUCTANCE := 7.0e-11

## Capacitance is line volume over the effective bulk modulus of what is in
## it. Sized for a yard plumbed in hose and pipe with air entrained in the
## oil, not for a laboratory loop of rigid steel: an order of magnitude
## softer, which is both what a real site behaves like and what keeps the
## explicit integrator's time constants above a frame.
const LINE_CAPACITANCE := 2.0e-10
const SUPPLY_CAPACITANCE := 1.5e-10
const HEADER_CAPACITANCE := 2.5e-10
const PIPE_CONDUCTANCE := 6.0e-9
const VALVE_CONDUCTANCE := 8.0e-9

const LEAK_PUBLISH_INTERVAL := 0.25
## Machine actuator demand at full command, in cubic metres per second.
const MACHINE_DEMAND_FLOW := 0.0012
const MACHINE_RATED_PRESSURE := 18.0e6

signal rupture_opened(edge_id: String, world_point: Vector3)

var network: ProcessNetwork

var _edge_ids: Dictionary = {}
var _edge_names: Dictionary = {}
var _valve_bodies: Dictionary = {}
var _pipe_bodies: Dictionary = {}
var _machine_nodes: Dictionary = {}
var _leak_banks: Dictionary = {}
var _leak_clocks: Dictionary = {}
var _routes: Array[Dictionary] = []
var _valve_sites: Array[Dictionary] = []


func _ready() -> void:
    process_mode = Node.PROCESS_MODE_PAUSABLE
    _build_yard_plant()


func _physics_process(delta: float) -> void:
    if network == null:
        return
    network.step(delta)
    _publish_leaks(delta)


## One service loop: tank and pump on the east skid, a trunk across the
## yard, and two branches that each feed a machine supply and a vent
## accumulator. Every position here is a place the yard already has
## something standing, so the graph and the geometry describe one plant.
func _build_yard_plant() -> void:
    network = ProcessNetworkScript.new()

    var reservoir := network.add_node(
        "reservoir",
        ProcessNetworkScript.KIND_RESERVOIR,
        1.0e-8,
        ProcessNetworkScript.AMBIENT_PRESSURE,
        Vector3(18.0, 2.6, -17.0),
        RESERVOIR_VOLUME
    )
    var header := network.add_node(
        "header",
        ProcessNetworkScript.KIND_JUNCTION,
        HEADER_CAPACITANCE,
        PUMP_SET_PRESSURE,
        Vector3(21.4, 1.05, -12.8)
    )
    network.attach_pump(header, PUMP_SET_PRESSURE, PUMP_MAX_FLOW, reservoir)

    var trunk := network.add_node(
        "trunk",
        ProcessNetworkScript.KIND_JUNCTION,
        LINE_CAPACITANCE,
        PUMP_SET_PRESSURE,
        Vector3(12.4, 1.55, -7.4)
    )
    var east_junction := network.add_node(
        "east_junction",
        ProcessNetworkScript.KIND_JUNCTION,
        LINE_CAPACITANCE,
        PUMP_SET_PRESSURE,
        Vector3(7.8, 1.55, -7.6)
    )
    var west_junction := network.add_node(
        "west_junction",
        ProcessNetworkScript.KIND_JUNCTION,
        LINE_CAPACITANCE,
        PUMP_SET_PRESSURE,
        Vector3(-14.0, 1.55, -6.0)
    )
    var east_vent_head := network.add_node(
        "east_vent_head",
        ProcessNetworkScript.KIND_JUNCTION,
        LINE_CAPACITANCE,
        PUMP_SET_PRESSURE,
        Vector3(7.8, 1.55, -9.3)
    )
    var west_vent_head := network.add_node(
        "west_vent_head",
        ProcessNetworkScript.KIND_JUNCTION,
        LINE_CAPACITANCE,
        PUMP_SET_PRESSURE,
        Vector3(-14.8, 1.55, -0.6)
    )
    var east_charge := network.add_node(
        "east_charge",
        ProcessNetworkScript.KIND_JUNCTION,
        LINE_CAPACITANCE,
        PUMP_SET_PRESSURE,
        Vector3(7.8, 1.50, -10.2)
    )
    var west_charge := network.add_node(
        "west_charge",
        ProcessNetworkScript.KIND_JUNCTION,
        LINE_CAPACITANCE,
        PUMP_SET_PRESSURE,
        Vector3(-15.3, 1.50, 4.4)
    )
    var east_plenum := network.add_node(
        "east_plenum",
        ProcessNetworkScript.KIND_PLENUM,
        VENT_ACCUMULATOR_CAPACITANCE,
        VENT_RESEAT_PRESSURE,
        Vector3(7.8, 1.34, -10.8)
    )
    var west_plenum := network.add_node(
        "west_plenum",
        ProcessNetworkScript.KIND_PLENUM,
        VENT_ACCUMULATOR_CAPACITANCE,
        VENT_RESEAT_PRESSURE,
        Vector3(-15.3, 1.34, 5.5)
    )
    var excavator_supply := network.add_node(
        "excavator_supply",
        ProcessNetworkScript.KIND_SUPPLY,
        SUPPLY_CAPACITANCE,
        PUMP_SET_PRESSURE,
        Vector3(5.2, 1.25, -4.2)
    )
    var crane_supply := network.add_node(
        "crane_supply",
        ProcessNetworkScript.KIND_SUPPLY,
        SUPPLY_CAPACITANCE,
        PUMP_SET_PRESSURE,
        Vector3(-7.6, 1.25, -10.6)
    )

    _register_edge(
        "V_TRUNK",
        network.add_edge(
            header,
            trunk,
            VALVE_CONDUCTANCE,
            ProcessNetworkScript.EDGE_VALVE,
            Vector3(19.6, 1.35, -11.6)
        ),
        "MAIN ISOLATION"
    )
    _register_edge(
        "P_TRUNK",
        network.add_edge(
            trunk,
            east_junction,
            PIPE_CONDUCTANCE,
            ProcessNetworkScript.EDGE_PIPE,
            Vector3(10.1, 1.55, -7.5)
        ),
        "TRUNK RUN"
    )
    _register_edge(
        "V_EAST_VENT",
        network.add_edge(
            east_junction,
            east_vent_head,
            VALVE_CONDUCTANCE,
            ProcessNetworkScript.EDGE_VALVE,
            Vector3(7.8, 1.35, -8.4)
        ),
        "EAST VENT ISOLATION"
    )
    # The spur itself is full bore: a hole in it is fed by the whole loop,
    # which is exactly why it is worth isolating. The orifice that meters
    # the accumulator sits at the accumulator, where a real one does.
    _register_edge(
        "P_EAST_VENT",
        network.add_edge(
            east_vent_head,
            east_charge,
            PIPE_CONDUCTANCE,
            ProcessNetworkScript.EDGE_PIPE,
            Vector3(7.8, 1.45, -10.0)
        ),
        "EAST VENT SPUR"
    )
    _register_edge(
        "R_EAST",
        network.add_edge(
            east_charge,
            east_plenum,
            VENT_CHARGE_CONDUCTANCE,
            ProcessNetworkScript.EDGE_RESTRICTION,
            Vector3(7.8, 1.40, -10.6)
        ),
        "EAST ACCUMULATOR ORIFICE"
    )
    _register_edge(
        "RELIEF_EAST",
        network.add_relief(
            east_plenum,
            VENT_CRACK_PRESSURE,
            VENT_RESEAT_PRESSURE,
            VENT_ORIFICE_AREA,
            Vector3(7.8, 1.34, -10.8)
        ),
        "EAST VENT RELIEF"
    )
    _register_edge(
        "V_EXCAVATOR",
        network.add_edge(
            east_junction,
            excavator_supply,
            VALVE_CONDUCTANCE,
            ProcessNetworkScript.EDGE_VALVE,
            Vector3(6.6, 1.35, -5.8)
        ),
        "EXCAVATOR SUPPLY"
    )
    _register_edge(
        "P_WEST",
        network.add_edge(
            trunk,
            west_junction,
            PIPE_CONDUCTANCE,
            ProcessNetworkScript.EDGE_PIPE,
            Vector3(-2.0, 1.55, -3.0)
        ),
        "WEST MAIN RUN"
    )
    _register_edge(
        "V_WEST_VENT",
        network.add_edge(
            west_junction,
            west_vent_head,
            VALVE_CONDUCTANCE,
            ProcessNetworkScript.EDGE_VALVE,
            Vector3(-14.4, 1.35, 2.7)
        ),
        "WEST VENT ISOLATION"
    )
    _register_edge(
        "P_WEST_VENT",
        network.add_edge(
            west_vent_head,
            west_charge,
            PIPE_CONDUCTANCE,
            ProcessNetworkScript.EDGE_PIPE,
            Vector3(-15.3, 1.45, 4.7)
        ),
        "WEST VENT SPUR"
    )
    _register_edge(
        "R_WEST",
        network.add_edge(
            west_charge,
            west_plenum,
            VENT_CHARGE_CONDUCTANCE,
            ProcessNetworkScript.EDGE_RESTRICTION,
            Vector3(-15.3, 1.40, 5.2)
        ),
        "WEST ACCUMULATOR ORIFICE"
    )
    _register_edge(
        "RELIEF_WEST",
        network.add_relief(
            west_plenum,
            VENT_CRACK_PRESSURE,
            VENT_RESEAT_PRESSURE,
            VENT_ORIFICE_AREA,
            Vector3(-15.3, 1.34, 5.5)
        ),
        "WEST VENT RELIEF"
    )
    _register_edge(
        "V_CRANE",
        network.add_edge(
            west_junction,
            crane_supply,
            VALVE_CONDUCTANCE,
            ProcessNetworkScript.EDGE_VALVE,
            Vector3(-10.4, 1.35, -4.4)
        ),
        "CRANE SUPPLY"
    )

    # Runs sit on a rack above the machines' own working envelope and clear
    # of where they park, so nothing is grinding a hole in the yard's
    # plumbing simply by standing where it was left. Reaching one takes a
    # raised boom or a swung hook - which is the point of putting them here.
    # The vent spurs drop to nozzle height, so those stay in bucket reach.
    _routes = [
        {"edge": "P_TRUNK", "from": Vector3(19.6, 5.50, -12.4), "to": Vector3(9.0, 5.50, -8.4), "radius": 0.17},
        {"edge": "P_EAST_VENT", "from": Vector3(7.9, 5.20, -8.8), "to": Vector3(7.8, 2.00, -10.4), "radius": 0.13},
        {"edge": "P_WEST", "from": Vector3(12.0, 5.50, -8.0), "to": Vector3(-14.0, 5.50, -6.0), "radius": 0.17},
        {"edge": "P_WEST_VENT", "from": Vector3(-14.6, 5.20, -1.0), "to": Vector3(-15.3, 2.00, 4.6), "radius": 0.13}
    ]
    _valve_sites = [
        {"edge": "V_TRUNK", "position": Vector3(19.6, 1.35, -12.4)},
        {"edge": "V_EAST_VENT", "position": Vector3(8.9, 1.35, -8.6)},
        {"edge": "V_EXCAVATOR", "position": Vector3(7.4, 1.35, -6.4)},
        {"edge": "V_WEST_VENT", "position": Vector3(-14.6, 1.35, -1.0)},
        {"edge": "V_CRANE", "position": Vector3(-10.6, 1.35, -6.6)}
    ]


func _register_edge(id: String, index: int, label: String) -> void:
    _edge_ids[id] = index
    _edge_names[index] = label


func route_specs() -> Array[Dictionary]:
    return _routes


func valve_specs() -> Array[Dictionary]:
    return _valve_sites


func edge_index(id: String) -> int:
    return int(_edge_ids.get(id, -1))


func edge_label(index: int) -> String:
    return str(_edge_names.get(index, "LINE"))


func edge_id_of(index: int) -> String:
    for id in _edge_ids:
        if int(_edge_ids[id]) == index:
            return str(id)
    return ""


func register_pipe_body(edge_id: String, body: Node) -> int:
    var index := edge_index(edge_id)
    if index >= 0:
        _pipe_bodies[index] = body
    return index


func register_valve_body(edge_id: String, body: Node) -> int:
    var index := edge_index(edge_id)
    if index >= 0:
        _valve_bodies[index] = body
    return index


## A pipe reports the hole it has actually torn. The network does not ask
## how it got there and does not second-guess the size.
func report_rupture(
        edge_index_value: int,
        area: float,
        world_point: Vector3,
        spray_direction: Vector3
) -> void:
    if network == null or edge_index_value < 0:
        return
    var previous := network.rupture_area(edge_index_value)
    network.set_rupture(edge_index_value, area, world_point, spray_direction)
    if previous < ProcessNetworkScript.MIN_LEAK_AREA and area >= ProcessNetworkScript.MIN_LEAK_AREA:
        rupture_opened.emit(edge_id_of(edge_index_value), world_point)


func set_valve(edge_index_value: int, aperture: float) -> void:
    if network == null:
        return
    network.set_valve_aperture(edge_index_value, aperture)


func valve_aperture(edge_index_value: int) -> float:
    return network.valve_aperture(edge_index_value) if network != null else 0.0


## Escaped fluid is not a particle effect. It is banked as real volume and
## handed to the material resolver as a fluid source, which is what makes
## the ground under a breach slippery and what eventually rusts it.
func _publish_leaks(delta: float) -> void:
    for edge_index_value in network.leaking_edges():
        var flow := network.leak_flow(edge_index_value)
        var banked := float(_leak_banks.get(edge_index_value, 0.0)) + flow * delta
        var clock := float(_leak_clocks.get(edge_index_value, 0.0)) + delta
        if clock < LEAK_PUBLISH_INTERVAL:
            _leak_banks[edge_index_value] = banked
            _leak_clocks[edge_index_value] = clock
            continue
        _leak_banks[edge_index_value] = 0.0
        _leak_clocks[edge_index_value] = 0.0
        var edge: Dictionary = network.edges[edge_index_value]
        # Deliberately untyped until validated: on teardown the scene frees
        # the pipe bodies while this node is still ticking, and binding a
        # freed instance to a typed local is itself the error.
        var source = _pipe_bodies.get(edge_index_value)
        if source == null or not is_instance_valid(source):
            _pipe_bodies.erase(edge_index_value)
            continue
        MaterialResponse.fluid_leak(
            source,
            edge.leak_point as Vector3,
            edge.leak_direction as Vector3,
            FoundryMaterial.HYDRAULIC_FLUID,
            clampf(banked * 42.0, 0.05, 0.9),
            {"reach": 8.0, "floor_material": FoundryMaterial.ASPHALT}
        )


func bind_machine(machine: Node, supply_id: String) -> void:
    if machine == null or network == null:
        return
    var index := network.node_index(supply_id)
    if index < 0:
        return
    _machine_nodes[machine.get_instance_id()] = index


func machine_supply_node(machine: Node) -> int:
    if machine == null:
        return -1
    return int(_machine_nodes.get(machine.get_instance_id(), -1))


## A machine states how hard it is working; the network answers with what it
## can actually deliver. Demand is republished every frame so a machine
## sitting idle stops loading the loop.
func request_machine_supply(machine: Node, command: float) -> void:
    var index := machine_supply_node(machine)
    if index < 0 or network == null:
        return
    network.request_supply(
        index,
        clampf(command, 0.0, 1.0) * MACHINE_DEMAND_FLOW,
        MACHINE_RATED_PRESSURE
    )


func machine_supply_state(machine: Node) -> Dictionary:
    var index := machine_supply_node(machine)
    if index < 0 or network == null:
        return {"pressure_ratio": 1.0, "flow_ratio": 1.0, "pressure": PUMP_SET_PRESSURE}
    return network.supply_state(index)


func vent_state(plenum_id: String, relief_id: String) -> Dictionary:
    if network == null:
        return {"open": false, "pressure": 0.0, "flow": 0.0, "charge": 0.0}
    var plenum := network.node_index(plenum_id)
    var relief := edge_index(relief_id)
    var gauge := network.gauge_pressure(plenum)
    return {
        "open": network.is_relief_open(relief),
        "pressure": gauge,
        "flow": network.flow_through(relief),
        "charge": clampf(
            gauge / maxf(VENT_CRACK_PRESSURE - ProcessNetworkScript.AMBIENT_PRESSURE, 1.0),
            0.0,
            1.0
        )
    }


## The single best valve to close to stop a live breach, chosen by what the
## graph says: it must actually cut the pump off from the hole, and among
## the valves that do, the one that strands the fewest machine supplies.
func plan_isolation() -> Dictionary:
    if network == null:
        return {}
    var source := network.node_index("header")
    var leaks := network.leaking_edges()
    if leaks.is_empty() or source < 0:
        return {}
    var live := network.reachable_from(source)
    var target := -1
    var worst_flow := 0.0
    for leak in leaks:
        if not network.edge_is_fed(leak, live):
            continue
        var flow := network.leak_flow(leak)
        if flow > worst_flow:
            worst_flow = flow
            target = leak
    if target < 0:
        return {}

    var best_valve := -1
    var best_supplies := -1
    for valve in network.valve_edges():
        if network.valve_aperture(valve) < ProcessNetworkScript.MIN_APERTURE:
            continue
        var without := network.reachable_from(source, valve)
        if network.edge_is_fed(target, without):
            continue
        var kept := 0
        for supply in network.supply_nodes():
            if without.has(supply):
                kept += 1
        if kept > best_supplies:
            best_supplies = kept
            best_valve = valve
    if best_valve < 0:
        return {}
    return {
        "valve": best_valve,
        "valve_id": edge_id_of(best_valve),
        "leak": target,
        "leak_flow": worst_flow,
        "supplies_kept": best_supplies,
        "body": _valve_bodies.get(best_valve)
    }


## The valve that takes this machine off supply without shutting the whole
## yard down: the same reasoning as isolation, read the other way round.
func plan_supply_denial(machine: Node) -> Dictionary:
    if network == null:
        return {}
    var supply := machine_supply_node(machine)
    var source := network.node_index("header")
    if supply < 0 or source < 0:
        return {}
    if not network.reachable_from(source).has(supply):
        return {}
    var best_valve := -1
    var best_kept := -1
    for valve in network.valve_edges():
        if network.valve_aperture(valve) < ProcessNetworkScript.MIN_APERTURE:
            continue
        var without := network.reachable_from(source, valve)
        if without.has(supply):
            continue
        var kept := 0
        for other in network.supply_nodes():
            if other != supply and without.has(other):
                kept += 1
        if kept > best_kept:
            best_kept = kept
            best_valve = valve
    if best_valve < 0:
        return {}
    return {
        "valve": best_valve,
        "valve_id": edge_id_of(best_valve),
        "supply": supply,
        "body": _valve_bodies.get(best_valve)
    }


## A branch that was isolated and has since been repaired - or a valve an
## operator closed in a hurry - leaves supplies dead that nothing is
## leaking from. Reopening those is the restoring half of the same verb.
func plan_restoration() -> Dictionary:
    if network == null:
        return {}
    var source := network.node_index("header")
    if source < 0:
        return {}
    var live := network.reachable_from(source)
    var best_valve := -1
    var best_gain := 0
    for valve in network.valve_edges():
        if network.valve_aperture(valve) >= ProcessNetworkScript.MIN_APERTURE:
            continue
        var edge: Dictionary = network.edges[valve]
        var a := int(edge.a)
        var b := int(edge.b)
        if not live.has(a) and not live.has(b):
            continue
        var opened := network.reachable_from(source, -1, valve)
        var leaking := false
        for leak in network.leaking_edges():
            if network.edge_is_fed(leak, opened):
                leaking = true
                break
        var gain := 0
        for supply in network.supply_nodes():
            if opened.has(supply) and not live.has(supply):
                gain += 1
        if leaking or gain <= 0:
            continue
        if gain > best_gain:
            best_gain = gain
            best_valve = valve
    if best_valve < 0:
        return {}
    return {
        "valve": best_valve,
        "valve_id": edge_id_of(best_valve),
        "gain": best_gain,
        "body": _valve_bodies.get(best_valve)
    }

