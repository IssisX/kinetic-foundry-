extends "res://scripts/humanoid_rig.gd"

const OrganicMesh = preload("res://scripts/organic_mesh.gd")
const GaitDebug = preload("res://scripts/humanoid_gait_debug.gd")

signal foot_planted(
    side: float,
    position: Vector3,
    normal: Vector3,
    speed: float
)

const MODE_IDLE := 0
const MODE_START := 1
const MODE_WALK := 2
const MODE_STOP := 3
const MODE_RUN := 4

const THIGH_LEN := 0.44
const SHIN_LEN := 0.44
const LEG_LEN := THIGH_LEN + SHIN_LEN
const ANKLE_TO_SOLE := 0.125
const FOOT_HALF_LENGTH := 0.21
const STEP_WIDTH := 0.09
const BASE_PELVIS_HEIGHT := 0.94
const GRAVITY := 9.81
const V_COMFORT := 0.45 * sqrt(GRAVITY * LEG_LEN)
const V_RUN := 0.75 * sqrt(GRAVITY * LEG_LEN)
const GROUND_MASK := 2 | 8

class FootState:
    var side := 0.0
    var planted := true
    var contact := Vector3.ZERO
    var normal := Vector3.UP
    var ankle := Vector3.ZERO
    var takeoff_contact := Vector3.ZERO
    var takeoff_normal := Vector3.UP
    var target_contact := Vector3.ZERO
    var target_normal := Vector3.UP
    var swing_time := 0.0
    var swing_duration := 0.40
    var cycle_previous := 0.0
    var contact_mode := 1
    var contact_z := 0.0
    var foot_pitch := 0.0
    var planted_velocity := 0.0
    var ground_error := 0.0
    var reach := 0.0
    var knee_flex := 0.0
    var actual_contact := Vector3.ZERO
    var actual_valid := false

    func _init(foot_side: float) -> void:
        side = foot_side

var _left := FootState.new(-1.0)
var _right := FootState.new(1.0)
var _mode := MODE_IDLE
var _initialized := false
var _phase := 0.02
var _stance_fraction := 0.60
var _phase_rate := 0.0
var _step_length := 0.42
var _cadence_hz := 0.0
var _motion_blend := 0.0
var _governed_speed := 0.0
var _last_walk_speed := 0.6
var _start_timer := 0.0
var _stop_timer := 0.0
var _step_index := 0
var _idle_time := 0.0
var _com_world := Vector3.ZERO
var _support_world := Vector3.ZERO
var _double_support := true
var _debug

var _sample_time := 0.0
var _left_stance_time := 0.0
var _right_stance_time := 0.0
var _double_support_time := 0.0
var _max_planted_velocity := 0.0
var _max_ground_error := 0.0

func _build() -> void:
    super()
    _add_organic_mass()
    if player_style:
        _debug = GaitDebug.new()
        add_child(_debug)
        _debug.visible = (
            OS.get_environment("KF_GAIT_DEBUG") == "1"
        )

func _add_organic_mass() -> void:
    if pelvis == null or torso == null:
        return

    var cloth := (
        Color(0.15, 0.18, 0.175)
        if player_style
        else Color(0.22, 0.255, 0.23)
    )
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

    _add_limb_shell(
        leg_l,
        Vector3(-0.39, 0.16, 0.14),
        Vector3(-0.05, 0.145, 0.125),
        cloth,
        13
    )
    _add_limb_shell(
        leg_r,
        Vector3(-0.39, 0.16, 0.14),
        Vector3(-0.05, 0.145, 0.125),
        cloth,
        13
    )
    _add_limb_shell(
        arm_l,
        Vector3(-0.49, 0.125, 0.112),
        Vector3(-0.03, 0.145, 0.13),
        cloth,
        12
    )
    _add_limb_shell(
        arm_r,
        Vector3(-0.49, 0.125, 0.112),
        Vector3(-0.03, 0.145, 0.13),
        cloth,
        12
    )

