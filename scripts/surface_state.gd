class_name SurfaceState
extends RefCounted

const FoundryMaterial = preload("res://scripts/foundry_material.gd")

## What has happened to one surface, kept as independent physical channels.
##
## Damage is never reduced to a single scalar here. Each channel has its own
## deposition, transport, decay and persistence law, because each has a
## different physical cause: current temperature falls in seconds, the paint
## it destroyed never comes back, water evaporates, oil transfers by contact,
## plastic set is permanent, and a fracture changes topology rather than
## shading.

const PERSISTENT_EPSILON := 0.0008

var material_id := FoundryMaterial.STRUCTURAL_STEEL
## What this particular body was painted. The catalog owns what is under
## the paint; the yard owns the paint itself.
var tint := Color(0.0, 0.0, 0.0, 0.0)

var exposure := 0.0
var plasticity := 0.0
var fracture_proximity := 0.0
var current_temperature := 0.0
var thermal_history := 0.0
var soot := 0.0
var oil := 0.0
var water := 0.0
var dirt := 0.0
var oxidation := 0.0
var fresh_fracture := 0.0

var abrasion_work := 0.0
var revision := 0


func configure(id: int, authored_tint: Color = Color(0.0, 0.0, 0.0, 0.0)) -> void:
    material_id = id
    if authored_tint.a > 0.0:
        tint = authored_tint


func base_albedo() -> Color:
    if tint.a > 0.0:
        return Color(tint.r, tint.g, tint.b, 1.0)
    return profile().get("albedo", Color.GRAY)


func profile() -> Dictionary:
    return FoundryMaterial.of(material_id)


## Sliding contact work removes coating over the swept area. Grinding also
## scrubs loose films away before it reaches the coating underneath.
func deposit_abrasion(work_joules: float, area: float, share: float = 1.0) -> void:
    if work_joules <= 0.0:
        return
    var swept := maxf(area, 0.0004)
    var removed := (
        work_joules * clampf(share, 0.0, 1.0)
        / (swept * FoundryMaterial.abrasion_energy(material_id))
    )
    if removed <= 0.0:
        return
    abrasion_work += work_joules
    var scrub := clampf(removed * 2.4, 0.0, 1.0)
    soot = maxf(0.0, soot - scrub)
    dirt = maxf(0.0, dirt - scrub * 0.8)
    oil = maxf(0.0, oil - scrub * 0.55)
    exposure = clampf(exposure + removed, 0.0, 1.0)
    revision += 1


func deposit_plastic(strain_energy: float, mass: float) -> void:
    if strain_energy <= 0.0:
        return
    var gain := strain_energy / maxf(mass * 420.0, 1.0)
    if gain < PERSISTENT_EPSILON:
        return
    plasticity = clampf(plasticity + gain, 0.0, 1.0)
    revision += 1


## Heat is two channels. The one that glows decays; the one that destroyed
## the coating does not.
func deposit_heat(joules: float, mass: float) -> void:
    if joules <= 0.0:
        return
    var data := profile()
    var capacity := maxf(float(data.get("heat_capacity", 490.0)), 1.0)
    var rise := joules / maxf(mass * capacity, 0.001)
    if rise <= 0.0:
        return
    current_temperature += rise
    thermal_history = maxf(thermal_history, current_temperature)

    var failure := float(data.get("coating_failure", 9000.0))
    if thermal_history > failure:
        var ruined := clampf((thermal_history - failure) / maxf(failure, 1.0), 0.0, 1.0)
        exposure = maxf(exposure, ruined)

    var boil := clampf(current_temperature / 120.0, 0.0, 1.0)
    water = maxf(0.0, water - boil)
    var burnt := clampf(current_temperature / 320.0, 0.0, 1.0) * oil
    if burnt > 0.0:
        oil = maxf(0.0, oil - burnt)
        soot = clampf(soot + burnt * 0.70, 0.0, 1.0)
    revision += 1


func deposit_fluid(fluid_id: int, amount: float) -> void:
    if amount <= 0.0:
        return
    var data := profile()
    match fluid_id:
        FoundryMaterial.HYDRAULIC_FLUID, FoundryMaterial.OIL:
            oil = clampf(
                oil + amount * float(data.get("oil_affinity", 0.34)),
                0.0,
                1.0
            )
        FoundryMaterial.WATER:
            water = clampf(
                water + amount * float(data.get("water_retention", 0.18)),
                0.0,
                1.0
            )
        FoundryMaterial.SOOT:
            soot = clampf(
                soot + amount * float(data.get("soot_affinity", 0.55)),
                0.0,
                1.0
            )
        FoundryMaterial.DIRT:
            dirt = clampf(dirt + amount * 0.8, 0.0, 1.0)
        _:
            return
    revision += 1


