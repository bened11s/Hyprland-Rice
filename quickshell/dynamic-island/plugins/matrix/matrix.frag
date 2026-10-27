#version 440
// Matrix-Regen. Ein Raster aus Zellen; je Spalte faellt ein "Kopf" mit
// Schweif nach unten, Tempo/Laenge/Startpunkt per Hash je Spalte. Die Zeichen
// wechseln in jeder Zelle zufaellig mit der Zeit. Die Glyphen kommen aus
// einem Atlas (eine Reihe, `glyphs` Zellen), weiss auf transparent.
layout(location = 0) in vec2 qt_TexCoord0;
layout(location = 0) out vec4 fragColor;

layout(std140, binding = 0) uniform buf {
    mat4 qt_Matrix;
    float qt_Opacity;
    float time;
    float cols;
    float rows;
    float glyphs;
    float speed;
    float density;
    vec4 headColor;
    vec4 trailColor;
};

layout(binding = 1) uniform sampler2D atlas;

float hash(vec2 p) {
    return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

// Helligkeit einer Zelle durch einen Tropfen (lane = 0/1: zwei je Spalte)
float drop(float col, float row, float lane, out float headness) {
    float r1 = hash(vec2(col, 3.0 + lane * 17.0));
    float r2 = hash(vec2(col, 11.0 + lane * 29.0));
    float v = speed * (0.55 + r1 * 0.9);              // Zellen je Sekunde
    float len = rows * (0.25 + r2 * 0.45);            // Schweiflaenge in Zellen
    float period = rows + len + rows * (0.1 + r1 * 0.6);    // Pause zwischen Durchgaengen
    float t = time * v + r2 * period * 3.0;
    float cycle = floor(t / period);
    // Dichte: manche Durchgaenge bleiben dunkel
    if (hash(vec2(col + lane * 101.0, cycle)) > density) {
        headness = 0.0;
        return 0.0;
    }
    float headPos = mod(t, period);
    float d = headPos - row;                          // Zellen hinter dem Kopf
    headness = step(0.0, d) * step(d, 1.0);
    if (d < 0.0 || d > len)
        return 0.0;
    float f = 1.0 - d / len;
    return pow(f, 1.25);
}

void main() {
    vec2 grid = vec2(cols, rows);
    vec2 cell = floor(qt_TexCoord0 * grid);
    vec2 local = fract(qt_TexCoord0 * grid);

    float h1, h2;
    float b1 = drop(cell.x, cell.y, 0.0, h1);
    float b2 = drop(cell.x, cell.y, 1.0, h2);
    float bright = max(b1, b2);
    float head = max(h1 * step(0.001, b1), h2 * step(0.001, b2));

    // Zeichen der Zelle, wechselt unregelmaessig
    float rate = 0.6 + hash(cell) * 3.0;
    float g = floor(hash(cell + floor(time * rate) * 0.37) * glyphs);
    vec2 uv = vec2((g + local.x) / glyphs, local.y);
    float a = texture(atlas, uv).a;

    vec4 c = mix(trailColor, headColor, head);
    float alpha = a * bright * c.a;
    fragColor = vec4(c.rgb * alpha, alpha) * qt_Opacity;
}