func _add_limb_shell(
        parent: Node3D,
        bottom: Vector3,
        top: Vector3,
        color: Color,
        segments: int
) -> void:
    if parent == null:
        return
    var shell := OrganicMesh.loft_node([
        bottom,
        Vector3(
            lerpf(bottom.x, top.x, 0.34),
            bottom.y * 1.03,
            bottom.z * 1.03
        ),
        Vector3(
            lerpf(bottom.x, top.x, 0.68),
            top.y * 1.04,
            top.z * 1.04
        ),
        top
    ], color, segments, 0.78)
    parent.add_child(shell)

func animate(
        delta: float,
        planar_speed: float,
        reference_speed: float,
        attack_amount: float,
        hit_amount: float,
        dead: bool
) -> void:
    if pelvis == null:
        return
    if not _initialized:
        _initialize_feet()

    _select_mode(planar_speed, dead)
    if _mode == MODE_RUN:
        _animate_run(delta, planar_speed, reference_speed)
    else:
        _animate_grounded_walk(delta, planar_speed)

    if attack_amount > 0.0:
        var action := sin(
            clampf(attack_amount, 0.0, 1.0) * PI
        )
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

    _apply_death(delta, dead)
    _update_diagnostics(delta)

func _select_mode(speed: float, dead: bool) -> void:
    if dead:
        return
    if speed >= V_RUN * 1.04:
        if _mode != MODE_RUN:
            _mode = MODE_RUN
            _initialized = false
        return
    if _mode == MODE_RUN:
        if speed > V_RUN * 0.84:
            return
        _initialize_feet()
        _mode = MODE_WALK
        _reset_acceptance_window()
        return
    if _mode == MODE_IDLE and speed > 0.08:
        _mode = MODE_START
        _start_timer = 0.22
        _step_index = 0
        _phase = 0.02
        _reset_acceptance_window()
    elif (
        (_mode == MODE_START or _mode == MODE_WALK)
        and speed < 0.07
    ):
        _mode = MODE_STOP
        _stop_timer = 0.0
    elif _mode == MODE_STOP and speed > 0.16:
        _mode = MODE_WALK
    elif (
        _mode == MODE_STOP
        and _left.planted
        and _right.planted
        and speed < 0.045
        and _stop_timer > 0.12
    ):
        _mode = MODE_IDLE

func _initialize_feet() -> void:
    var root := _body()
    if root == null or get_world_3d() == null:
        return
    var right := root.global_basis.x.normalized()
    var forward := -root.global_basis.z.normalized()
    var root_position := root.global_position
    _initialize_foot(
        _left,
        root_position - right * STEP_WIDTH * 0.5
        + forward * 0.025
    )
    _initialize_foot(
        _right,
        root_position + right * STEP_WIDTH * 0.5
        - forward * 0.025
    )
    _left.cycle_previous = fposmod(_phase + 0.5, 1.0)
    _right.cycle_previous = _phase
    _initialized = true
    _double_support = true

func _initialize_foot(
        state: FootState,
        candidate: Vector3
) -> void:
    var sample := _ground_sample(candidate)
    state.contact = sample.position
    state.normal = sample.normal
    state.target_contact = state.contact
    state.target_normal = state.normal
    state.planted = true
    state.contact_mode = 1
    state.contact_z = 0.0
    state.foot_pitch = 0.0
    state.actual_valid = false

func _animate_grounded_walk(
        delta: float,
        speed: float
) -> void:
    _idle_time += delta
    _update_governor(speed)

    if _mode == MODE_START and _start_timer > 0.0:
        _start_timer = maxf(0.0, _start_timer - delta)
    else:
        _phase = fposmod(
            _phase + _phase_rate * delta,
            1.0
        )
        if _mode == MODE_START:
            _mode = MODE_WALK
    phase = _phase * TAU

    var right_cycle := _phase
    var left_cycle := fposmod(_phase + 0.5, 1.0)
    _update_foot(
        _right,
        _left,
        right_cycle,
        delta
    )
    _update_foot(
        _left,
        _right,
        left_cycle,
        delta
    )
    _double_support = _left.planted and _right.planted

    _pose_pelvis(delta, speed)
    _solve_leg(leg_l, knee_l, foot_l, _left)
    _solve_leg(leg_r, knee_r, foot_r, _right)
    _pose_upper_body(speed)

    if _mode == MODE_STOP:
        _stop_timer += delta

