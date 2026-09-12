class_name MobileHud
extends Control

var move_axis := Vector2.ZERO
var look_accum := Vector2.ZERO
var attack_pulse := false
var grab_pulse := false
var use_pulse := false
var smash_held := false

var _move_touch := -1
var _look_touch := -1
var _move_origin := Vector2.ZERO
var _move_pos := Vector2.ZERO
var _view_size := Vector2(1920.0, 1080.0)
var _ui_scale := 1.0
var _machine_mode := false
var _health_ratio := 1.0
var _damage_flash := 0.0
var _target
var _context_text := "POWER // COMBAT // MACHINES"
var _interaction_hint := ""
var _objective_title := "BREAK THE YARD CREW"
var _objective_detail := "CUT THE CREW DOWN UNTIL THE MACHINE IS EXPOSED"
var _objective_progress := 0.0
var _machine_integrity := 1.0
var _machine_hydraulics := 1.0
var _machine_tracks := 1.0
var _machine_force := 0.0
var _machine_holding := false

var _action_labels: Array[Label] = []
var _mode_label: Label
var _title_label: Label
var _context_label: Label
var _objective_title_label: Label
var _objective_detail_label: Label
var _interaction_label: Label
var _last_font_scale := -1.0

const BASE_STICK_R := 112.0
const BASE_DEAD_R := 20.0

func _ready() -> void:
    mouse_filter = Control.MOUSE_FILTER_IGNORE
    set_process_input(true)
    set_process(true)
    _build_labels()
    _resize_to_viewport()

func _label(size_px: int, color: Color) -> Label:
    var label := Label.new()
    label.mouse_filter = Control.MOUSE_FILTER_IGNORE
    label.add_theme_font_size_override("font_size", size_px)
    label.add_theme_color_override("font_color", color)
    label.add_theme_color_override("font_shadow_color", Color(0.0, 0.0, 0.0, 0.90))
    label.add_theme_constant_override("shadow_offset_x", 2)
    label.add_theme_constant_override("shadow_offset_y", 2)
    label.add_theme_constant_override("outline_size", 1)
    label.add_theme_color_override("font_outline_color", Color(0.0, 0.0, 0.0, 0.75))
    return label

func _build_labels() -> void:
    _title_label = _label(23, Color(0.98, 0.78, 0.32, 1.0))
    _title_label.text = "KINETIC FOUNDRY"
    add_child(_title_label)

    _mode_label = _label(16, Color(0.80, 0.84, 0.80, 0.96))
    add_child(_mode_label)

    _context_label = _label(17, Color(0.92, 0.91, 0.84, 0.96))
    _context_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
    add_child(_context_label)

    _interaction_label = _label(18, Color(1.0, 0.77, 0.26, 1.0))
    _interaction_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
    _interaction_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
    add_child(_interaction_label)

    _objective_title_label = _label(20, Color(1.0, 0.69, 0.20, 1.0))
    _objective_title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
    add_child(_objective_title_label)

    _objective_detail_label = _label(14, Color(0.82, 0.84, 0.80, 0.96))
    _objective_detail_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
    add_child(_objective_detail_label)

    for _i in 3:
        var label := _label(20, Color(1.0, 0.98, 0.90, 1.0))
        label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
        label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
        add_child(label)
        _action_labels.append(label)
    _refresh_labels()

func set_machine_mode(enabled: bool) -> void:
    _machine_mode = enabled
    if enabled:
        _interaction_hint = "LEFT: DRIVE + STEER    RIGHT: SWING + BOOM    ACTIONS: CURL / CLAMP / EXIT"
    elif _interaction_hint.begins_with("LEFT:"):
        _interaction_hint = ""
    _refresh_labels()

func set_health(value: float) -> void:
    _health_ratio = clampf(value, 0.0, 1.0)

func set_target(node) -> void:
    _target = node

func set_context(text: String) -> void:
    _context_text = text

func set_interaction_hint(text: String) -> void:
    if _machine_mode and not text.is_empty() and not text.begins_with("LEFT:"):
        return
    _interaction_hint = text

func set_objective(title: String, detail: String) -> void:
    _objective_title = title
    _objective_detail = detail

func set_objective_progress(value: float) -> void:
    _objective_progress = clampf(value, 0.0, 1.0)

