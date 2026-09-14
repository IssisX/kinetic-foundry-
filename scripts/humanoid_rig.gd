extends Node3D

const GeomUtil = preload("res://scripts/geom.gd")

var player_style := false
var look_id := 0
var role := 0
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

var _brow_l: Node3D
var _brow_r: Node3D
var _jaw: Node3D
var _mouth: Node3D
var _lid_l: Node3D
var _lid_r: Node3D
var _look_data: Dictionary = {}


func configure(is_player: bool, id: int = 0, crew_role: int = 0) -> void:
    player_style = is_player
    look_id = id
    role = crew_role
    _build()


func _look() -> Dictionary:
    var rng := RandomNumberGenerator.new()
    rng.seed = int(absi(hash("%s-%s-%s" % [look_id, role, 1 if player_style else 2])))
    var skins := [
        Color(0.86, 0.68, 0.54),
        Color(0.76, 0.56, 0.42),
        Color(0.64, 0.44, 0.32),
        Color(0.50, 0.34, 0.24),
        Color(0.38, 0.24, 0.16),
        Color(0.90, 0.74, 0.60)
    ]
    var eyes := [
        Color(0.14, 0.22, 0.20),
        Color(0.32, 0.18, 0.08),
        Color(0.16, 0.32, 0.42),
        Color(0.24, 0.20, 0.12),
        Color(0.28, 0.38, 0.18),
        Color(0.40, 0.36, 0.30)
    ]
    var hairs := [
        Color(0.07, 0.05, 0.04),
        Color(0.22, 0.12, 0.06),
        Color(0.38, 0.24, 0.10),
        Color(0.12, 0.12, 0.13),
        Color(0.46, 0.42, 0.34),
        Color(0.18, 0.08, 0.05)
    ]
    if player_style:
        return {
            "cloth": Color(0.16, 0.18, 0.17),
            "cloth_dark": Color(0.09, 0.10, 0.09),
            "skin": Color(0.78, 0.58, 0.44),
            "gear": Color(0.11, 0.12, 0.11),
            "boot": Color(0.07, 0.07, 0.07),
            "eye": Color(0.16, 0.32, 0.34),
            "hair": Color(0.08, 0.06, 0.05),
            "hat": Color(0.14, 0.15, 0.14),
            "wear_hat": false,
            "beard": false,
            "mustache": false,
            "scowl": false,
            "mouth_w": 0.068,
            "brow_drop": 0.0,
            "hair_long": true,
            "head_s": 1.02
        }
    var runner := role == 2
    var heavy := role == 1
    var rigger := role == 3
    var plate := role == 4
    return {
        "cloth": Color(0.23, 0.25, 0.22).lerp(Color(0.16, 0.18, 0.24), rng.randf() * 0.55),
        "cloth_dark": Color(0.12, 0.13, 0.12),
        "skin": skins[rng.randi() % skins.size()],
        "gear": Color(0.12, 0.13, 0.12),
        "boot": Color(0.07, 0.07, 0.07),
        "eye": eyes[rng.randi() % eyes.size()],
        "hair": hairs[rng.randi() % hairs.size()],
        "hat": Color(0.82, 0.62, 0.12) if rigger else Color(0.76, 0.54, 0.10),
        "wear_hat": rigger,
        "beard": heavy or rng.randf() > 0.58,
        "mustache": (not heavy) and rng.randf() > 0.62,
        "scowl": heavy or plate,
        "mouth_w": 0.048 + rng.randf() * 0.034,
        "brow_drop": (0.016 if heavy else 0.0) + rng.randf() * 0.010,
        "hair_long": rng.randf() > 0.48,
        "head_s": 0.94 + rng.randf() * 0.12
    }