func _update_governor(speed: float) -> void:
    if _mode == MODE_IDLE:
        _governed_speed = 0.0
        _phase_rate = 0.0
        _cadence_hz = 0.0
        return

    var requested := speed
    if _mode == MODE_STOP:
        var stop_falloff := exp(-_stop_timer * 2.2)
        requested = maxf(
            0.32,
            _last_walk_speed * stop_falloff
        )
    _governed_speed = minf(requested, V_RUN * 0.99)
    _last_walk_speed = maxf(_governed_speed, 0.32)
    var u := clampf(
        _governed_speed / V_COMFORT,
        0.0,
        1.4
    )
    _step_length = LEG_LEN * (0.38 + 0.22 * u)
    _cadence_hz = (
        _governed_speed / maxf(_step_length, 0.001)
    )
    _phase_rate = _cadence_hz * 0.5
    _stance_fraction = lerpf(
        0.64,
        0.56,
        clampf((u - 0.5) / 0.9, 0.0, 1.0)
    )

func _update_foot(
        state: FootState,
        other: FootState,
        cycle: float,
        delta: float
) -> void:
    var crossed_to_swing := (
        state.cycle_previous < _stance_fraction
        and cycle >= _stance_fraction
    )
    var wrapped := cycle < state.cycle_previous

    if state.planted:
        state.ankle = _stance_ankle(state, cycle)
        if crossed_to_swing and other.planted:
            _begin_swing(state)
    else:
        state.swing_time += delta
        var swing_t := clampf(
            state.swing_time
            / maxf(state.swing_duration, 0.001),
            0.0,
            1.0
        )
        state.ankle = _swing_ankle(state, swing_t)
        if swing_t >= 1.0 or wrapped:
            _finish_swing(state)

    state.cycle_previous = cycle

func _begin_swing(state: FootState) -> void:
    var root := _body()
    if root == null:
        return
    state.planted = false
    state.takeoff_contact = state.contact
    state.takeoff_normal = state.normal
    state.swing_time = 0.0
    state.swing_duration = (
        (1.0 - _stance_fraction)
        / maxf(_phase_rate, 0.01)
    )

    var forward := _movement_forward()
    var right := root.global_basis.x.normalized()
    var velocity := _planar_velocity()
    var step_scale := 1.0
    if _mode == MODE_START:
        step_scale = [0.50, 0.80, 1.0][mini(_step_index, 2)]
    elif _mode == MODE_STOP:
        step_scale = clampf(
            0.55 - _stop_timer * 0.30,
            0.22,
            0.55
        )

    var ahead := (
        forward * _step_length * 0.52 * step_scale
    )
    var side := right * STEP_WIDTH * 0.5 * state.side
    var predicted_root := (
        root.global_position
        + velocity * state.swing_duration
    )
    if _mode == MODE_STOP:
        predicted_root = root.global_position + velocity * (
            state.swing_duration * 0.22
        )
    var candidate := predicted_root + ahead + side
    var horizontal := candidate - predicted_root
    horizontal.y = 0.0
    var max_lead := LEG_LEN * 0.38
    if horizontal.length() > max_lead:
        candidate = (
            predicted_root
            + horizontal.normalized() * max_lead
        )

    var sample := _ground_sample(candidate)
    state.target_contact = sample.position
    state.target_normal = sample.normal
    state.contact_mode = 3
    _step_index += 1

