extends "res://scripts/structure.gd"

const MaterialFx = preload("res://scripts/material_fx.gd")

func damage_support(index: int, amount: float, direction: Vector3) -> void:
    var hit_pos := global_position
    if index >= 0 and index < supports.size() and is_instance_valid(supports[index]):
        hit_pos = supports[index].global_position + Vector3.UP * 1.05
    damage_support_at(
        index,
        amount,
        direction,
        hit_pos,
        amount * amount * 3.0
    )

func damage_support_at(
        index: int,
        amount: float,
        direction: Vector3,
        world_point: Vector3,
        impact_energy: float
) -> void:
    if index < 0 or index >= support_health.size():
        return
    var hp_before := support_health[index]
    super.damage_support(index, amount, direction)

    var removed := maxf(0.0, hp_before - support_health[index])
    if removed <= 0.0:
        return

    MaterialFx.steel(
        get_parent(),
        world_point,
        direction,
        clampf(maxf(removed / 20.0, impact_energy / 6000.0), 0.55, 5.2)
    )

    get_tree().call_group(
        "physical_event_listener",
        "physical_event",
        {
            "type": "machine_contact",
            "position": world_point,
            "impulse": sqrt(maxf(2.0 * 180.0 * impact_energy, 0.0)),
            "mass": 180.0,
            "fracture": clampf(
                removed / 95.0 + impact_energy / 22000.0,
                0.0,
                1.0
            ),
            "radius": 2.3,
            "novelty": clampf(0.55 + removed / 120.0, 0.55, 1.0),
            "material": "steel"
        }
    )

    if removed > 28.0 or support_health[index] <= 0.0:
        MaterialFx.concrete(
            get_parent(),
            world_point - Vector3.UP * minf(world_point.y, 2.8),
            direction + Vector3.UP * 0.35,
            clampf(removed / 24.0, 0.8, 4.2)
        )

func _evaluate_failure() -> void:
    var was_collapsed := collapsed
    super()
    if was_collapsed or not collapsed:
        return
    var event_position := global_position + Vector3.UP * 3.4
    var event_mass := 950.0
    if deck != null and is_instance_valid(deck):
        event_position = deck.global_position
        event_mass = deck.mass
    get_tree().call_group(
        "physical_event_listener",
        "physical_event",
        {
            "type": "collapse",
            "position": event_position,
            "impulse": event_mass * 12.5,
            "mass": event_mass,
            "fracture": 1.0,
            "radius": 11.0,
            "novelty": 1.0,
            "material": "steel"
        }
    )
