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
                _refine_proportions(player_rig)
                _decorate_player(player_rig)
    for enemy in get_tree().get_nodes_in_group("enemy"):
        if not is_instance_valid(enemy):
            continue
        var rig = enemy.get("_rig")
        if rig == null:
            continue
        _refine_proportions(rig)
        var variant := int(enemy.get_instance_id()) % 3
        _decorate_rig(rig, variant)

func _refine_proportions(rig) -> void:
    if rig.has_meta("proportion_finish"):
        return
    rig.set_meta("proportion_finish", true)

    var head_root = rig.get("head_root")
    if head_root != null:
        for child in head_root.get_children():
            if not (child is MeshInstance3D):
                continue
            var mesh_child := child as MeshInstance3D
            if mesh_child.mesh is SphereMesh:
                if mesh_child.position.y > 0.36:
                    mesh_child.scale *= Vector3(0.88, 0.90, 0.88)
                    mesh_child.position.y -= 0.012
                else:
                    mesh_child.scale *= Vector3(0.95, 0.97, 0.95)
            elif mesh_child.mesh is CylinderMesh and mesh_child.position.y > 0.30:
                mesh_child.scale *= Vector3(0.89, 0.88, 0.89)
            elif mesh_child.mesh is CapsuleMesh and mesh_child.position.y > 0.30:
                mesh_child.scale *= Vector3(0.88, 0.82, 0.86)

    for arm_key in ["arm_l", "arm_r"]:
        var arm = rig.get(arm_key)
        if arm == null:
            continue
        for child in arm.get_children():
            if child is MeshInstance3D:
                var mesh_child := child as MeshInstance3D
                if mesh_child.mesh is SphereMesh:
                    mesh_child.scale *= Vector3(0.84, 0.90, 0.84)
                elif mesh_child.mesh is CapsuleMesh:
                    mesh_child.scale *= Vector3(0.92, 1.03, 0.92)
        var elbow := arm.get_node_or_null("Elbow") as Node3D
        if elbow != null:
            for child in elbow.get_children():
                if not (child is MeshInstance3D):
                    continue
                var mesh_child := child as MeshInstance3D
                if mesh_child.mesh is SphereMesh:
                    var factor := 0.78 if mesh_child.position.y > -0.20 else 0.84
                    mesh_child.scale *= Vector3(factor, factor, factor)
                elif mesh_child.mesh is CapsuleMesh:
                    mesh_child.scale *= Vector3(0.91, 1.04, 0.91)

    for leg_key in ["leg_l", "leg_r"]:
        var leg = rig.get(leg_key)
        if leg == null:
            continue
        for child in leg.get_children():
            if child is MeshInstance3D and (child as MeshInstance3D).mesh is CapsuleMesh:
                (child as MeshInstance3D).scale *= Vector3(0.93, 1.03, 0.93)
        var knee := leg.get_node_or_null("Knee") as Node3D
        if knee != null:
            for child in knee.get_children():
                if not (child is MeshInstance3D):
                    continue
                var mesh_child := child as MeshInstance3D
                if mesh_child.mesh is SphereMesh:
                    mesh_child.scale *= Vector3(0.80, 0.80, 0.80)
                elif mesh_child.mesh is CapsuleMesh and mesh_child.position.y < -0.10:
                    mesh_child.scale *= Vector3(0.92, 1.03, 0.92)

