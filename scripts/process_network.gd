class_name ProcessNetwork
extends RefCounted

## Authoritative lumped-parameter process network for the foundry's fluid
## infrastructure.
##
## The graph is the authority for pressure, stored inventory, flow, and what
## a branch can still deliver. Machines, vents, hazards and AI consume that
## state; none of them keeps a second answer to "is this line live". This is
## not CFD: every vessel is one capacitance, every run of pipe one
## conductance, and every hole one orifice. What it is required to get right
## is causality - a breach that outflows the pump collapses the header, and
## everything downstream finds out by reading the same numbers.

const KIND_AMBIENT := 0
const KIND_RESERVOIR := 1
const KIND_JUNCTION := 2
const KIND_SUPPLY := 3
const KIND_PLENUM := 4

const EDGE_PIPE := 0
const EDGE_VALVE := 1
const EDGE_RESTRICTION := 2
const EDGE_RELIEF := 3

const AMBIENT_PRESSURE := 101325.0
## Vena-contracta coefficient for a sharp-edged orifice. A torn steel wall
## is not a machined nozzle, but it is much closer to this than to a pipe.
const DISCHARGE_COEFFICIENT := 0.62
## Openings below this are sub-weep and not worth solving or drawing.
const MIN_LEAK_AREA := 1.0e-7
const MIN_APERTURE := 0.02
## Explicit integration is only conditionally stable. The substep count is
## derived from the stiffest node's own RC time constant rather than a fixed
## guess, the same way the fracture solver sizes its substeps.
const SUBSTEP_SAFETY := 0.35
## Explicit integration of an RC network diverges once the step passes the
## smallest time constant, and clamping pressure at atmosphere hides that as
## a loop that simply will not come up. The cap is a backstop, not the
## design: the capacitances are chosen so a normal frame needs a handful.
const MAX_SUBSTEPS := 16

var nodes: Array[Dictionary] = []
var edges: Array[Dictionary] = []

## Which edges touch each node, kept current as edges are added. The graph
## is tiny (single digits of nodes) but this is rebuilt every substep, and a
## per-node scan of every edge is the wrong complexity for a topology that
## never changes shape after setup - only aperture and rupture area move.
var _node_edges: Array[Array] = []
var _net_scratch: Array[float] = []
var _inflow_scratch: Array[float] = []

var _ambient_index := -1
var _ids: Dictionary = {}
var _total_leak_flow := 0.0
var _spilled_volume := 0.0


func _init() -> void:
    _ambient_index = nodes.size()
    nodes.append({
        "id": "ambient",
        "kind": KIND_AMBIENT,
        "capacitance": 1.0,
        "pressure": AMBIENT_PRESSURE,
        "fixed": true,
        "stored": -1.0,
        "density": 870.0,
        "position": Vector3.ZERO,
        "demand": 0.0,
        "rated_pressure": AMBIENT_PRESSURE,
        "served_flow": 0.0,
        "pump_pressure": 0.0,
        "pump_max_flow": 0.0,
        "pump_enabled": false,
        "pump_source": -1,
        "pump_flow": 0.0
    })
    _node_edges.append([])
    _ids["ambient"] = _ambient_index


func ambient() -> int:
    return _ambient_index


## capacitance is dV/dP for this vessel: volume divided by the effective
## bulk modulus of what is in it. Stiff oil gives a small number and fast
## pressure swings; a gas plenum gives a large one and a slow blowdown.
func add_node(
        id: String,
        kind: int,
        capacitance: float,
        initial_pressure: float,
        world_position: Vector3 = Vector3.ZERO,
        stored_volume: float = -1.0,
        fluid_density: float = 870.0
) -> int:
    var index := nodes.size()
    nodes.append({
        "id": id,
        "kind": kind,
        "capacitance": maxf(capacitance, 1.0e-12),
        "pressure": maxf(initial_pressure, AMBIENT_PRESSURE),
        "fixed": false,
        "stored": stored_volume,
        "density": maxf(fluid_density, 0.5),
        "position": world_position,
        "demand": 0.0,
        "rated_pressure": maxf(initial_pressure, AMBIENT_PRESSURE + 1.0),
        "served_flow": 0.0,
        "pump_pressure": 0.0,
        "pump_max_flow": 0.0,
        "pump_enabled": false,
        "pump_source": -1,
        "pump_flow": 0.0
    })
    _node_edges.append([])
    _ids[id] = index
    return index