func set_fracture_proximity(value: float) -> void:
    var next := clampf(value, 0.0, 1.0)
    if absf(next - fracture_proximity) < PERSISTENT_EPSILON:
        return
    fracture_proximity = next
    revision += 1


func tick(delta: float) -> void:
    if delta <= 0.0:
        return
    var data := profile()
    var changed := false

    if current_temperature > 0.01:
        current_temperature *= exp(-float(data.get("cool_rate", 0.42)) * delta)
        if current_temperature <= 0.01:
            current_temperature = 0.0
        changed = true

    if water > 0.0:
        var evaporation := (0.035 + current_temperature * 0.004) * delta
        water = maxf(0.0, water - evaporation)
        changed = true

    if oil > 0.0:
        oil = maxf(0.0, oil - 0.004 * delta)
        changed = true

    # Rain is the only thing that takes soot off. Heat damage stays.
    if soot > 0.0 and water > 0.05:
        soot = maxf(0.0, soot - water * 0.22 * delta)
        changed = true

    if bool(data.get("oxidises", true)) and exposure > 0.05 and oxidation < 1.0:
        var moisture := 0.08 + water * 0.92
        oxidation = clampf(
            oxidation + exposure * moisture * 0.012 * delta,
            0.0,
            1.0
        )
        changed = true

    if changed:
        revision += 1


## Films move between surfaces that touch. Structural history does not.
func transfer_to(other: SurfaceState, ratio: float) -> void:
    if other == null:
        return
    var share := clampf(ratio, 0.0, 0.5)
    if share <= 0.0:
        return
    var moved_oil := oil * share
    var moved_dirt := dirt * share
    var moved_soot := soot * share
    if moved_oil <= 0.0 and moved_dirt <= 0.0 and moved_soot <= 0.0:
        return
    oil -= moved_oil
    dirt -= moved_dirt
    soot -= moved_soot
    other.oil = clampf(other.oil + moved_oil, 0.0, 1.0)
    other.dirt = clampf(other.dirt + moved_dirt, 0.0, 1.0)
    other.soot = clampf(other.soot + moved_soot, 0.0, 1.0)
    revision += 1
    other.revision += 1


## A fragment keeps the history of the surface it came from. Its torn faces
## are new material and carry none of it.
func clone_for_fragment(interior_ratio: float) -> SurfaceState:
    var copy := SurfaceState.new()
    copy.material_id = material_id
    copy.tint = tint
    copy.exposure = exposure
    copy.plasticity = plasticity
    copy.current_temperature = current_temperature
    copy.thermal_history = thermal_history
    copy.soot = soot
    copy.oil = oil
    copy.water = water
    copy.dirt = dirt
    copy.oxidation = oxidation
    copy.fracture_proximity = 1.0
    copy.fresh_fracture = clampf(interior_ratio, 0.0, 1.0)
    copy.revision = 1
    return copy


func composite_albedo() -> Color:
    var data := profile()
    var substrate: Color = data.get("substrate", data.get("albedo", Color.GRAY))
    var colour := base_albedo()

    if bool(data.get("coating", false)):
        if exposure <= 0.45:
            colour = colour.lerp(
                data.get("primer", substrate),
                clampf(exposure / 0.45, 0.0, 1.0)
            )
        else:
            colour = Color(data.get("primer", substrate)).lerp(
                substrate,
                clampf((exposure - 0.45) / 0.55, 0.0, 1.0)
            )
    else:
        colour = colour.lerp(substrate, exposure * 0.35)

    if oxidation > 0.0:
        colour = colour.lerp(data.get("oxide", colour), oxidation * 0.88)

    if fresh_fracture > 0.0:
        colour = colour.lerp(
            data.get("fracture_face", colour),
            fresh_fracture * 0.85
        )

    colour = colour.lerp(_heat_tint(), _heat_tint_weight())

    if dirt > 0.0:
        colour = colour.lerp(FoundryMaterial.of(FoundryMaterial.DIRT).albedo, dirt * 0.55)
    if oil > 0.0:
        colour = colour.lerp(FoundryMaterial.of(FoundryMaterial.OIL).albedo, oil * 0.72)
    if water > 0.0:
        colour = colour.darkened(water * 0.28)
    if soot > 0.0:
        colour = colour.lerp(FoundryMaterial.of(FoundryMaterial.SOOT).albedo, soot * 0.90)
    return colour