func _decorate_player(rig) -> void:
    if rig.has_meta("player_detail"):
        return
    rig.set_meta("player_detail", true)
    var torso = rig.get("torso")
    var arm_l = rig.get("arm_l")
    var arm_r = rig.get("arm_r")
    if torso != null:
        # Rounded harness pack - avoids the rectangular backpack silhouette that
        # made the player read like a toy minifigure from the gameplay camera.
        var back := GeomUtil.capsule_mesh(0.20, 0.52, Color(0.09, 0.11, 0.105))
        back.scale = Vector3(1.25, 1.0, 0.62)
        back.position = Vector3(0.0, 0.34, 0.30)
        torso.add_child(back)
        for side in [-1.0, 1.0]:
            var buckle := GeomUtil.cylinder_mesh(0.052, 0.045, Color(0.58, 0.39, 0.08), 0.72, 0.16)
            buckle.rotation.x = PI * 0.5
            buckle.position = Vector3(side * 0.24, 0.44, -0.31)
            torso.add_child(buckle)
        var belt_case := GeomUtil.capsule_mesh(0.09, 0.24, Color(0.11, 0.09, 0.06))
        belt_case.rotation.z = PI * 0.5
        belt_case.scale = Vector3(1.0, 1.0, 0.72)
        belt_case.position = Vector3(0.31, -0.08, 0.0)
        torso.add_child(belt_case)
    for arm in [arm_l, arm_r]:
        if arm == null:
            continue
        var brace := GeomUtil.capsule_mesh(0.09, 0.22, Color(0.19, 0.20, 0.18))
        brace.scale = Vector3(1.0, 1.0, 0.84)
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
        var strip := GeomUtil.capsule_mesh(0.035, 0.58, Color(0.86, 0.60, 0.10))
        strip.position = Vector3(side * 0.22, 0.35, -0.285)
        torso.add_child(strip)
    var pouch := GeomUtil.capsule_mesh(0.08, 0.20, Color(0.16, 0.13, 0.08))
    pouch.rotation.z = PI * 0.5
    pouch.scale = Vector3(1.0, 1.0, 0.76)
    pouch.position = Vector3(0.28, -0.06, -0.27)
    torso.add_child(pouch)

func _heavy_gear(rig) -> void:
    var torso = rig.get("torso")
    var head_root = rig.get("head_root")
    if torso != null:
        var plate := GeomUtil.capsule_mesh(0.16, 0.66, Color(0.10, 0.11, 0.105))
        plate.rotation.z = PI * 0.5
        plate.scale = Vector3(1.0, 1.0, 0.42)
        plate.position = Vector3(0.0, 0.37, -0.29)
        torso.add_child(plate)
        for side in [-1.0, 1.0]:
            var shoulder := GeomUtil.capsule_mesh(0.105, 0.27, Color(0.50, 0.16, 0.05))
            shoulder.rotation.z = PI * 0.5
            shoulder.scale = Vector3(1.0, 1.0, 0.88)
            shoulder.position = Vector3(side * 0.49, 0.64, 0.0)
            torso.add_child(shoulder)
    if head_root != null:
        var visor := GeomUtil.capsule_mesh(0.035, 0.30, Color(0.08, 0.17, 0.18))
        visor.rotation.z = PI * 0.5
        visor.scale = Vector3(1.0, 1.0, 0.50)
        visor.position = Vector3(0.0, 0.31, -0.245)
        head_root.add_child(visor)

func _utility_gear(rig) -> void:
    var torso = rig.get("torso")
    var head_root = rig.get("head_root")
    if torso != null:
        var pack := GeomUtil.capsule_mesh(0.18, 0.50, Color(0.12, 0.17, 0.16))
        pack.scale = Vector3(1.22, 1.0, 0.62)
        pack.position = Vector3(0.0, 0.32, 0.31)
        torso.add_child(pack)
        var radio := GeomUtil.capsule_mesh(0.055, 0.27, Color(0.06, 0.075, 0.07))
        radio.position = Vector3(-0.34, 0.49, -0.28)
        torso.add_child(radio)
        var antenna := GeomUtil.cylinder_mesh(0.018, 0.28, Color(0.10, 0.11, 0.10), 0.72, 0.28)
        antenna.position = Vector3(-0.34, 0.72, -0.28)
        torso.add_child(antenna)
    if head_root != null:
        var lamp := GeomUtil.cylinder_mesh(0.055, 0.07, Color(0.28, 0.50, 0.48), 0.34, 0.14)
        lamp.rotation.x = PI * 0.5
        lamp.material_override = GeomUtil.emissive_material(Color(0.12, 0.42, 0.38), 1.7, 0.30, 0.12)
        lamp.position = Vector3(0.0, 0.46, -0.24)
        head_root.add_child(lamp)
