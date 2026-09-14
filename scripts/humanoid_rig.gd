extends Node3D

const GeomUtil = preload("res://scripts/geom.gd")

var player_style := false
var phase := 0.0
var attack_side := 1.0
var attack_mode := 0
var death_blend := 0.0
var limp_l := 0.0
var limp_r := 0.0
var crush := 0.0
var crush_dir := Vector3(0.0, 0.0, 1.0)

var pelvis: Node3D
var spine: Node3D
var torso: Node3D
var head_root: Node3D
var arm_l: Node3D
var arm_r: Node3D
var elbow_l: Node3D
var elbow_r: Node3D
var leg_l: Node3D
var leg_r: Node3D
var knee_l: Node3D
var knee_r: Node3D
var foot_l: Node3D
var foot_r: Node3D
var toe_l: Node3D
var toe_r: Node3D

func configure(is_player: bool) -> void:
    player_style = is_player
    _build()

func _build() -> void:
    var cloth := Color(0.18, 0.20, 0.19) if player_style else Color(0.24, 0.26, 0.23)
    var cloth_dark := Color(0.10, 0.11, 0.105)
    var skin := Color(0.76, 0.56, 0.44) if player_style else Color(0.66, 0.50, 0.38)
    var gear := Color(0.12, 0.13, 0.125)
    var boot := Color(0.07, 0.075, 0.07)
    var hat := Color(0.16, 0.17, 0.165) if player_style else Color(0.78, 0.58, 0.12)

    pelvis = Node3D.new()
    pelvis.name = "Pelvis"
    pelvis.position = Vector3(0.0, 0.94, 0.0)
    add_child(pelvis)

    var hip_mass := GeomUtil.capsule_mesh(0.18, 0.26, cloth_dark)
    hip_mass.scale = Vector3(1.48, 1.0, 0.88)
    hip_mass.position.y = -0.02
    pelvis.add_child(hip_mass)
    var belt := GeomUtil.cylinder_mesh(0.21, 0.06, gear, 0.88, 0.12)
    belt.scale = Vector3(1.38, 1.0, 0.92)
    belt.position.y = 0.10
    pelvis.add_child(belt)
    for side in [-1.0, 1.0]:
        var pouch := GeomUtil.box_mesh(Vector3(0.07, 0.09, 0.05), gear, 0.90, 0.08)
        pouch.position = Vector3(side * 0.20, 0.01, 0.02)
        pelvis.add_child(pouch)

    spine = Node3D.new()
    spine.name = "Spine"
    spine.position = Vector3(0.0, 0.12, 0.0)
    pelvis.add_child(spine)

    torso = Node3D.new()
    torso.name = "Torso"
    torso.position = Vector3(0.0, 0.12, 0.0)
    spine.add_child(torso)

    var rib := GeomUtil.capsule_mesh(0.20, 0.60, cloth)
    rib.scale = Vector3(1.38 if player_style else 1.24, 1.0, 0.72)
    rib.position = Vector3(0.0, 0.28, 0.01)
    torso.add_child(rib)

    var placket := GeomUtil.box_mesh(
        Vector3(0.055, 0.34, 0.028),
        cloth_dark,
        0.88,
        0.04
    )
    placket.position = Vector3(0.0, 0.30, -0.148)
    torso.add_child(placket)

    var collar := GeomUtil.cylinder_mesh(0.10, 0.045, cloth, 0.82, 0.0)
    collar.position = Vector3(0.0, 0.62, 0.0)
    torso.add_child(collar)

    var shoulders := GeomUtil.capsule_mesh(0.095, 0.68 if player_style else 0.60, cloth)
    shoulders.rotation.z = PI * 0.5
    shoulders.position = Vector3(0.0, 0.58, 0.01)
    torso.add_child(shoulders)

    head_root = Node3D.new()
    head_root.name = "Head"
    head_root.position = Vector3(0.0, 0.72, 0.02)
    torso.add_child(head_root)
    _build_head(head_root, skin, hat, gear)

    arm_l = _build_arm(torso, -1.0, cloth, gear, skin)
    arm_r = _build_arm(torso, 1.0, cloth, gear, skin)
    elbow_l = arm_l.get_node("Elbow")
    elbow_r = arm_r.get_node("Elbow")
    leg_l = _build_leg(pelvis, -1.0, cloth_dark, gear, boot)
    leg_r = _build_leg(pelvis, 1.0, cloth_dark, gear, boot)
    knee_l = leg_l.get_node("Knee")
    knee_r = leg_r.get_node("Knee")
    foot_l = knee_l.get_node("Foot")
    foot_r = knee_r.get_node("Foot")
    toe_l = foot_l.get_node("Toe")
    toe_r = foot_r.get_node("Toe")