func _finish_swing(state: FootState) -> void:
    state.planted = true
    state.contact = state.target_contact
    state.normal = state.target_normal
    state.swing_time = state.swing_duration
    state.contact_mode = 0
    state.contact_z = FOOT_HALF_LENGTH
    state.foot_pitch = deg_to_rad(14.0)
    state.actual_valid = false
    foot_planted.emit(
        state.side,
        state.contact,
        state.normal,
        _governed_speed
    )

func _stance_ankle(
        state: FootState,
        cycle: float
) -> Vector3:
    var pitch := 0.0
    var contact_z := 0.0
    if cycle < 0.12:
        var heel_t := cycle / 0.12
        pitch = lerpf(
            deg_to_rad(14.0),
            0.0,
            heel_t
        )
        contact_z = lerpf(
            FOOT_HALF_LENGTH,
            0.0,
            heel_t
        )
        state.contact_mode = 0
    elif cycle < 0.30:
        state.contact_mode = 1
    elif cycle < 0.50:
        var ball_t := (cycle - 0.30) / 0.20
        pitch = lerpf(
            0.0,
            deg_to_rad(-12.0),
            ball_t
        )
        contact_z = lerpf(0.0, -0.13, ball_t)
        state.contact_mode = 2
    else:
        var range := maxf(_stance_fraction - 0.50, 0.01)
        var toe_t := clampf(
            (cycle - 0.50) / range,
            0.0,
            1.0
        )
        pitch = lerpf(
            deg_to_rad(-12.0),
            deg_to_rad(-21.0),
            toe_t
        )
        contact_z = lerpf(
            -0.13,
            -FOOT_HALF_LENGTH,
            toe_t
        )
        state.contact_mode = 3
    state.contact_z = contact_z
    state.foot_pitch = pitch
    return _ankle_from_contact(
        state.contact,
        state.normal,
        state.side,
        pitch,
        contact_z
    )

func _swing_ankle(
        state: FootState,
        swing_t: float
) -> Vector3:
    var h := swing_t * swing_t * (3.0 - 2.0 * swing_t)
    var contact := state.takeoff_contact.lerp(
        state.target_contact,
        h
    )
    var normal := state.takeoff_normal.slerp(
        state.target_normal,
        h
    ).normalized()
    var clearance := (
        0.015
        + 0.040
        * clampf(
            _governed_speed / V_COMFORT,
            0.0,
            1.0
        )
    )
    contact += (
        normal * clearance
        * 4.0 * swing_t * (1.0 - swing_t)
    )

    var pitch := 0.0
    if swing_t < 0.36:
        pitch = lerpf(
            deg_to_rad(-18.0),
            deg_to_rad(8.0),
            swing_t / 0.36
        )
    elif swing_t < 0.78:
        pitch = deg_to_rad(8.0)
    else:
        pitch = lerpf(
            deg_to_rad(8.0),
            deg_to_rad(14.0),
            (swing_t - 0.78) / 0.22
        )
    state.contact_mode = 4
    state.contact_z = FOOT_HALF_LENGTH
    state.foot_pitch = pitch
    return _ankle_from_contact(
        contact,
        normal,
        state.side,
        pitch,
        FOOT_HALF_LENGTH
    )

func _ankle_from_contact(
        contact: Vector3,
        normal: Vector3,
        side: float,
        pitch: float,
        contact_z: float
) -> Vector3:
    var basis := _foot_basis(normal, side, pitch)
    var offset := basis * Vector3(
        0.0,
        -ANKLE_TO_SOLE,
        contact_z
    )
    return contact - offset

func _foot_basis(
        normal: Vector3,
        side: float,
        pitch: float
) -> Basis:
    var forward := _movement_forward().slide(normal)
    if forward.length_squared() < 0.001:
        forward = Vector3.FORWARD.slide(normal)
    forward = forward.normalized()
    forward = Basis(
        normal,
        deg_to_rad(6.0) * side
    ) * forward
    var right := forward.cross(normal).normalized()
    var base := Basis(right, normal, -forward)
    return (
        base * Basis(Vector3.RIGHT, pitch)
    ).orthonormalized()

