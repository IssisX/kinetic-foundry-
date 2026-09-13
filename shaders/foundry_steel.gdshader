shader_type spatial;
render_mode cull_disabled;

uniform vec3 base_color : source_color = vec3(0.24, 0.25, 0.23);
uniform vec3 bare_steel : source_color = vec3(0.34, 0.35, 0.33);
uniform vec3 heat_color : source_color = vec3(0.72, 0.12, 0.015);
uniform float intact_roughness = 0.86;
uniform float exposed_roughness = 0.54;
uniform float intact_metallic = 0.34;
uniform float exposed_metallic = 0.82;

varying vec4 solver_state;

void vertex() {
    solver_state = COLOR;
}

void fragment() {
    float damage = clamp(solver_state.r, 0.0, 1.0);
    float heat = clamp(solver_state.g, 0.0, 1.0);
    float load = clamp(solver_state.b, 0.0, 1.0);
    float exposure = smoothstep(0.12, 0.92, damage);
    float thermal = smoothstep(0.34, 0.96, heat);
    float stress_polish = smoothstep(0.25, 1.0, load) * 0.10;

    vec3 surface = mix(base_color, bare_steel, exposure);
    surface = mix(surface, heat_color, thermal * (0.16 + 0.34 * damage));

    ALBEDO = surface;
    ROUGHNESS = clamp(
        mix(intact_roughness, exposed_roughness, exposure) - stress_polish,
        0.18,
        1.0
    );
    METALLIC = mix(intact_metallic, exposed_metallic, exposure);
    EMISSION = heat_color * pow(heat, 3.0) * (0.18 + 0.42 * damage);
}