func _build_head(root: Node3D, skin: Color, hat: Color, gear: Color) -> void:
    var neck := GeomUtil.cylinder_mesh(0.065, 0.16, skin, 0.78, 0.0)
    neck.position.y = 0.05
    root.add_child(neck)

    var skull := GeomUtil.sphere_mesh(0.152 if player_style else 0.145, skin)
    skull.scale = Vector3(0.90, 1.10, 0.94)
    skull.position = Vector3(0.0, 0.22, 0.02)
    root.add_child(skull)

    var jaw := GeomUtil.sphere_mesh(0.098, skin)
    jaw.scale = Vector3(0.88, 0.68, 0.80)
    jaw.position = Vector3(0.0, 0.115, -0.015)
    root.add_child(jaw)

    var chin := GeomUtil.sphere_mesh(0.042, skin)
    chin.scale = Vector3(0.85, 0.70, 0.90)
    chin.position = Vector3(0.0, 0.072, -0.095)
    root.add_child(chin)

    var brow := GeomUtil.box_mesh(Vector3(0.18, 0.028, 0.045), skin, 0.70, 0.0)
    brow.position = Vector3(0.0, 0.242, -0.118)
    root.add_child(brow)

    var nose := GeomUtil.capsule_mesh(0.018, 0.062, skin)
    nose.rotation.x = 0.62
    nose.position = Vector3(0.0, 0.178, -0.152)
    root.add_child(nose)

    var mouth := GeomUtil.box_mesh(Vector3(0.068, 0.011, 0.016), Color(0.46, 0.24, 0.22), 0.55, 0.0)
    mouth.position = Vector3(0.0, 0.112, -0.142)
    root.add_child(mouth)

    for side in [-1.0, 1.0]:
        var ear := GeomUtil.sphere_mesh(0.036, skin)
        ear.scale = Vector3(0.40, 1.08, 0.70)
        ear.position = Vector3(side * 0.138, 0.200, 0.018)
        root.add_child(ear)

        var cheek := GeomUtil.sphere_mesh(0.048, skin)
        cheek.scale = Vector3(0.78, 0.72, 0.62)
        cheek.position = Vector3(side * 0.092, 0.148, -0.072)
        root.add_child(cheek)

        var brow_hair := GeomUtil.box_mesh(
            Vector3(0.055, 0.012, 0.018),
            Color(0.14, 0.11, 0.09) if player_style else Color(0.22, 0.15, 0.10),
            0.92,
            0.0
        )
        brow_hair.position = Vector3(side * 0.048, 0.232, -0.128)
        root.add_child(brow_hair)

        var sclera := GeomUtil.sphere_mesh(0.026, Color(0.94, 0.94, 0.91))
        sclera.position = Vector3(side * 0.046, 0.198, -0.138)
        root.add_child(sclera)
        var iris := GeomUtil.sphere_mesh(
            0.015,
            Color(0.16, 0.22, 0.20) if player_style else Color(0.24, 0.16, 0.10)
        )
        iris.position = Vector3(side * 0.046, 0.196, -0.152)
        root.add_child(iris)
        var pupil := GeomUtil.sphere_mesh(0.007, Color(0.04, 0.04, 0.04))
        pupil.position = Vector3(side * 0.046, 0.196, -0.160)
        root.add_child(pupil)

    var scalp := GeomUtil.sphere_mesh(0.155, Color(0.12, 0.10, 0.09) if player_style else Color(0.20, 0.14, 0.10))
    scalp.scale = Vector3(0.88, 0.38, 0.90)
    scalp.position = Vector3(0.0, 0.318, 0.02)
    root.add_child(scalp)

    # Hard-hat sits on the crown. A ring brim, not a visor over the face.
    var dome := GeomUtil.sphere_mesh(0.168, hat)
    dome.scale = Vector3(1.00, 0.40, 0.98)
    dome.position = Vector3(0.0, 0.355, 0.02)
    root.add_child(dome)
    var brim := GeomUtil.cylinder_mesh(0.188, 0.016, hat, 0.72, 0.08)
    brim.scale = Vector3(1.08, 1.0, 1.04)
    brim.position = Vector3(0.0, 0.292, 0.02)
    root.add_child(brim)
    var band := GeomUtil.cylinder_mesh(0.160, 0.032, gear, 0.84, 0.10)
    band.position = Vector3(0.0, 0.302, 0.02)
    root.add_child(band)