## A pressure-compensated pump: it holds its set point until demand exceeds
## what it can move, and then it simply cannot, which is the whole point.
func attach_pump(
        node_index: int,
        set_pressure: float,
        max_flow: float,
        source_index: int
) -> void:
    if node_index < 0 or node_index >= nodes.size():
        return
    var node := nodes[node_index]
    node.pump_pressure = maxf(set_pressure, AMBIENT_PRESSURE)
    node.pump_max_flow = maxf(max_flow, 0.0)
    node.pump_enabled = true
    node.pump_source = source_index
    node.rated_pressure = node.pump_pressure


func add_edge(
        a: int,
        b: int,
        conductance: float,
        kind: int = EDGE_PIPE,
        world_position: Vector3 = Vector3.ZERO
) -> int:
    var index := edges.size()
    edges.append({
        "a": a,
        "b": b,
        "conductance": maxf(conductance, 0.0),
        "kind": kind,
        "aperture": 1.0,
        "rupture_area": 0.0,
        "flow": 0.0,
        "leak_flow": 0.0,
        "position": world_position,
        "leak_point": world_position,
        "leak_direction": Vector3.UP,
        "crack_pressure": 0.0,
        "reseat_pressure": 0.0,
        "orifice_area": 0.0,
        "open": false
    })
    _node_edges[a].append(index)
    _node_edges[b].append(index)
    return index


## A relief/vent path to atmosphere. Cracking above one pressure and
## reseating below another is what makes a vent cycle at all: the hysteresis
## is the oscillator, so when the branch can no longer reach cracking
## pressure the vent simply stops, with nothing to switch off.
func add_relief(
        from_node: int,
        crack_pressure: float,
        reseat_pressure: float,
        orifice_area: float,
        world_position: Vector3 = Vector3.ZERO
) -> int:
    var index := add_edge(
        from_node,
        _ambient_index,
        0.0,
        EDGE_RELIEF,
        world_position
    )
    var edge := edges[index]
    edge.crack_pressure = crack_pressure
    edge.reseat_pressure = minf(reseat_pressure, crack_pressure - 1.0)
    edge.orifice_area = maxf(orifice_area, 0.0)
    edge.aperture = 0.0
    return index


func node_index(id: String) -> int:
    return int(_ids.get(id, -1))


func set_valve_aperture(edge_index: int, aperture: float) -> void:
    if edge_index < 0 or edge_index >= edges.size():
        return
    edges[edge_index].aperture = clampf(aperture, 0.0, 1.0)


func valve_aperture(edge_index: int) -> float:
    if edge_index < 0 or edge_index >= edges.size():
        return 0.0
    return float(edges[edge_index].aperture)


## A breach is an area, not a flag. Whatever opened it is responsible for
## deciding how big it is; the network only has to discharge it.
func set_rupture(
        edge_index: int,
        area: float,
        world_point: Vector3,
        spray_direction: Vector3
) -> void:
    if edge_index < 0 or edge_index >= edges.size():
        return
    var edge := edges[edge_index]
    edge.rupture_area = maxf(area, 0.0)
    edge.leak_point = world_point
    edge.leak_direction = (
        spray_direction.normalized()
        if spray_direction.length_squared() > 0.0001
        else Vector3.UP
    )


func rupture_area(edge_index: int) -> float:
    if edge_index < 0 or edge_index >= edges.size():
        return 0.0
    return float(edges[edge_index].rupture_area)


func pressure_at(node_index: int) -> float:
    if node_index < 0 or node_index >= nodes.size():
        return AMBIENT_PRESSURE
    return float(nodes[node_index].pressure)


func gauge_pressure(node_index: int) -> float:
    return maxf(pressure_at(node_index) - AMBIENT_PRESSURE, 0.0)


func stored_volume(node_index: int) -> float:
    if node_index < 0 or node_index >= nodes.size():
        return 0.0
    return float(nodes[node_index].stored)


