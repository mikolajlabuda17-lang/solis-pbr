// ============================================================================
// Solis PBR — Microfacet GGX BRDF, Soft PCF Colored Shadows & Block Lighting
// ============================================================================

// Trowbridge-Reitz GGX Normal Distribution Function
fn d_ggx(n_dot_h: f32, alpha: f32) -> f32 {
    let a2 = max(alpha * alpha, 1e-4);
    let d = (n_dot_h * a2 - n_dot_h) * n_dot_h + 1.0;
    return a2 / max(PI * d * d, 1e-6);
}

// Height-Correlated Smith GGX Visibility Term (G / (4 * NdotL * NdotV))
fn v_smith_ggx(n_dot_v: f32, n_dot_l: f32, alpha: f32) -> f32 {
    let a2 = max(alpha * alpha, 1e-4);
    let gv = n_dot_l * sqrt(n_dot_v * (n_dot_v - n_dot_v * a2) + a2);
    let gl = n_dot_v * sqrt(n_dot_l * (n_dot_l - n_dot_l * a2) + a2);
    return 0.5 / max(gv + gl, 1e-5);
}

// Schlick Fresnel Approximation
fn f_schlick(cos_theta: f32, f0: vec3<f32>) -> vec3<f32> {
    return f0 + (vec3<f32>(1.0) - f0) * pow5(saturate_f(1.0 - cos_theta));
}

// Roughness-attenuated Fresnel for ambient sky/environment reflections
fn f_schlick_roughness(cos_theta: f32, f0: vec3<f32>, roughness: f32) -> vec3<f32> {
    let max_refl = max(vec3<f32>(1.0 - roughness), f0);
    return f0 + (max_refl - f0) * pow5(saturate_f(1.0 - cos_theta));
}

// Evaluate Cook-Torrance GGX Specular lobe
fn eval_ggx_specular(
    n: vec3<f32>,
    v: vec3<f32>,
    l: vec3<f32>,
    roughness: f32,
    f0: vec3<f32>
) -> vec3<f32> {
    let n_dot_l = max(dot(n, l), 0.0);
    let n_dot_v = max(dot(n, v), 1e-3);
    if n_dot_l <= 0.0 || specular_strength <= 0.001 {
        return vec3<f32>(0.0);
    }
    let h = normalize(v + l);
    let n_dot_h = saturate_f(dot(n, h));
    let v_dot_h = saturate_f(dot(v, h));

    let alpha = max(roughness * roughness, 0.025);
    let d = min(d_ggx(n_dot_h, alpha), 36.0);
    let vis = v_smith_ggx(n_dot_v, n_dot_l, alpha);
    let f = f_schlick(v_dot_h, f0);

    return d * vis * f * n_dot_l * specular_strength;
}