func _pose_pelvis(delta: float, speed: float) -> void:
    var moving := clampf(
        speed / maxf(V_COMFORT, 0.01),
        0.0,
        1.0
    )
    if _mode == MODE_STOP:
        moving = clampf(
            _governed_speed / V_COMFORT,
            0.0,
            1.0
        )
    _motion_blend = move_toward(
        _motion_blend,
        moving,
        delta * 4.2
    )

    var wave := sin(TAU * _phase)
    var vertical := -cos(TAU * 2.0 * _phase)
    var lower_ground := minf(
        _left.contact.y,
        _right.contact.y
    )
    var root := _body()
    var root_y := (
        root.global_position.y if root != null else 0.0
    )
    var slope_normal := (
        _left.normal + _right.normal
    ).normalized()
    var local_normal := slope_normal
    if root != null:
        local_normal = (
            root.global_basis.inverse() * slope_normal
        )
    var slope_pitch := atan2(
        -local_normal.z,
        maxf(local_normal.y, 0.20)
    ) * 0.24
    var slope_roll := atan2(
        local_normal.x,
        maxf(local_normal.y, 0.20)
    ) * 0.20

    var idle_sway := sin(_idle_time * 1.55) * 0.008
    var lateral := wave * 0.024 * _motion_blend
    var bob := (
        vertical * 0.020 * LEG_LEN * _motion_blend
    )
    pelvis.position.x = (
        lateral
        + idle_sway * (1.0 - _motion_blend)
    )
    pelvis.position.y = (
        lower_ground
        - root_y
        + BASE_PELVIS_HEIGHT
        + bob
    )
    pelvis.position.z = (
        sin(_idle_time * 1.10) * 0.006
        * (1.0 - _motion_blend)
    )
    if _mode == MODE_START and _start_timer > 0.0:
        var apa := sin(
            (1.0 - _start_timer / 0.22) * PI
        )
        pelvis.position.x -= 0.018 * apa
        pelvis.position.z += 0.022 * apa

    var pelvis_yaw := (
        deg_to_rad(4.0) * wave * _motion_blend
    )
    var pelvis_list := (
        deg_to_rad(-4.5) * wave * _motion_blend
    )
    pelvis.rotation = Vector3(
        slope_pitch,
        pelvis_yaw,
        pelvis_list + slope_roll
    )
    _com_world = pelvis.global_position + Vector3.UP * 0.09
    _support_world = _support_center()

func _solve_leg(
        hip: Node3D,
        knee: Node3D,
        foot: Node3D,
        state: FootState
) -> void:
    var hip_position := hip.global_position
    var to_target := state.ankle - hip_position
    var raw_distance := to_target.length()
    var distance := clampf(
        raw_distance,
        0.08,
        LEG_LEN - 0.010
    )
    var direction := to_target.normalized()
    if raw_distance < 0.001:
        direction = Vector3.DOWN

    var along := (
        THIGH_LEN * THIGH_LEN
        - SHIN_LEN * SHIN_LEN
        + distance * distance
    ) / (2.0 * distance)
    var bend := sqrt(maxf(
        THIGH_LEN * THIGH_LEN - along * along,
        0.0
    ))
    var forward := _movement_forward()
    var pole := (
        hip_position
        + forward * 0.45
        + Vector3.UP * 0.10
    )
    var pole_vector := pole - hip_position
    var perpendicular := (
        pole_vector
        - direction * pole_vector.dot(direction)
    )
    if perpendicular.length_squared() < 0.001:
        perpendicular = forward
    perpendicular = perpendicular.normalized()
    var knee_position := (
        hip_position
        + direction * along
        + perpendicular * bend
    )

    var root := _body()
    var world_right := (
        root.global_basis.x.normalized()
        if root != null
        else Vector3.RIGHT
    )
    var upper_direction := (
        knee_position - hip_position
    ).normalized()
    var upper_basis := _bone_basis(
        upper_direction,
        world_right,
        forward
    )
    hip.global_transform = Transform3D(
        upper_basis,
        hip_position
    )

    var cosine := clampf(
        (
            THIGH_LEN * THIGH_LEN
            + SHIN_LEN * SHIN_LEN
            - distance * distance
        ) / (2.0 * THIGH_LEN * SHIN_LEN),
        -1.0,
        1.0
    )
    state.knee_flex = PI - acos(cosine)
    var lower_direction := (
        state.ankle - knee_position
    ).normalized()
    var lower_basis := _bone_basis(
        lower_direction,
        world_right,
        forward
    )
    knee.global_transform = Transform3D(
        lower_basis,
        knee_position
    )

    var desired_foot_basis := _foot_basis(
        state.normal,
        state.side,
        state.foot_pitch
    )
    foot.global_transform = Transform3D(
        desired_foot_basis,
        state.ankle
    )
    state.reach = raw_distance / LEG_LEN