func flow_through(edge_index: int) -> float:
    if edge_index < 0 or edge_index >= edges.size():
        return 0.0
    return float(edges[edge_index].flow)


func leak_flow(edge_index: int) -> float:
    if edge_index < 0 or edge_index >= edges.size():
        return 0.0
    return float(edges[edge_index].leak_flow)


func total_leak_flow() -> float:
    return _total_leak_flow


func spilled_volume() -> float:
    return _spilled_volume


func is_relief_open(edge_index: int) -> bool:
    if edge_index < 0 or edge_index >= edges.size():
        return false
    return bool(edges[edge_index].open)


## A consumer asks for flow at a working pressure. What it gets back depends
## on what the branch can still deliver, which is the only place machine
## capability is allowed to come from.
func request_supply(
        node_index: int,
        demand_flow: float,
        rated_pressure: float
) -> void:
    if node_index < 0 or node_index >= nodes.size():
        return
    var node := nodes[node_index]
    node.demand = maxf(demand_flow, 0.0)
    node.rated_pressure = maxf(rated_pressure, AMBIENT_PRESSURE + 1.0)


## Pressure ratio caps force; flow ratio caps actuator speed. They are
## different limits because they are different physical shortages: no
## pressure means no force at any speed, no flow means no speed at any force.
func supply_state(node_index: int) -> Dictionary:
    if node_index < 0 or node_index >= nodes.size():
        return {"pressure_ratio": 0.0, "flow_ratio": 0.0, "pressure": AMBIENT_PRESSURE}
    var node := nodes[node_index]
    var rated_gauge := maxf(
        float(node.rated_pressure) - AMBIENT_PRESSURE,
        1.0
    )
    var pressure_ratio := clampf(
        gauge_pressure(node_index) / rated_gauge,
        0.0,
        1.0
    )
    var demand := float(node.demand)
    var flow_ratio := 1.0
    if demand > 0.0:
        flow_ratio = clampf(float(node.served_flow) / demand, 0.0, 1.0)
    return {
        "pressure_ratio": pressure_ratio,
        "flow_ratio": flow_ratio,
        "pressure": float(node.pressure)
    }


func step(delta: float) -> void:
    if delta <= 0.0 or nodes.size() <= 1:
        return
    var safe_delta := clampf(delta, 0.001, 0.12)
    var substeps := _substep_count(safe_delta)
    var sub_delta := safe_delta / float(substeps)
    for _i in substeps:
        _integrate(sub_delta)


## Stiffness here is real: a small oil-filled line has a tiny capacitance and
## will ring apart under a frame-sized explicit step. Size the substep from
## the worst node rather than hoping 1/60 is enough.
func _substep_count(delta: float) -> int:
    var worst := INF
    for i in nodes.size():
        var node := nodes[i]
        if bool(node.fixed):
            continue
        var conductance_sum := 0.0
        for edge_index in _node_edges[i]:
            var edge := edges[edge_index]
            conductance_sum += float(edge.conductance) * float(edge.aperture)
            conductance_sum += _orifice_conductance(edge, i)
        if conductance_sum <= 0.0:
            continue
        worst = minf(worst, float(node.capacitance) / conductance_sum)
    if worst == INF or worst <= 0.0:
        return 1
    return clampi(
        int(ceil(delta / maxf(worst * SUBSTEP_SAFETY, 0.0001))),
        1,
        MAX_SUBSTEPS
    )


## An orifice is not a conductance, but for the purpose of asking "how fast
## can this node empty" it behaves like one at the current pressure, and
## that is what decides whether a frame-sized step is safe.
func _orifice_conductance(edge: Dictionary, node_index: int) -> float:
    var area := 0.0
    if int(edge.kind) == EDGE_RELIEF:
        if int(edge.a) != node_index or not bool(edge.open):
            return 0.0
        area = float(edge.orifice_area)
    else:
        area = float(edge.rupture_area)
    if area < MIN_LEAK_AREA:
        return 0.0
    var over := maxf(float(nodes[node_index].pressure) - AMBIENT_PRESSURE, 1.0)
    var density := maxf(float(nodes[node_index].density), 0.5)
    var discharge := DISCHARGE_COEFFICIENT * area * sqrt(2.0 * over / density)
    return discharge / over


