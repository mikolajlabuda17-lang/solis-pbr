// ============================================================================
// Solis PBR — Post Pass 2 (`shafts_quarter`, 0.25x): 3D Volumetric Light Shafts
// ============================================================================

fn post(input: PostInput) -> vec4<f32> {
    if !godrays_enabled || godrays_strength <= 0.01 || frame.dimension != 0 {
        return vec4<f32>(0.0);
    }

    let env = eval_environment();
    let d = depth_at(input.uv);

    // Reconstruct world-space view ray & maximum march distance
    let p_near = view_position(input.uv, 0.5);
    let p_far = view_position(input.uv, 0.01);
    let ray_dir = normalize(p_far - p_near);
    let max_march = 56.0;
    let geom_dist = select(max_march, min(length(view_position(input.uv, d)), max_march), d > 0.0);

    let cos_l = dot(ray_dir, frame.light_direction);
    let in_water = frame.eye_in == 1u || frame.in_water > 0.01;

    // Aerosol Mie forward-scattering phase (strongest looking near the light, subtle sideways)
    let g_mie = select(0.66, 0.58, in_water);
    let phase = dual_hg_phase(cos_l, g_mie, -0.15, 0.88);

    // Outdoor camera exposure guard so sealed deep caves don't get spurious haze when shadows are off
    let outdoor_gate = smoothstep(0.05, 0.55, frame.eye_light_smooth.y);
    let jitter = interleaved_gradient_noise(input.pixel);

    var accum_vis = 0.0;

    if frame.has_shadow == 1u && shadows_enabled {
        // True 3D Volumetric Raymarch through Horizon's Shadow Map!
        let steps = 12u;
        let dt = geom_dist / f32(steps);

        for (var i = 0u; i < 12u; i++) {
            let t = (f32(i) + jitter) * dt;
            let sample_pos = ray_dir * t;
            let sp = shadow_position(sample_pos);

            var lit = 0.0;
            if sp.x > 0.002 && sp.x < 0.998 && sp.y > 0.002 && sp.y < 0.998 && sp.z > 0.0 && sp.z < 1.0 {
                lit = textureSampleCompareLevel(shadow_map, shadow_sampler, sp.xy, sp.z);
            } else {
                lit = outdoor_gate;
            }

            // Underwater volumetric caustic modulation along the shaft!
            if in_water && lit > 0.01 {
                let wp = sample_pos + frame.camera_position;
                let c_uv = (wp.xz - frame.light_direction.xz * wp.y) * 0.08 + vec2<f32>(frame.time * 0.03, frame.time * 0.02);
                let caust = sample_noise(c_uv).b;
                lit *= 0.45 + 1.65 * caust;
            }

            // Exponential atmospheric extinction along ray
            let weight = exp(-t * 0.024);
            accum_vis += lit * weight;
        }
        accum_vis = (accum_vis / 12.0) * min(geom_dist / 24.0, 1.35);
    } else {
        // Fast fallback when shadow map is disabled: Screen-Space Radial Occlusion toward Light
        let clip_l = frame.projection * frame.view * vec4<f32>(frame.light_direction * 128.0, 1.0);
        if clip_l.w <= 0.01 {
            return vec4<f32>(0.0);
        }
        let ndc_l = clip_l.xy / clip_l.w;
        let light_uv = vec2<f32>(ndc_l.x * 0.5 + 0.5, 0.5 - ndc_l.y * 0.5);
        let delta = (light_uv - input.uv) / 10.0;

        var occ = 0.0;
        for (var j = 0u; j < 10u; j++) {
            let suv = input.uv + delta * (f32(j) + jitter);
            if suv.x >= 0.0 && suv.x <= 1.0 && suv.y >= 0.0 && suv.y <= 1.0 {
                let sd = depth_at(suv);
                occ += select(0.0, 1.0, sd == 0.0);
            }
        }
        accum_vis = (occ / 10.0) * outdoor_gate * smoothstep(0.0, 0.45, cos_l);
    }

    let medium_tint = select(
        mix(vec3<f32>(1.0, 0.94, 0.86), vec3<f32>(0.78, 0.88, 1.15), env.eclipse_totality)
            * (0.085 + frame.rain * 0.075 + env.twilight_factor * 0.065 + env.eclipse_totality * 0.22),
        vec3<f32>(0.16, 0.58, 0.72) * 0.28,
        in_water
    );

    let shaft_rgb = env.active_radiance * medium_tint * phase * accum_vis * godrays_strength;
    return vec4<f32>(max(shaft_rgb, vec3<f32>(0.0)), 1.0);
}