func set_machine_telemetry(integrity: float, hydraulics: float, tracks: float, force_ratio: float, holding: bool) -> void:
    _machine_integrity = clampf(integrity, 0.0, 1.0)
    _machine_hydraulics = clampf(hydraulics, 0.0, 1.0)
    _machine_tracks = clampf(tracks, 0.0, 1.0)
    _machine_force = clampf(force_ratio, 0.0, 1.0)
    _machine_holding = holding
    if _machine_mode and _action_labels.size() >= 2:
        _action_labels[1].text = "RELEASE" if holding else "CLAMP"

func flash_damage() -> void:
    _damage_flash = 1.0

func _refresh_labels() -> void:
    if _action_labels.size() < 3:
        return
    if _machine_mode:
        _action_labels[0].text = "CURL / SMASH"
        _action_labels[1].text = "RELEASE" if _machine_holding else "CLAMP"
        _action_labels[2].text = "EXIT"
        _mode_label.text = "EXCAVATOR // DIRECT PHYSICAL CONTROL"
    else:
        _action_labels[0].text = "HIT"
        _action_labels[1].text = "GRAB"
        _action_labels[2].text = "USE"
        _mode_label.text = "ON FOOT // ADAPTIVE LOCK"

func _resize_to_viewport() -> void:
    _view_size = get_viewport_rect().size
    position = Vector2.ZERO
    size = _view_size
    var sx: float = _view_size.x / 1920.0
    var sy: float = _view_size.y / 1080.0
    _ui_scale = clampf(minf(sx, sy), 0.66, 1.28)
    if absf(_last_font_scale - _ui_scale) > 0.025:
        _last_font_scale = _ui_scale
        _apply_font_scale()

func _apply_font_scale() -> void:
    var s := _ui_scale
    _title_label.add_theme_font_size_override("font_size", maxi(17, int(23.0 * s)))
    _mode_label.add_theme_font_size_override("font_size", maxi(13, int(16.0 * s)))
    _context_label.add_theme_font_size_override("font_size", maxi(13, int(17.0 * s)))
    _interaction_label.add_theme_font_size_override("font_size", maxi(14, int(18.0 * s)))
    _objective_title_label.add_theme_font_size_override("font_size", maxi(15, int(20.0 * s)))
    _objective_detail_label.add_theme_font_size_override("font_size", maxi(12, int(14.0 * s)))
    for label in _action_labels:
        label.add_theme_font_size_override("font_size", maxi(15, int(20.0 * s)))

func _process(delta: float) -> void:
    _resize_to_viewport()
    _damage_flash = maxf(0.0, _damage_flash - delta * 3.8)
    var s := _ui_scale
    var margin := 28.0 * s

    _title_label.position = Vector2(margin + 18.0 * s, margin + 10.0 * s)
    _title_label.size = Vector2(330.0 * s, 34.0 * s)
    _mode_label.position = Vector2(margin + 18.0 * s, margin + 43.0 * s)
    _mode_label.size = Vector2(430.0 * s, 28.0 * s)

    var objective_w := minf(760.0 * s, _view_size.x * 0.52)
    _objective_title_label.text = _objective_title
    _objective_title_label.position = Vector2((_view_size.x - objective_w) * 0.5, margin + 6.0 * s)
    _objective_title_label.size = Vector2(objective_w, 32.0 * s)
    _objective_detail_label.text = _objective_detail
    _objective_detail_label.position = Vector2((_view_size.x - objective_w) * 0.5, margin + 37.0 * s)
    _objective_detail_label.size = Vector2(objective_w, 28.0 * s)

    _context_label.text = _context_text
    _context_label.position = Vector2(_view_size.x * 0.5 - 320.0 * s, _view_size.y - 50.0 * s)
    _context_label.size = Vector2(640.0 * s, 30.0 * s)

    _interaction_label.text = _interaction_hint
    _interaction_label.visible = not _interaction_hint.is_empty()
    _interaction_label.position = Vector2(_view_size.x * 0.5 - 420.0 * s, _view_size.y - 104.0 * s)
    _interaction_label.size = Vector2(840.0 * s, 40.0 * s)

    for i in mini(3, _action_labels.size()):
        var rect := _button_rect(i)
        _action_labels[i].position = rect.position + Vector2(0.0, rect.size.y * 0.50)
        _action_labels[i].size = Vector2(rect.size.x, rect.size.y * 0.45)
    queue_redraw()

func consume_look() -> Vector2:
    var out := look_accum
    look_accum = Vector2.ZERO
    return out

func consume_attack() -> bool:
    var out := attack_pulse
    attack_pulse = false
    return out