func _integrate(delta: float) -> void:
    # Scratch arrays are kept between calls rather than reallocated every
    # substep - up to MAX_SUBSTEPS times a frame, forever - since the node
    # count only changes at setup.
    if _net_scratch.size() != nodes.size():
        _net_scratch.resize(nodes.size())
        _inflow_scratch.resize(nodes.size())
    var net := _net_scratch
    # Inflow is tracked separately from net because they answer different
    # questions: net decides pressure, arriving flow decides whether a
    # consumer is actually being fed at the rate it asked for.
    var inflow := _inflow_scratch
    for i in net.size():
        net[i] = 0.0
        inflow[i] = 0.0

    _total_leak_flow = 0.0

    for i in nodes.size():
        var node := nodes[i]
        node.served_flow = 0.0
        if not bool(node.pump_enabled) or float(node.pump_pressure) <= 0.0:
            node.pump_flow = 0.0
            continue
        var head := float(node.pump_pressure) - float(node.pressure)
        if head <= 0.0:
            node.pump_flow = 0.0
            continue
        # Compensated pumps swash over to hold the set point. Below it they
        # deliver everything they have, and that ceiling is what a big
        # enough hole beats.
        var delivered := minf(
            float(node.pump_max_flow),
            head / maxf(float(node.pump_pressure) - AMBIENT_PRESSURE, 1.0)
            * float(node.pump_max_flow)
            * 4.0
        )
        var source := int(node.pump_source)
        if source >= 0 and source < nodes.size():
            var remaining := float(nodes[source].stored)
            # A negative store means "not tracked"; an empty tracked one
            # means the pump is pulling on air and delivers nothing.
            if remaining >= 0.0 and remaining <= 0.0:
                delivered = 0.0
        node.pump_flow = maxf(delivered, 0.0)
        net[i] += node.pump_flow
        inflow[i] += node.pump_flow

    for edge_index in edges.size():
        var edge := edges[edge_index]
        var a := int(edge.a)
        var b := int(edge.b)
        if int(edge.kind) == EDGE_RELIEF:
            _step_relief(edge, a, net, delta)
            continue

        var pressure_a := float(nodes[a].pressure)
        var pressure_b := float(nodes[b].pressure)
        var conductance := float(edge.conductance) * float(edge.aperture)
        var flow := conductance * (pressure_a - pressure_b)
        edge.flow = flow
        net[a] -= flow
        net[b] += flow
        if flow >= 0.0:
            inflow[b] += flow
        else:
            inflow[a] -= flow

        var area := float(edge.rupture_area)
        if area < MIN_LEAK_AREA:
            edge.leak_flow = 0.0
            continue
        # The hole sits somewhere along the run, so it sees roughly the mean
        # of the two ends and drains both of them.
        var mean_pressure := (pressure_a + pressure_b) * 0.5
        var over := mean_pressure - AMBIENT_PRESSURE
        if over <= 0.0:
            edge.leak_flow = 0.0
            continue
        var density := maxf(float(nodes[a].density), 0.5)
        var escape := (
            DISCHARGE_COEFFICIENT * area * sqrt(2.0 * over / density)
        )
        edge.leak_flow = escape
        _total_leak_flow += escape
        var gauge_a := maxf(pressure_a - AMBIENT_PRESSURE, 0.0)
        var gauge_b := maxf(pressure_b - AMBIENT_PRESSURE, 0.0)
        var share := gauge_a / maxf(gauge_a + gauge_b, 0.0001)
        net[a] -= escape * share
        net[b] -= escape * (1.0 - share)

    for i in nodes.size():
        var node := nodes[i]
        if int(node.kind) != KIND_SUPPLY:
            continue
        var demand := float(node.demand)
        if demand <= 0.0:
            continue
        # An actuator cannot pull oil out of a dead line: what it draws is
        # capped by how much of its working pressure is actually there.
        var rated_gauge := maxf(
            float(node.rated_pressure) - AMBIENT_PRESSURE,
            1.0
        )
        var available := clampf(
            gauge_pressure(i) / rated_gauge,
            0.0,
            1.0
        )
        net[i] -= demand * available
        # What the branch actually delivered to this point. When the pump is
        # saturated - by a breach, or by another machine - this falls short
        # of the demand even while the pressure still reads well, and that
        # shortfall is a speed limit rather than a force limit.
        node.served_flow = minf(demand, maxf(inflow[i], 0.0))

    for i in nodes.size():
        var node := nodes[i]
        if bool(node.fixed):
            continue
        var change := net[i] / maxf(float(node.capacitance), 1.0e-12) * delta
        node.pressure = maxf(
            AMBIENT_PRESSURE,
            float(node.pressure) + change
        )
        if float(node.stored) >= 0.0:
            node.stored = maxf(0.0, float(node.stored) + net[i] * delta)

    if _total_leak_flow > 0.0:
        _spilled_volume += _total_leak_flow * delta
        _drain_inventory(_total_leak_flow * delta)


