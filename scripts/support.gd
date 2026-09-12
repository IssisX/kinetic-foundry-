extends StaticBody3D

const ImpactFx = preload("res://scripts/impact_fx.gd")

var frame

func machine_hit(amount: float, direction: Vector3) -> void:
    if frame == null:
        return
    ImpactFx.spawn(
        get_parent(),
        global_position + Vector3.UP * 0.35,
        direction,
        Color(0.92, 0.57, 0.15),
        clampf(amount / 22.0, 0.8, 4.2),
        10
    )
    var index := int(get_meta("support_index", -1))
    frame.damage_support(index, amount, direction)
