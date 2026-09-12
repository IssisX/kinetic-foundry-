class_name PhysicsAudio
extends Node3D

const MIX_RATE := 24000
const MAX_VOICES := 14

var _voices: Array[AudioStreamPlayer3D] = []
var _serial := 0

func _ready() -> void:
    add_to_group("physical_event_listener")

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
        return clampf(68.0 / pow(maxf(mass / 650.0, 0.25), 0.18), 34.0, 74.0)
    if material.contains("concrete"):
        return clampf(132.0 / pow(maxf(mass / 120.0, 0.22), 0.22), 72.0, 178.0)
    var steel_frequency := 285.0 / pow(maxf(mass / 80.0, 0.25), 0.24)
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