func _build() -> void:
    _look_data = _look()
    var look: Dictionary = _look_data
    var cloth: Color = look.get("cloth")
    var cloth_dark: Color = look.get("cloth_dark")
    var skin: Color = look.get("skin")
    var gear: Color = look.get("gear")
    var boot: Color = look.get("boot")

    pelvis = Node3D.new()
    pelvis.name = "Pelvis"
    pelvis.position = Vector3(0.0, 0.94, 0.0)
    add_child(pelvis)

    var hips := GeomUtil.box_mesh(Vector3(0.36, 0.22, 0.20), cloth_dark, 0.90, 0.04)
    hips.position.y = 0.00
    pelvis.add_child(hips)
    var belt := GeomUtil.box_mesh(Vector3(0.38, 0.05, 0.22), gear, 0.90, 0.10)
    belt.position.y = 0.12
    pelvis.add_child(belt)

    spine = Node3D.new()
    spine.name = "Spine"
    spine.position = Vector3(0.0, 0.12, 0.0)
    pelvis.add_child(spine)

    torso = Node3D.new()
    torso.name = "Torso"
    torso.position = Vector3(0.0, 0.12, 0.0)
    spine.add_child(torso)

    var chest := GeomUtil.box_mesh(
        Vector3(0.40 if player_style else 0.36, 0.36, 0.20),
        cloth,
        0.86,
        0.03
    )
    chest.position = Vector3(0.0, 0.40, 0.01)
    torso.add_child(chest)
    var gut := GeomUtil.box_mesh(
        Vector3(0.36 if player_style else 0.33, 0.24, 0.18),
        cloth,
        0.88,
        0.03
    )
    gut.position = Vector3(0.0, 0.14, 0.01)
    torso.add_child(gut)

    for side in [-1.0, 1.0]:
        var pad := GeomUtil.box_mesh(Vector3(0.13, 0.10, 0.16), cloth, 0.86, 0.04)
        pad.position = Vector3(side * 0.26, 0.56, 0.01)
        torso.add_child(pad)

    head_root = Node3D.new()
    head_root.name = "Head"
    head_root.position = Vector3(0.0, 0.70, 0.02)
    torso.add_child(head_root)
    _build_head(head_root, look)

    arm_l = _build_arm(torso, -1.0, cloth, gear, skin)
    arm_r = _build_arm(torso, 1.0, cloth, gear, skin)
    elbow_l = arm_l.get_node("Elbow")
    elbow_r = arm_r.get_node("Elbow")
    leg_l = _build_leg(pelvis, -1.0, cloth_dark, boot)
    leg_r = _build_leg(pelvis, 1.0, cloth_dark, boot)
    knee_l = leg_l.get_node("Knee")
    knee_r = leg_r.get_node("Knee")
    foot_l = knee_l.get_node("Foot")
    foot_r = knee_r.get_node("Foot")
    toe_l = foot_l.get_node("Toe")
    toe_r = foot_r.get_node("Toe")


