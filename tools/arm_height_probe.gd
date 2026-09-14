extends SceneTree

## Verifies the excavator's AI idle-sway arm pose never dips the tool tip
## below ground, by composing the real boom -> stick -> tool transform
## chain (from excavator_visual.gd's actual pivot offsets) rather than
## trusting rotation-sign intuition - boom_angle's sign runs the opposite
## way from what it looks like it should, and it and stick_angle interact
## rather than lift independently. Re-run this after touching any of the
## constants below or the idle-sway values in excavator.gd's
## _enemy_control().
##
## Run: ./tools/godot --headless --path . --script tools/arm_height_probe.gd

const CHASSIS_Y := -0.17
const BOOM_POS := Vector3(0.62, 2.37, -0.88)
const STICK_POS := Vector3(0.0, 0.0, -4.28)
const TOOL_POS := Vector3(0.0, 0.0, -3.28)
const TIP_LOCAL := Vector3(0.0, -0.20, -1.10)

## The values excavator.gd's _enemy_control() actually centers its sway on.
const BOOM_CENTER := 0.0
const BOOM_AMPLITUDE := 0.10
const STICK_CENTER := 0.30
const STICK_AMPLITUDE := 0.10
const TOOL_CENTER := -0.15
const TOOL_AMPLITUDE := 0.22
const YAW_AMPLITUDE := 0.46

const MIN_SAFE_CLEARANCE := 1.0

func _tip_height(boom_angle: float, stick_angle: float, tool_angle: float, arm_yaw: float) -> float:
    var t := Transform3D(Basis.IDENTITY, Vector3(0.0, CHASSIS_Y, 0.0))
    t *= Transform3D(Basis.from_euler(Vector3(boom_angle, arm_yaw, 0.0)), BOOM_POS)
    t *= Transform3D(Basis.from_euler(Vector3(stick_angle, 0.0, 0.0)), STICK_POS)
    t *= Transform3D(Basis.from_euler(Vector3(tool_angle, 0.0, 0.0)), TOOL_POS)
    return (t * TIP_LOCAL).y

func _init() -> void:
    var worst := INF
    var worst_pose := ""
    for bf in [-1.0, -0.5, 0.0, 0.5, 1.0]:
        for sf in [-1.0, -0.5, 0.0, 0.5, 1.0]:
            for tf in [-1.0, -0.5, 0.0, 0.5, 1.0]:
                for yf in [-1.0, 0.0, 1.0]:
                    var boom_a: float = BOOM_CENTER + bf * BOOM_AMPLITUDE
                    var stick_a: float = STICK_CENTER + sf * STICK_AMPLITUDE
                    var tool_a: float = TOOL_CENTER + tf * TOOL_AMPLITUDE
                    var yaw_a: float = yf * YAW_AMPLITUDE
                    var y := _tip_height(boom_a, stick_a, tool_a, yaw_a)
                    if y < worst:
                        worst = y
                        worst_pose = "boom=%.2f stick=%.2f tool=%.2f yaw=%.2f" % [boom_a, stick_a, tool_a, yaw_a]

    print("worst-case idle-sway tool tip height: %.3f m  (at %s)" % [worst, worst_pose])
    if worst >= MIN_SAFE_CLEARANCE:
        print("ARM_HEIGHT_OK")
        quit(0)
    else:
        push_error("ARM_HEIGHT_FAILED: idle sway can reach %.3fm, below the %.1fm floor" % [worst, MIN_SAFE_CLEARANCE])
        quit(1)
