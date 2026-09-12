extends "res://scripts/mobile_hud.gd"

var _machine_profile: Dictionary = {}

func set_machine_profile(profile: Dictionary) -> void:
    _machine_profile = profile.duplicate(true)
    if not _machine_mode:
        set_machine_mode(true)
    _apply_machine_profile()

func clear_machine_profile() -> void:
    _machine_profile.clear()
    set_machine_mode(false)

func set_machine_mode(enabled: bool) -> void:
    super(enabled)
    if enabled:
        _apply_machine_profile()
    else:
        _machine_profile.clear()

func set_machine_telemetry(integrity: float, hydraulics: float, tracks: float, force_ratio: float, holding: bool) -> void:
    super(integrity, hydraulics, tracks, force_ratio, holding)
    if _machine_mode and not _machine_profile.is_empty() and _action_labels.size() >= 2:
        _action_labels[1].text = "RELEASE" if holding else str(_machine_profile.get("secondary", "CLAMP"))

func _apply_machine_profile() -> void:
    if not _machine_mode or _action_labels.size() < 3:
        return
    var machine_name := str(_machine_profile.get("machine_name", "MACHINE"))
    _mode_label.text = str(_machine_profile.get("mode", machine_name + " // OPERATOR POV"))
    _action_labels[0].text = str(_machine_profile.get("primary", "ACTION 1"))
    _action_labels[1].text = "RELEASE" if _machine_holding else str(_machine_profile.get("secondary", "ACTION 2"))
    _action_labels[2].text = str(_machine_profile.get("tertiary", "EXIT"))
    _interaction_hint = "%s    |    %s" % [
        str(_machine_profile.get("left_hint", "DRIVE")),
        str(_machine_profile.get("right_hint", "WORKING ASSEMBLY"))
    ]

func _draw_status_panel() -> void:
    if not _machine_mode:
        super()
        return
    var s := _ui_scale
    var panel := Rect2(Vector2(24.0, 18.0) * s, Vector2(420.0, 102.0) * s)
    _rounded(panel, Color(0.010, 0.016, 0.016, 0.89), Color(0.78, 0.50, 0.11, 0.88), 2.0 * s)
    draw_string(
        ThemeDB.fallback_font,
        Vector2(44.0, 53.0) * s,
        str(_machine_profile.get("machine_name", "MACHINE")) + " // OPERATOR",
        HORIZONTAL_ALIGNMENT_LEFT,
        330.0 * s,
        maxi(16, int(22.0 * s)),
        Color(1.0, 0.76, 0.28, 1.0)
    )
    draw_string(
        ThemeDB.fallback_font,
        Vector2(44.0, 84.0) * s,
        str(_machine_profile.get("center_hint", "PHYSICAL CONTROL")),
        HORIZONTAL_ALIGNMENT_LEFT,
        350.0 * s,
        maxi(11, int(14.0 * s)),
        Color(0.82, 0.86, 0.81, 0.96)
    )

func _draw_target_bracket() -> void:
    if _machine_mode:
        _draw_machine_reticle()
        return
    super()

func _draw_machine_reticle() -> void:
    var s := _ui_scale
    var center := _view_size * 0.5
    var r := 27.0 * s
    var c := Color(1.0, 0.63, 0.14, 0.78)
    draw_arc(center, r, -0.82, 0.82, 12, c, 2.2 * s)
    draw_arc(center, r, PI - 0.82, PI + 0.82, 12, c, 2.2 * s)
    draw_line(center + Vector2(-7.0, 0.0) * s, center + Vector2(7.0, 0.0) * s, c, 2.0 * s)
    draw_line(center + Vector2(0.0, -7.0) * s, center + Vector2(0.0, 7.0) * s, c, 2.0 * s)

    var force_len := 82.0 * s * _machine_force
    draw_line(center + Vector2(0.0, 38.0) * s, center + Vector2(0.0, 38.0) * s + Vector2(force_len, 0.0), Color(0.96, 0.43, 0.08, 0.90), 5.0 * s)
    draw_line(center + Vector2(0.0, 38.0) * s, center + Vector2(82.0, 38.0) * s, Color(0.24, 0.25, 0.22, 0.65), 2.0 * s)

func _draw_move_zone() -> void:
    super()
    if not _machine_mode:
        return
    var s := _ui_scale
    var center := Vector2(142.0, _view_size.y - 142.0) * s
    draw_string(ThemeDB.fallback_font, center + Vector2(-63.0, 112.0) * s, "DRIVE / STEER", HORIZONTAL_ALIGNMENT_CENTER, 126.0 * s, maxi(11, int(13.0 * s)), Color(0.92, 0.86, 0.68, 0.88))