func consume_grab() -> bool:
    var out := grab_pulse
    grab_pulse = false
    return out

func consume_use() -> bool:
    var out := use_pulse
    use_pulse = false
    return out

func _input(event: InputEvent) -> void:
    if event is InputEventScreenTouch:
        _touch(event)
    elif event is InputEventScreenDrag:
        _drag(event)

func _touch(event: InputEventScreenTouch) -> void:
    if event.pressed:
        if _try_action(event.position):
            return
        if event.position.x < _view_size.x * 0.46:
            if _move_touch < 0:
                _move_touch = event.index
                _move_origin = event.position
                _move_pos = event.position
                move_axis = Vector2.ZERO
            return
        if _look_touch < 0:
            _look_touch = event.index
    else:
        if event.index == _move_touch:
            _move_touch = -1
            move_axis = Vector2.ZERO
        if event.index == _look_touch:
            _look_touch = -1
        smash_held = false

func _drag(event: InputEventScreenDrag) -> void:
    var stick_r := BASE_STICK_R * _ui_scale
    var dead_r := BASE_DEAD_R * _ui_scale
    if event.index == _move_touch:
        _move_pos = event.position
        var delta := _move_pos - _move_origin
        move_axis = Vector2.ZERO if delta.length() < dead_r else delta.limit_length(stick_r) / stick_r
    elif event.index == _look_touch:
        look_accum += event.relative

func _try_action(pos: Vector2) -> bool:
    if _button_rect(0).has_point(pos):
        attack_pulse = true
        smash_held = true
        return true
    if _button_rect(1).has_point(pos):
        grab_pulse = true
        return true
    if _button_rect(2).has_point(pos):
        use_pulse = true
        return true
    return false

func _button_rect(index: int) -> Rect2:
    var s := _ui_scale
    var button_size := Vector2(188.0, 126.0) * s
    var pad := 34.0 * s
    var gap := 18.0 * s
    var x := _view_size.x - button_size.x - pad
    var y := _view_size.y - button_size.y - pad
    if index == 1:
        x -= button_size.x + gap
    elif index == 2:
        y -= button_size.y + gap
        x -= button_size.x * 0.42
    return Rect2(Vector2(x, y), button_size)

func _draw() -> void:
    _draw_status_panel()
    _draw_objective_panel()
    if _machine_mode:
        _draw_machine_panel()
    _draw_move_zone()
    _draw_action_button(0, Color(0.86, 0.22, 0.055, 0.94))
    _draw_action_button(1, Color(0.94, 0.57, 0.075, 0.92))
    _draw_action_button(2, Color(0.08, 0.58, 0.66, 0.92))
    _draw_target_bracket()
    if not _interaction_hint.is_empty():
        _draw_interaction_panel()
    if _damage_flash > 0.0:
        draw_rect(Rect2(Vector2.ZERO, _view_size), Color(0.70, 0.045, 0.02, 0.13 * _damage_flash), false, 12.0 * _ui_scale)

func _draw_status_panel() -> void:
    var s := _ui_scale
    var panel := Rect2(Vector2(28.0, 20.0) * s, Vector2(400.0, 106.0) * s)
    _rounded(panel, Color(0.012, 0.018, 0.019, 0.87), Color(0.58, 0.45, 0.20, 0.84), 2.0 * s)
    var bar_bg := Rect2(Vector2(48.0, 96.0) * s, Vector2(304.0, 12.0) * s)
    draw_rect(bar_bg, Color(0.055, 0.065, 0.062, 0.96))
    var hp_color := Color(0.92, 0.55, 0.08, 0.98) if _health_ratio >= 0.34 else Color(0.94, 0.12, 0.045, 1.0)
    draw_rect(Rect2(bar_bg.position, Vector2(bar_bg.size.x * _health_ratio, bar_bg.size.y)), hp_color)
    draw_string(ThemeDB.fallback_font, Vector2(365.0, 108.0) * s, "%d%%" % int(_health_ratio * 100.0), HORIZONTAL_ALIGNMENT_RIGHT, 38.0 * s, maxi(11, int(15.0 * s)), Color(0.92, 0.90, 0.82, 0.96))

