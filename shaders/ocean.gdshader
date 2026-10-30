// Open sea seen from above: layered moving ripples, swell, color by weather, sun glitter.
shader_type spatial;
render_mode cull_disabled;

uniform vec3 deep_color : source_color = vec3(0.03, 0.2, 0.36);
uniform vec3 shallow_color : source_color = vec3(0.1, 0.42, 0.58);
uniform float chop = 0.9;          // how rough the surface is
uniform float spec = 0.45;         // strength of sun reflections
uniform float time_s = 0.0;        // battle time (stops when paused)
uniform vec2 wind_dir = vec2(-0.78, 0.62);
// textures from the Boujie water shader (MIT license, see assets/textures/boujie/LICENSE.md)
uniform sampler2D foam_tex : source_color, filter_linear_mipmap, repeat_enable;
uniform sampler2D detail_tex : source_color, filter_linear_mipmap, repeat_enable;

varying vec3 world_pos;

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
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
// height field: long swell plus wind ripples at several scales
float lod(float px, float f) { return 1.0 - smoothstep(0.15, 0.7, px * f); }
float height(vec2 p, float t, float px) {
	vec2 w = wind_dir;
	float hgt = 0.0;
	hgt += sin(dot(p, w) * 0.045 + t * 0.9) * 0.3 * lod(px, 0.045);
	hgt += sin(dot(p, vec2(w.y, -w.x)) * 0.031 - t * 0.7) * 0.2 * lod(px, 0.031);
	hgt += (noise(p * 0.08 + w * t * 0.12) - 0.5) * 1.4 * chop * lod(px, 0.08);
	hgt += (noise(p * 0.22 - w.yx * t * 0.25) - 0.5) * 0.7 * chop * lod(px, 0.22);
	hgt += (noise(p * 0.65 + w * t * 0.5) - 0.5) * 0.18 * chop * lod(px, 0.65);
	return hgt;
}

void fragment() {
	vec2 p = world_pos.xz;
	float t = time_s;
	float px = length(fwidth(p));
	float e = max(0.6, px);
	float h0 = height(p, t, px);
	float hx = height(p + vec2(e, 0.0), t, px);
	float hz = height(p + vec2(0.0, e), t, px);
	vec3 n = normalize(vec3(h0 - hx, e * 1.6, h0 - hz));
	// world normal -> view space
	NORMAL = normalize((VIEW_MATRIX * vec4(n, 0.0)).xyz);
	// large slow patches of lighter and darker water give the sea variety
	float patch = noise(p * 0.0018 + t * 0.002) * 0.6 + noise(p * 0.006 - t * 0.004) * 0.4;
	float crest = clamp(h0 * 0.35 + 0.5, 0.0, 1.0);
	vec3 col = mix(deep_color, shallow_color, clamp(patch * 0.55 + crest * 0.35, 0.0, 1.0));
	// faint whitecaps when the sea is rough
	// fine color detail from a real water texture, drifting with the wind
	vec3 det = texture(detail_tex, p / 70.0 + wind_dir * t * 0.004).rgb;
	col *= mix(1.0, 0.8 + 0.4 * dot(det, vec3(0.2, 0.3, 0.5)), lod(px, 0.02));
	// whitecaps: patches of the whitewater texture where crests are high and the sea is rough
	float capmask = smoothstep(0.78, 0.98, noise(p * 0.05 + t * 0.03) * 0.55 + crest * 0.5) * clamp(chop - 0.55, 0.0, 1.0);
	float wf = texture(foam_tex, p / 26.0 - wind_dir * t * 0.02).r;
	float cap = smoothstep(0.6, 0.95, wf) * capmask * lod(px, 0.1);
	col = mix(col, vec3(0.86, 0.9, 0.92), cap * 0.6);
	ALBEDO = col;
	ROUGHNESS = mix(0.18, 0.45, smoothstep(0.5, 6.0, px));
	SPECULAR = spec;
	METALLIC = 0.0;
}
