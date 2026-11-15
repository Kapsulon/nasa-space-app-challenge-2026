shader_type canvas_item;

// Shows the texture centered at its own aspect ratio inside a stretched
// TextureRect (stretch_mode = Scale), and fills the leftover bands by
// repeating the texture's edge pixels outwards.

void fragment() {
    // UV spans 0..1 over the whole rect, so its screen derivatives give the rect's shape.
    float rect_aspect = abs(dFdy(UV.y) / dFdx(UV.x));
    float tex_aspect = TEXTURE_PIXEL_SIZE.y / TEXTURE_PIXEL_SIZE.x;
    vec2 scale = vec2(max(rect_aspect / tex_aspect, 1.0), max(tex_aspect / rect_aspect, 1.0));
    vec2 uv = (UV - 0.5) * scale + 0.5;
    uv = clamp(uv, TEXTURE_PIXEL_SIZE * 0.5, 1.0 - TEXTURE_PIXEL_SIZE * 0.5);
    COLOR = texture(TEXTURE, uv);
}