func _build_arm(parent: Node3D, side: float, cloth: Color, gear: Color, skin: Color) -> Node3D:
    var shoulder := Node3D.new()
    shoulder.name = "ArmL" if side < 0.0 else "ArmR"
    shoulder.position = Vector3(side * 0.36, 0.56, 0.0)
    parent.add_child(shoulder)

    var deltoid := GeomUtil.sphere_mesh(0.115 if player_style else 0.105, cloth)
    deltoid.scale = Vector3(1.05, 1.12, 0.95)
    shoulder.add_child(deltoid)

    var upper := GeomUtil.capsule_mesh(0.072, 0.42, cloth)
    upper.position.y = -0.20
    shoulder.add_child(upper)

    var elbow := Node3D.new()
    elbow.name = "Elbow"
    elbow.position.y = -0.42
    shoulder.add_child(elbow)

    var joint := GeomUtil.sphere_mesh(0.064, cloth)
    elbow.add_child(joint)

    var forearm := GeomUtil.capsule_mesh(0.058, 0.38, cloth)
    forearm.position.y = -0.18
    elbow.add_child(forearm)

    var cuff := GeomUtil.cylinder_mesh(0.054, 0.045, gear, 0.88, 0.08)
    cuff.position.y = -0.34
    elbow.add_child(cuff)

    var palm := GeomUtil.box_mesh(Vector3(0.065, 0.095, 0.036), skin, 0.72, 0.0)
    palm.position = Vector3(0.0, -0.42, -0.01)
    elbow.add_child(palm)
    for finger_i in 3:
        var finger := GeomUtil.capsule_mesh(0.011, 0.052, skin)
        finger.position = Vector3(-0.020 + float(finger_i) * 0.020, -0.49, -0.01)
        elbow.add_child(finger)
    var thumb := GeomUtil.capsule_mesh(0.012, 0.042, skin)
    thumb.rotation.z = side * 0.7
    thumb.position = Vector3(side * 0.036, -0.43, 0.01)
    elbow.add_child(thumb)
    return shoulder


func _build_leg(parent: Node3D, side: float, cloth: Color, gear: Color, boot: Color) -> Node3D:
    var hip := Node3D.new()
    hip.name = "LegL" if side < 0.0 else "LegR"
    hip.position = Vector3(side * 0.12, -0.08, 0.0)
    parent.add_child(hip)

    var thigh := GeomUtil.capsule_mesh(0.100, 0.42, cloth)
    thigh.position.y = -0.20
    thigh.scale = Vector3(1.08, 1.0, 0.95)
    hip.add_child(thigh)

    var knee := Node3D.new()
    knee.name = "Knee"
    knee.position.y = -0.42
    hip.add_child(knee)

    var knee_joint := GeomUtil.sphere_mesh(0.085, cloth)
    knee.add_child(knee_joint)

    var shin := GeomUtil.capsule_mesh(0.072, 0.40, cloth)
    shin.position.y = -0.20
    knee.add_child(shin)

    var foot := Node3D.new()
    foot.name = "Foot"
    foot.position.y = -0.42
    knee.add_child(foot)

    var ankle := GeomUtil.sphere_mesh(0.052, boot)
    ankle.position.y = 0.04
    foot.add_child(ankle)
    var sole := GeomUtil.box_mesh(Vector3(0.095, 0.065, 0.25), boot, 0.92, 0.0)
    sole.position = Vector3(0.0, -0.02, -0.06)
    foot.add_child(sole)

    var toe := Node3D.new()
    toe.name = "Toe"
    toe.position = Vector3(0.0, -0.02, -0.20)
    foot.add_child(toe)
    var cap := GeomUtil.sphere_mesh(0.046, boot)
    cap.scale = Vector3(1.15, 0.62, 1.20)
    toe.add_child(cap)
    return hip


