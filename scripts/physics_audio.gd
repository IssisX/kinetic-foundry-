class_name PhysicsAudio
extends Node3D

const MIX_RATE := 24000
const MAX_VOICES := 14
const STREAM_BUFFER_SECONDS := 0.28

var _voices: Array[AudioStreamPlayer3D] = []
var _serial := 0
var _machine: Node3D
var _machine_player: AudioStreamPlayer3D
var _machine_playback: AudioStreamGeneratorPlayback
var _engine_phase := 0.0
var _hydraulic_phase := 0.0
var _track_phase := 0.0
var _noise_state := 0.137

func _ready() -> void:
    add_to_group("physical_event_listener")
    add_to_group("physics_audio")
    if OS.get_environment("KF_CAPTURE") != "1":
        _build_machine_stream()

func _process(_delta: float) -> void:
    if OS.get_environment("KF_CAPTURE") == "1":
        return
    _update_machine_stream()

func physical_event(event: Dictionary) -> void:
    if OS.get_environment("KF_CAPTURE") == "1":
        return
    var event_type := str(event.get("type", "impact"))
    var position_value: Variant = event.get("position", Vector3.ZERO)
    var position := position_value as Vector3
    var impulse := maxf(float(event.get("impulse", 0.0)), 0.0)
    var mass := maxf(float(event.get("mass", 1.0)), 1.0)
    var fracture := clampf(float(event.get("fracture", 0.0)), 0.0, 1.0)
    var radius := maxf(float(event.get("radius", 1.0)), 0.5)
    var material := str(event.get("material", "steel"))

    var importance := clampf(
        log(1.0 + impulse * 0.025) / 4.2
        + fracture * 0.34
        + clampf(mass / 1800.0, 0.0, 0.25),
        0.0,
        1.35
    )
    if importance < 0.075 and event_type != "collapse":
        return

    _prune_voices()
    if _voices.size() >= MAX_VOICES:
        if importance < 0.42:
            return
        var oldest := _voices.pop_front()
        if is_instance_valid(oldest):
            oldest.stop()
            oldest.queue_free()

    var duration := _duration_for(event_type, mass, fracture)
    var wav := _synthesize(
        event_type,
        material,
        impulse,
        mass,
        fracture,
        duration,
        position
    )
    var player := AudioStreamPlayer3D.new()
    player.stream = wav
    player.global_position = position
    player.unit_size = maxf(2.8, radius * 0.55)
    player.max_distance = clampf(26.0 + radius * 3.5, 30.0, 92.0)
    player.attenuation_filter_cutoff_hz = 15000.0
    player.attenuation_filter_db = -9.0
    player.volume_db = lerpf(-11.0, 2.0, clampf(importance, 0.0, 1.0))
    add_child(player)
    player.top_level = true
    _voices.append(player)
    player.finished.connect(_on_voice_finished.bind(player))
    player.play()

func _build_machine_stream() -> void:
    var generator := AudioStreamGenerator.new()
    generator.mix_rate = MIX_RATE
    generator.buffer_length = STREAM_BUFFER_SECONDS
    _machine_player = AudioStreamPlayer3D.new()
    _machine_player.stream = generator
    _machine_player.volume_db = -48.0
    _machine_player.unit_size = 7.0
    _machine_player.max_distance = 80.0
    _machine_player.attenuation_filter_cutoff_hz = 12500.0
    _machine_player.attenuation_filter_db = -8.0
    add_child(_machine_player)
    _machine_player.top_level = true
    _machine_player.play()
    _machine_playback = (
        _machine_player.get_stream_playback()
        as AudioStreamGeneratorPlayback
    )

