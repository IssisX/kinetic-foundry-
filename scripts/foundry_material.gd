class_name FoundryMaterial
extends RefCounted

## Canonical material constitution of the world.
##
## One identity per physically important surface. That identity resolves
## independently into visual, mechanical, thermal, fracture, acoustic and
## contamination profiles. No subsystem may keep a second identity for the
## same surface: the renderer, the fracture graph and the audio synthesiser
## all read this table.

const STRUCTURAL_STEEL := 0
const PAINTED_STEEL := 1
const HARDENED_STEEL := 2
const CAST_IRON := 3
const CONCRETE := 4
const RUBBER := 5
const GLASS := 6
const TIMBER := 7
const ASPHALT := 8
const HYDRAULIC_FLUID := 9
const OIL := 10
const WATER := 11
const SOOT := 12
const DIRT := 13

const FRAGMENT_SHEAR := 0
const FRAGMENT_SPALL := 1
const FRAGMENT_SHATTER := 2
const FRAGMENT_SPLINTER := 3
const FRAGMENT_TEAR := 4

const AMBIENT_KELVIN := 293.0

static var _catalog: Dictionary = {}
static var _legacy: Dictionary = {}


static func of(id: int) -> Dictionary:
    if _catalog.is_empty():
        _build()
    return _catalog.get(id, _catalog[STRUCTURAL_STEEL])


static func exists(id: int) -> bool:
    if _catalog.is_empty():
        _build()
    return _catalog.has(id)


static func id_from_legacy(name_text: String) -> int:
    if _legacy.is_empty():
        _build()
    return int(_legacy.get(name_text.to_lower(), STRUCTURAL_STEEL))


static func name_of(id: int) -> String:
    return str(of(id).get("name", "STRUCTURAL_STEEL"))


## Contact between two identities. Abrasion is paid by the softer surface,
## sparks need two hard ferrous bodies, and the grit/ring balance of the
## pair is what the audio and FX layers consume.
static func pair(first: int, second: int) -> Dictionary:
    var a := of(first)
    var b := of(second)
    var hardness_a := float(a.get("hardness", 0.5))
    var hardness_b := float(b.get("hardness", 0.5))
    var total := maxf(hardness_a + hardness_b, 0.001)
    var ferrous_pair: bool = bool(a.get("ferrous", false)) and bool(b.get("ferrous", false))
    return {
        "abrasion_share_a": hardness_b / total,
        "abrasion_share_b": hardness_a / total,
        "friction": sqrt(
            maxf(float(a.get("friction", 0.5)), 0.01)
            * maxf(float(b.get("friction", 0.5)), 0.01)
        ),
        "restitution": minf(
            float(a.get("restitution", 0.3)),
            float(b.get("restitution", 0.3))
        ),
        "spark": ferrous_pair and minf(hardness_a, hardness_b) >= 0.55,
        "grit": maxf(float(a.get("grit_gain", 0.2)), float(b.get("grit_gain", 0.2))),
        "ring": minf(float(a.get("ring_gain", 0.5)), float(b.get("ring_gain", 0.5)))
    }


## Friction work that strips one square metre of this surface, in joules.
## Not the bulk material energy: most sliding work leaves as heat, so this
## is deliberately orders of magnitude larger than a cutting energy.
static func abrasion_energy(id: int) -> float:
    return maxf(float(of(id).get("abrasion_energy", 2500000.0)), 1.0)


static func _entry(overrides: Dictionary) -> Dictionary:
    var entry := {
        "name": "STRUCTURAL_STEEL",
        "albedo": Color(0.31, 0.32, 0.30),
        "roughness": 0.82,
        "metallic": 0.42,
        "coating": false,
        "primer": Color(0.34, 0.16, 0.10),
        "substrate": Color(0.31, 0.32, 0.30),
        "oxide": Color(0.36, 0.17, 0.07),
        "fracture_face": Color(0.52, 0.53, 0.51),
        "density": 7850.0,
        "hardness": 0.62,
        "friction": 0.42,
        "restitution": 0.28,
        "ferrous": true,
        "yield_strain": 0.018,
        "failure_strain": 0.18,
        "toughness": 180.0,
        "surface_energy": 420.0,
        "fragment_style": FRAGMENT_SHEAR,
        "heat_capacity": 490.0,
        "glow_onset": 520.0,
        "coating_failure": 9000.0,
        "cool_rate": 0.42,
        "ring_hz": 285.0,
        "mass_exponent": 0.24,
        "ring_gain": 0.78,
        "grit_gain": 0.20,
        "decay": 3.1,
        "oil_affinity": 0.34,
        "soot_affinity": 0.55,
        "water_retention": 0.18,
        "oxidises": true,
        "abrasion_energy": 2500000.0,
        "dust": 0.0
    }
    for key in overrides:
        entry[key] = overrides[key]
    return entry


