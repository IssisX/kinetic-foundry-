extends Node

## The seam between physical events and material state.
##
## Solvers, machines and bodies report what physically happened, in physical
## quantities. This resolver is the only thing that turns those events into
## surface history, the only producer of `physical_event`, and the only
## author of contact effects. Shaders and audio never query the physics
## engine themselves; they read the state written here.

const FoundryMaterial = preload("res://scripts/foundry_material.gd")
const EnergyPartition = preload("res://scripts/energy_partition.gd")
const SurfaceState = preload("res://scripts/surface_state.gd")
const ModalResonator = preload("res://scripts/modal_resonator.gd")
const ImpactFxScript = preload("res://scripts/impact_fx.gd")
const MaterialFxScript = preload("res://scripts/material_fx.gd")

const EVENT_IMPACT := "impact"
const EVENT_SCRAPE := "scrape"
const EVENT_MACHINE := "machine_contact"
const EVENT_FRACTURE := "fracture"
const EVENT_COLLAPSE := "collapse"
const EVENT_HYDRAULIC := "hydraulic"

const DECAY_INTERVAL := 0.1
const SPARK_SLIDE_SPEED := 1.5
const LIVE_FX_BUDGET := 24
const MIN_AUDIBLE_ENERGY := 8.0
## Sliding work is continuous. It is reported as an event once it has
## accumulated enough to be worth hearing, carrying the work it represents.
const SCRAPE_EVENT_JOULES := 420.0

var _surfaces: Dictionary = {}
var _scrape_bank: Dictionary = {}
var _resonators: Dictionary = {}
var _decay_clock := 0.0
var _live_fx := 0
var _events_this_second := 0
var _event_clock := 0.0
var _event_rate := 0.0
var _emitting := false


func _ready() -> void:
    process_mode = Node.PROCESS_MODE_ALWAYS


func _process(delta: float) -> void:
    _event_clock += delta
    if _event_clock >= 1.0:
        _event_rate = float(_events_this_second) / _event_clock
        _events_this_second = 0
        _event_clock = 0.0

    _step_resonators(delta)

    _decay_clock += delta
    if _decay_clock < DECAY_INTERVAL:
        return
    var elapsed := _decay_clock
    _decay_clock = 0.0
    _tick_surfaces(elapsed)


func register(
        target: Object,
        material_id: int,
        tint: Color = Color(0.0, 0.0, 0.0, 0.0)
) -> SurfaceState:
    if target == null:
        return null
    var key := target.get_instance_id()
    var existing: Dictionary = _surfaces.get(key, {})
    if not existing.is_empty():
        var state: SurfaceState = existing.get("state")
        state.configure(material_id, tint)
        return state
    var created := SurfaceState.new()
    created.configure(material_id, tint)
    _surfaces[key] = {"ref": weakref(target), "state": created}
    return created


func state_for(target: Object, default_material: int = FoundryMaterial.STRUCTURAL_STEEL) -> SurfaceState:
    if target == null:
        return null
    var entry: Dictionary = _surfaces.get(target.get_instance_id(), {})
    if entry.is_empty():
        return register(target, default_material)
    return entry.get("state")


func material_of(target: Object, fallback: int = FoundryMaterial.STRUCTURAL_STEEL) -> int:
    if target == null:
        return fallback
    var entry: Dictionary = _surfaces.get(target.get_instance_id(), {})
    if entry.is_empty():
        return fallback
    var state: SurfaceState = entry.get("state")
    return state.material_id


func forget(target: Object) -> void:
    if target == null:
        return
    _surfaces.erase(target.get_instance_id())


## Normal loading. Permanent set and a little scale loss, plus the heat the
## plastic work actually produced.
func impact(
        target: Object,
        world_point: Vector3,
        direction: Vector3,
        energy: float,
        mass: float,
        tool_material: int = FoundryMaterial.HARDENED_STEEL,
        options: Dictionary = {}
) -> Dictionary:
    var terms := EnergyPartition.split(energy)
    if float(terms.input) <= 0.0:
        return terms

    var state := state_for(target, int(options.get("material", FoundryMaterial.STRUCTURAL_STEEL)))
    var area := maxf(float(options.get("area", 0.06)), 0.0008)
    var pairing := FoundryMaterial.pair(int(options.get("material", material_of(target))), tool_material)

    if state != null:
        state.deposit_plastic(float(terms.plastic), maxf(mass, 1.0))
        state.deposit_abrasion(
            float(terms.fracture) * 0.12,
            area,
            float(pairing.abrasion_share_a)
        )
        state.deposit_heat(float(terms.plastic) * 0.35, maxf(mass, 1.0))

    var consequence := _consequence(
        state,
        terms,
        pairing,
        0.0,
        area,
        float(options.get("fracture", 0.0))
    )
    _excite(target, mass, float(terms.acoustic))
    _spawn_effects(target, world_point, direction, state, consequence, pairing)
    _emit(
        str(options.get("type", EVENT_IMPACT)),
        world_point,
        direction,
        terms,
        mass,
        state,
        consequence,
        options
    )
    return consequence