func _update_machine_stream() -> void:
    if _machine_player == null or _machine_playback == null:
        return
    if _machine == null or not is_instance_valid(_machine):
        _machine = get_tree().get_first_node_in_group("machine") as Node3D
    if _machine == null or not is_instance_valid(_machine):
        _machine_player.volume_db = -60.0
        return

    _machine_player.global_position = _machine.global_position + Vector3.UP * 1.2
    var speed := 0.0
    if _machine is CharacterBody3D:
        var body := _machine as CharacterBody3D
        speed = Vector3(body.velocity.x, 0.0, body.velocity.z).length()

    var effort := 0.0
    var reaction := 0.0
    var stability := 0.0
    if _machine.has_method("get_sustained_contact_state"):
        var state: Dictionary = _machine.get_sustained_contact_state()
        effort = clampf(float(state.get("effort", 0.0)), 0.0, 1.0)
        reaction = clampf(float(state.get("reaction_ratio", 0.0)), 0.0, 1.0)
        stability = clampf(float(state.get("stability_ratio", 0.0)), 0.0, 1.5)

    var hydraulic_ratio := 1.0
    if _machine.has_method("get_hydraulic_ratio"):
        hydraulic_ratio = clampf(float(_machine.get_hydraulic_ratio()), 0.0, 1.0)

    var audible := maxf(
        0.12,
        clampf(speed / 7.0, 0.0, 1.0) * 0.46
        + effort * 0.48
        + reaction * 0.36
    )
    if _machine.has_method("is_player_driven") and bool(_machine.is_player_driven()):
        audible = maxf(audible, 0.34)
    var target_db := lerpf(-34.0, -7.0, clampf(audible, 0.0, 1.0))
    _machine_player.volume_db = lerpf(
        _machine_player.volume_db,
        target_db,
        0.12
    )

    var available := mini(_machine_playback.get_frames_available(), 1536)
    for _i in available:
        var engine_hz := 43.0 + speed * 5.6 + effort * 8.0
        var hydraulic_hz := (
            118.0
            + effort * 118.0
            + reaction * 74.0
            + (1.0 - hydraulic_ratio) * 32.0
        )
        var track_hz := 5.5 + speed * 3.2

        _engine_phase = fmod(
            _engine_phase + TAU * engine_hz / float(MIX_RATE),
            TAU
        )
        _hydraulic_phase = fmod(
            _hydraulic_phase + TAU * hydraulic_hz / float(MIX_RATE),
            TAU
        )
        _track_phase = fmod(
            _track_phase + TAU * track_hz / float(MIX_RATE),
            TAU
        )

        _noise_state = fmod(_noise_state * 17.731 + 0.139, 1.0)
        var noise := _noise_state * 2.0 - 1.0
        var engine := (
            sin(_engine_phase) * 0.48
            + sin(_engine_phase * 2.0 + 0.2) * 0.17
            + sin(_engine_phase * 3.0 + 0.7) * 0.07
        )
        var hydraulic := (
            sin(_hydraulic_phase) * 0.26
            + sin(_hydraulic_phase * 1.51 + 0.4) * 0.11
        ) * effort * (0.34 + reaction * 0.66)
        var track_gate := maxf(0.0, sin(_track_phase))
        track_gate = track_gate * track_gate * track_gate
        var tracks := (
            track_gate
            * noise
            * clampf(speed / 6.0, 0.0, 1.0)
            * 0.22
        )
        var strain_groan := (
            sin(_engine_phase * 0.37 + _hydraulic_phase * 0.08)
            * reaction
            * effort
            * 0.18
        )
        var instability := (
            noise
            * maxf(stability - 0.82, 0.0)
            * 0.08
        )
        var sample := tanh(
            engine * 0.42
            + hydraulic
            + tracks
            + strain_groan
            + instability
        ) * 0.72
        _machine_playback.push_frame(Vector2(sample, sample))

func _duration_for(event_type: String, mass: float, fracture: float) -> float:
    if event_type == "collapse":
        return clampf(0.95 + mass / 2600.0 + fracture * 0.45, 1.0, 2.2)
    if event_type == "hydraulic":
        return clampf(0.34 + fracture * 0.55, 0.34, 0.95)
    if event_type == "fracture":
        return clampf(0.28 + fracture * 0.60, 0.30, 1.05)
    return clampf(0.18 + log(1.0 + mass) * 0.035, 0.18, 0.62)

