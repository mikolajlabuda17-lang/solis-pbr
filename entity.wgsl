// ============================================================================
// Solis PBR — Entity & Block-Entity Stage (`[entity]`)
// ============================================================================

fn entity(input: EntityInput) -> Surface {
    let base_raw = input.albedo.rgb * input.tint.rgb;
    // Apply hurt / creeper / TNT flash in perceptual gamma space as vanilla expects
    const inv_gamma = vec3<f32>(1.0 / 2.2);
    const gamma_vec = vec3<f32>(2.2);
    let base_flashed = pow(
        mix(
            pow(max(base_raw, vec3<f32>(0.0)), inv_gamma),
            pow(max(input.overlay.rgb, vec3<f32>(0.0)), inv_gamma),
            saturate_f(input.overlay.a)
        ),
        gamma_vec
    );

    // Emissive eyes & full-bright layers (spider/enderman eyes, warden bioluminescence)
    if input.full_light && input.light.x > 0.96 && input.light.y > 0.96 {
        let glow_strength = select(1.85, 1.15, frame.dimension == 0 && frame.sun_direction.y > 0.1);
        let lit_full = apply_aerial_fog(base_flashed * input.shade * glow_strength, input.position);
        return Surface(vec4<f32>(lit_full, input.albedo.a * input.tint.a));
    }

    let dist = length(input.position);
    let view_dir = -input.position / max(dist, 1e-4);
    let n = normalize(input.normal);

    // Subtle rain sheen on outdoor mobs/players/chests
    let sky_vis = smoothstep(0.02, 0.95, input.light.y);
    let wet = select(0.0, frame.wetness * smoothstep(0.65, 0.92, input.light.y), rain_puddles && frame.dimension == 0 && frame.precipitation == 1u);
    let smoothness = mix(0.22, 0.68, wet);
    let roughness = max(sqr(1.0 - smoothness), 0.05);
    let f0 = vec3<f32>(0.04);

    var lit = vec3<f32>(0.0);

    if frame.dimension == 0 {
        let env = eval_environment();
        let shadow = eval_sun_shadow(input.position, n, input.screen, 0.25);

        // Soft wrap NdotL so voxel character models and chests retain pleasing 3D form
        let n_dot_l = saturate_f((dot(n, frame.light_direction) + 0.22) / 1.22);
        let spec = eval_ggx_specular(n, view_dir, frame.light_direction, roughness, f0);
        let direct = (base_flashed * n_dot_l + spec) * env.active_radiance * shadow * saturate_f(sky_vis * 1.15);

        let hemi_up = n.y * 0.5 + 0.5;
        let sky_hemi = mix(env.sky_horizon * 0.42, env.sky_zenith * 1.25 + env.sky_horizon * 0.42, hemi_up);
        let min_amb = vec3<f32>(0.018, 0.026, 0.046) * (1.0 + frame.brightness * 0.65 + frame.night_vision * 6.5);
        let ambient = base_flashed * max(sky_hemi, min_amb) * (sky_vis * sky_vis) * mix(1.0, input.shade, 0.45);

        let cave_lift = base_flashed * (0.005 + frame.brightness * 0.012 + frame.night_vision * 0.24);
        lit += direct + ambient + cave_lift;
    } else {
        lit += base_flashed * input.shade * input.lightmap;
    }

    // Colored Block Light & Held Dynamic Light
    let block_rad = eval_block_illumination(input.position, input.light.x, input.lightmap, input.colored_light);
    lit += base_flashed * block_rad * mix(1.0, input.shade, 0.35);

    let final_rgb = apply_aerial_fog(max(lit, vec3<f32>(0.0)), input.position);
    return Surface(vec4<f32>(final_rgb, input.albedo.a * input.tint.a));
}