func apply_body_impact(direction: Vector3, energy: float, world_point: Vector3 = Vector3.ZERO) -> void:
    var severity := clampf(energy / 6500.0, 0.0, 1.0)
    crush = clampf(crush + severity * 0.85, 0.0, 1.0)
    if direction.length_squared() > 0.001:
        crush_dir = direction.normalized()
    var local_y := world_point.y
    if local_y < 1.05 or crush_dir.y < -0.15:
        var side := crush_dir.dot(global_basis.x) if is_inside_tree() else crush_dir.x
        if side < 0.0:
            limp_l = clampf(limp_l + severity * 0.70, 0.0, 1.0)
        else:
            limp_r = clampf(limp_r + severity * 0.70, 0.0, 1.0)


func animate(delta: float, planar_speed: float, reference_speed: float, attack_amount: float, hit_amount: float, dead: bool) -> void:
    if pelvis == null:
        return
    var speed_n := clampf(planar_speed / maxf(reference_speed, 0.1), 0.0, 1.35)
    phase += delta * (4.2 + planar_speed * 1.35)
    var stride := sin(phase) * 0.62 * speed_n
    var lift_l := maxf(0.0, -sin(phase)) * 0.72 * speed_n
    var lift_r := maxf(0.0, sin(phase)) * 0.72 * speed_n
    leg_l.rotation = Vector3(stride, 0.0, 0.0)
    leg_r.rotation = Vector3(-stride, 0.0, 0.0)
    knee_l.rotation.x = lift_l
    knee_r.rotation.x = lift_r
    arm_l.rotation = Vector3(-stride * 0.72, 0.0, 0.0)
    arm_r.rotation = Vector3(stride * 0.72, 0.0, 0.0)
    elbow_l.rotation.x = -0.10 - absf(stride) * 0.22
    elbow_r.rotation.x = -0.10 - absf(stride) * 0.22
    pelvis.position.y = 0.94 + absf(sin(phase * 2.0)) * 0.025 * speed_n
    if spine != null:
        spine.rotation = Vector3(0.0, -sin(phase) * 0.10 * speed_n, sin(phase) * 0.06 * speed_n)
    torso.rotation = Vector3(-0.04 * speed_n, sin(phase) * 0.14 * speed_n, -sin(phase) * 0.08 * speed_n)
    head_root.rotation = Vector3(0.02 * speed_n, -torso.rotation.y * 0.45, 0.0)

    if attack_amount > 0.0:
        var action := sin(clampf(attack_amount, 0.0, 1.0) * PI)
        if attack_mode == 1:
            _pose_kick(action)
        elif attack_mode == 2:
            _pose_tackle(action)
        else:
            _pose_punch(action)

    if hit_amount > 0.0:
        torso.rotation.x -= hit_amount * 0.30
        torso.rotation.z += attack_side * hit_amount * 0.16
        head_root.rotation.x = hit_amount * 0.22

    _apply_crush(delta)
    death_blend = move_toward(death_blend, 1.0 if dead else 0.0, delta * (2.8 if dead else 5.0))
    if death_blend > 0.0:
        rotation.z = lerp(0.0, attack_side * 1.32, death_blend)
        rotation.x = lerp(0.0, -0.24, death_blend)
        position.y = -0.12 * death_blend
        leg_l.rotation.x *= 1.0 - death_blend * 0.75
        leg_r.rotation.x *= 1.0 - death_blend * 0.75
    else:
        rotation.z = 0.0
        rotation.x = 0.0
        position.y = 0.0