func _synthesize(
        event_type: String,
        material: String,
        impulse: float,
        mass: float,
        fracture: float,
        duration: float,
        position: Vector3
) -> AudioStreamWAV:
    var frame_count := maxi(64, int(duration * float(MIX_RATE)))
    var bytes := PackedByteArray()
    bytes.resize(frame_count * 2)

    var rng := RandomNumberGenerator.new()
    _serial += 1
    var seed_value := int(
        absf(position.x * 738.0)
        + absf(position.y * 1931.0)
        + absf(position.z * 421.0)
        + impulse * 3.0
        + mass
        + float(_serial * 811)
    )
    rng.seed = seed_value

    var material_kind := material.to_lower()
    var base_frequency := _base_frequency(material_kind, mass, event_type)
    var energy := clampf(log(1.0 + impulse * 0.020) / 4.0, 0.06, 1.0)
    var low_mix := clampf(mass / 1200.0, 0.0, 1.0)

    for i in frame_count:
        var t := float(i) / float(MIX_RATE)
        var u := t / maxf(duration, 0.001)
        var transient := exp(-t * lerpf(34.0, 11.0, low_mix))
        var body_decay := exp(-t * lerpf(8.5, 2.8, low_mix))
        var tail := pow(maxf(0.0, 1.0 - u), 1.35)
        var noise := rng.randf_range(-1.0, 1.0)
        var sample := 0.0

        if event_type == "hydraulic":
            var hiss := noise * exp(-t * 4.8)
            var pump := sin(TAU * 96.0 * t) * exp(-t * 7.0)
            sample = hiss * 0.62 + pump * 0.22
        elif event_type == "collapse":
            var rumble := (
                sin(TAU * base_frequency * 0.52 * t)
                + sin(TAU * base_frequency * 0.81 * t) * 0.62
                + sin(TAU * base_frequency * 1.37 * t) * 0.28
            )
            var crunch := noise * (0.38 + fracture * 0.45) * exp(-t * 2.9)
            sample = rumble * body_decay * 0.48 + crunch
        elif material_kind.contains("concrete"):
            var thud := sin(TAU * base_frequency * t) * body_decay
            var grit := noise * transient * (0.42 + fracture * 0.50)
            var crack := sin(TAU * base_frequency * 3.7 * t) * transient * fracture
            sample = thud * 0.52 + grit * 0.55 + crack * 0.18
        else:
            var mode_a := sin(TAU * base_frequency * t)
            var mode_b := sin(TAU * base_frequency * 2.41 * t + 0.33)
            var mode_c := sin(TAU * base_frequency * 4.17 * t + 1.10)
            var ring := (
                mode_a * 0.56
                + mode_b * 0.25
                + mode_c * 0.12
            ) * body_decay
            var scrape := noise * transient * (0.16 + fracture * 0.34)
            sample = ring + scrape

        sample *= energy * tail
        sample = tanh(sample * 1.45) * 0.86
        var encoded := clampi(int(sample * 32767.0), -32768, 32767)
        bytes.encode_s16(i * 2, encoded)

    var wav := AudioStreamWAV.new()
    wav.format = AudioStreamWAV.FORMAT_16_BITS
    wav.mix_rate = MIX_RATE
    wav.stereo = false
    wav.loop_mode = AudioStreamWAV.LOOP_DISABLED
    wav.data = bytes
    return wav

func _base_frequency(material: String, mass: float, event_type: String) -> float:
    if event_type == "collapse":
        return clampf(
            68.0 / pow(maxf(mass / 650.0, 0.25), 0.18),
            34.0,
            74.0
        )
    if material.contains("concrete"):
        return clampf(
            132.0 / pow(maxf(mass / 120.0, 0.22), 0.22),
            72.0,
            178.0
        )
    var steel_frequency := (
        285.0 / pow(maxf(mass / 80.0, 0.25), 0.24)
    )
    return clampf(steel_frequency, 82.0, 410.0)

func _prune_voices() -> void:
    var valid: Array[AudioStreamPlayer3D] = []
    for voice in _voices:
        if is_instance_valid(voice) and voice.playing:
            valid.append(voice)
        elif is_instance_valid(voice):
            voice.queue_free()
    _voices = valid

func _on_voice_finished(player: AudioStreamPlayer3D) -> void:
    if is_instance_valid(player):
        player.queue_free()
    _voices.erase(player)