## What leaves through a hole came out of a tank somewhere. Draining the
## reservoir is what makes a long unattended leak a permanent loss rather
## than an infinite fountain.
func _drain_inventory(volume: float) -> void:
    for node in nodes:
        if int(node.kind) != KIND_RESERVOIR:
            continue
        if float(node.stored) < 0.0:
            continue
        node.stored = maxf(0.0, float(node.stored) - volume)
        return


func _step_relief(
        edge: Dictionary,
        from_index: int,
        net: Array[float],
        _delta: float
) -> void:
    var pressure := float(nodes[from_index].pressure)
    if bool(edge.open):
        if pressure <= float(edge.reseat_pressure):
            edge.open = false
    elif pressure >= float(edge.crack_pressure):
        edge.open = true
    edge.aperture = 1.0 if bool(edge.open) else 0.0
    if not bool(edge.open):
        edge.flow = 0.0
        return
    var over := pressure - AMBIENT_PRESSURE
    if over <= 0.0:
        edge.flow = 0.0
        return
    var density := maxf(float(nodes[from_index].density), 0.5)
    var discharge := (
        DISCHARGE_COEFFICIENT
        * float(edge.orifice_area)
        * sqrt(2.0 * over / density)
    )
    edge.flow = discharge
    net[from_index] -= discharge


## Everything the network can still reach from a live source, walking only
## through paths that are actually open. This is what "isolated" means here:
## not a flag on a branch, but a branch the source can no longer get to.
## `forced_edge` answers "what would this reach if that valve were open"
## without opening it, so a planner can weigh a move it has not made.
func reachable_from(
        source: int,
        blocked_edge: int = -1,
        forced_edge: int = -1
) -> Dictionary:
    var seen := {}
    if source < 0 or source >= nodes.size():
        return seen
    var queue: Array[int] = [source]
    seen[source] = true
    while not queue.is_empty():
        var current: int = queue.pop_front()
        for edge_index in edges.size():
            if edge_index == blocked_edge:
                continue
            var edge := edges[edge_index]
            if int(edge.kind) == EDGE_RELIEF:
                continue
            if float(edge.aperture) < MIN_APERTURE and edge_index != forced_edge:
                continue
            var a := int(edge.a)
            var b := int(edge.b)
            var next := -1
            if a == current:
                next = b
            elif b == current:
                next = a
            if next < 0 or seen.has(next):
                continue
            if next == _ambient_index:
                continue
            seen[next] = true
            queue.append(next)
    return seen


func edge_is_fed(edge_index: int, reachable: Dictionary) -> bool:
    if edge_index < 0 or edge_index >= edges.size():
        return false
    var edge := edges[edge_index]
    return reachable.has(int(edge.a)) or reachable.has(int(edge.b))


func leaking_edges() -> Array[int]:
    var result: Array[int] = []
    for edge_index in edges.size():
        if float(edges[edge_index].leak_flow) > 0.0:
            result.append(edge_index)
    return result


func valve_edges() -> Array[int]:
    var result: Array[int] = []
    for edge_index in edges.size():
        if int(edges[edge_index].kind) == EDGE_VALVE:
            result.append(edge_index)
    return result


func supply_nodes() -> Array[int]:
    var result: Array[int] = []
    for i in nodes.size():
        if int(nodes[i].kind) == KIND_SUPPLY:
            result.append(i)
    return result