func _draw_objective_panel() -> void:
    var s := _ui_scale
    var width := minf(820.0 * s, _view_size.x * 0.56)
    var x := (_view_size.x - width) * 0.5
    var panel := Rect2(Vector2(x, 16.0 * s), Vector2(width, 94.0 * s))
    _rounded(panel, Color(0.010, 0.016, 0.017, 0.84), Color(0.42, 0.35, 0.19, 0.76), 1.8 * s)
    var bg := Rect2(Vector2(x + 24.0 * s, 86.0 * s), Vector2(width - 48.0 * s, 7.0 * s))
    draw_rect(bg, Color(0.06, 0.07, 0.067, 0.94))
    draw_rect(Rect2(bg.position, Vector2(bg.size.x * _objective_progress, bg.size.y)), Color(0.96, 0.56, 0.06, 0.98))

func _draw_machine_panel() -> void:
    var s := _ui_scale
    var panel := Rect2(Vector2(28.0, 142.0) * s, Vector2(400.0, 156.0) * s)
    _rounded(panel, Color(0.012, 0.018, 0.019, 0.87), Color(0.55, 0.40, 0.13, 0.80), 2.0 * s)
    draw_string(ThemeDB.fallback_font, Vector2(48.0, 168.0) * s, "MACHINE STATE", HORIZONTAL_ALIGNMENT_LEFT, 180.0 * s, maxi(11, int(15.0 * s)), Color(0.98, 0.72, 0.24))
    _meter(Vector2(48.0, 186.0) * s, "INT", _machine_integrity, Color(0.92, 0.38, 0.055))
    _meter(Vector2(48.0, 214.0) * s, "HYD", _machine_hydraulics, Color(0.10, 0.68, 0.76))
    _meter(Vector2(48.0, 242.0) * s, "TRK", _machine_tracks, Color(0.74, 0.72, 0.58))
    _meter(Vector2(48.0, 270.0) * s, "FRC", _machine_force, Color(0.98, 0.62, 0.08))
    var clamp_text := "LOAD CLAMPED" if _machine_holding else "CLAMP OPEN"
    draw_string(ThemeDB.fallback_font, Vector2(248.0, 168.0) * s, clamp_text, HORIZONTAL_ALIGNMENT_RIGHT, 150.0 * s, maxi(10, int(13.0 * s)), Color(0.86, 0.88, 0.82))

func _meter(pos: Vector2, name: String, value: float, color: Color) -> void:
    var s := _ui_scale
    draw_string(ThemeDB.fallback_font, pos + Vector2(0.0, 12.0 * s), name, HORIZONTAL_ALIGNMENT_LEFT, 42.0 * s, maxi(10, int(12.0 * s)), Color(0.80, 0.82, 0.77))
    var bg := Rect2(pos + Vector2(48.0 * s, 3.0 * s), Vector2(286.0, 9.0) * s)
    draw_rect(bg, Color(0.055, 0.065, 0.062, 0.96))
    draw_rect(Rect2(bg.position, Vector2(bg.size.x * value, bg.size.y)), color)

func _draw_move_zone() -> void:
    var s := _ui_scale
    var center := Vector2(154.0 * s, _view_size.y - 154.0 * s)
    var outer := 92.0 * s
    draw_circle(center, outer, Color(0.012, 0.020, 0.021, 0.58))
    draw_arc(center, outer, 0.0, TAU, 56, Color(0.72, 0.56, 0.27, 0.65), 3.0 * s)
    draw_arc(center, 48.0 * s, 0.0, TAU, 48, Color(0.76, 0.79, 0.72, 0.32), 2.0 * s)
    draw_line(center + Vector2(-20.0, 0.0) * s, center + Vector2(20.0, 0.0) * s, Color(0.68, 0.70, 0.65, 0.22), 1.5 * s)
    draw_line(center + Vector2(0.0, -20.0) * s, center + Vector2(0.0, 20.0) * s, Color(0.68, 0.70, 0.65, 0.22), 1.5 * s)
    if _move_touch >= 0:
        var stick_r := BASE_STICK_R * s
        draw_circle(_move_origin, stick_r, Color(0.02, 0.03, 0.03, 0.52))
        draw_arc(_move_origin, stick_r, 0.0, TAU, 56, Color(0.91, 0.68, 0.27, 0.82), 3.5 * s)
        draw_circle(_move_origin + move_axis * stick_r, 44.0 * s, Color(0.90, 0.82, 0.64, 0.88))

func _draw_action_button(index: int, accent: Color) -> void:
    var s := _ui_scale
    var rect := _button_rect(index)
    _rounded(rect, Color(0.010, 0.018, 0.020, 0.86), Color(accent.r, accent.g, accent.b, 0.94), 3.0 * s)
    draw_rect(Rect2(rect.position, Vector2(7.0 * s, rect.size.y)), accent)
    _draw_action_icon(index, rect, accent)

