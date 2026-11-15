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
## The content without the cursor. The cursor glyph always sits at the end
## of `text`; blinking only changes `visible_characters`, so the text is never
## re-parsed and the scroll position doesn't jump.
var _content: String = ""
var _cursor_time: float = 0.0
var _cursor_on: bool = false


func _ready() -> void:
    bbcode_enabled = true
    # Lay out the whole text, hidden characters included, so revealing
    # characters (or blinking the cursor) never reflows the lines.
    visible_characters_behavior = TextServer.VC_CHARS_AFTER_SHAPING
    _set_text(_content)
    visible_characters = 0


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
    _set_text("")
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
    _set_text(_content)
    _complete()


func _enqueue(bbcode: String, human: bool, pause_after: float) -> void:
    _queue.append({"text": bbcode, "human": human, "pause": pause_after})
    _busy = true


func _complete() -> void:
    _busy = false
    _show_all()
    output_done.emit()


## Characters of the content, without the cursor.
func _content_length() -> int:
    return get_parsed_text().length() - (1 if show_cursor else 0)


## Everything visible, plus the cursor when it is in its "on" phase.
func _show_all() -> void:
    visible_characters = _content_length() + (1 if show_cursor and _cursor_on else 0)


func _process(delta: float) -> void:
    if show_cursor:
        _cursor_time += delta
        var on := fmod(_cursor_time, 1.0) < 0.5
        if on != _cursor_on and not _busy:
            _cursor_on = on
            _show_all()

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
        # Work out how much is already on screen (-1 means "everything"),
        # without the cursor, which stays hidden while text comes in.
        _cursor_on = false
        var length := _content_length()
        var shown := length if visible_characters < 0 else mini(visible_characters, length)
        _content += _current["text"]
        _set_text(_content)
        visible_characters = shown
        _target = _content_length()
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
    _set_text(_content)
    visible_characters = _content_length()


func _set_text(content: String) -> void:
    var shown := visible_characters
    text = content + (CURSOR if show_cursor else "")
    visible_characters = shown