## Two bodies met. The resolver owns the joules; the callers own gameplay
## damage. Relative speed and the two masses are the only inputs.
func collide(
        striker: Object,
        struck: Object,
        world_point: Vector3,
        direction: Vector3,
        relative_speed: float,
        options: Dictionary = {}
) -> Dictionary:
    var mass_a := mass_of(striker)
    var mass_b := mass_of(struck)
    var energy := EnergyPartition.collision_energy(
        mass_a,
        mass_b,
        relative_speed
    )
    if energy <= 0.0:
        return {}
    var merged := options.duplicate()
    if not merged.has("radius"):
        merged["radius"] = clampf(sqrt(energy) * 0.085, 2.4, 14.0)
    if not merged.has("area"):
        merged["area"] = 0.12
    var consequence := impact(
        struck,
        world_point,
        direction,
        energy,
        mass_a,
        int(merged.get("tool_material", material_of(striker))),
        merged
    )
    consequence["energy"] = energy
    consequence["mass_a"] = mass_a
    consequence["mass_b"] = mass_b
    return consequence


func mass_of(body: Object) -> float:
    if body == null:
        return EnergyPartition.IMMOVABLE_MASS
    if body is RigidBody3D:
        return maxf((body as RigidBody3D).mass, 1.0)
    var value = body.get("mass")
    if value != null:
        return maxf(float(value), 1.0)
    var machine_mass = body.get("machine_mass")
    if machine_mass != null:
        return maxf(float(machine_mass), 1.0)
    return EnergyPartition.IMMOVABLE_MASS


## Sliding contact. Friction work removes coating along the real trajectory
## and heats what is left behind.
func scrape(
        target: Object,
        world_point: Vector3,
        direction: Vector3,
        normal_force: float,
        slide_speed: float,
        delta: float,
        tool_material: int = FoundryMaterial.HARDENED_STEEL,
        options: Dictionary = {}
) -> Dictionary:
    var target_material := int(options.get("material", material_of(target)))
    var pairing := FoundryMaterial.pair(target_material, tool_material)
    var work := (
        maxf(normal_force, 0.0)
        * float(pairing.friction)
        * maxf(slide_speed, 0.0)
        * maxf(delta, 0.0)
    )
    var terms := EnergyPartition.split(work)
    if work <= 0.0:
        return terms

    var state := state_for(target, target_material)
    var area := maxf(float(options.get("area", 0.04)), 0.0008)
    if state != null:
        state.deposit_abrasion(work * 0.55, area, float(pairing.abrasion_share_a))
        state.deposit_heat(work * 0.40, maxf(float(options.get("mass", 120.0)), 1.0))

    var tool_state: SurfaceState = options.get("tool_state")
    if tool_state != null:
        tool_state.deposit_abrasion(work * 0.18, area, float(pairing.abrasion_share_b))
        if state != null:
            state.transfer_to(tool_state, 0.08)

    var consequence := _consequence(state, terms, pairing, slide_speed, area, 0.0)
    _spawn_effects(target, world_point, direction, state, consequence, pairing)

    var key := target.get_instance_id() if target != null else 0
    var banked := float(_scrape_bank.get(key, 0.0)) + work
    if banked >= SCRAPE_EVENT_JOULES:
        _scrape_bank[key] = 0.0
        _emit(
            EVENT_SCRAPE,
            world_point,
            direction,
            EnergyPartition.split(banked),
            float(options.get("mass", 120.0)),
            state,
            consequence,
            options
        )
    else:
        _scrape_bank[key] = banked
    return consequence