func _bone_basis(
        down: Vector3,
        right_hint: Vector3,
        forward_hint: Vector3
) -> Basis:
    var y_axis := -down.normalized()
    var x_axis := (
        right_hint
        - y_axis * right_hint.dot(y_axis)
    )
    if x_axis.length_squared() < 0.001:
        x_axis = forward_hint.cross(y_axis)
    x_axis = x_axis.normalized()
    var z_axis := x_axis.cross(y_axis).normalized()
    return Basis(x_axis, y_axis, z_axis).orthonormalized()

func _pose_upper_body(speed: float) -> void:
    var speed_scale := clampf(
        speed / V_COMFORT,
        0.0,
        1.4
    )
    var leg_wave := cos(TAU * _phase)
    var arm_amplitude := deg_to_rad(
        lerpf(
            7.0,
            31.0,
            clampf(speed_scale, 0.0, 1.0)
        )
    ) * _motion_blend
    arm_l.rotation = Vector3(
        arm_amplitude * leg_wave,
        0.0,
        -0.035 * _motion_blend
    )
    arm_r.rotation = Vector3(
        -arm_amplitude * leg_wave,
        0.0,
        0.035 * _motion_blend
    )
    var elbow_flex := deg_to_rad(
        lerpf(
            18.0,
            28.0,
            clampf(speed_scale, 0.0, 1.0)
        )
    )
    elbow_l.rotation.x = -elbow_flex
    elbow_r.rotation.x = -elbow_flex

    var thorax_yaw := -pelvis.rotation.y * 0.72
    var breath := (
        sin(_idle_time * TAU * 0.22) * 0.010
    )
    torso.position.y = (
        0.24 + breath * (1.0 - _motion_blend)
    )
    torso.rotation = Vector3(
        -0.018 * speed_scale * _motion_blend,
        thorax_yaw,
        -pelvis.rotation.z * 0.34
    )
    head_root.rotation = Vector3(
        0.012 * speed_scale,
        -torso.rotation.y * 0.55,
        -torso.rotation.z * 0.42
    )

func _animate_run(
        delta: float,
        speed: float,
        reference_speed: float
) -> void:
    var speed_n := clampf(
        speed / maxf(reference_speed, 0.1),
        0.0,
        1.35
    )
    _phase = fposmod(
        _phase + delta * lerpf(1.35, 1.95, speed_n),
        1.0
    )
    phase = _phase * TAU
    var wave := sin(phase)
    var flight := maxf(
        0.0,
        -cos(phase * 2.0)
    )
    var stride := wave * lerpf(0.52, 0.82, speed_n)
    leg_l.rotation = Vector3(stride, 0.0, -0.03)
    leg_r.rotation = Vector3(-stride, 0.0, 0.03)
    knee_l.rotation.x = -(
        0.20 + maxf(0.0, -wave) * 1.02
    )
    knee_r.rotation.x = -(
        0.20 + maxf(0.0, wave) * 1.02
    )
    foot_l.rotation.x = 0.10
    foot_r.rotation.x = 0.10
    pelvis.position = Vector3(
        0.0,
        BASE_PELVIS_HEIGHT + flight * 0.055,
        0.0
    )
    pelvis.rotation = Vector3(
        -0.07,
        -wave * 0.045,
        -wave * 0.025
    )
    arm_l.rotation = Vector3(
        -stride * 0.88,
        0.0,
        -0.06
    )
    arm_r.rotation = Vector3(
        stride * 0.88,
        0.0,
        0.06
    )
    elbow_l.rotation.x = -0.62
    elbow_r.rotation.x = -0.62
    torso.position.y = 0.24
    torso.rotation = Vector3(-0.10, wave * 0.07, 0.0)
    head_root.rotation = Vector3(
        0.04,
        -torso.rotation.y * 0.45,
        0.0
    )
    _double_support = false
    _com_world = pelvis.global_position + Vector3.UP * 0.09
    _support_world = (
        _com_world - Vector3.UP * BASE_PELVIS_HEIGHT
    )

