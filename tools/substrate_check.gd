extends SceneTree

## Headless acceptance for the material substrate.
##
## Run: ./tools/godot --headless --script tools/substrate_check.gd
## Each check states the physical claim it is defending. A claim that cannot
## fail is not a check, so every one of these compares two histories that
## the old single-scalar damage model could not tell apart.

var _failures := 0


func _initialize() -> void:
    _check_sliding_differs_from_striking()
    _check_thermal_history_outlives_temperature()
    _check_paint_order()
    _check_fragment_inherits_history()
    _check_oil_transfers_and_costs_traction()
    _check_energy_partition_sums()
    _check_identity_is_shared()

    if _failures == 0:
        print("SUBSTRATE_CHECK_OK")
        quit(0)
        return
    print("SUBSTRATE_CHECK_FAILED count=", _failures)
    quit(1)


func _expect(condition: bool, claim: String) -> void:
    if condition:
        print("  ok   ", claim)
        return
    _failures += 1
    print("  FAIL ", claim)


func _fresh(id: int) -> SurfaceState:
    var state := SurfaceState.new()
    state.configure(id)
    return state


## The same joules delivered by grinding and by one strike must not produce
## the same surface. Sliding work takes coating off; normal loading sets it.
func _check_sliding_differs_from_striking() -> void:
    print("sliding work and normal loading are different histories")
    var total := 12000.0
    var ground := _fresh(FoundryMaterial.PAINTED_STEEL)
    for i in 40:
        ground.deposit_abrasion(total / 40.0, 0.04)
    var struck := _fresh(FoundryMaterial.PAINTED_STEEL)
    struck.deposit_plastic(total, 180.0)
    struck.deposit_abrasion(total * 0.12, 0.04)

    _expect(
        ground.exposure > struck.exposure * 2.0,
        "grinding strips more coating than a strike of equal energy"
    )
    _expect(
        struck.plasticity > ground.plasticity,
        "the strike leaves permanent set the grind does not"
    )


## Glow is not damage. One decays in seconds, the other destroyed the paint.
func _check_thermal_history_outlives_temperature() -> void:
    print("current temperature and thermal history are separate channels")
    var state := _fresh(FoundryMaterial.PAINTED_STEEL)
    # A sustained fire on one 5 kg painted member, not the whole frame.
    state.deposit_heat(600000.0, 5.0)
    var hot := state.current_temperature
    var peak := state.thermal_history
    var burned := state.exposure
    _expect(hot > 0.0 and peak >= hot, "heating raises both channels")
    _expect(burned > 0.0, "heat past the coating limit destroys the paint")

    for i in 200:
        state.tick(0.1)
    _expect(
        state.current_temperature < hot * 0.05,
        "temperature falls away once the heat source is gone"
    )
    _expect(
        is_equal_approx(state.thermal_history, peak),
        "thermal history does not cool off"
    )
    _expect(
        state.exposure >= burned,
        "paint destroyed by heat does not come back"
    )


## Paint, primer, substrate, oxide is an order, not a blend of everything.
func _check_paint_order() -> void:
    print("coating wears through in physical order")
    var state := _fresh(FoundryMaterial.PAINTED_STEEL)
    state.tint = Color(0.62, 0.47, 0.10, 1.0)
    var intact := state.composite_albedo()
    var intact_metallic := state.composite_metallic()

    state.exposure = 0.30
    var primed := state.composite_albedo()
    state.exposure = 1.0
    var bare := state.composite_albedo()
    var bare_metallic := state.composite_metallic()
    state.oxidation = 1.0
    var rusted := state.composite_albedo()

    _expect(
        intact.r > primed.r or intact.g > primed.g,
        "paint darkens toward primer as it wears"
    )
    _expect(
        bare.b > primed.b,
        "bare steel is less red than the primer under the paint"
    )
    _expect(
        bare_metallic > intact_metallic,
        "stripping paint uncovers metal, so metallic rises"
    )
    _expect(
        state.composite_metallic() < bare_metallic,
        "rust is a dielectric, so oxidation takes metallic back down"
    )
    _expect(rusted.r > rusted.b, "oxide reads warm")