## Topology actually changed. The surface energy the solver paid is the
## energy this event is allowed to spend.
func fracture(
        target: Object,
        world_point: Vector3,
        direction: Vector3,
        surface_energy: float,
        mass: float,
        options: Dictionary = {}
) -> Dictionary:
    var terms := EnergyPartition.split(surface_energy)
    var state := state_for(target, int(options.get("material", material_of(target))))
    if state != null:
        state.set_fracture_proximity(1.0)
        state.deposit_heat(float(terms.plastic) * 0.25, maxf(mass, 1.0))
    var pairing := FoundryMaterial.pair(
        material_of(target),
        int(options.get("tool_material", FoundryMaterial.HARDENED_STEEL))
    )
    var consequence := _consequence(state, terms, pairing, 0.0, 0.35, 1.0)
    consequence["splinters"] = clampi(
        int(float(terms.fracture) / 620.0) + 2,
        2,
        9
    )
    _spawn_effects(target, world_point, direction, state, consequence, pairing)
    _emit(
        str(options.get("type", EVENT_FRACTURE)),
        world_point,
        direction,
        terms,
        mass,
        state,
        consequence,
        options
    )
    return consequence


## Load that passes through a body into whatever is underneath it. The pad
## under a failing column, the ground under a track, the floor under a
## dropped load: the surface that receives it decides what it looks like.
func impact_below(
        from: Vector3,
        direction: Vector3,
        energy: float,
        mass: float,
        options: Dictionary = {}
) -> Dictionary:
    var landed := _raycast_down(from, float(options.get("reach", 4.0)))
    if landed.is_empty():
        return {}
    var body: Object = landed.get("collider")
    var point: Vector3 = landed.get("position", from)
    var merged := options.duplicate()
    merged["material"] = int(options.get("material", FoundryMaterial.CONCRETE))
    if not merged.has("radius"):
        merged["radius"] = 3.0
    return impact(
        body,
        point,
        direction,
        energy,
        mass,
        int(options.get("tool_material", FoundryMaterial.STRUCTURAL_STEEL)),
        merged
    )


func heat(target: Object, joules: float, mass: float, material_hint: int = FoundryMaterial.STRUCTURAL_STEEL) -> void:
    var state := state_for(target, material_hint)
    if state == null:
        return
    state.deposit_heat(joules, mass)


## A leak is a fluid source, not a particle burst. What it reaches keeps it.
func fluid_leak(
        source: Object,
        world_point: Vector3,
        direction: Vector3,
        fluid_id: int,
        amount: float,
        options: Dictionary = {}
) -> void:
    if amount <= 0.0:
        return
    var source_state := state_for(source, material_of(source))
    if source_state != null:
        source_state.deposit_fluid(fluid_id, amount * 0.45)

    var landed := _raycast_down(world_point, float(options.get("reach", 6.0)))
    if not landed.is_empty():
        var floor_body: Object = landed.get("collider")
        var floor_state := state_for(
            floor_body,
            int(options.get("floor_material", FoundryMaterial.ASPHALT))
        )
        if floor_state != null:
            floor_state.deposit_fluid(fluid_id, amount)

    if _live_fx < LIVE_FX_BUDGET:
        _live_fx += 1
        MaterialFxScript.hydraulic(
            _fx_parent(source),
            world_point,
            direction,
            clampf(amount * 4.0, 0.6, 4.5)
        )
        _release_fx_later()

    _emit(
        EVENT_HYDRAULIC,
        world_point,
        direction,
        EnergyPartition.split(amount * 900.0),
        float(options.get("mass", 40.0)),
        source_state,
        {"sparks": 0, "dust": 0, "splinters": 0},
        {"material": fluid_id, "radius": 3.2}
    )


## Films redistribute when two surfaces rub. Nothing else crosses.
func fluid_contact(first: Object, second: Object, ratio: float) -> void:
    var a := state_for(first, material_of(first))
    var b := state_for(second, material_of(second))
    if a == null or b == null:
        return
    a.transfer_to(b, ratio)


## A piece that breaks off is the same material with the same history. Its
## torn faces are the only new surface on it.
func adopt_fragment(
        fragment: Object,
        parent_state: SurfaceState,
        interior_ratio: float = 0.5
) -> SurfaceState:
    if fragment == null:
        return null
    if parent_state == null:
        return register(fragment, FoundryMaterial.STRUCTURAL_STEEL)
    var inherited := parent_state.clone_for_fragment(interior_ratio)
    _surfaces[fragment.get_instance_id()] = {
        "ref": weakref(fragment),
        "state": inherited
    }
    return inherited


func traction_at(target: Object) -> float:
    var entry: Dictionary = _surfaces.get(
        target.get_instance_id() if target != null else 0,
        {}
    )
    if entry.is_empty():
        return 1.0
    var state: SurfaceState = entry.get("state")
    return state.traction_scale()


