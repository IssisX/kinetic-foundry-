extends "res://scripts/humanoid_motion.gd"

# Final visual proportion pass layered over the analytic gait/organic loft rig.
# The physics/control skeleton stays authoritative; this only removes the
# oversized ball-joint / hard-hat silhouette that made workers read like toys.

func _build() -> void:
    super()
    _refine_head()
    _refine_arms()
    _refine_legs()

func _refine_head() -> void:
    if head_root == null:
        return
    for child in head_root.get_children():
        if not (child is MeshInstance3D):
            continue
        var mesh_child := child as MeshInstance3D
        if mesh_child.mesh is SphereMesh:
            if mesh_child.position.y > 0.36:
                # Helmet dome.
                mesh_child.scale *= Vector3(0.88, 0.90, 0.88)
                mesh_child.position.y -= 0.012
            else:
                # Head volume - keep human mass but reduce bobble-head read.
                mesh_child.scale *= Vector3(0.95, 0.97, 0.95)
        elif mesh_child.mesh is CylinderMesh and mesh_child.position.y > 0.30:
            # Helmet band.
            mesh_child.scale *= Vector3(0.89, 0.88, 0.89)
        elif mesh_child.mesh is CapsuleMesh and mesh_child.position.y > 0.30:
            # Brim.
            mesh_child.scale *= Vector3(0.88, 0.82, 0.86)

func _refine_arms() -> void:
    for arm in [arm_l, arm_r]:
        if arm == null:
            continue
        for child in arm.get_children():
            if child is MeshInstance3D:
                var mesh_child := child as MeshInstance3D
                if mesh_child.mesh is SphereMesh:
                    # Shoulder cap - reduce toy-ball silhouette.
                    mesh_child.scale *= Vector3(0.84, 0.90, 0.84)
                elif mesh_child.mesh is CapsuleMesh:
                    mesh_child.scale *= Vector3(0.92, 1.03, 0.92)
        var elbow := arm.get_node_or_null("Elbow") as Node3D
        if elbow == null:
            continue
        for child in elbow.get_children():
            if not (child is MeshInstance3D):
                continue
            var mesh_child := child as MeshInstance3D
            if mesh_child.mesh is SphereMesh:
                var factor := 0.78 if mesh_child.position.y > -0.20 else 0.84
                mesh_child.scale *= Vector3(factor, factor, factor)
            elif mesh_child.mesh is CapsuleMesh:
                mesh_child.scale *= Vector3(0.91, 1.04, 0.91)

func _refine_legs() -> void:
    for leg in [leg_l, leg_r]:
        if leg == null:
            continue
        for child in leg.get_children():
            if child is MeshInstance3D and (child as MeshInstance3D).mesh is CapsuleMesh:
                (child as MeshInstance3D).scale *= Vector3(0.93, 1.03, 0.93)
        var knee := leg.get_node_or_null("Knee") as Node3D
        if knee == null:
            continue
        for child in knee.get_children():
            if not (child is MeshInstance3D):
                continue
            var mesh_child := child as MeshInstance3D
            if mesh_child.mesh is SphereMesh:
                mesh_child.scale *= Vector3(0.80, 0.80, 0.80)
            elif mesh_child.mesh is CapsuleMesh and mesh_child.position.y < -0.10:
                mesh_child.scale *= Vector3(0.92, 1.03, 0.92)
