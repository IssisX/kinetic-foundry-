extends "res://scripts/structure.gd"

const MaterialFx = preload("res://scripts/material_fx.gd")

func damage_support(index: int, amount: float, direction: Vector3) -> void:
    if index < 0 or index >= support_health.size():
        return
    var hp_before := support_health[index]
    var hit_pos := global_position
    if index < supports.size() and is_instance_valid(supports[index]):
        hit_pos = supports[index].global_position + Vector3.UP * 1.05

    super(index, amount, direction)

    var removed := maxf(0.0, hp_before - support_health[index])
    if removed <= 0.0:
        return

    MaterialFx.steel(
        get_parent(),
        hit_pos,
        direction,
        clampf(removed / 20.0, 0.55, 4.8)
    )

    if removed > 28.0 or support_health[index] <= 0.0:
        MaterialFx.concrete(
            get_parent(),
            hit_pos - Vector3.UP * 2.8,
            direction + Vector3.UP * 0.35,
            clampf(removed / 24.0, 0.8, 4.2)
        )
