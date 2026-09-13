shader_type spatial;
render_mode cull_disabled, depth_draw_opaque, specular_schlick_ggx;

// Every field below is produced by a solver or by surface history.
// COLOR.r = node damage D, COLOR.g = tensile strain heat, COLOR.b = |lambda|
// as a fraction of node weight. The uniforms are the body-wide surface state.

uniform vec4 base_color : source_color = vec4(0.31, 0.32, 0.30, 1.0);
uniform vec4 substrate_color : source_color = vec4(0.34, 0.35, 0.33, 1.0);
uniform vec4 oxide_color : source_color = vec4(0.36, 0.17, 0.07, 1.0);
uniform vec4 crack_color : source_color = vec4(0.045, 0.020, 0.010, 1.0);
uniform vec4 heat_color : source_color = vec4(0.92, 0.18, 0.03, 1.0);
uniform vec4 film_color : source_color = vec4(0.06, 0.05, 0.04, 1.0);

uniform float metallic_base : hint_range(0.0, 1.0) = 0.42;
uniform float roughness_base : hint_range(0.0, 1.0) = 0.82;
uniform float exposure_level : hint_range(0.0, 1.0) = 0.0;
uniform float oxidation_level : hint_range(0.0, 1.0) = 0.0;
uniform float film_amount : hint_range(0.0, 1.0) = 0.0;
uniform float film_gloss : hint_range(0.0, 1.0) = 0.0;
uniform float thermal_emission : hint_range(0.0, 8.0) = 0.0;
uniform float crack_depth = 0.035;
uniform float shimmer_m = 0.0;
uniform vec3 impact_local = vec3(0.0);
uniform float impact_radius = 0.0;
uniform float impact_depth = 0.0;

varying vec4 v_solver;
varying float v_crater;
varying float v_wave;
varying float v_ao;

void vertex() {
	v_solver = COLOR;
	v_wave = clamp(COLOR.a, 0.0, 1.0);
	float d = clamp(COLOR.r, 0.0, 1.0);
	float crater = 0.0;
	if (impact_radius > 0.001) {
		float q = length(VERTEX - impact_local) / impact_radius;
		if (q < 1.0) {
			float x = 1.0 - q;
			crater = x * x * x * x * (1.0 + 4.0 * q);
		}
	}
	v_crater = crater;
	VERTEX += NORMAL * (shimmer_m - crack_depth * d * d - impact_depth * crater + v_wave * 0.012);

	vec3 world_n = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
	vec3 world_p = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	float hemi = mix(0.55, 1.0, clamp(world_n.y * 0.5 + 0.5, 0.0, 1.0));
	float height = mix(0.62, 1.0, smoothstep(0.02, 1.7, max(world_p.y, 0.0)));
	float underside = mix(0.58, 1.0, clamp(world_n.y + 0.18, 0.0, 1.0));
	v_ao = clamp(hemi * height * underside, 0.35, 1.0);
}

void fragment() {
	float d = clamp(v_solver.r, 0.0, 1.0);
	float heat = clamp(v_solver.g, 0.0, 1.0);
	float load = clamp(v_solver.b, 0.0, 1.0);
	float wave = clamp(v_wave, 0.0, 1.0);

	// Working steel goes bare, then dark oxide. Only the narrow band right
	// at a failing bond reads as an actual opening.
	float bare = clamp(exposure_level + smoothstep(0.05, 0.45, d) * 0.55, 0.0, 1.0);
	vec3 albedo = mix(base_color.rgb, substrate_color.rgb, bare);
	albedo = mix(
		albedo,
		oxide_color.rgb,
		clamp(oxidation_level + smoothstep(0.20, 0.80, d) * 0.85, 0.0, 1.0)
	);
	albedo = mix(albedo, crack_color.rgb, smoothstep(0.86, 1.0, d));
	albedo = mix(albedo, film_color.rgb, film_amount * 0.78);
	// Crease occlusion without depending on AO support on Compatibility.
	albedo *= 1.0 - 0.22 * d * d;
	albedo *= 1.0 - 0.16 * v_crater;
	albedo *= 1.0 + 0.22 * wave;

	float strain_glow = pow(heat, 4.0) * (0.35 + 0.65 * d);
	float wave_glow = pow(wave, 1.6) * 0.85;

	ALBEDO = albedo;
	METALLIC = clamp(
		mix(metallic_base, 0.52, exposure_level) * (1.0 - 0.74 * oxidation_level),
		0.0,
		1.0
	);
	ROUGHNESS = clamp(
		roughness_base + d * 0.22 + oxidation_level * 0.18 - load * 0.05 - film_gloss * 0.55 - wave * 0.12,
		0.05,
		0.99
	);
	EMISSION = heat_color.rgb * (strain_glow + thermal_emission + wave_glow);
	AO = v_ao;
	AO_LIGHT_AFFECT = 0.22;
}
