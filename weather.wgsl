// ============================================================================
// Solis PBR — Weather Stage (`[weather]`): Physical Rain & Snow Lighting
// ============================================================================

fn weather(input: WeatherInput) -> vec4<f32> {
    let env = eval_environment();
    let dist = length(input.position);
    let sky_vis = smoothstep(0.0, 0.95, input.light.y);

    // Ambient sky + forward-scattered sun/moon light through precipitation
    let view_dir = input.position / max(dist, 1e-4);
    let cos_l = dot(view_dir, frame.light_direction);
    let phase = 0.65 + 1.85 * hg_phase(cos_l, 0.58);

    let sky_rad = (env.sky_horizon * 0.75 + env.active_radiance * 0.24 * phase) * sky_vis
                + vec3<f32>(0.014, 0.020, 0.036) * (1.0 + frame.night_vision * 4.0);

    // Warm torch / lantern illumination on nearby rain & snow streaks
    let b = saturate_f(input.light.x);
    let torch_rad = vec3<f32>(1.25, 0.72, 0.32) * (b * b) * block_light_intensity * 0.85;

    let total_irr = sky_rad + torch_rad;

    if input.snow {
        // Soft high-albedo snow crystals
        let snow_rgb = apply_aerial_fog(input.color.rgb * total_irr * 1.15, input.position);
        let dist_fade = 1.0 - smoothstep(28.0, 56.0, dist);
        return vec4<f32>(snow_rgb, input.color.a * 0.82 * dist_fade);
    }

    // Translucent refractive rain streaks (subtle silver-blue sheen, never distracting white bars)
    let rain_tint = mix(vec3<f32>(0.72, 0.82, 0.95), vec3<f32>(1.0), 0.35);
    let rain_rgb = apply_aerial_fog(input.color.rgb * rain_tint * total_irr * 0.95, input.position);
    let near_soft = smoothstep(0.6, 2.2, dist) * (1.0 - smoothstep(24.0, 48.0, dist));
    let rain_alpha = input.color.a * 0.34 * near_soft;

    return vec4<f32>(rain_rgb, rain_alpha);
}