func _build_head(root: Node3D, look: Dictionary) -> void:
    var skin: Color = look.get("skin")
    var hair: Color = look.get("hair")
    var eye: Color = look.get("eye")
    var scowl: bool = bool(look.get("scowl", false))
    var brow_drop: float = float(look.get("brow_drop", 0.0))
    var head_s: float = float(look.get("head_s", 1.0))
    var mouth_w: float = float(look.get("mouth_w", 0.06))

    var neck := GeomUtil.box_mesh(Vector3(0.11, 0.14, 0.11), skin, 0.78, 0.0)
    neck.position.y = 0.06
    root.add_child(neck)

    # Flattened in Z so the face is a plane we can put features on,
    # not a sphere the camera reads as a helmet.
    var skull := GeomUtil.sphere_mesh(0.148 * head_s, skin)
    skull.scale = Vector3(0.92, 1.06, 0.80)
    skull.position = Vector3(0.0, 0.228, 0.055)
    root.add_child(skull)

    var face := GeomUtil.box_mesh(Vector3(0.168, 0.176, 0.070), skin, 0.62, 0.0)
    face.position = Vector3(0.0, 0.186, -0.102)
    root.add_child(face)

    _jaw = GeomUtil.box_mesh(Vector3(0.140, 0.070, 0.080), skin, 0.64, 0.0)
    _jaw.position = Vector3(0.0, 0.100, -0.090)
    root.add_child(_jaw)

    var chin := GeomUtil.sphere_mesh(0.036, skin)
    chin.scale = Vector3(0.90, 0.55, 0.85)
    chin.position = Vector3(0.0, 0.058, -0.128)
    root.add_child(chin)

    var nose := GeomUtil.box_mesh(Vector3(0.028, 0.058, 0.052), skin, 0.55, 0.0)
    nose.position = Vector3(0.0, 0.176, -0.168)
    root.add_child(nose)

    _mouth = GeomUtil.box_mesh(
        Vector3(mouth_w, 0.016, 0.020),
        Color(0.42, 0.16, 0.16) if scowl else Color(0.50, 0.24, 0.24),
        0.50,
        0.0
    )
    _mouth.position = Vector3(0.0, 0.096 if scowl else 0.104, -0.155)
    root.add_child(_mouth)

    for side in [-1.0, 1.0]:
        var ear := GeomUtil.sphere_mesh(0.034, skin)
        ear.scale = Vector3(0.34, 1.12, 0.68)
        ear.position = Vector3(side * 0.140, 0.200, 0.030)
        root.add_child(ear)

        var cheek := GeomUtil.sphere_mesh(0.040, skin)
        cheek.scale = Vector3(0.62, 0.58, 0.48)
        cheek.position = Vector3(side * 0.078, 0.140, -0.092)
        root.add_child(cheek)

        var brow := GeomUtil.box_mesh(
            Vector3(0.052, 0.012, 0.018),
            hair,
            0.92,
            0.0
        )
        brow.position = Vector3(
            side * 0.050,
            0.248 - brow_drop,
            -0.142
        )
        brow.rotation.z = side * (0.16 if scowl else 0.05)
        root.add_child(brow)
        if side < 0.0:
            _brow_l = brow
        else:
            _brow_r = brow

        var lid := GeomUtil.box_mesh(Vector3(0.048, 0.006, 0.010), skin, 0.60, 0.0)
        lid.position = Vector3(side * 0.048, 0.218, -0.150)
        root.add_child(lid)
        if side < 0.0:
            _lid_l = lid
        else:
            _lid_r = lid

        var sclera := GeomUtil.sphere_mesh(0.032, Color(0.97, 0.97, 0.95))
        sclera.position = Vector3(side * 0.048, 0.198, -0.148)
        root.add_child(sclera)
        var iris := GeomUtil.sphere_mesh(0.020, eye)
        iris.position = Vector3(side * 0.048, 0.196, -0.166)
        root.add_child(iris)
        var pupil := GeomUtil.sphere_mesh(0.009, Color(0.03, 0.03, 0.03))
        pupil.position = Vector3(side * 0.048, 0.196, -0.176)
        root.add_child(pupil)

    var scalp := GeomUtil.sphere_mesh(0.150 * head_s, hair)
    scalp.scale = Vector3(0.90, 0.34, 0.72)
    scalp.position = Vector3(0.0, 0.338, 0.070)
    root.add_child(scalp)

    if bool(look.get("hair_long", false)):
        for side in [-1.0, 1.0]:
            var lock := GeomUtil.sphere_mesh(0.042, hair)
            lock.scale = Vector3(0.48, 1.20, 0.58)
            lock.position = Vector3(side * 0.122, 0.175, 0.040)
            root.add_child(lock)

    if bool(look.get("beard", false)):
        var beard := GeomUtil.box_mesh(Vector3(0.130, 0.070, 0.070), hair, 0.90, 0.0)
        beard.position = Vector3(0.0, 0.062, -0.072)
        root.add_child(beard)
    if bool(look.get("mustache", false)):
        var stash := GeomUtil.box_mesh(Vector3(0.068, 0.010, 0.016), hair, 0.90, 0.0)
        stash.position = Vector3(0.0, 0.118, -0.154)
        root.add_child(stash)

    # Crown only, high on the skull. Never a brim, never a band.
    if bool(look.get("wear_hat", false)):
        var dome := GeomUtil.sphere_mesh(0.152 * head_s, look.get("hat"))
        dome.scale = Vector3(0.94, 0.30, 0.86)
        dome.position = Vector3(0.0, 0.392, 0.055)
        root.add_child(dome)


