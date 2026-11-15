shader_type canvas_item;

// CRT overlay for a full-screen ColorRect: dark scanlines plus a cinema
// vignette that darkens the corners. Draws nothing else, so put it above the
// picture and below the text.

// Scanline period in viewport pixels (half of it is dark).
uniform float scanline_spacing = 4.0;
uniform float scanline_alpha = 0.32;
// Distance from the center (0 = center, 1 = corner) where the vignette starts.
uniform float vignette_start = 0.55;
uniform vec4 vignette_color : source_color = vec4(0.008, 0.024, 0.09, 0.85);
// Viewport height the scanlines are measured against.
uniform float viewport_height = 1080.0;

void fragment() {
	float y = SCREEN_UV.y * viewport_height;
	float scan = mod(y, scanline_spacing) >= scanline_spacing * 0.5 ? scanline_alpha : 0.0;

	vec2 aspect = vec2(16.0 / 9.0, 1.0);
	float dist = length((UV - 0.5) * aspect) / length(0.5 * aspect);
	float vig = clamp((dist - vignette_start) / (1.0 - vignette_start), 0.0, 1.0) * vignette_color.a;

	float alpha = 1.0 - (1.0 - vig) * (1.0 - scan);
	vec3 rgb = vignette_color.rgb * vig * (1.0 - scan) / max(alpha, 0.0001);
	COLOR = vec4(rgb, alpha);
}