func _apply_crush(delta: float) -> void:
    crush = move_toward(crush, maxf(limp_l, limp_r) * 0.22, delta * 1.4)
    if torso == null:
        return
    var squash := 1.0 - crush * 0.16
    var spread := 1.0 + crush * 0.10
    torso.scale = Vector3(spread, squash, spread)


func _pose_punch(amount: float) -> void:
    torso.rotation.y += attack_side * amount * 0.40
    var attack_arm := arm_r if attack_side > 0.0 else arm_l
    var attack_elbow := elbow_r if attack_side > 0.0 else elbow_l
    attack_arm.rotation.x = -1.05 * amount
    attack_arm.rotation.z = -attack_side * 0.24 * amount
    attack_elbow.rotation.x = -0.42 + 1.12 * amount
    head_root.rotation.y = -attack_side * amount * 0.14

func _pose_kick(amount: float) -> void:
    var kick_leg := leg_r if attack_side > 0.0 else leg_l
    var kick_knee := knee_r if attack_side > 0.0 else knee_l
    var brace_leg := leg_l if attack_side > 0.0 else leg_r
    torso.rotation.x = -0.20 * amount
    torso.rotation.y = -attack_side * 0.22 * amount
    torso.rotation.z = -attack_side * 0.16 * amount
    kick_leg.rotation.x = -1.25 * amount
    kick_leg.rotation.z = attack_side * 0.16 * amount
    kick_knee.rotation.x = 0.22 + 0.72 * (1.0 - amount)
    brace_leg.rotation.x = 0.22 * amount
    arm_l.rotation.x = 0.54 * amount
    arm_r.rotation.x = 0.54 * amount
    arm_l.rotation.z = -0.34 * amount
    arm_r.rotation.z = 0.34 * amount

func _pose_tackle(amount: float) -> void:
    torso.rotation.x = -0.48 * amount
    pelvis.position.y = 0.94 - 0.12 * amount
    arm_l.rotation.x = 0.74 * amount
    arm_r.rotation.x = 0.74 * amount
    arm_l.rotation.z = -0.30 * amount
    arm_r.rotation.z = 0.30 * amount
    elbow_l.rotation.x = -0.52 * amount
    elbow_r.rotation.x = -0.52 * amount
    leg_l.rotation.x = -0.26 * amount
    leg_r.rotation.x = 0.26 * amount
    head_root.rotation.x = 0.18 * amount

func pose_climb(t: float, side: float) -> void:
    if pelvis == null:
        return
    var pull := sin(clampf(t, 0.0, 1.0) * PI)
    phase += 0.13
    if spine != null:
        spine.rotation = Vector3(-0.08 - pull * 0.10, side * 0.06, -side * 0.08)
    torso.rotation = Vector3(-0.18 - pull * 0.18, side * 0.08, -side * 0.10)
    pelvis.position.y = 0.94 + pull * 0.06
    arm_l.rotation = Vector3(-1.35 + sin(phase) * 0.10, 0.0, -0.38)
    arm_r.rotation = Vector3(-1.42 - sin(phase) * 0.10, 0.0, 0.38)
    elbow_l.rotation.x = 0.72 + pull * 0.34
    elbow_r.rotation.x = 0.82 + pull * 0.28
    leg_l.rotation.x = -0.68 + pull * 0.36
    leg_r.rotation.x = 0.44 - pull * 0.18
    knee_l.rotation.x = 1.02
    knee_r.rotation.x = 0.78
    head_root.rotation = Vector3(-0.08, -side * 0.18, 0.0)

func set_attack_side(side: float) -> void:
    attack_side = 1.0 if side >= 0.0 else -1.0

func set_attack_mode(mode: int) -> void:
    attack_mode = clampi(mode, 0, 2)