func _update_diagnostics(delta: float) -> void:
    if not _initialized or _mode == MODE_RUN:
        return
    _measure_foot(_left, foot_l, delta)
    _measure_foot(_right, foot_r, delta)
    if (
        (_mode == MODE_START or _mode == MODE_WALK)
        and _sample_time < 4.0
    ):
        var sample_delta := minf(delta, 4.0 - _sample_time)
        _sample_time += sample_delta
        if _left.planted:
            _left_stance_time += sample_delta
        if _right.planted:
            _right_stance_time += sample_delta
        if _double_support:
            _double_support_time += sample_delta
        _max_planted_velocity = maxf(
            _max_planted_velocity,
            maxf(
                _left.planted_velocity,
                _right.planted_velocity
            )
        )
        _max_ground_error = maxf(
            _max_ground_error,
            maxf(
                _left.ground_error,
                _right.ground_error
            )
        )
    if _debug != null and _debug.visible:
        _debug.present(get_gait_observables())

func _measure_foot(
        state: FootState,
        foot: Node3D,
        delta: float
) -> void:
    var offset := foot.global_basis * Vector3(
        0.0,
        -ANKLE_TO_SOLE,
        state.contact_z
    )
    var actual := foot.global_position + offset
    if state.planted:
        state.ground_error = absf(
            (actual - state.contact).dot(state.normal)
        )
        if state.actual_valid:
            state.planted_velocity = (
                actual.distance_to(state.actual_contact)
                / maxf(delta, 0.001)
            )
        else:
            state.planted_velocity = 0.0
        state.actual_contact = actual
        state.actual_valid = true
    else:
        state.planted_velocity = 0.0
        state.ground_error = 0.0
        state.actual_valid = false

func get_gait_observables() -> Dictionary:
    return {
        "mode": _mode_name(),
        "phase": _phase,
        "cadence_hz": _cadence_hz,
        "step_length": _step_length,
        "stance_fraction": _stance_fraction,
        "double_support": _double_support,
        "com": _com_world,
        "support": _support_world,
        "left": _foot_observables(_left, leg_l),
        "right": _foot_observables(_right, leg_r)
    }

func get_gait_acceptance_window() -> Dictionary:
    var duration := maxf(_sample_time, 0.001)
    return {
        "duration": _sample_time,
        "left_stance_fraction": (
            _left_stance_time / duration
        ),
        "right_stance_fraction": (
            _right_stance_time / duration
        ),
        "double_support_fraction": (
            _double_support_time / duration
        ),
        "max_planted_velocity": _max_planted_velocity,
        "max_ground_error": _max_ground_error,
        "walk_threshold": V_RUN
    }

func set_gait_debug_enabled(enabled: bool) -> void:
    if _debug != null:
        _debug.visible = enabled

func reset_gait_state() -> void:
    _mode = MODE_IDLE
    _initialized = false
    _phase = 0.02
    _motion_blend = 0.0
    _start_timer = 0.0
    _stop_timer = 0.0
    _step_index = 0
    _reset_acceptance_window()