## A piece that breaks off is the same material with the same past.
func _check_fragment_inherits_history() -> void:
    print("history survives the break")
    var parent := _fresh(FoundryMaterial.PAINTED_STEEL)
    parent.tint = Color(0.62, 0.47, 0.10, 1.0)
    parent.deposit_abrasion(9000.0, 0.05)
    parent.deposit_heat(200000.0, 40.0)
    parent.deposit_fluid(FoundryMaterial.SOOT, 0.6)

    var shard := parent.clone_for_fragment(0.7)
    _expect(shard.material_id == parent.material_id, "identity survives")
    _expect(
        is_equal_approx(shard.exposure, parent.exposure),
        "worn coating survives onto the shard"
    )
    _expect(
        is_equal_approx(shard.thermal_history, parent.thermal_history),
        "thermal history survives onto the shard"
    )
    _expect(shard.soot > 0.0, "contamination survives onto the shard")
    _expect(
        shard.fresh_fracture > 0.0,
        "the torn face is new material and says so"
    )
    _expect(
        shard.composite_albedo() != parent.composite_albedo(),
        "a shard showing fresh interior does not look like its parent's skin"
    )


## One leak becomes several consequences, including a mechanical one.
func _check_oil_transfers_and_costs_traction() -> void:
    print("films move by contact and cost traction")
    var floor_state := _fresh(FoundryMaterial.CONCRETE)
    var track := _fresh(FoundryMaterial.RUBBER)
    floor_state.deposit_fluid(FoundryMaterial.HYDRAULIC_FLUID, 0.9)
    var before := floor_state.oil
    _expect(before > 0.0, "porous concrete holds the fluid it is given")
    _expect(
        floor_state.traction_scale() < 1.0,
        "an oiled surface is worth less grip"
    )

    floor_state.transfer_to(track, 0.25)
    _expect(track.oil > 0.0, "a track passing through it picks some up")
    _expect(
        floor_state.oil < before,
        "what the track took is no longer on the floor"
    )

    var steel := _fresh(FoundryMaterial.STRUCTURAL_STEEL)
    steel.deposit_fluid(FoundryMaterial.HYDRAULIC_FLUID, 0.9)
    _expect(
        steel.oil < floor_state.oil + track.oil,
        "steel beads oil where concrete soaks it"
    )


func _check_energy_partition_sums() -> void:
    print("impact energy is divided once")
    var terms := EnergyPartition.split(10000.0)
    var total := (
        float(terms.fracture)
        + float(terms.kinetic)
        + float(terms.plastic)
        + float(terms.acoustic)
        + float(terms.residual)
    )
    _expect(
        is_equal_approx(total, float(terms.input)),
        "the shares account for the whole input and no more"
    )
    _expect(
        EnergyPartition.split(1.0e9).input <= EnergyPartition.MAX_EVENT_ENERGY,
        "a single event cannot spend unbounded energy"
    )
    var closing := EnergyPartition.collision_energy(360.0, 85.0, 6.0)
    _expect(
        closing > 0.0 and closing < 0.5 * 360.0 * 36.0,
        "closing energy uses reduced mass, not the heavier body alone"
    )


## The renderer, the fracture graph and the audio bank must not disagree
## about what a surface is made of.
func _check_identity_is_shared() -> void:
    print("one identity resolves into several domain profiles")
    var concrete := FoundryMaterial.of(FoundryMaterial.CONCRETE)
    var steel := FoundryMaterial.of(FoundryMaterial.STRUCTURAL_STEEL)
    _expect(
        float(concrete.grit_gain) > float(steel.grit_gain),
        "concrete is grittier than steel to the audio layer"
    )
    _expect(
        float(concrete.surface_energy) < float(steel.surface_energy),
        "concrete is cheaper to fracture than steel to the solver"
    )
    _expect(
        float(concrete.dust) > float(steel.dust),
        "concrete makes dust and steel does not, to the effects layer"
    )
    _expect(
        float(concrete.oil_affinity) > float(steel.oil_affinity),
        "concrete soaks oil and steel does not, to the contamination layer"
    )
    _expect(
        FoundryMaterial.id_from_legacy("concrete") == FoundryMaterial.CONCRETE,
        "legacy string tags resolve into the shared identity"
    )
    var pairing := FoundryMaterial.pair(
        FoundryMaterial.STRUCTURAL_STEEL,
        FoundryMaterial.HARDENED_STEEL
    )
    _expect(bool(pairing.spark), "two hard ferrous bodies can spark")
    _expect(
        not bool(FoundryMaterial.pair(
            FoundryMaterial.CONCRETE,
            FoundryMaterial.RUBBER
        ).spark),
        "rubber on concrete cannot"
    )
    _expect(
        float(pairing.abrasion_share_a) > float(pairing.abrasion_share_b),
        "the softer of the pair pays more of the abrasion"
    )
