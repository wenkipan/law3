shader_type canvas_item;
uniform float progress : hint_range(0.0, 1.0) = 0.0;
uniform bool blueprint = false;
uniform float atlas_rows = 1.0;
void fragment() {
    vec4 tex = texture(TEXTURE, UV);
    bool filled = fract(UV.y * atlas_rows) >= 1.0 - progress;
    if (filled == blueprint) { tex.a = 0.0; }
    COLOR *= tex;
}
