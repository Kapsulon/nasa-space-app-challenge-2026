extends Node
## Background music, kept playing across scene changes (autoload "Music").
## Each scene asks for its track with Music.play(&"phase_1"). Asking for the
## track that is already playing does nothing, so the music flows on between
## scenes that share it (plan phase -> launch report -> launch). Changing track
## crossfades.
##
##   menu    : mission select
##   phase_1 : planning, launch report, launch (and back after a failed launch)
##   phase_2 : the mission

const TRACKS: Dictionary[StringName, AudioStream] = {
    &"menu": preload("res://assets/audio/menu.wav"),
    &"phase_1": preload("res://assets/audio/phase_1.wav"),
    &"phase_2": preload("res://assets/audio/phase_2.wav"),
}
## Music level, kept under the sound effects.
const VOLUME_DB: float = -8.0
const FADE_SECONDS: float = 1.5

## The track playing (or fading in), &"" when silent.
var current: StringName = &""

var _players: Array[AudioStreamPlayer] = []
var _active: int = 0
var _tweens: Dictionary[AudioStreamPlayer, Tween] = {}


func _ready() -> void:
    process_mode = Node.PROCESS_MODE_ALWAYS
    for i in 2:
        var player := AudioStreamPlayer.new()
        player.volume_linear = 0.0
        player.finished.connect(_on_finished.bind(player))
        add_child(player)
        _players.append(player)


func play(track: StringName) -> void:
    if track == current or not TRACKS.has(track):
        return
    current = track
    var old := _players[_active]
    _active = 1 - _active
    var player := _players[_active]
    player.stream = TRACKS[track]
    player.volume_linear = 0.0
    player.play()
    _fade(player, db_to_linear(VOLUME_DB))
    _fade(old, 0.0)


func stop() -> void:
    current = &""
    _fade(_players[_active], 0.0)


func _fade(player: AudioStreamPlayer, to: float) -> void:
    if _tweens.has(player):
        _tweens[player].kill()
    if to <= 0.0 and not player.playing:
        return
    # Ignore Engine.time_scale (the launch can be fast-forwarded).
    var tween := create_tween().set_ignore_time_scale(true)
    tween.tween_property(player, "volume_linear", to, FADE_SECONDS)
    if to <= 0.0:
        tween.tween_callback(player.stop)
    _tweens[player] = tween


## The tracks loop through their import settings. In case one doesn't, start
## it over when it ends.
func _on_finished(player: AudioStreamPlayer) -> void:
    if player == _players[_active] and current != &"":
        player.play()
