extends Node

const GeomUtil = preload("res://scripts/geom.gd")

func _ready() -> void:
    call_deferred("_decorate")

func _decorate() -> void:
    await get_tree().process_frame
    await get_tree().process_frame
    for player in get_tree().get_nodes_in_group("player"):
        if is_instance_valid(player):
            var player_rig = player.get("_rig")
            if player_rig != null:
                _decorate_player(player_rig)
    for enemy in get_tree().get_nodes_in_group("enemy"):
        if not is_instance_valid(enemy):
            continue
        var rig = enemy.get("_rig")
        if rig == null:
            continue
        var variant := int(enemy.get_instance_id()) % 3
        _decorate_rig(rig, variant)

func _decorate_player(rig) -> void:
    if rig.has_meta("player_detail"):
        return
    rig.set_meta("player_detail", true)
    var torso = rig.get("torso")
    var arm_l = rig.get("arm_l")
    var arm_r = rig.get("arm_r")
    if torso != null:
        var back := GeomUtil.box_mesh(Vector3(0.56, 0.58, 0.20), Color(0.09, 0.11, 0.105), 0.88, 0.12)
        back.position = Vector3(0.0, 0.34, 0.32)
        torso.add_child(back)
        for side in [-1.0, 1.0]:
            var buckle := GeomUtil.box_mesh(Vector3(0.10, 0.10, 0.06), Color(0.58, 0.39, 0.08), 0.72, 0.16)
            buckle.position = Vector3(side * 0.24, 0.44, -0.31)
            torso.add_child(buckle)
        var belt_case := GeomUtil.box_mesh(Vector3(0.30, 0.20, 0.15), Color(0.11, 0.09, 0.06), 0.92, 0.04)
        belt_case.position = Vector3(0.31, -0.08, 0.0)
        torso.add_child(belt_case)
    for arm in [arm_l, arm_r]:
        if arm == null:
            continue
        var brace := GeomUtil.box_mesh(Vector3(0.20, 0.26, 0.19), Color(0.19, 0.20, 0.18), 0.84, 0.24)
        brace.position = Vector3(0.0, -0.18, -0.02)
        arm.add_child(brace)

func _decorate_rig(rig, variant: int) -> void:
    if rig.has_meta("population_detail"):
        return
    rig.set_meta("population_detail", true)
    if variant == 0:
        _worker_gear(rig)
    elif variant == 1:
        _heavy_gear(rig)
    else:
        _utility_gear(rig)

func _worker_gear(rig) -> void:
    var torso = rig.get("torso")
    if torso == null:
        return
    for side in [-1.0, 1.0]:
        var strip := GeomUtil.box_mesh(Vector3(0.07, 0.62, 0.04), Color(0.86, 0.60, 0.10), 0.76, 0.02)
        strip.position = Vector3(side * 0.22, 0.35, -0.285)
        torso.add_child(strip)
    var pouch := GeomUtil.box_mesh(Vector3(0.26, 0.20, 0.16), Color(0.16, 0.13, 0.08), 0.92, 0.03)
    pouch.position = Vector3(0.28, -0.06, -0.27)
    torso.add_child(pouch)

func _heavy_gear(rig) -> void:
    var torso = rig.get("torso")
    var head_root = rig.get("head_root")
    if torso != null:
        var plate := GeomUtil.box_mesh(Vector3(0.82, 0.50, 0.10), Color(0.10, 0.11, 0.105), 0.88, 0.16)
        plate.position = Vector3(0.0, 0.37, -0.29)
        torso.add_child(plate)
        for side in [-1.0, 1.0]:
            var shoulder := GeomUtil.box_mesh(Vector3(0.30, 0.18, 0.42), Color(0.50, 0.16, 0.05), 0.86, 0.09)
            shoulder.position = Vector3(side * 0.50, 0.64, 0.0)
            torso.add_child(shoulder)
    if head_root != null:
        var visor := GeomUtil.box_mesh(Vector3(0.38, 0.10, 0.035), Color(0.08, 0.17, 0.18), 0.20, 0.34)
        visor.position = Vector3(0.0, 0.31, -0.245)
        head_root.add_child(visor)

func _utility_gear(rig) -> void:
    var torso = rig.get("torso")
    var head_root = rig.get("head_root")
    if torso != null:
        var pack := GeomUtil.box_mesh(Vector3(0.48, 0.58, 0.20), Color(0.12, 0.17, 0.16), 0.90, 0.08)
        pack.position = Vector3(0.0, 0.32, 0.33)
        torso.add_child(pack)
        var radio := GeomUtil.box_mesh(Vector3(0.15, 0.32, 0.10), Color(0.06, 0.075, 0.07), 0.82, 0.18)
        radio.position = Vector3(-0.34, 0.49, -0.28)
        torso.add_child(radio)
        var antenna := GeomUtil.cylinder_mesh(0.025, 0.30, Color(0.10, 0.11, 0.10), 0.72, 0.28)
        antenna.position = Vector3(-0.34, 0.72, -0.28)
        torso.add_child(antenna)
    if head_root != null:
        var lamp := GeomUtil.box_mesh(Vector3(0.12, 0.10, 0.08), Color(0.28, 0.50, 0.48), 0.34, 0.14)
        lamp.material_override = GeomUtil.emissive_material(Color(0.12, 0.42, 0.38), 1.7, 0.30, 0.12)
        lamp.position = Vector3(0.0, 0.46, -0.24)
        head_root.add_child(lamp)