## What this substrate currently costs, for the performance bill.
func get_cost_bill() -> Dictionary:
    var films := 0
    for key in _surfaces:
        var entry: Dictionary = _surfaces[key]
        var state: SurfaceState = entry.get("state")
        if state.oil > 0.01 or state.water > 0.01 or state.soot > 0.01:
            films += 1
    return {
        "surfaces": _surfaces.size(),
        "films": films,
        "events_per_second": _event_rate,
        "live_fx": _live_fx
    }


func _tick_surfaces(delta: float) -> void:
    var dead: Array[int] = []
    for key in _surfaces:
        var entry: Dictionary = _surfaces[key]
        var ref: WeakRef = entry.get("ref")
        if ref == null or ref.get_ref() == null:
            dead.append(key)
            continue
        var state: SurfaceState = entry.get("state")
        state.tick(delta)
    for key in dead:
        _surfaces.erase(key)
        _scrape_bank.erase(key)
        _resonators.erase(key)


## Lazily created only for bodies something has actually excited, keyed off
## the same catalog identity as everything else - a hardened tool rings
## differently than concrete because it is registered as different steel,
## not because it has a second, private frequency table.
func _resonator_for(target: Object) -> ModalResonator:
    if target == null:
        return null
    var key := target.get_instance_id()
    var existing: ModalResonator = _resonators.get(key)
    if existing != null:
        return existing
    var data := FoundryMaterial.of(material_of(target))
    var base_hz := float(data.get("ring_hz", 285.0))
    var created := ModalResonator.new()
    created.configure(
        [base_hz * 0.55, base_hz * 0.87, base_hz * 1.4],
        [0.045, 0.05, 0.065]
    )
    _resonators[key] = created
    return created


## Public seam for transmitted vibration that should ring a body without
## touching its surface history - a support hit shaking the deck it holds
## up, not a direct contact on the deck's own face.
func excite_resonance(target: Object, mass: float, energy: float) -> void:
    _excite(target, mass, float(EnergyPartition.split(energy).acoustic))


func _excite(target: Object, mass: float, acoustic_energy: float) -> void:
    if target == null or acoustic_energy <= 0.0:
        return
    # Same E -> velocity relation used everywhere else in this game
    # (EnergyPartition.kinetic_impulse), applied to a small effective modal
    # mass rather than the whole body: only a fraction of a plate actually
    # participates in any one vibration mode.
    var modal_mass := maxf(mass * 0.02, 0.5)
    var kick := sqrt(2.0 * acoustic_energy / modal_mass)
    _resonator_for(target).excite(kick)


func _step_resonators(delta: float) -> void:
    for key in _resonators:
        (_resonators[key] as ModalResonator).step(delta)


## A component that fractures does not hand its shards the parent's ring.
func kill_resonance(target: Object) -> void:
    if target == null:
        return
    var res: ModalResonator = _resonators.get(target.get_instance_id())
    if res != null:
        res.kill()


## Meters of normal-offset shimmer. The velocity-kick derivation in
## _excite already yields a physically-scaled displacement in meters (a
## moderate hit rings low-single-digit millimeters, a full collapse peaks
## close to the clamp) - this only guards the shader uniform against an
## unbounded value, it does not re-scale the physics.
func resonance_shimmer(target: Object) -> float:
    if target == null:
        return 0.0
    var res: ModalResonator = _resonators.get(target.get_instance_id())
    if res == null:
        return 0.0
    return clampf(res.amplitude(), -0.012, 0.012)


func _consequence(
        state: SurfaceState,
        terms: Dictionary,
        pairing: Dictionary,
        slide_speed: float,
        area: float,
        fracture_ratio: float
) -> Dictionary:
    var acoustic := float(terms.acoustic)
    var sparks := 0
    if bool(pairing.spark) and slide_speed >= SPARK_SLIDE_SPEED:
        sparks = clampi(int(acoustic / 2.4) + 1, 1, 10)
    var dust := 0
    var dust_factor := 0.0
    if state != null:
        dust_factor = float(state.profile().get("dust", 0.0))
    if dust_factor > 0.0:
        dust = clampi(int(float(terms.fracture) * dust_factor / 260.0), 0, 14)
    return {
        "input": float(terms.input),
        "acoustic": acoustic,
        "surface": float(terms.fracture),
        "plastic": float(terms.plastic),
        "kinetic": float(terms.kinetic),
        "sparks": sparks,
        "dust": dust,
        "splinters": 0,
        "grit": float(pairing.grit),
        "ring": float(pairing.ring),
        "fracture": clampf(fracture_ratio, 0.0, 1.0),
        "area": area
    }


