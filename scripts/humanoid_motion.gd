extends "res://scripts/humanoid_rig.gd"

const OrganicMesh = preload("res://scripts/organic_mesh.gd")

var _motion_blend := 0.0
var _gait_frequency := 1.0

const THIGH_LEN := 0.56
const SHIN_LEN := 0.56
const STANCE_FRACTION := 0.62

func _build() -> void:
    super()
    _add_organic_mass()

func _add_organic_mass() -> void:
    if pelvis == null or torso == null:
        return

    var cloth := Color(0.15, 0.18, 0.175) if player_style else Color(0.22, 0.255, 0.23)
    var dark := Color(0.055, 0.065, 0.062)

    var pelvis_shell := OrganicMesh.loft_node([
        Vector3(-0.18, 0.22, 0.16),
        Vector3(-0.06, 0.31, 0.22),
        Vector3(0.12, 0.33, 0.23),
        Vector3(0.24, 0.28, 0.20)
    ], dark, 16, 0.86)
    pelvis_shell.position = Vector3(0.0, 0.02, 0.0)
    pelvis_shell.scale.x = 1.08 if player_style else 1.0
    pelvis.add_child(pelvis_shell)

    var torso_shell := OrganicMesh.loft_node([
        Vector3(-0.10, 0.27, 0.20),
        Vector3(0.06, 0.31, 0.22),
        Vector3(0.30, 0.39, 0.245),
        Vector3(0.56, 0.44, 0.255),
        Vector3(0.72, 0.41, 0.24),
        Vector3(0.82, 0.30, 0.20)
    ], cloth, 18, 0.74)
    torso_shell.position = Vector3(0.0, -0.01, 0.015)
    torso_shell.scale.x = 1.07 if player_style else 1.0
    torso.add_child(torso_shell)

    _add_limb_shell(leg_l, Vector3(-0.51, 0.16, 0.14), Vector3(-0.06, 0.145, 0.125), cloth, 13)
    _add_limb_shell(leg_r, Vector3(-0.51, 0.16, 0.14), Vector3(-0.06, 0.145, 0.125), cloth, 13)
    _add_limb_shell(arm_l, Vector3(-0.49, 0.125, 0.112), Vector3(-0.03, 0.145, 0.13), cloth, 12)
    _add_limb_shell(arm_r, Vector3(-0.49, 0.125, 0.112), Vector3(-0.03, 0.145, 0.13), cloth, 12)

func _add_limb_shell(parent: Node3D, bottom: Vector3, top: Vector3, color: Color, segments: int) -> void:
    if parent == null:
        return
    var shell := OrganicMesh.loft_node([
        bottom,
        Vector3(lerpf(bottom.x, top.x, 0.34), bottom.y * 1.03, bottom.z * 1.03),
        Vector3(lerpf(bottom.x, top.x, 0.68), top.y * 1.04, top.z * 1.04),
        top
    ], color, segments, 0.78)
    parent.add_child(shell)

func animate(delta: float, planar_speed: float, reference_speed: float, attack_amount: float, hit_amount: float, dead: bool) -> void:
    if pelvis == null:
        return

    var target_blend := clampf(planar_speed / maxf(reference_speed * 0.72, 0.1), 0.0, 1.0)
    _motion_blend = move_toward(_motion_blend, target_blend, delta * (5.8 if target_blend > _motion_blend else 8.5))
    var speed_n := clampf(planar_speed / maxf(reference_speed, 0.1), 0.0, 1.25)
    _gait_frequency = lerpf(1.25, 2.35, clampf(speed_n, 0.0, 1.0))
    phase = fposmod(phase + delta * TAU * _gait_frequency * maxf(_motion_blend, 0.12), TAU)

    var cycle_l := fposmod(phase / TAU, 1.0)
    var cycle_r := fposmod(cycle_l + 0.5, 1.0)
    _solve_leg(leg_l, knee_l, cycle_l, speed_n, -1.0)
    _solve_leg(leg_r, knee_r, cycle_r, speed_n, 1.0)

    var stride_wave := sin(phase)
    var arm_swing := stride_wave * (0.38 + speed_n * 0.34) * _motion_blend
    arm_l.rotation = Vector3(-arm_swing, 0.0, -0.04 * _motion_blend)
    arm_r.rotation = Vector3(arm_swing, 0.0, 0.04 * _motion_blend)
    elbow_l.rotation.x = -0.24 - absf(arm_swing) * 0.34
    elbow_r.rotation.x = -0.24 - absf(arm_swing) * 0.34

    var stance_bias := sin(phase) * _motion_blend
    var double_support := absf(sin(phase * 2.0))
    pelvis.position.y = 0.94 - 0.018 * _motion_blend + double_support * 0.018 * _motion_blend
    pelvis.position.x = stance_bias * 0.026
    pelvis.rotation = Vector3(0.0, -stride_wave * 0.038 * _motion_blend, -stance_bias * 0.032)
    torso.rotation = Vector3(
        -0.035 * speed_n * _motion_blend,
        stride_wave * 0.095 * _motion_blend,
        stance_bias * 0.028
    )
    head_root.rotation = Vector3(0.018 * speed_n, -torso.rotation.y * 0.42, -torso.rotation.z * 0.34)

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

func _solve_leg(hip: Node3D, knee: Node3D, cycle: float, speed_n: float, side: float) -> void:
    var moving := _motion_blend
    if moving <= 0.01:
        hip.rotation = hip.rotation.lerp(Vector3.ZERO, 0.35)
        knee.rotation.x = lerpf(knee.rotation.x, -0.08, 0.35)
        return

    var step_length := lerpf(0.20, 0.76, clampf(speed_n, 0.0, 1.0)) * moving
    var foot_forward := 0.0
    var foot_lift := 0.0

    if cycle < STANCE_FRACTION:
        var stance_t := cycle / STANCE_FRACTION
        foot_forward = lerpf(step_length * 0.52, -step_length * 0.48, stance_t)
        foot_lift = 0.0
    else:
        var swing_t := (cycle - STANCE_FRACTION) / (1.0 - STANCE_FRACTION)
        var smooth_t := swing_t * swing_t * (3.0 - 2.0 * swing_t)
        foot_forward = lerpf(-step_length * 0.48, step_length * 0.52, smooth_t)
        foot_lift = sin(swing_t * PI) * lerpf(0.13, 0.30, clampf(speed_n, 0.0, 1.0)) * moving

    var target_y_down := 1.055 - foot_lift
    var target_forward := foot_forward
    var distance := clampf(sqrt(target_y_down * target_y_down + target_forward * target_forward), 0.24, THIGH_LEN + SHIN_LEN - 0.018)

    var line_angle := atan2(target_forward, target_y_down)
    var cos_hip := clampf((THIGH_LEN * THIGH_LEN + distance * distance - SHIN_LEN * SHIN_LEN) / (2.0 * THIGH_LEN * distance), -1.0, 1.0)
    var hip_offset := acos(cos_hip)
    var cos_knee := clampf((THIGH_LEN * THIGH_LEN + SHIN_LEN * SHIN_LEN - distance * distance) / (2.0 * THIGH_LEN * SHIN_LEN), -1.0, 1.0)
    var knee_internal := acos(cos_knee)
    var knee_flex := PI - knee_internal

    var hip_pitch := line_angle + hip_offset
    hip.rotation.x = lerpf(hip.rotation.x, hip_pitch, 0.52)
    hip.rotation.z = lerpf(hip.rotation.z, side * (0.028 + 0.018 * speed_n) * moving, 0.30)
    knee.rotation.x = lerpf(knee.rotation.x, -knee_flex, 0.58)
