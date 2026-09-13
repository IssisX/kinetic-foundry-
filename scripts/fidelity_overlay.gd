class_name FidelityOverlay
extends Control

## Fold-friendly developer fidelity control. A short touch changes only live
## representation knobs. Holding the slider for 0.4 s explicitly rebuilds the
## scene at the selected topology resolution, preserving honesty about cracks.

const HOLD_SECONDS := 0.40

var _view_size := Vector2(1920.0, 1080.0)
var _touch_id := -1
var _hold_time := 0.0
var _rebuild_fired := false
var _pressed_on_slider := false

func _ready() -> void:
    mouse_filter = Control.MOUSE_FILTER_IGNORE
    set_process(true)
    set_process_input(true)
    _resize()

func _process(delta: float) -> void:
    _resize()
    if _touch_id >= 0 and _pressed_on_slider and not _rebuild_fired:
        _hold_time += delta
        if _hold_time >= HOLD_SECONDS:
            _rebuild_fired = true
            Fidelity.request_rebuild()
    queue_redraw()

func _resize() -> void:
    _view_size = get_viewport_rect().size
    position = Vector2.ZERO
    size = _view_size

func _input(event: InputEvent) -> void:
    if event is InputEventScreenTouch:
        _touch(event)
    elif event is InputEventScreenDrag:
        _drag(event)
    elif event is InputEventKey and event.pressed and not event.echo:
        if event.keycode == KEY_F6:
            Fidelity.set_live_f((Fidelity.f + 1) % 4)
        elif event.keycode == KEY_F7:
            Fidelity.request_rebuild()

func _touch(event: InputEventScreenTouch) -> void:
    if event.pressed:
        if _slider_rect().has_point(event.position):
            _touch_id = event.index
            _hold_time = 0.0
            _rebuild_fired = false
            _pressed_on_slider = true
            _select_from_x(event.position.x)
            get_viewport().set_input_as_handled()
            return
        if _rebuild_rect().has_point(event.position):
            Fidelity.request_rebuild()
            get_viewport().set_input_as_handled()
            return
    elif event.index == _touch_id:
        _touch_id = -1
        _hold_time = 0.0
        _pressed_on_slider = false
        _rebuild_fired = false
        get_viewport().set_input_as_handled()

func _drag(event: InputEventScreenDrag) -> void:
    if event.index != _touch_id or not _pressed_on_slider:
        return
    _select_from_x(event.position.x)
    _hold_time = 0.0
    _rebuild_fired = false
    get_viewport().set_input_as_handled()

func _select_from_x(x: float) -> void:
    var slider := _slider_rect()
    var t := clampf((x - slider.position.x) / maxf(slider.size.x, 1.0), 0.0, 1.0)
    Fidelity.set_live_f(clampi(roundi(t * 3.0), 0, 3))

func _panel_rect() -> Rect2:
    var scale := clampf(minf(_view_size.x / 1920.0, _view_size.y / 1080.0), 0.68, 1.22)
    var panel_size := Vector2(438.0, 154.0) * scale
    return Rect2(
        Vector2(_view_size.x - panel_size.x - 28.0 * scale, 20.0 * scale),
        panel_size
    )

func _slider_rect() -> Rect2:
    var panel := _panel_rect()
    var pad := panel.size.x * 0.075
    return Rect2(
        Vector2(panel.position.x + pad, panel.position.y + panel.size.y * 0.39),
        Vector2(panel.size.x - pad * 2.0, panel.size.y * 0.22)
    )

func _rebuild_rect() -> Rect2:
    var panel := _panel_rect()
    return Rect2(
        Vector2(panel.position.x + panel.size.x * 0.61, panel.position.y + panel.size.y * 0.70),
        Vector2(panel.size.x * 0.31, panel.size.y * 0.20)
    )

func _draw() -> void:
    var panel := _panel_rect()
    var scale := panel.size.x / 438.0
    draw_style_box(_panel_style(), panel)
    var font := ThemeDB.fallback_font
    var title_pos := panel.position + Vector2(22.0, 28.0) * scale
    draw_string(
        font,
        title_pos,
        "FIDELITY  F%d    TOPO F%d" % [Fidelity.f, Fidelity.topology_f],
        HORIZONTAL_ALIGNMENT_LEFT,
        panel.size.x - 44.0 * scale,
        maxi(12, int(17.0 * scale)),
        Color(1.0, 0.79, 0.27)
    )

    var slider := _slider_rect()
    draw_rect(slider, Color(0.05, 0.065, 0.064, 0.95), true)
    draw_line(
        Vector2(slider.position.x + 10.0 * scale, slider.get_center().y),
        Vector2(slider.end.x - 10.0 * scale, slider.get_center().y),
        Color(0.66, 0.67, 0.62, 0.95),
        3.0 * scale
    )
    for index in 4:
        var x := lerpf(
            slider.position.x + 12.0 * scale,
            slider.end.x - 12.0 * scale,
            float(index) / 3.0
        )
        var active := index == Fidelity.f
        draw_circle(
            Vector2(x, slider.get_center().y),
            (10.0 if active else 5.0) * scale,
            Color(1.0, 0.57, 0.08) if active else Color(0.60, 0.62, 0.58)
        )
        draw_string(
            font,
            Vector2(x - 7.0 * scale, slider.end.y + 17.0 * scale),
            str(index),
            HORIZONTAL_ALIGNMENT_LEFT,
            18.0 * scale,
            maxi(10, int(12.0 * scale)),
            Color(0.84, 0.85, 0.80)
        )

    var telemetry := (
        "N %d  B %d  SH %d  PHYS %.2f ms"
        % [
            Fidelity.telemetry_nodes,
            Fidelity.telemetry_bonds,
            Fidelity.telemetry_shards,
            Fidelity.telemetry_ms_phys
        ]
    )
    var telemetry_color := (
        Color(1.0, 0.28, 0.08)
        if Fidelity.telemetry_ms_phys > 12.0
        else Color(0.72, 0.90, 0.72)
    )
    draw_string(
        font,
        panel.position + Vector2(22.0, 134.0) * scale,
        telemetry,
        HORIZONTAL_ALIGNMENT_LEFT,
        panel.size.x * 0.62,
        maxi(10, int(12.0 * scale)),
        telemetry_color
    )

    var rebuild := _rebuild_rect()
    var needs_rebuild := Fidelity.f != Fidelity.topology_f
    draw_rect(
        rebuild,
        Color(0.46, 0.16, 0.045, 0.95) if needs_rebuild else Color(0.09, 0.11, 0.10, 0.88),
        true
    )
    draw_string(
        font,
        rebuild.position + Vector2(10.0, rebuild.size.y * 0.70),
        "REBUILD PLATE" if needs_rebuild else "TOPOLOGY LIVE",
        HORIZONTAL_ALIGNMENT_CENTER,
        rebuild.size.x - 20.0 * scale,
        maxi(9, int(11.0 * scale)),
        Color(1.0, 0.89, 0.65)
    )

func _panel_style() -> StyleBoxFlat:
    var style := StyleBoxFlat.new()
    style.bg_color = Color(0.008, 0.014, 0.014, 0.90)
    style.border_color = Color(0.48, 0.38, 0.18, 0.88)
    style.set_border_width_all(2)
    style.corner_radius_top_left = 10
    style.corner_radius_top_right = 10
    style.corner_radius_bottom_left = 10
    style.corner_radius_bottom_right = 10
    return style
