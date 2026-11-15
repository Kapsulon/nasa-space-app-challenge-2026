class_name TerminalLabel extends RichTextLabel
## A RichTextLabel that behaves like a terminal. Queue output with
## print_text() (fast, machine output, short pause per line) or type_text()
## (human typing speed with jitter), and it plays it back in order.
## skip() reveals everything instantly.

signal output_done

## Characters per second for printed (machine) output.
@export var print_cps: float = 400.0
## Characters per second for typed (human) input.
@export var type_cps: float = 18.0
## Pause at the end of each printed line.
@export var line_pause: float = 0.03
## Show a blinking block cursor after the text.
@export var show_cursor: bool = true
## Oldest lines are dropped beyond this many (0 = keep everything). Keep each
## line's BBCode tags closed on that line when using it.
@export var max_lines: int = 0

const CURSOR := "█"

var _queue: Array[Dictionary] = []
var _current: Dictionary = {}
var _target: int = 0
var _progress: float = 0.0
var _wait: float = 0.0
var _busy: bool = false
## The content without the cursor.
var _content: String = ""
var _cursor_time: float = 0.0
var _cursor_on: bool = false


func _ready() -> void:
    bbcode_enabled = true


func is_busy() -> bool:
    return _busy


func clear_terminal() -> void:
    _queue.clear()
    _current = {}
    _busy = false
    _wait = 0.0
    _content = ""
    _progress = 0.0
    _target = 0
    _set_text("", false)
    visible_characters = 0


## Machine output: appears fast, line by line.
func print_text(bbcode: String, pause_after: float = 0.0) -> void:
    _enqueue(bbcode, false, pause_after)


## Human input: typed character by character at a natural, uneven speed.
func type_text(bbcode: String, pause_after: float = 0.25) -> void:
    _enqueue(bbcode, true, pause_after)


func wait(seconds: float) -> void:
    _enqueue("", false, seconds)


## Runs `callback` once everything queued before it has been shown.
func then(callback: Callable) -> void:
    _queue.append({"text": "", "human": false, "pause": 0.0, "callback": callback})
    _busy = true


## Reveal everything that is queued right away.
func skip() -> void:
    if not _busy:
        return
    var callbacks: Array[Callable] = []
    for segment in _queue:
        _content += segment["text"]
        if segment.has("callback"):
            callbacks.append(segment["callback"])
    _queue.clear()
    for callback in callbacks:
        callback.call()
    _current = {}
    _wait = 0.0
    _complete()


func _enqueue(bbcode: String, human: bool, pause_after: float) -> void:
    _queue.append({"text": bbcode, "human": human, "pause": pause_after})
    _busy = true


func _complete() -> void:
    _busy = false
    _set_text(_content, _cursor_on)
    visible_characters = -1
    output_done.emit()


func _process(delta: float) -> void:
    if show_cursor:
        _cursor_time += delta
        var on := fmod(_cursor_time, 1.0) < 0.5
        if on != _cursor_on and not _busy:
            _cursor_on = on
            _set_text(_content, _cursor_on)

    if not _busy:
        return
    if _wait > 0.0:
        _wait -= delta
        return

    if _current.is_empty():
        if _queue.is_empty():
            _complete()
            return
        _current = _queue.pop_front()
        if _current.has("callback"):
            var callback: Callable = _current["callback"]
            _current = {}
            callback.call()
            return
        _trim()
        # Work out how much is already on screen (-1 means "everything").
        _cursor_on = false
        _set_text(_content, false)
        var shown := visible_characters if visible_characters >= 0 else get_parsed_text().length()
        _content += _current["text"]
        _set_text(_content, false)
        visible_characters = shown
        _target = get_parsed_text().length()
        _progress = float(shown)
        return

    var human: bool = _current["human"]
    var cps := type_cps * randf_range(0.35, 1.8) if human else print_cps
    var before := int(_progress)
    _progress = minf(_progress + cps * delta, float(_target))
    var next := int(_progress)
    if not human:
        var line_end := get_parsed_text().find("\n", before)
        if line_end != -1 and line_end < next:
            next = line_end + 1
            _progress = float(next)
            _wait = line_pause
    visible_characters = next
    if next >= _target:
        _wait = _current["pause"]
        _current = {}


func _trim() -> void:
    if max_lines <= 0:
        return
    var lines := _content.split("\n")
    if lines.size() <= max_lines:
        return
    _content = "\n".join(lines.slice(lines.size() - max_lines))
    _set_text(_content, false)
    visible_characters = -1


func _set_text(content: String, with_cursor: bool) -> void:
    var shown := visible_characters
    text = content + (CURSOR if with_cursor else "")
    visible_characters = shown
