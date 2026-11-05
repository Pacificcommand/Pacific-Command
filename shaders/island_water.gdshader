// The water round an island: sand and coral showing through the shallows, turquoise lagoons and
// reef flats, the surf breaking on the reef edge and a line of foam along the shore. Fades out
// over deep water, where the open-sea shader shows.
shader_type spatial;
render_mode cull_disabled, blend_mix, depth_draw_never, specular_schlick_ggx;
#include "island_common.gdshaderinc"


void vertex() {
	v_uv = island_vertex(VERTEX);
	v_world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec4 m = texture(map, v_uv);
	float dist = (m.r - 0.5) * 2.0 * sd;          // metres off the shore (negative)
	if (dist > 0.0) {
		discard;
	}
	float depth = max(0.0, -ground(v_uv));
	vec2 w = v_world.xz;
	float n1 = fbm3(w * 0.02);
	float n2 = vnoise(w * 0.15 + vec2(TIME * 0.05, 0.0));
	// colour by depth: sand under a metre of water, coral heads, turquoise, then deep blue
	vec3 flat_c = vec3(0.36, 0.56, 0.52);
	vec3 reef_c = vec3(0.20, 0.48, 0.52);
	vec3 lag_c = vec3(0.10, 0.42, 0.52);
	vec3 deep_c = vec3(0.06, 0.30, 0.46);
	vec3 col = mix(flat_c, reef_c, smoothstep(0.4, 2.5, depth));
	col = mix(col, lag_c, smoothstep(2.5, 10.0, depth));
	col = mix(col, deep_c, smoothstep(10.0, 28.0, depth));
	// coral heads and sand patches on the reef flat
	col = mix(col, vec3(0.45, 0.62, 0.55), smoothstep(0.55, 0.75, n1) * (1.0 - smoothstep(1.0, 4.0, depth)) * 0.6);
	float a = (1.0 - smoothstep(8.0, 30.0, depth)) * mix(0.62, 0.85, smoothstep(0.5, 6.0, depth));
	if (lagoon_all) {
		a = max(a, 0.42);
		col = mix(col, vec3(0.10, 0.48, 0.58), 1.0 - smoothstep(0.0, 14.0, 34.0 - depth));
	}
	// surf where the reef drops off: a broken white band that comes and goes
	float edge = smoothstep(1.2, 2.4, depth) * (1.0 - smoothstep(2.4, 5.5, depth));
	float wave = sin(dist * 0.08 + TIME * 1.7 + n1 * 6.0) * 0.5 + 0.5;
	float surf = edge * smoothstep(0.35, 0.85, wave * 0.7 + n2 * 0.5);
	// and a thin line of foam on the beach
	float shore = smoothstep(-5.0, -0.5, dist) * (0.6 + 0.4 * n2);
	col = mix(col, vec3(0.88, 0.91, 0.92), clamp(surf * 0.6 + shore * 0.6, 0.0, 1.0));
	a = max(a, clamp(surf * 0.8 + shore * 0.7, 0.0, 1.0));
	// fade out before the edge of the map window, so the shallows never end in a hard line
	float ed = min(min(v_uv.x, 1.0 - v_uv.x), min(v_uv.y, 1.0 - v_uv.y));
	a *= smoothstep(0.0, 0.06, ed);
	if (a < 0.01) {
		discard;
	}
	ALBEDO = col;
	ALPHA = a;
	ROUGHNESS = 0.25;
	SPECULAR = 0.4;
}
