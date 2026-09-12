extends Node3D

const GeomUtil = preload("res://scripts/geom.gd")

var player_style := false
var phase := 0.0
var attack_side := 1.0
var attack_mode := 0
var death_blend := 0.0

var pelvis: Node3D
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

func configure(is_player: bool) -> void:
    player_style = is_player
    _build()

func _build() -> void:
    var cloth := Color(0.16, 0.19, 0.185) if player_style else Color(0.22, 0.26, 0.235)
    var cloth_dark := Color(0.065, 0.075, 0.072)
    var accent := Color(0.48, 0.29, 0.065) if player_style else Color(0.72, 0.49, 0.07)
    var skin := Color(0.62, 0.46, 0.35) if player_style else Color(0.54, 0.41, 0.33)
    var gear := Color(0.085, 0.10, 0.095)
    var steel := Color(0.18, 0.20, 0.19)

    pelvis = Node3D.new()
    pelvis.position = Vector3(0.0, 0.94, 0.0)
    add_child(pelvis)

    var hip_mass := GeomUtil.capsule_mesh(0.285, 0.52, cloth_dark)
    hip_mass.scale = Vector3(1.18 if player_style else 1.08, 1.0, 0.72)
    pelvis.add_child(hip_mass)
    var hip_belt := GeomUtil.cylinder_mesh(0.34, 0.11, gear, 0.90, 0.08)
    hip_belt.scale = Vector3(1.08, 1.0, 0.72)
    hip_belt.position.y = 0.17
    pelvis.add_child(hip_belt)

    torso = Node3D.new()
    torso.position = Vector3(0.0, 0.24, 0.0)
    pelvis.add_child(torso)

    var torso_mass := GeomUtil.capsule_mesh(0.37 if player_style else 0.345, 0.90, cloth)
    torso_mass.scale = Vector3(1.18 if player_style else 1.08, 1.0, 0.70)
    torso_mass.position.y = 0.36
    torso.add_child(torso_mass)

    var shoulder_girdle := GeomUtil.capsule_mesh(0.145, 0.90 if player_style else 0.82, cloth)
    shoulder_girdle.rotation.z = PI * 0.5
    shoulder_girdle.position = Vector3(0.0, 0.67, 0.0)
    torso.add_child(shoulder_girdle)

    var chest_plate := GeomUtil.cylinder_mesh(0.31, 0.085, accent, 0.78, 0.07)
    chest_plate.rotation.x = PI * 0.5
    chest_plate.scale = Vector3(1.30, 1.0, 0.78)
    chest_plate.position = Vector3(0.0, 0.43, -0.29)
    torso.add_child(chest_plate)

    var abdomen_pad := GeomUtil.capsule_mesh(0.22, 0.37, gear)
    abdomen_pad.scale = Vector3(1.28, 1.0, 0.50)
    abdomen_pad.position = Vector3(0.0, 0.06, -0.20)
    torso.add_child(abdomen_pad)

    for side in [-1.0, 1.0]:
        var strap := GeomUtil.capsule_mesh(0.036, 0.72, gear)
        strap.position = Vector3(side * 0.24, 0.38, -0.30)
        torso.add_child(strap)

    head_root = Node3D.new()
    head_root.position = Vector3(0.0, 0.88, 0.0)
    torso.add_child(head_root)

    var neck := GeomUtil.cylinder_mesh(0.105, 0.22, skin, 0.82, 0.0)
    neck.position.y = 0.02
    head_root.add_child(neck)

    var head := GeomUtil.sphere_mesh(0.235 if player_style else 0.225, skin)
    head.scale = Vector3(0.94, 1.08, 0.92)
    head.position.y = 0.27
    head_root.add_child(head)

    var jaw := GeomUtil.capsule_mesh(0.125, 0.24, skin)
    jaw.scale = Vector3(1.20, 0.85, 0.76)
    jaw.position = Vector3(0.0, 0.15, -0.055)
    head_root.add_child(jaw)

    var helmet_dome := GeomUtil.sphere_mesh(0.27, Color(0.12, 0.145, 0.135) if player_style else Color(0.76, 0.54, 0.075))
    helmet_dome.scale = Vector3(1.04, 0.52, 1.02)
    helmet_dome.position = Vector3(0.0, 0.43, 0.0)
    head_root.add_child(helmet_dome)

    var helmet_band := GeomUtil.cylinder_mesh(0.275, 0.075, Color(0.10, 0.12, 0.115) if player_style else Color(0.62, 0.41, 0.05), 0.76, 0.05)
    helmet_band.position = Vector3(0.0, 0.36, 0.0)
    head_root.add_child(helmet_band)

    var brim := GeomUtil.capsule_mesh(0.055, 0.42, Color(0.10, 0.12, 0.115) if player_style else Color(0.62, 0.41, 0.05))
    brim.rotation.z = PI * 0.5
    brim.scale = Vector3(1.0, 1.0, 0.62)
    brim.position = Vector3(0.0, 0.35, -0.23)
    head_root.add_child(brim)

    var face_guard := GeomUtil.capsule_mesh(0.035, 0.32, steel)
    face_guard.rotation.z = PI * 0.5
    face_guard.position = Vector3(0.0, 0.25, -0.225)
    head_root.add_child(face_guard)

    arm_l = _build_arm(torso, -1.0, cloth, gear, skin)
    arm_r = _build_arm(torso, 1.0, cloth, gear, skin)
    elbow_l = arm_l.get_node("Elbow")
    elbow_r = arm_r.get_node("Elbow")
    leg_l = _build_leg(pelvis, -1.0, cloth_dark, gear)
    leg_r = _build_leg(pelvis, 1.0, cloth_dark, gear)
    knee_l = leg_l.get_node("Knee")
    knee_r = leg_r.get_node("Knee")

