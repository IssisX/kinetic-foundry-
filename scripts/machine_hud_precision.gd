extends "res://scripts/machine_hud.gd"

var _machine_tool_touch := -1

func set_machine_mode(enabled: bool) -> void:
    if not enabled:
        _machine_tool_touch = -1
        smash_held = false
    super(enabled)

func _touch(event: InputEventScreenTouch) -> void:
    if _machine_mode:
        if event.pressed and _button_rect(0).has_point(event.position):
            _machine_tool_touch = event.index
            attack_pulse = true
            smash_held = true
            get_viewport().set_input_as_handled()
            return
        if not event.pressed and event.index == _machine_tool_touch:
            _machine_tool_touch = -1
            smash_held = false
            get_viewport().set_input_as_handled()
            return
    super(event)

func _drag(event: InputEventScreenDrag) -> void:
    if _machine_mode and event.index == _machine_tool_touch:
        # The primary action surface doubles as a precision two-axis pad.
        # The excavator consumes this as stick reach + bucket curl.
        look_accum += event.relative
        get_viewport().set_input_as_handled()
        return
    super(event)
