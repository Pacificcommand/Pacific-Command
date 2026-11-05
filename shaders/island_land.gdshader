// An island's land: beaches, palm groves, jungle, scrub, cane fields, rock and cliffs, airfields
// and towns, coloured from the baked map with fine noise for detail.
shader_type spatial;
render_mode cull_disabled, diffuse_lambert;
#include "island_common.gdshaderinc"

void vertex() {
	v_uv = island_vertex(VERTEX);
	v_world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec4 m = texture(map, v_uv);
	float dist = (m.r - 0.5) * 2.0 * sd;          // metres inland
	if (dist < 0.0) {
		discard;
	}
	vec2 w = v_world.xz;
	// the normal from the height map (smoother than the mesh's)
	float e = texel;
	float span = e * 2.0 * half * 2.0;
	float hl = ground(v_uv - vec2(e, 0.0));
	float hr = ground(v_uv + vec2(e, 0.0));
	float hu = ground(v_uv - vec2(0.0, e));
	float hd = ground(v_uv + vec2(0.0, e));
	vec3 nw = normalize(vec3(hl - hr, span, hu - hd));
	NORMAL = normalize((VIEW_MATRIX * vec4(nw, 0.0)).xyz);
	float h = ground(v_uv);
	float slope = 1.0 - nw.y;
	float veg = m.b;
	float clear = m.a;
	float n1 = fbm3(w * 0.012);
	float n2 = fbm3(w * 0.06);
	float n3 = vnoise(w * 0.35);

	// bare ground for this kind of island
	// (Iwo's beaches and terraces are black volcanic sand and grey ash)
	vec3 sand = kind == 3 ? vec3(0.16, 0.15, 0.14) : vec3(0.80, 0.74, 0.57);
	vec3 soil = kind == 3 ? vec3(0.24, 0.22, 0.20) : (kind == 1 ? vec3(0.60, 0.56, 0.46) : (kind == 0 ? vec3(0.74, 0.69, 0.55) : vec3(0.40, 0.33, 0.24)));
	vec3 rock = kind == 1 ? vec3(0.66, 0.64, 0.57) : (kind == 3 ? vec3(0.30, 0.27, 0.25) : vec3(0.38, 0.36, 0.33));
	vec3 col = mix(soil, sand, smoothstep(40.0, 8.0, dist) * 0.7);
	// vegetation by type
	vec3 g1, g2;
	if (vtype == 0) { g1 = vec3(0.22, 0.32, 0.12); g2 = vec3(0.14, 0.24, 0.09); }
	else if (vtype == 1) { g1 = vec3(0.07, 0.16, 0.06); g2 = vec3(0.13, 0.24, 0.09); }
	else if (vtype == 2) { g1 = vec3(0.32, 0.34, 0.20); g2 = vec3(0.22, 0.28, 0.15); }
	else { g1 = vec3(0.42, 0.54, 0.24); g2 = vec3(0.30, 0.44, 0.18); }
	// canopy: light and dark crowns at a few scales
	vec3 green = mix(g1, g2, smoothstep(0.3, 0.7, n2)) * (0.72 + 0.45 * n3) * (0.85 + 0.25 * vnoise(w * 0.9));
	if (vtype == 3) {
		// cane fields: a patchwork of plots of different sizes, turned a little, on the flats; scrub
		// and woods on the slopes and in the gullies
		float ang = 0.35 * (fbm3(w * 0.0008) - 0.5);
		vec2 q = vec2(cos(ang) * w.x - sin(ang) * w.y, sin(ang) * w.x + cos(ang) * w.y);
		vec2 sz = vec2(90.0, 60.0) * (0.8 + 0.6 * vnoise(floor(q / 400.0)));
		vec2 cell = floor(q / sz);
		float f = hash2(cell);
		vec3 field = mix(vec3(0.30, 0.40, 0.17), vec3(0.40, 0.44, 0.23), f);
		field = mix(field, vec3(0.44, 0.37, 0.26), step(0.86, f));      // ploughed
		vec2 fr = fract(q / sz);
		float edge = step(0.95, max(fr.x, fr.y));
		field = mix(field, vec3(0.26, 0.36, 0.18), edge * 0.7);
		vec3 wood = mix(vec3(0.20, 0.33, 0.15), vec3(0.28, 0.38, 0.19), n3);
		float woods = max(smoothstep(0.06, 0.16, slope), smoothstep(0.62, 0.72, n1));
		green = mix(field, wood, woods);
	}
	if (kind == 3) {
		// Iwo: patches of scrub and grass on the ash
		green = mix(vec3(0.30, 0.33, 0.22), vec3(0.38, 0.40, 0.26), n3);
	}
	float cover = smoothstep(0.15, 0.6, veg + (n2 - 0.5) * 0.35);
	col = mix(col, green, cover);
	// steep ground is rock (coral cliffs pale, volcanic dark), the highest peaks barer
	col = mix(col, rock, smoothstep(0.35, 0.6, slope) * (1.0 - cover * 0.5));
	col = mix(col, rock * 1.05, smoothstep(1100.0, 1900.0, h) * 0.5);
	// the beach: dry sand, wet sand at the water's edge
	col = mix(col, sand, smoothstep(14.0, 3.0, dist) * (kind == 1 ? 0.5 : 1.0));
	col = mix(col, sand * 0.78, smoothstep(3.0, 0.0, dist));
	// cleared ground: airfields (crushed coral or packed earth) and towns
	if (clear > 0.75) {
		vec3 strip = (kind == 0 || kind == 1) ? vec3(0.88, 0.86, 0.80) : vec3(0.60, 0.58, 0.52);
		strip *= 0.92 + 0.08 * n3;
		col = mix(col, strip, smoothstep(0.75, 0.95, clear));
	} else if (clear > 0.3) {
		vec2 lot = floor(w / 16.0);
		float r = hash2(lot);
		vec3 roof = r < 0.3 ? vec3(0.55, 0.30, 0.22) : (r < 0.6 ? vec3(0.50, 0.48, 0.45) : vec3(0.62, 0.55, 0.42));
		vec3 ground_c = vec3(0.58, 0.54, 0.46);
		float building = step(0.45, r) * step(0.2, fract(w.x / 16.0)) * step(0.2, fract(w.y / 16.0));
		col = mix(col, mix(ground_c, roof, building), smoothstep(0.3, 0.5, clear) * 0.9);
	}
	ALBEDO = col;
	ROUGHNESS = 0.95;
	SPECULAR = 0.15;
}
