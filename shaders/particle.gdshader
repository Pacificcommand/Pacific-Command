// Flat particle sprites for a top-down camera: foam, oil, smoke, splashes, debris, fire, flashes, tracers.
// INSTANCE_CUSTOM.x = sprite shape, INSTANCE_CUSTOM.y = random seed, COLOR = tint and alpha.
shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never, blend_mix;

uniform float lit = 1.0;          // overall light level (dimmer at night)
uniform bool additive = false;    // fire and flashes glow
uniform float glow_boost = 3.0;
// Kenney smoke pack atlas (CC0): rows = white puff, black smoke, explosion, flash; 4 variants each
uniform sampler2D atlas : source_color, filter_linear_mipmap;
// Boujie water shader whitewater texture (MIT)
uniform sampler2D foam_tex : source_color, filter_linear_mipmap, repeat_enable;

varying float shape;
varying float seed;

void vertex() {
	shape = INSTANCE_CUSTOM.x;
	seed = INSTANCE_CUSTOM.y;
}

float hash(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}
float noise(vec2 p) {
	vec2 i = floor(p), f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1, 0)), u.x), mix(hash(i + vec2(0, 1)), hash(i + vec2(1, 1)), u.x), u.y);
}

vec4 cell(float row, vec2 uv) {
	float c = mod(floor(seed * 2.7), 4.0);
	return texture(atlas, (uv + vec2(c, row)) / 4.0);
}

void fragment() {
	vec2 p = UV * 2.0 - 1.0;
	float d = length(p);
	vec3 col = COLOR.rgb;
	float a = 0.0;
	if (shape < 0.5) {            // 0: smoke puff (Kenney white puff, tinted)
		vec4 t = cell(0.0, UV);
		a = t.a;
		col *= mix(0.75, 1.0, t.r);
	} else if (shape < 1.5) {     // 1: foam: whitewater texture inside a soft round mask
		float f = texture(foam_tex, UV * 0.55 + vec2(seed * 0.37, seed * 0.71)).r;
		a = smoothstep(1.0, 0.3, d) * smoothstep(0.45, 0.85, f + (1.0 - d) * 0.2);
	} else if (shape < 2.5) {     // 2: muzzle flash / star shell (Kenney flash)
		vec4 t = cell(3.0, UV);
		a = t.a;
		col *= t.rgb;
	} else if (shape < 3.5) {     // 3: tracer streak along local x
		a = smoothstep(1.0, 0.0, abs(p.y) * 3.0 + abs(p.x) * 0.6);
	} else if (shape < 4.5) {     // 4: debris chip
		a = step(max(abs(p.x), abs(p.y)), 0.8);
	} else {                      // 5: fire and explosion (Kenney explosion)
		vec4 t = cell(2.0, UV);
		a = t.a;
		col = t.rgb * mix(vec3(1.0), COLOR.rgb, 0.3);
	}
	if (additive) {
		ALBEDO = col * glow_boost;
	} else {
		ALBEDO = col * lit;
	}
	ALPHA = clamp(a * COLOR.a, 0.0, 1.0);
}