func composite_roughness() -> float:
    var data := profile()
    var value := float(data.get("roughness", 0.8))
    value += exposure * 0.10
    value += oxidation * 0.24
    value += plasticity * 0.06
    value -= oil * 0.62
    value -= water * 0.66
    value += dirt * 0.06
    value += soot * 0.10
    return clampf(value, 0.04, 1.0)


## Stripping paint uncovers metal, so exposure raises metallic on a coated
## surface. Rust is a dielectric, so oxidation takes it back down again.
func composite_metallic() -> float:
    var data := profile()
    var value := float(data.get("metallic", 0.0))
    if bool(data.get("coating", false)):
        value = lerpf(value, 0.52, exposure)
    value *= (1.0 - oxidation * 0.74)
    value *= (1.0 - soot * 0.55)
    return clampf(value, 0.0, 1.0)


func emission_color() -> Color:
    var data := profile()
    var onset := float(data.get("glow_onset", 520.0))
    if current_temperature <= onset:
        return Color(0.0, 0.0, 0.0)
    var over := clampf((current_temperature - onset) / maxf(onset, 1.0), 0.0, 1.6)
    var shape := pow(over, 4.0)
    var tint := Color(0.85, 0.14, 0.02).lerp(Color(1.0, 0.76, 0.34), clampf(over, 0.0, 1.0))
    return tint * clampf(shape, 0.0, 3.2)


func emission_energy() -> float:
    var data := profile()
    var onset := float(data.get("glow_onset", 520.0))
    if current_temperature <= onset:
        return 0.0
    var over := clampf((current_temperature - onset) / maxf(onset, 1.0), 0.0, 1.6)
    return clampf(pow(over, 4.0) * 2.6, 0.0, 6.0)


## Mechanical consumer of the same state: a wet or oily surface is worth
## less traction to anything standing on it.
func traction_scale() -> float:
    var oil_data := FoundryMaterial.of(FoundryMaterial.OIL)
    var water_data := FoundryMaterial.of(FoundryMaterial.WATER)
    var loss := (
        oil * float(oil_data.get("traction_loss", 0.68))
        + water * float(water_data.get("traction_loss", 0.34))
    )
    return clampf(1.0 - loss, 0.22, 1.0)


func film_amount() -> float:
    return clampf(soot * 1.0 + oil * 0.86 + water * 0.48 + dirt * 0.42, 0.0, 1.0)


func film_color() -> Color:
    var total := soot + oil + water + dirt
    if total <= 0.0001:
        return Color(0.06, 0.05, 0.04)
    var mix := Color(0.0, 0.0, 0.0)
    mix += FoundryMaterial.of(FoundryMaterial.SOOT).albedo * (soot / total)
    mix += FoundryMaterial.of(FoundryMaterial.OIL).albedo * (oil / total)
    mix += FoundryMaterial.of(FoundryMaterial.WATER).albedo * (water / total)
    mix += FoundryMaterial.of(FoundryMaterial.DIRT).albedo * (dirt / total)
    return mix


func film_gloss() -> float:
    return clampf(oil * 0.76 + water * 0.92 - soot * 0.55 - dirt * 0.30, 0.0, 1.0)


func apply_to_material(target: StandardMaterial3D) -> void:
    if target == null:
        return
    target.albedo_color = composite_albedo()
    target.roughness = composite_roughness()
    target.metallic = composite_metallic()
    var energy := emission_energy()
    if energy > 0.0:
        target.emission_enabled = true
        target.emission = emission_color()
        target.emission_energy_multiplier = energy
    elif target.emission_enabled:
        target.emission_enabled = false


## (damage, heat, load) packing for the solved skin, matching the vertex
## contract the graphics layer consumes.
func pack_vertex_color(node_damage: float, node_load: float) -> Color:
    var data := profile()
    var onset := maxf(float(data.get("glow_onset", 520.0)), 1.0)
    return Color(
        clampf(maxf(node_damage, exposure * 0.55 + fracture_proximity * 0.45), 0.0, 1.0),
        clampf(current_temperature / onset, 0.0, 1.0),
        clampf(node_load, 0.0, 1.0),
        1.0
    )


func _heat_tint() -> Color:
    var data := profile()
    if not bool(data.get("ferrous", false)):
        return Color(0.22, 0.20, 0.18)
    if thermal_history < 260.0:
        return Color(0.68, 0.52, 0.20)
    if thermal_history < 380.0:
        return Color(0.30, 0.31, 0.52)
    return Color(0.24, 0.23, 0.22)


func _heat_tint_weight() -> float:
    var data := profile()
    var failure := float(data.get("coating_failure", 9000.0))
    if failure >= 8000.0:
        failure = 220.0
    return clampf((thermal_history - failure * 0.45) / maxf(failure, 1.0), 0.0, 0.62)