func _build_arm(parent: Node3D, side: float, cloth: Color, gear: Color, skin: Color) -> Node3D:
    var shoulder := Node3D.new()
    shoulder.name = "ArmL" if side < 0.0 else "ArmR"
    shoulder.position = Vector3(side * 0.34, 0.54, 0.0)
    parent.add_child(shoulder)

    var deltoid := GeomUtil.box_mesh(Vector3(0.14, 0.14, 0.14), cloth, 0.86, 0.04)
    shoulder.add_child(deltoid)

    var upper := GeomUtil.capsule_mesh(0.055, 0.46, cloth)
    upper.position.y = -0.22
    shoulder.add_child(upper)

    var elbow := Node3D.new()
    elbow.name = "Elbow"
    elbow.position.y = -0.44
    shoulder.add_child(elbow)

    var joint := GeomUtil.sphere_mesh(0.052, cloth)
    elbow.add_child(joint)

    var forearm := GeomUtil.capsule_mesh(0.046, 0.40, cloth)
    forearm.position.y = -0.18
    elbow.add_child(forearm)

    var cuff := GeomUtil.box_mesh(Vector3(0.09, 0.04, 0.09), gear, 0.88, 0.08)
    cuff.position.y = -0.36
    elbow.add_child(cuff)

    var palm := GeomUtil.box_mesh(Vector3(0.062, 0.090, 0.034), skin, 0.72, 0.0)
    palm.position = Vector3(0.0, -0.44, -0.01)
    elbow.add_child(palm)
    for finger_i in 3:
        var finger := GeomUtil.capsule_mesh(0.010, 0.050, skin)
        finger.position = Vector3(-0.018 + float(finger_i) * 0.018, -0.51, -0.01)
        elbow.add_child(finger)
    var thumb := GeomUtil.capsule_mesh(0.011, 0.040, skin)
    thumb.rotation.z = side * 0.7
    thumb.position = Vector3(side * 0.034, -0.45, 0.01)
    elbow.add_child(thumb)
    return shoulder


func _build_leg(parent: Node3D, side: float, cloth: Color, boot: Color) -> Node3D:
    var hip := Node3D.new()
    hip.name = "LegL" if side < 0.0 else "LegR"
    hip.position = Vector3(side * 0.13, -0.08, 0.0)
    parent.add_child(hip)

    var thigh := GeomUtil.capsule_mesh(0.078, 0.50, cloth)
    thigh.position.y = -0.22
    hip.add_child(thigh)

    var knee := Node3D.new()
    knee.name = "Knee"
    knee.position.y = -0.44
    hip.add_child(knee)

    var knee_joint := GeomUtil.sphere_mesh(0.062, cloth)
    knee.add_child(knee_joint)

    var shin := GeomUtil.capsule_mesh(0.058, 0.48, cloth)
    shin.position.y = -0.22
    knee.add_child(shin)

    var foot := Node3D.new()
    foot.name = "Foot"
    foot.position.y = -0.44
    knee.add_child(foot)

    var ankle := GeomUtil.sphere_mesh(0.048, boot)
    ankle.position.y = 0.04
    foot.add_child(ankle)
    var sole := GeomUtil.box_mesh(Vector3(0.090, 0.060, 0.24), boot, 0.92, 0.0)
    sole.position = Vector3(0.0, -0.02, -0.05)
    foot.add_child(sole)

    var toe := Node3D.new()
    toe.name = "Toe"
    toe.position = Vector3(0.0, -0.02, -0.18)
    foot.add_child(toe)
    var cap := GeomUtil.box_mesh(Vector3(0.088, 0.045, 0.08), boot, 0.90, 0.0)
    cap.position.z = 0.0
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

    _express()
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


func _express() -> void:
    if _brow_l == null or _lid_l == null:
        return
    var t := phase * 0.35 + float(look_id % 17) * 0.41
    var blink := 1.0 if fmod(t, 5.4) < 0.16 else 0.0
    _lid_l.position.y = 0.218 - blink * 0.016
    _lid_r.position.y = 0.218 - blink * 0.016
    _lid_l.scale.y = 1.0 + blink * 2.4
    _lid_r.scale.y = 1.0 + blink * 2.4
    if _jaw != null:
        _jaw.position.y = 0.100 + sin(t * 0.7) * 0.004
    if _mouth != null:
        _mouth.scale.x = 1.0 + sin(t * 0.9) * 0.04


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
    _express()

func set_attack_side(side: float) -> void:
    attack_side = 1.0 if side >= 0.0 else -1.0

func set_attack_mode(mode: int) -> void:
    attack_mode = clampi(mode, 0, 2)