func _spawn_effects(
        target: Object,
        world_point: Vector3,
        direction: Vector3,
        state: SurfaceState,
        consequence: Dictionary,
        _pairing: Dictionary
) -> void:
    if _live_fx >= LIVE_FX_BUDGET:
        return
    if float(consequence.get("input", 0.0)) < MIN_AUDIBLE_ENERGY:
        return
    var parent := _fx_parent(target)
    if parent == null:
        return
    var aim := direction
    if aim.length_squared() < 0.0001:
        aim = Vector3.UP

    var sparks := int(consequence.get("sparks", 0))
    if sparks > 0:
        _live_fx += 1
        var glow := Color(1.0, 0.52, 0.10)
        if state != null and state.oil > 0.25:
            glow = Color(1.0, 0.36, 0.05)
        ImpactFxScript.spawn(
            parent,
            world_point,
            aim,
            glow,
            clampf(float(consequence.acoustic) * 0.22, 0.6, 4.0),
            clampi(sparks, 4, 14)
        )
        _release_fx_later()

    var dust := int(consequence.get("dust", 0))
    if dust > 0 and _live_fx < LIVE_FX_BUDGET:
        _live_fx += 1
        MaterialFxScript.concrete(
            parent,
            world_point,
            aim,
            clampf(float(dust) * 0.30, 0.7, 4.2)
        )
        _release_fx_later()

    var splinters := int(consequence.get("splinters", 0))
    if splinters > 0 and _live_fx < LIVE_FX_BUDGET:
        _live_fx += 1
        var shard_colour := Color(0.42, 0.40, 0.36)
        if state != null:
            shard_colour = state.profile().get("fracture_face", shard_colour)
        ImpactFxScript.spawn(
            parent,
            world_point,
            aim,
            shard_colour,
            clampf(float(consequence.surface) / 900.0, 0.7, 4.6),
            clampi(splinters, 4, 16)
        )
        _release_fx_later()


func _release_fx_later() -> void:
    var timer := get_tree().create_timer(1.6)
    timer.timeout.connect(_on_fx_released)


func _on_fx_released() -> void:
    _live_fx = maxi(0, _live_fx - 1)


func _emit(
        event_type: String,
        world_point: Vector3,
        direction: Vector3,
        terms: Dictionary,
        mass: float,
        state: SurfaceState,
        consequence: Dictionary,
        options: Dictionary
) -> void:
    if _emitting:
        return
    _emitting = true
    var material_id := FoundryMaterial.STRUCTURAL_STEEL
    if state != null:
        material_id = state.material_id
    if options.has("material"):
        material_id = int(options.material)

    _events_this_second += 1
    get_tree().call_group(
        "physical_event_listener",
        "physical_event",
        {
            "type": event_type,
            "position": world_point,
            "direction": direction,
            "impulse": EnergyPartition.kinetic_impulse(mass, float(terms.input)),
            "mass": maxf(mass, 1.0),
            "fracture": float(consequence.get("fracture", 0.0)),
            "radius": float(options.get("radius", 4.0)),
            "novelty": clampf(float(options.get("novelty", 0.7)), 0.0, 1.0),
            "material": FoundryMaterial.name_of(material_id).to_lower(),
            "material_id": material_id,
            "energy_in": float(terms.input),
            "acoustic_energy": float(terms.acoustic),
            "surface_energy": float(terms.fracture),
            "plastic_energy": float(terms.plastic),
            "kinetic_energy": float(terms.kinetic),
            "grit": float(consequence.get("grit", 0.2)),
            "ring": float(consequence.get("ring", 0.6))
        }
    )
    _emitting = false


func _fx_parent(target: Object) -> Node:
    if target is Node3D:
        var node := target as Node3D
        if node.is_inside_tree():
            var parent := node.get_parent()
            if parent != null:
                return parent
    if get_tree() == null:
        return null
    return get_tree().current_scene


func _raycast_down(from: Vector3, reach: float) -> Dictionary:
    var tree := get_tree()
    if tree == null or tree.root == null:
        return {}
    var world := tree.root.get_world_3d()
    if world == null:
        return {}
    var query := PhysicsRayQueryParameters3D.create(
        from,
        from + Vector3.DOWN * maxf(reach, 0.1),
        1 | 2 | 4 | 8
    )
    query.collide_with_areas = false
    return world.direct_space_state.intersect_ray(query)