func _foot_observables(
        state: FootState,
        hip: Node3D
) -> Dictionary:
    return {
        "state": (
            "PLANTED" if state.planted else "SWINGING"
        ),
        "planted": state.planted,
        "contact_mode": state.contact_mode,
        "contact": state.contact,
        "normal": state.normal,
        "hip": hip.global_position,
        "reach": state.reach,
        "knee_flex_degrees": rad_to_deg(
            state.knee_flex
        ),
        "planted_velocity": state.planted_velocity,
        "ground_error": state.ground_error,
        "swing_progress": clampf(
            state.swing_time
            / maxf(state.swing_duration, 0.001),
            0.0,
            1.0
        )
    }

func _reset_acceptance_window() -> void:
    _sample_time = 0.0
    _left_stance_time = 0.0
    _right_stance_time = 0.0
    _double_support_time = 0.0
    _max_planted_velocity = 0.0
    _max_ground_error = 0.0

func _support_center() -> Vector3:
    if _left.planted and _right.planted:
        return (_left.contact + _right.contact) * 0.5
    if _left.planted:
        return _left.contact
    if _right.planted:
        return _right.contact
    return _com_world - Vector3.UP * BASE_PELVIS_HEIGHT

func _ground_sample(candidate: Vector3) -> Dictionary:
    var root := _body()
    var from := candidate + Vector3.UP * 1.45
    var to := candidate - Vector3.UP * 2.10
    var query := PhysicsRayQueryParameters3D.create(
        from,
        to,
        GROUND_MASK
    )
    query.collide_with_areas = false
    if root is CollisionObject3D:
        query.exclude = [root.get_rid()]
    var hit := (
        get_world_3d().direct_space_state.intersect_ray(query)
    )
    if hit.is_empty():
        return {
            "position": Vector3(
                candidate.x,
                0.0,
                candidate.z
            ),
            "normal": Vector3.UP,
            "valid": false
        }
    var normal: Vector3 = hit.normal
    var up_dot := clampf(
        normal.dot(Vector3.UP),
        -1.0,
        1.0
    )
    var slope := acos(up_dot)
    if slope > deg_to_rad(35.0):
        normal = Vector3.UP.slerp(
            normal,
            deg_to_rad(35.0) / slope
        ).normalized()
    return {
        "position": hit.position,
        "normal": normal,
        "valid": true
    }

func _movement_forward() -> Vector3:
    var velocity := _planar_velocity()
    if velocity.length_squared() > 0.09:
        return velocity.normalized()
    var root := _body()
    if root != null:
        var forward := -root.global_basis.z
        forward.y = 0.0
        if forward.length_squared() > 0.001:
            return forward.normalized()
    return Vector3.FORWARD

func _planar_velocity() -> Vector3:
    var root := _body()
    if root is CharacterBody3D:
        var velocity: Vector3 = root.velocity
        velocity.y = 0.0
        return velocity
    return Vector3.ZERO

func _body() -> Node3D:
    return get_parent() as Node3D

func _mode_name() -> String:
    match _mode:
        MODE_IDLE:
            return "IDLE"
        MODE_START:
            return "START"
        MODE_WALK:
            return "WALK"
        MODE_STOP:
            return "STOP"
        MODE_RUN:
            return "RUN"
    return "UNKNOWN"

func _apply_death(delta: float, dead: bool) -> void:
    death_blend = move_toward(
        death_blend,
        1.0 if dead else 0.0,
        delta * (2.8 if dead else 5.0)
    )
    if death_blend > 0.0:
        rotation.z = lerp(
            0.0,
            attack_side * 1.32,
            death_blend
        )
        rotation.x = lerp(0.0, -0.24, death_blend)
        position.y = -0.12 * death_blend
        leg_l.rotation.x *= 1.0 - death_blend * 0.75
        leg_r.rotation.x *= 1.0 - death_blend * 0.75
    else:
        rotation.z = 0.0
        rotation.x = 0.0
        position.y = 0.0