func _build_arm(parent: Node3D, side: float, cloth: Color, gear: Color, skin: Color) -> Node3D:
    var shoulder := Node3D.new()
    shoulder.name = "ArmL" if side < 0.0 else "ArmR"
    shoulder.position = Vector3(side * 0.47, 0.67, 0.0)
    parent.add_child(shoulder)

    var deltoid := GeomUtil.sphere_mesh(0.18 if player_style else 0.165, cloth)
    deltoid.scale = Vector3(1.0, 1.10, 0.92)
    shoulder.add_child(deltoid)

    var upper := GeomUtil.capsule_mesh(0.12 if player_style else 0.108, 0.55, cloth)
    upper.position.y = -0.27
    upper.scale = Vector3(1.03, 1.0, 0.94)
    shoulder.add_child(upper)

    var upper_guard := GeomUtil.cylinder_mesh(0.135, 0.16, gear, 0.90, 0.10)
    upper_guard.position.y = -0.12
    shoulder.add_child(upper_guard)

    var elbow := Node3D.new()
    elbow.name = "Elbow"
    elbow.position.y = -0.53
    shoulder.add_child(elbow)

    var elbow_joint := GeomUtil.sphere_mesh(0.12, gear)
    elbow_joint.scale = Vector3(1.05, 0.92, 1.0)
    elbow.add_child(elbow_joint)

    var forearm := GeomUtil.capsule_mesh(0.103, 0.49, cloth)
    forearm.position.y = -0.245
    forearm.scale = Vector3(0.98, 1.0, 0.91)
    elbow.add_child(forearm)

    var wrist := GeomUtil.cylinder_mesh(0.085, 0.10, gear, 0.92, 0.08)
    wrist.position.y = -0.46
    elbow.add_child(wrist)

    var hand := GeomUtil.capsule_mesh(0.105, 0.22, skin)
    hand.position = Vector3(0.0, -0.54, -0.025)
    hand.scale = Vector3(1.0, 0.92, 0.72)
    elbow.add_child(hand)

    var glove := GeomUtil.sphere_mesh(0.11, gear)
    glove.scale = Vector3(1.0, 0.80, 0.78)
    glove.position = Vector3(0.0, -0.56, -0.07)
    elbow.add_child(glove)
    return shoulder

func _build_leg(parent: Node3D, side: float, cloth: Color, gear: Color) -> Node3D:
    var hip := Node3D.new()
    hip.name = "LegL" if side < 0.0 else "LegR"
    hip.position = Vector3(side * 0.20, -0.08, 0.0)
    parent.add_child(hip)

    var thigh := GeomUtil.capsule_mesh(0.155, 0.58, cloth)
    thigh.position.y = -0.28
    thigh.scale = Vector3(1.04, 1.0, 0.92)
    hip.add_child(thigh)

    var knee := Node3D.new()
    knee.name = "Knee"
    knee.position.y = -0.56
    hip.add_child(knee)

    var knee_joint := GeomUtil.sphere_mesh(0.14, gear)
    knee_joint.scale = Vector3(1.05, 0.86, 1.0)
    knee.add_child(knee_joint)

    var knee_pad := GeomUtil.sphere_mesh(0.115, Color(0.10, 0.11, 0.105))
    knee_pad.scale = Vector3(1.0, 0.68, 0.48)
    knee_pad.position = Vector3(0.0, -0.01, -0.11)
    knee.add_child(knee_pad)

    var shin := GeomUtil.capsule_mesh(0.125, 0.51, cloth)
    shin.position.y = -0.255
    shin.scale = Vector3(0.96, 1.0, 0.88)
    knee.add_child(shin)

    var ankle := GeomUtil.cylinder_mesh(0.10, 0.11, gear, 0.94, 0.08)
    ankle.position.y = -0.49
    knee.add_child(ankle)

    var boot := GeomUtil.capsule_mesh(0.125, 0.44, Color(0.035, 0.042, 0.039))
    boot.rotation.x = PI * 0.5
    boot.scale = Vector3(1.08, 1.0, 0.78)
    boot.position = Vector3(0.0, -0.57, -0.11)
    knee.add_child(boot)
    return hip

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
    torso.rotation = Vector3(0.0, sin(phase) * 0.055 * speed_n, -sin(phase) * 0.025 * speed_n)
    head_root.rotation = Vector3.ZERO

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