func _draw_action_icon(index: int, rect: Rect2, accent: Color) -> void:
    var s := _ui_scale
    var c := rect.position + Vector2(rect.size.x * 0.5, rect.size.y * 0.31)
    var line := Color(accent.r, accent.g, accent.b, 1.0)
    var w := 4.0 * s
    if index == 0:
        if _machine_mode:
            draw_line(c + Vector2(-26.0, -18.0) * s, c + Vector2(12.0, 18.0) * s, line, w)
            draw_rect(Rect2(c + Vector2(4.0, 10.0) * s, Vector2(30.0, 18.0) * s), line, false, w)
        else:
            for i in 4:
                draw_circle(c + Vector2((-24.0 + float(i) * 16.0) * s, -8.0 * s), 8.0 * s, line)
            draw_rect(Rect2(c + Vector2(-26.0, -3.0) * s, Vector2(58.0, 23.0) * s), line, false, w)
    elif index == 1:
        draw_arc(c + Vector2(-12.0, 0.0) * s, 22.0 * s, -1.2, 1.2, 20, line, w)
        draw_arc(c + Vector2(12.0, 0.0) * s, 22.0 * s, PI - 1.2, PI + 1.2, 20, line, w)
        draw_line(c + Vector2(-4.0, -18.0) * s, c + Vector2(-4.0, 18.0) * s, line, w)
        draw_line(c + Vector2(4.0, -18.0) * s, c + Vector2(4.0, 18.0) * s, line, w)
    else:
        draw_line(c + Vector2(-24.0, 0.0) * s, c + Vector2(20.0, 0.0) * s, line, w)
        draw_line(c + Vector2(7.0, -14.0) * s, c + Vector2(22.0, 0.0) * s, line, w)
        draw_line(c + Vector2(7.0, 14.0) * s, c + Vector2(22.0, 0.0) * s, line, w)
        draw_rect(Rect2(c + Vector2(-30.0, -22.0) * s, Vector2(16.0, 44.0) * s), line, false, w)

func _draw_interaction_panel() -> void:
    var s := _ui_scale
    var width := minf(900.0 * s, _view_size.x * 0.58)
    var rect := Rect2(Vector2((_view_size.x - width) * 0.5, _view_size.y - 114.0 * s), Vector2(width, 48.0 * s))
    _rounded(rect, Color(0.008, 0.014, 0.015, 0.82), Color(0.90, 0.58, 0.11, 0.72), 2.0 * s)

func _rounded(rect: Rect2, fill: Color, border: Color, border_width: float) -> void:
    var style := StyleBoxFlat.new()
    style.bg_color = fill
    style.border_color = border
    style.set_border_width_all(maxi(1, int(border_width)))
    var radius := maxi(8, int(14.0 * _ui_scale))
    style.corner_radius_top_left = radius
    style.corner_radius_top_right = radius
    style.corner_radius_bottom_left = radius
    style.corner_radius_bottom_right = radius
    draw_style_box(style, rect)

func _draw_target_bracket() -> void:
    if _target == null or not is_instance_valid(_target) or not (_target is Node3D):
        return
    var camera := get_viewport().get_camera_3d()
    if camera == null or camera.is_position_behind(_target.global_position + Vector3.UP * 1.25):
        return
    var p := camera.unproject_position(_target.global_position + Vector3.UP * 1.25)
    var r := 34.0 * _ui_scale
    var c := Color(1.0, 0.60, 0.10, 0.96)
    var w := 3.5 * _ui_scale
    draw_line(p + Vector2(-r, -r), p + Vector2(-r * 0.32, -r), c, w)
    draw_line(p + Vector2(-r, -r), p + Vector2(-r, -r * 0.32), c, w)
    draw_line(p + Vector2(r, -r), p + Vector2(r * 0.32, -r), c, w)
    draw_line(p + Vector2(r, -r), p + Vector2(r, -r * 0.32), c, w)
    draw_line(p + Vector2(-r, r), p + Vector2(-r * 0.32, r), c, w)
    draw_line(p + Vector2(-r, r), p + Vector2(-r, r * 0.32), c, w)
    draw_line(p + Vector2(r, r), p + Vector2(r * 0.32, r), c, w)
    draw_line(p + Vector2(r, r), p + Vector2(r, r * 0.32), c, w)
