class_name FoundryMenu
extends CanvasLayer

## Title, pause, and options. Process-always so the yard can halt without
## swallowing the Fold-6 pause target. Capture never instantiates this.

enum { TITLE, PAUSE, OPTIONS, HIDDEN }

var screen := HIDDEN
var _game: Node3D
var _host: Control
var _pause_btn: Button
var _panel: Panel
var _title: Label
var _sub: Label
var _buttons: Array[Button] = []
var _from_pause := false

const AMBER := Color(1.0, 0.78, 0.28, 1.0)
const MUTED := Color(0.78, 0.80, 0.76, 0.96)


func begin(root: Node3D) -> void:
    _game = root
    process_mode = Node.PROCESS_MODE_ALWAYS
    layer = 80
    _build()
    if OS.get_environment("KF_CAPTURE") == "1":
        _set_screen(HIDDEN)
        if _pause_btn != null:
            _pause_btn.visible = false
        return
    _set_screen(TITLE)


func _build() -> void:
    _host = Control.new()
    _host.name = "Host"
    _host.set_anchors_preset(Control.PRESET_FULL_RECT)
    _host.mouse_filter = Control.MOUSE_FILTER_STOP
    add_child(_host)

    var dim := ColorRect.new()
    dim.name = "Dim"
    dim.set_anchors_preset(Control.PRESET_FULL_RECT)
    dim.color = Color(0.02, 0.03, 0.028, 0.78)
    dim.mouse_filter = Control.MOUSE_FILTER_STOP
    _host.add_child(dim)

    _panel = Panel.new()
    _panel.name = "Panel"
    _style_panel(_panel)
    _host.add_child(_panel)

    _title = _make_label(36, AMBER)
    _title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
    _panel.add_child(_title)

    _sub = _make_label(15, MUTED)
    _sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
    _sub.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
    _panel.add_child(_sub)

    for i in 6:
        var btn := Button.new()
        btn.custom_minimum_size = Vector2(0, 56)
        _style_button(btn)
        btn.visible = false
        btn.pressed.connect(_on_button.bind(i))
        _panel.add_child(btn)
        _buttons.append(btn)

    _pause_btn = Button.new()
    _pause_btn.text = "PAUSE"
    _pause_btn.focus_mode = Control.FOCUS_NONE
    _style_button(_pause_btn)
    _pause_btn.pressed.connect(_on_pause_pressed)
    _host.add_child(_pause_btn)


func _make_label(size_px: int, color: Color) -> Label:
    var label := Label.new()
    label.add_theme_font_size_override("font_size", size_px)
    label.add_theme_color_override("font_color", color)
    label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.85))
    label.add_theme_constant_override("shadow_offset_x", 2)
    label.add_theme_constant_override("shadow_offset_y", 2)
    return label


func _style_panel(panel: Panel) -> void:
    var box := StyleBoxFlat.new()
    box.bg_color = Color(0.07, 0.08, 0.078, 0.96)
    box.border_color = Color(0.78, 0.52, 0.14, 0.92)
    box.set_border_width_all(2)
    box.set_corner_radius_all(10)
    box.content_margin_left = 28
    box.content_margin_right = 28
    box.content_margin_top = 24
    box.content_margin_bottom = 24
    panel.add_theme_stylebox_override("panel", box)


func _style_button(btn: Button) -> void:
    btn.focus_mode = Control.FOCUS_NONE
    var normal := StyleBoxFlat.new()
    normal.bg_color = Color(0.14, 0.15, 0.14, 0.98)
    normal.border_color = Color(0.62, 0.44, 0.14, 0.90)
    normal.set_border_width_all(1)
    normal.set_corner_radius_all(8)
    var hover := normal.duplicate()
    hover.bg_color = Color(0.22, 0.18, 0.10, 0.98)
    var press := normal.duplicate()
    press.bg_color = Color(0.32, 0.22, 0.08, 1.0)
    btn.add_theme_stylebox_override("normal", normal)
    btn.add_theme_stylebox_override("hover", hover)
    btn.add_theme_stylebox_override("pressed", press)
    btn.add_theme_color_override("font_color", AMBER)
    btn.add_theme_color_override("font_hover_color", Color(1, 0.92, 0.62, 1))
    btn.add_theme_color_override("font_pressed_color", Color(1, 1, 1, 1))
    btn.add_theme_font_size_override("font_size", 18)


func _process(_delta: float) -> void:
    _layout()
    if screen == HIDDEN and Input.is_action_just_pressed("ui_cancel"):
        _on_pause_pressed()
    elif screen != HIDDEN and screen != TITLE and Input.is_action_just_pressed("ui_cancel"):
        if screen == OPTIONS:
            _set_screen(PAUSE if _from_pause else TITLE)
        else:
            _resume()


func _input(event: InputEvent) -> void:
    if not (event is InputEventKey) or not event.pressed or event.echo:
        return
    var key: int = event.physical_keycode
    if screen == TITLE and (key == KEY_ENTER or key == KEY_SPACE or key == KEY_KP_ENTER):
        _resume()
        get_viewport().set_input_as_handled()
        return
    if key == KEY_ESCAPE or key == KEY_P:
        if screen == HIDDEN:
            _on_pause_pressed()
            get_viewport().set_input_as_handled()
        elif screen == PAUSE:
            _resume()
            get_viewport().set_input_as_handled()