// Soft Rotated Vogel-Disk PCF Shadow + Colored Stained Glass / Water Filtering
fn eval_sun_shadow(
    cam_pos: vec3<f32>,
    geom_normal: vec3<f32>,
    screen_uv: vec2<f32>,
    foliage_relax: f32
) -> vec3<f32> {
    if !shadows_enabled || frame.has_shadow == 0u || frame.dimension != 0 {
        return vec3<f32>(1.0);
    }

    let dist = length(cam_pos);
    let max_reach = max(frame.shadow_distance * 0.96, 16.0);
    let dist_fade = smoothstep(max_reach, max_reach * 0.78, dist);
    if dist_fade <= 0.001 {
        return vec3<f32>(1.0);
    }

    // Normal & slope offset bias scaled cleanly with shadow texel size and distance
    let cos_inc = saturate_f(dot(geom_normal, frame.light_direction));
    let texel_world = max(frame.shadow_center_texel, 0.035) * (1.0 + dist * 0.014);
    let normal_offset = texel_world * mix(2.1, 0.65, cos_inc) * mix(1.0, 1.45, foliage_relax);
    let light_offset = texel_world * 0.65;
    let biased_pos = cam_pos + geom_normal * normal_offset + frame.light_direction * light_offset;

    let sp = shadow_position(biased_pos);
    if sp.x <= 0.002 || sp.x >= 0.998 || sp.y <= 0.002 || sp.y >= 0.998 || sp.z <= 0.0 || sp.z >= 1.0 {
        return vec3<f32>(1.0);
    }

    let inv_res = 1.0 / max(frame.shadow_resolution, 512.0);
    let filter_radius = inv_res * (0.85 + shadow_softness * 1.15);
    let angle = interleaved_gradient_noise(screen_uv * frame.resolution) * TAU;

    var solid_sum = 0.0;
    // 6-tap rotated Vogel spiral PCF
    for (var i = 0u; i < 6u; i++) {
        let r = sqrt((f32(i) + 0.5) / 6.0) * filter_radius;
        let theta = f32(i) * GOLDEN_ANGLE + angle;
        let uv_off = vec2<f32>(cos(theta), sin(theta)) * r;
        solid_sum += textureSampleCompareLevel(shadow_map, shadow_sampler, sp.xy + uv_off, sp.z);
    }
    let solid_vis = solid_sum * (1.0 / 6.0);

    var shadow_rgb = vec3<f32>(solid_vis);

    // Translucent stained glass / ice / water tinting
    if colored_shadows && solid_vis > 0.01 {
        let trans_vis = textureSampleCompareLevel(shadow_map_translucent, shadow_sampler, sp.xy, sp.z);
        let covered = saturate_f(solid_vis - trans_vis);
        if covered > 0.01 {
            let dims = vec2<f32>(textureDimensions(shadow_color));
            let tc = clamp(vec2<i32>(sp.xy * dims), vec2<i32>(0), vec2<i32>(dims) - vec2<i32>(1));
            let sc = textureLoad(shadow_color, tc, 0);
            // sc.a == 1.0 marks water fluid; < 1.0 marks stained glass / ice
            let is_water_caster = sc.a > 0.995;
            let water_trans = vec3<f32>(0.42, 0.78, 0.88);
            let glass_trans = mix(vec3<f32>(1.0), sc.rgb * 1.18, saturate_f(sc.a * 1.15));
            let filter_tint = select(glass_trans, water_trans, is_water_caster);
            shadow_rgb = solid_vis * mix(vec3<f32>(1.0), filter_tint, covered);
        }
    }

    return mix(vec3<f32>(1.0), shadow_rgb, dist_fade);
}

// Physically-motivated Colored Block Light + Dynamic Held/Particle Lights
fn eval_block_illumination(
    cam_pos: vec3<f32>,
    block_level: f32,
    vanilla_lightmap: vec3<f32>,
    dynamic_colored: vec3<f32>
) -> vec3<f32> {
    // Nonlinear quadratic/cubic light falloff so torches have rich hot cores & soft tails
    let b = saturate_f(block_level);
    let physical_curve = (b * b * 0.68 + b * b * b * b * 0.52) * block_light_intensity;

    // Default warm incandescent 2400K candle/torch baseline blended with nearby [[lights]] sources
    let default_warm = vec3<f32>(1.28, 0.72, 0.30);
    let grid_tint = block_light_color(cam_pos);
    let source_col = mix(default_warm, grid_tint.rgb * 1.12, saturate_f(grid_tint.a * 1.35));

    // Preserve vanilla night-vision / dimension baseline in vanilla_lightmap when block_level is low
    var block_rad = source_col * physical_curve;

    // Add held torches, dropped glowing items & firefly/flame particle lights
    block_rad += dynamic_colored * 1.35 * block_light_intensity;

    // Ensure caves with Brightness slider / Night Vision remain playable
    let min_lift = vanilla_lightmap * (0.06 + frame.brightness * 0.08 + frame.night_vision * 0.55);
    return max(block_rad, min_lift * b);
}
