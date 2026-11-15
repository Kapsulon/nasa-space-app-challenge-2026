extends RefCounted
## Player settings (volume, music, fullscreen), saved in user://settings.cfg.
## The Music autoload loads and applies them at start-up; the menu's options
## screen edits them. Use through a preload, e.g.
## `const GameSettings := preload("res://classes/game_settings.gd")`.

const PATH: String = "user://settings.cfg"
## Audio bus the music plays on (created by the Music autoload).
const MUSIC_BUS: StringName = &"Music"

## Master volume, 0..1.
static var volume: float = 1.0
## Music volume on top of the master volume, 0..1.
static var music: float = 1.0
static var fullscreen: bool = true


static func load_and_apply() -> void:
    fullscreen = _is_fullscreen()
    var config := ConfigFile.new()
    if config.load(PATH) == OK:
        volume = clampf(config.get_value("audio", "volume", volume), 0.0, 1.0)
        music = clampf(config.get_value("audio", "music", music), 0.0, 1.0)
        fullscreen = config.get_value("display", "fullscreen", fullscreen)
    apply()


static func apply() -> void:
    AudioServer.set_bus_volume_linear(0, volume)
    var bus := AudioServer.get_bus_index(MUSIC_BUS)
    if bus >= 0:
        AudioServer.set_bus_volume_linear(bus, music)
    # The game view embedded in the editor can't change its window mode.
    if fullscreen != _is_fullscreen() and not Engine.is_embedded_in_editor():
        DisplayServer.window_set_mode(
            DisplayServer.WINDOW_MODE_FULLSCREEN if fullscreen else DisplayServer.WINDOW_MODE_WINDOWED)


static func save() -> void:
    var config := ConfigFile.new()
    config.set_value("audio", "volume", volume)
    config.set_value("audio", "music", music)
    config.set_value("display", "fullscreen", fullscreen)
    config.save(PATH)


static func _is_fullscreen() -> bool:
    var mode := DisplayServer.window_get_mode()
    return mode == DisplayServer.WINDOW_MODE_FULLSCREEN or mode == DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN
