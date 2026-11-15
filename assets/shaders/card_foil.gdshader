shader_type canvas_item;
render_mode blend_add;

// Holographic foil laid over a Mythic card: a slow rainbow sheen plus a
// bright glare band that sweeps across the card now and then.

/// Card frame, used to keep the foil off the frame's transparent corners.
uniform sampler2D frame : filter_nearest;
/// Picture window of the card (left, top, right, bottom in 0..1), which is
/// transparent in the frame but still gets the foil.
uniform vec4 window = vec4(0.082, 0.112, 0.909, 0.577);
uniform float rainbow_strength : hint_range(0.0, 1.0) = 0.16;
uniform float glare_strength : hint_range(0.0, 1.0) = 0.35;
/// Seconds between two glare sweeps.
uniform float glare_period : hint_range(0.5, 10.0) = 3.5;
/// Size of the foil's chunky pixels, in cells across the card.
uniform float cells : hint_range(16.0, 400.0) = 110.0;

vec3 hue(float h) {
    return clamp(abs(fract(h + vec3(0.0, 2.0 / 3.0, 1.0 / 3.0)) * 6.0 - 3.0) - 1.0, 0.0, 1.0);
}

void fragment() {
    // Snap to big pixels so the foil matches the pixel art.
    vec2 uv = (floor(UV * vec2(cells, cells / 0.71)) + 0.5) / vec2(cells, cells / 0.71);
    float diag = uv.x * 0.71 + uv.y;

    // Rainbow bands drifting along the diagonal, with a little wobble.
    float wobble = sin(uv.y * 9.0 + TIME * 0.8) * 0.05 + sin(uv.x * 13.0 - TIME * 0.6) * 0.04;
    vec3 rainbow = hue(diag * 1.3 + wobble - TIME * 0.12);
    float bands = 0.6 + 0.4 * sin(diag * 22.0 + TIME * 1.5);

    // Glare: a narrow bright band crossing the card, then a pause.
    float sweep = fract(TIME / glare_period) * 3.2 - 0.6;
    float glare = smoothstep(0.16, 0.0, abs(diag - sweep));

    float in_window = step(window.x, UV.x) * step(UV.x, window.z) * step(window.y, UV.y) * step(UV.y, window.w);
    float mask = max(texture(frame, UV).a, in_window);

    vec3 color = rainbow * bands * rainbow_strength + (0.5 + 0.5 * rainbow) * glare * glare_strength;
    COLOR = vec4(color * mask, 1.0);
}