func _layout() -> void:
    var view := get_viewport().get_visible_rect().size
    _host.size = view
    var s := clampf(minf(view.x / 1920.0, view.y / 1080.0), 0.72, 1.20)
    var capturing := OS.get_environment("KF_CAPTURE") == "1"
    var pause_size := Vector2(128.0, 56.0) * s
    _pause_btn.position = Vector2(view.x - pause_size.x - 22.0 * s, 16.0 * s)
    _pause_btn.size = pause_size
    _pause_btn.visible = screen == HIDDEN and not capturing
    _pause_btn.mouse_filter = (
        Control.MOUSE_FILTER_STOP if _pause_btn.visible else Control.MOUSE_FILTER_IGNORE
    )

    var dim := _host.get_node_or_null("Dim") as ColorRect
    if dim != null:
        dim.visible = screen != HIDDEN
        dim.size = view

    var visible_n := 0
    for btn in _buttons:
        if btn.visible:
            visible_n += 1
    var panel_w := minf(560.0 * s, view.x - 48.0)
    var panel_h := minf((168.0 + float(visible_n) * 70.0 + 20.0) * s, view.y - 36.0)
    _panel.size = Vector2(panel_w, panel_h)
    _panel.position = Vector2((view.x - panel_w) * 0.5, (view.y - panel_h) * 0.5)
    _panel.visible = screen != HIDDEN

    _title.position = Vector2(16.0 * s, 8.0 * s)
    _title.size = Vector2(panel_w - 32.0 * s, 48.0 * s)
    _sub.position = Vector2(24.0 * s, 58.0 * s)
    _sub.size = Vector2(panel_w - 48.0 * s, 72.0 * s)

    var y := 148.0 * s
    for btn in _buttons:
        if not btn.visible:
            continue
        btn.position = Vector2(28.0 * s, y)
        btn.size = Vector2(panel_w - 56.0 * s, 58.0 * s)
        y += 70.0 * s


func _set_screen(next: int) -> void:
    screen = next
    var tree := get_tree()
    if tree != null:
        tree.paused = next != HIDDEN
    if _host != null:
        _host.mouse_filter = (
            Control.MOUSE_FILTER_IGNORE if next == HIDDEN else Control.MOUSE_FILTER_STOP
        )
    match next:
        TITLE:
            _title.text = "KINETIC FOUNDRY"
            _sub.text = "Power is mass in motion. Three machines shove, hang, and tear. Stress, deformation, and damage are the same law as the wreckage."
            _set_buttons(["ENTER YARD", "OPTIONS"])
        PAUSE:
            _title.text = "YARD HALTED"
            _sub.text = "The machines keep their mass. Resume, retune the view, or abandon the yard."
            _set_buttons(["RESUME", "OPTIONS", "ABANDON YARD"])
        OPTIONS:
            _title.text = "VIEW LAW"
            _sub.text = "These knobs hide or show solver state. They do not invent a second physics."
            var option_labels: Array = _option_labels()
            option_labels.append("BACK")
            _set_buttons(option_labels)
        HIDDEN:
            _set_buttons([])


func _option_labels() -> Array[String]:
    return [
        "STRESS OVERLAY    //    %s" % ("ON" if GameOptions.stress_visible else "OFF"),
        "DEFORMATION    //    %s" % ("ON" if GameOptions.deformation_visible else "OFF"),
        "DAMAGE SKIN    //    %s" % ("ON" if GameOptions.damage_visible else "OFF"),
        "FIDELITY    //    F%d" % Fidelity.f
    ]


func _set_buttons(labels: Array) -> void:
    for i in _buttons.size():
        var btn := _buttons[i]
        if i < labels.size():
            btn.text = str(labels[i])
            btn.visible = true
        else:
            btn.visible = false
            btn.text = ""


func _on_pause_pressed() -> void:
    if screen == TITLE:
        return
    _from_pause = true
    _set_screen(PAUSE)


func _resume() -> void:
    _set_screen(HIDDEN)


func _on_button(index: int) -> void:
    match screen:
        TITLE:
            if index == 0:
                _resume()
            elif index == 1:
                _from_pause = false
                _set_screen(OPTIONS)
        PAUSE:
            if index == 0:
                _resume()
            elif index == 1:
                _from_pause = true
                _set_screen(OPTIONS)
            elif index == 2:
                _set_screen(TITLE)
        OPTIONS:
            if index == 0:
                GameOptions.toggle_stress()
            elif index == 1:
                GameOptions.toggle_deformation()
            elif index == 2:
                GameOptions.toggle_damage()
            elif index == 3:
                var next_f := (Fidelity.f + 1) % 4
                Fidelity.set_live(next_f)
                Fidelity.request_rebuild(next_f)
            else:
                _set_screen(PAUSE if _from_pause else TITLE)
                return
            var option_labels: Array = _option_labels()
            option_labels.append("BACK")
            _set_buttons(option_labels)
