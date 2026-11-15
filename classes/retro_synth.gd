extends AudioStreamPlayer
## Tiny 8-bit synth (intro, plan phase), mixed live into an AudioStreamGenerator:
## sawtooth bass hits with a falling pitch, and short square-wave ticks.

const MIX_RATE: float = 22050.0

var enabled: bool = true

## {start, dur, f0, f1, gain, saw, phase}, times in seconds of generated audio.
var _voices: Array[Dictionary] = []
var _playback: AudioStreamGeneratorPlayback
var _time: float = 0.0


func _ready() -> void:
    var generator := AudioStreamGenerator.new()
    generator.mix_rate = MIX_RATE
    generator.buffer_length = 0.12
    stream = generator
    play()
    _playback = get_stream_playback() as AudioStreamGeneratorPlayback


## Sawtooth that drops from `freq` to 28 Hz.
func bass_hit(freq: float = 95.0, duration: float = 0.22, delay: float = 0.0) -> void:
    _add(freq, 28.0, duration, 0.14, true, delay)


func word_tick(freq: float = 680.0, delay: float = 0.0) -> void:
    _add(freq, freq, 0.055, 0.06, false, delay)


func red_alert() -> void:
    bass_hit(130.0, 0.28)
    word_tick(320.0, 0.06)
    word_tick(240.0, 0.16)


func title_chord() -> void:
    bass_hit(110.0, 0.45)
    for i in 4:
        word_tick([261.63, 329.63, 392.0, 523.25][i], i * 0.055)


func _add(f0: float, f1: float, duration: float, gain: float, saw: bool, delay: float) -> void:
    if not enabled:
        return
    _voices.append({"start": _time + delay, "dur": duration, "f0": f0, "f1": f1, "gain": gain, "saw": saw, "phase": 0.0})


func _process(_delta: float) -> void:
    if _playback == null:
        return
    for i in _playback.get_frames_available():
        var sample := 0.0
        for voice in _voices:
            var t: float = _time - voice["start"]
            if t < 0.0 or t >= voice["dur"]:
                continue
            var k: float = t / voice["dur"]
            var freq: float = voice["f0"] * pow(voice["f1"] / voice["f0"], k)
            var phase: float = fmod(voice["phase"] + freq / MIX_RATE, 1.0)
            voice["phase"] = phase
            var wave := (2.0 * phase - 1.0) if voice["saw"] else (1.0 if phase < 0.5 else -1.0)
            var gain: float = voice["gain"]
            sample += wave * gain * pow(0.001 / gain, k)
        _playback.push_frame(Vector2(sample, sample))
        _time += 1.0 / MIX_RATE
    _voices = _voices.filter(func(v: Dictionary): return _time < v["start"] + v["dur"])
