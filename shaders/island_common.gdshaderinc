// Shared by the island land and water shaders. The map (see tools/island_builder/bake.py):
// R signed distance to the coast (0.5 = shore), G height (log encoded), B vegetation, A cleared ground.
uniform sampler2D map : filter_linear, repeat_disable;
uniform sampler2D hmap : filter_linear, repeat_disable;    // heights in metres (16-bit source)
uniform float half = 5000.0;       // half the window, metres
uniform float texel = 0.0009765625;
uniform int kind = 2;               // 0 atoll, 1 raised coral, 2 volcanic, 3 volcanic ash (Iwo)
uniform int vtype = 1;              // 0 palm groves, 1 jungle, 2 scrub, 3 cane fields
uniform float sd = 200.0;           // metres across the R channel
uniform bool lagoon_all = false;    // the whole window is a lagoon (Truk)

varying vec2 v_uv;
varying vec3 v_world;

float dec_h(float g) {
	float e = g * 255.0;
	return e >= 64.0 ? 2.0 * (exp((e - 64.0) / 191.0 * log(1501.0)) - 1.0)
	                 : -2.0 * (exp((64.0 - e) / 64.0 * log(41.0)) - 1.0);
}

float hash2(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}
float vnoise(vec2 p) {
	vec2 i = floor(p), f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash2(i), hash2(i + vec2(1, 0)), u.x), mix(hash2(i + vec2(0, 1)), hash2(i + vec2(1, 1)), u.x), u.y);
}
float fbm3(vec2 p) {
	return vnoise(p) * 0.55 + vnoise(p * 2.03 + 7.1) * 0.3 + vnoise(p * 4.1 + 3.3) * 0.15;
}

// the ground height at a map uv
float ground(vec2 uv) {
	return texture(hmap, uv).r;
}

// where a mesh vertex goes: the land stands on the map's height; the shallows lie just above the
// (opaque) sea plane. Returns the map uv (the caller stores it in v_uv).
vec2 island_vertex(inout vec3 vtx) {
	vec2 uv = vtx.xz / (2.0 * half) + 0.5;
	float h = ground(uv);
	vtx.y = h > 0.0 ? h : 0.06 + h * 0.0006;
	return uv;
}