static func _build() -> void:
    _catalog = {
        STRUCTURAL_STEEL: _entry({}),
        PAINTED_STEEL: _entry({
            "name": "PAINTED_STEEL",
            "albedo": Color(0.62, 0.47, 0.10),
            "roughness": 0.58,
            "metallic": 0.10,
            "coating": true,
            "hardness": 0.58,
            "coating_failure": 180.0,
            "ring_gain": 0.70,
            "abrasion_energy": 1200000.0,
            "soot_affinity": 0.72
        }),
        HARDENED_STEEL: _entry({
            "name": "HARDENED_STEEL",
            "albedo": Color(0.26, 0.27, 0.28),
            "roughness": 0.64,
            "metallic": 0.58,
            "hardness": 0.88,
            "yield_strain": 0.026,
            "failure_strain": 0.11,
            "toughness": 260.0,
            "surface_energy": 560.0,
            "ring_hz": 348.0,
            "decay": 2.4,
            "abrasion_energy": 6000000.0
        }),
        CAST_IRON: _entry({
            "name": "CAST_IRON",
            "albedo": Color(0.22, 0.22, 0.23),
            "roughness": 0.90,
            "metallic": 0.34,
            "hardness": 0.70,
            "yield_strain": 0.006,
            "failure_strain": 0.035,
            "toughness": 95.0,
            "surface_energy": 165.0,
            "fragment_style": FRAGMENT_SHATTER,
            "ring_hz": 212.0,
            "ring_gain": 0.52,
            "grit_gain": 0.42,
            "decay": 5.8,
            "fracture_face": Color(0.44, 0.43, 0.42)
        }),
        CONCRETE: _entry({
            "name": "CONCRETE",
            "albedo": Color(0.47, 0.46, 0.43),
            "roughness": 0.94,
            "metallic": 0.0,
            "oxide": Color(0.42, 0.40, 0.36),
            "fracture_face": Color(0.58, 0.56, 0.51),
            "density": 2400.0,
            "hardness": 0.40,
            "friction": 0.68,
            "restitution": 0.16,
            "ferrous": false,
            "yield_strain": 0.004,
            "failure_strain": 0.028,
            "toughness": 70.0,
            "surface_energy": 95.0,
            "fragment_style": FRAGMENT_SPALL,
            "heat_capacity": 880.0,
            "glow_onset": 100000.0,
            "cool_rate": 0.12,
            "ring_hz": 132.0,
            "mass_exponent": 0.22,
            "ring_gain": 0.24,
            "grit_gain": 0.86,
            "decay": 7.4,
            "oil_affinity": 0.92,
            "water_retention": 0.88,
            "oxidises": false,
            "abrasion_energy": 550000.0,
            "dust": 1.0
        }),
        RUBBER: _entry({
            "name": "RUBBER",
            "albedo": Color(0.09, 0.09, 0.10),
            "roughness": 0.96,
            "metallic": 0.0,
            "fracture_face": Color(0.13, 0.13, 0.14),
            "density": 1100.0,
            "hardness": 0.12,
            "friction": 0.95,
            "restitution": 0.55,
            "ferrous": false,
            "yield_strain": 0.35,
            "failure_strain": 1.40,
            "toughness": 40.0,
            "surface_energy": 210.0,
            "fragment_style": FRAGMENT_TEAR,
            "heat_capacity": 1900.0,
            "glow_onset": 100000.0,
            "coating_failure": 220.0,
            "cool_rate": 0.08,
            "ring_hz": 74.0,
            "ring_gain": 0.10,
            "grit_gain": 0.34,
            "decay": 14.0,
            "oil_affinity": 0.78,
            "oxidises": false,
            "abrasion_energy": 350000.0
        }),
        GLASS: _entry({
            "name": "GLASS",
            "albedo": Color(0.42, 0.50, 0.52),
            "roughness": 0.10,
            "metallic": 0.0,
            "fracture_face": Color(0.72, 0.80, 0.82),
            "density": 2500.0,
            "hardness": 0.80,
            "friction": 0.24,
            "restitution": 0.42,
            "ferrous": false,
            "yield_strain": 0.001,
            "failure_strain": 0.004,
            "toughness": 30.0,
            "surface_energy": 55.0,
            "fragment_style": FRAGMENT_SHATTER,
            "heat_capacity": 840.0,
            "glow_onset": 100000.0,
            "cool_rate": 0.22,
            "ring_hz": 620.0,
            "mass_exponent": 0.30,
            "ring_gain": 0.94,
            "grit_gain": 0.62,
            "decay": 6.2,
            "oil_affinity": 0.12,
            "water_retention": 0.05,
            "oxidises": false,
            "abrasion_energy": 4000000.0
        }),
        TIMBER: _entry({
            "name": "TIMBER",
            "albedo": Color(0.38, 0.27, 0.15),
            "roughness": 0.92,
            "metallic": 0.0,
            "fracture_face": Color(0.62, 0.48, 0.28),
            "density": 550.0,
            "hardness": 0.22,
            "friction": 0.58,
            "restitution": 0.24,
            "ferrous": false,
            "yield_strain": 0.008,
            "failure_strain": 0.05,
            "toughness": 60.0,
            "surface_energy": 120.0,
            "fragment_style": FRAGMENT_SPLINTER,
            "heat_capacity": 1700.0,
            "glow_onset": 100000.0,
            "coating_failure": 160.0,
            "cool_rate": 0.10,
            "ring_hz": 168.0,
            "ring_gain": 0.34,
            "grit_gain": 0.48,
            "decay": 9.5,
            "oil_affinity": 0.68,
            "water_retention": 0.74,
            "oxidises": false,
            "abrasion_energy": 300000.0
        }),
        ASPHALT: _entry({
            "name": "ASPHALT",
            "albedo": Color(0.15, 0.15, 0.16),
            "roughness": 0.97,
            "metallic": 0.0,
            "fracture_face": Color(0.21, 0.20, 0.19),
            "density": 2300.0,
            "hardness": 0.26,
            "friction": 0.76,
            "restitution": 0.12,
            "ferrous": false,
            "yield_strain": 0.012,
            "failure_strain": 0.06,
            "toughness": 55.0,
            "surface_energy": 80.0,
            "fragment_style": FRAGMENT_SPALL,
            "heat_capacity": 920.0,
            "glow_onset": 100000.0,
            "coating_failure": 95.0,
            "cool_rate": 0.09,
            "ring_hz": 96.0,
            "ring_gain": 0.12,
            "grit_gain": 0.78,
            "decay": 11.0,
            "oil_affinity": 0.85,
            "water_retention": 0.34,
            "oxidises": false,
            "abrasion_energy": 400000.0,
            "dust": 0.6
        }),
        HYDRAULIC_FLUID: _entry({
            "name": "HYDRAULIC_FLUID",
            "albedo": Color(0.19, 0.09, 0.03),
            "roughness": 0.14,
            "metallic": 0.0,
            "density": 870.0,
            "hardness": 0.02,
            "friction": 0.06,
            "ferrous": false,
            "ring_hz": 60.0,
            "ring_gain": 0.04,
            "grit_gain": 0.06,
            "oxidises": false,
            "film": true,
            "film_darkening": 0.74,
            "film_gloss": 0.80,
            "traction_loss": 0.62
        }),
        OIL: _entry({
            "name": "OIL",
            "albedo": Color(0.12, 0.10, 0.06),
            "roughness": 0.16,
            "metallic": 0.0,
            "density": 900.0,
            "hardness": 0.02,
            "friction": 0.05,
            "ferrous": false,
            "ring_gain": 0.04,
            "grit_gain": 0.05,
            "oxidises": false,
            "film": true,
            "film_darkening": 0.80,
            "film_gloss": 0.76,
            "traction_loss": 0.68
        }),
        WATER: _entry({
            "name": "WATER",
            "albedo": Color(0.16, 0.19, 0.22),
            "roughness": 0.06,
            "metallic": 0.0,
            "density": 1000.0,
            "hardness": 0.01,
            "friction": 0.10,
            "ferrous": false,
            "ring_gain": 0.06,
            "grit_gain": 0.04,
            "oxidises": false,
            "film": true,
            "film_darkening": 0.42,
            "film_gloss": 0.92,
            "traction_loss": 0.34
        }),
        SOOT: _entry({
            "name": "SOOT",
            "albedo": Color(0.045, 0.042, 0.040),
            "roughness": 0.99,
            "metallic": 0.0,
            "density": 120.0,
            "hardness": 0.02,
            "friction": 0.30,
            "ferrous": false,
            "ring_gain": 0.02,
            "grit_gain": 0.30,
            "oxidises": false,
            "film": true,
            "film_darkening": 0.94,
            "film_gloss": 0.02,
            "traction_loss": 0.12
        }),
        DIRT: _entry({
            "name": "DIRT",
            "albedo": Color(0.30, 0.24, 0.16),
            "roughness": 0.98,
            "metallic": 0.0,
            "density": 1500.0,
            "hardness": 0.08,
            "friction": 0.62,
            "ferrous": false,
            "ring_gain": 0.04,
            "grit_gain": 0.68,
            "oxidises": false,
            "film": true,
            "film_darkening": 0.30,
            "film_gloss": 0.04,
            "traction_loss": 0.18,
            "dust": 0.8
        })
    }
    _legacy = {
        "steel": STRUCTURAL_STEEL,
        "structural_steel": STRUCTURAL_STEEL,
        "support": STRUCTURAL_STEEL,
        "deck": STRUCTURAL_STEEL,
        "paint": PAINTED_STEEL,
        "painted_steel": PAINTED_STEEL,
        "machine": PAINTED_STEEL,
        "gate": PAINTED_STEEL,
        "hardened": HARDENED_STEEL,
        "tool": HARDENED_STEEL,
        "iron": CAST_IRON,
        "cast_iron": CAST_IRON,
        "concrete": CONCRETE,
        "rubber": RUBBER,
        "track": RUBBER,
        "glass": GLASS,
        "timber": TIMBER,
        "wood": TIMBER,
        "asphalt": ASPHALT,
        "ground": ASPHALT,
        "hydraulic": HYDRAULIC_FLUID,
        "oil": OIL,
        "water": WATER,
        "soot": SOOT,
        "dirt": DIRT
    }
