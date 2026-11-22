// ============================================================================
// Solis PBR — Post Pass 5 (Final Chain): FXAA, Bloom Upsample, Flare & Grade
// ============================================================================

// Perceptual luminance for FXAA edge detection (in sqrt/gamma perceptual space)
fn fxaa_luma(c: vec3<f32>) -> f32 {
    return sqrt(max(luma(c), 0.0));
}

// Spatial FXAA 3.11-inspired edge filter on `previous`
fn sample_fxaa(uv: vec2<f32>) -> vec3<f32> {
    let c_m = textureSampleLevel(previous, linear_sampler, uv, 0.0).rgb;
    if !fxaa_enabled {
        return c_m;
    }

    let inv_res = 1.0 / max(frame.resolution, vec2<f32>(1.0));
    let c_n = textureSampleLevel(previous, linear_sampler, uv + vec2<f32>( 0.0, -inv_res.y), 0.0).rgb;
    let c_s = textureSampleLevel(previous, linear_sampler, uv + vec2<f32>( 0.0,  inv_res.y), 0.0).rgb;
    let c_w = textureSampleLevel(previous, linear_sampler, uv + vec2<f32>(-inv_res.x,  0.0), 0.0).rgb;
    let c_e = textureSampleLevel(previous, linear_sampler, uv + vec2<f32>( inv_res.x,  0.0), 0.0).rgb;

    let l_m = fxaa_luma(c_m);
    let l_n = fxaa_luma(c_n);
    let l_s = fxaa_luma(c_s);
    let l_w = fxaa_luma(c_w);
    let l_e = fxaa_luma(c_e);

    let l_min = min(l_m, min(min(l_n, l_s), min(l_w, l_e)));
    let l_max = max(l_m, max(max(l_n, l_s), max(l_w, l_e)));
    let range = l_max - l_min;

    // Early exit on flat regions
    if range < max(0.0312, l_max * 0.125) {
        return c_m;
    }

    let c_nw = textureSampleLevel(previous, linear_sampler, uv + vec2<f32>(-inv_res.x, -inv_res.y), 0.0).rgb;
    let c_ne = textureSampleLevel(previous, linear_sampler, uv + vec2<f32>( inv_res.x, -inv_res.y), 0.0).rgb;
    let c_sw = textureSampleLevel(previous, linear_sampler, uv + vec2<f32>(-inv_res.x,  inv_res.y), 0.0).rgb;
    let c_se = textureSampleLevel(previous, linear_sampler, uv + vec2<f32>( inv_res.x,  inv_res.y), 0.0).rgb;

    let l_nw = fxaa_luma(c_nw);
    let l_ne = fxaa_luma(c_ne);
    let l_sw = fxaa_luma(c_sw);
    let l_se = fxaa_luma(c_se);

    var dir = vec2<f32>(
        -((l_nw + l_ne) - (l_sw + l_se)),
         ((l_nw + l_sw) - (l_ne + l_se))
    );

    let dir_reduce = max((l_nw + l_ne + l_sw + l_se) * (0.25 * 0.25), 1e-5);
    let rcp_min = 1.0 / (min(abs(dir.x), abs(dir.y)) + dir_reduce);
    dir = clamp(dir * rcp_min, vec2<f32>(-6.0), vec2<f32>(6.0)) * inv_res;

    let rgb_a = 0.5 * (
        textureSampleLevel(previous, linear_sampler, uv + dir * (1.0 / 3.0 - 0.5), 0.0).rgb +
        textureSampleLevel(previous, linear_sampler, uv + dir * (2.0 / 3.0 - 0.5), 0.0).rgb
    );
    let rgb_b = rgb_a * 0.5 + 0.25 * (
        textureSampleLevel(previous, linear_sampler, uv + dir * -0.5, 0.0).rgb +
        textureSampleLevel(previous, linear_sampler, uv + dir *  0.5, 0.0).rgb
    );

    let l_b = fxaa_luma(rgb_b);
    if l_b < l_min || l_b > l_max {
        return rgb_a;
    }
    return rgb_b;
}

// Wide 9-tap tent upsample of `bloom_quarter`
fn sample_bloom_tent(uv: vec2<f32>) -> vec3<f32> {
    if !bloom_enabled || bloom_strength <= 0.005 {
        return vec3<f32>(0.0);
    }
    let r = 5.5 / max(frame.resolution, vec2<f32>(1.0));
    var b = textureSampleLevel(bloom_quarter, linear_sampler, uv, 0.0).rgb * 0.25;
    b += textureSampleLevel(bloom_quarter, linear_sampler, uv + vec2<f32>( r.x,  0.0), 0.0).rgb * 0.125;
    b += textureSampleLevel(bloom_quarter, linear_sampler, uv + vec2<f32>(-r.x,  0.0), 0.0).rgb * 0.125;
    b += textureSampleLevel(bloom_quarter, linear_sampler, uv + vec2<f32>( 0.0,  r.y), 0.0).rgb * 0.125;
    b += textureSampleLevel(bloom_quarter, linear_sampler, uv + vec2<f32>( 0.0, -r.y), 0.0).rgb * 0.125;
    b += textureSampleLevel(bloom_quarter, linear_sampler, uv + vec2<f32>( r.x,  r.y), 0.0).rgb * 0.0625;
    b += textureSampleLevel(bloom_quarter, linear_sampler, uv + vec2<f32>(-r.x,  r.y), 0.0).rgb * 0.0625;
    b += textureSampleLevel(bloom_quarter, linear_sampler, uv + vec2<f32>( r.x, -r.y), 0.0).rgb * 0.0625;
    b += textureSampleLevel(bloom_quarter, linear_sampler, uv + vec2<f32>(-r.x, -r.y), 0.0).rgb * 0.0625;
    return b * bloom_strength;
}

// Subtle Optical Sun Lens Ghosts & Anamorphic Streak
fn eval_sun_lens_flare(uv: vec2<f32>) -> vec3<f32> {
    if !sun_flare || frame.dimension != 0 || frame.sun_direction.y <= 0.01 || frame.rain > 0.75 {
        return vec3<f32>(0.0);
    }

    let clip_s = frame.projection * frame.view * vec4<f32>(frame.sun_direction * 128.0, 1.0);
    if clip_s.w <= 0.05 {
        return vec3<f32>(0.0);
    }
    let ndc_s = clip_s.xy / clip_s.w;
    if abs(ndc_s.x) > 1.05 || abs(ndc_s.y) > 1.05 {
        return vec3<f32>(0.0);
    }

    let sun_uv = vec2<f32>(ndc_s.x * 0.5 + 0.5, 0.5 - ndc_s.y * 0.5);
    // Check sun visibility in depth buffer (5-point cross check)
    let px = 0.006;
    var sun_vis = select(0.0, 0.4, depth_at(sun_uv) == 0.0);
    sun_vis += select(0.0, 0.15, depth_at(clamp(sun_uv + vec2<f32>( px, 0.0), vec2<f32>(0.0), vec2<f32>(1.0))) == 0.0);
    sun_vis += select(0.0, 0.15, depth_at(clamp(sun_uv + vec2<f32>(-px, 0.0), vec2<f32>(0.0), vec2<f32>(1.0))) == 0.0);
    sun_vis += select(0.0, 0.15, depth_at(clamp(sun_uv + vec2<f32>(0.0,  px), vec2<f32>(0.0), vec2<f32>(1.0))) == 0.0);
    sun_vis += select(0.0, 0.15, depth_at(clamp(sun_uv + vec2<f32>(0.0, -px), vec2<f32>(0.0), vec2<f32>(1.0))) == 0.0);

    if sun_vis <= 0.01 {
        return vec3<f32>(0.0);
    }

    let aspect = frame.resolution.x / max(frame.resolution.y, 1.0);
    let to_center = vec2<f32>(0.5) - sun_uv;
    let ghost1_uv = sun_uv + to_center * 0.65;
    let ghost2_uv = sun_uv + to_center * 1.35;
    let ghost3_uv = sun_uv + to_center * 1.85;

    let d1 = length((uv - ghost1_uv) * vec2<f32>(aspect, 1.0));
    let d2 = length((uv - ghost2_uv) * vec2<f32>(aspect, 1.0));
    let d3 = length((uv - ghost3_uv) * vec2<f32>(aspect, 1.0));

    let ecl = eval_solar_eclipse();
    let g1_col = mix(vec3<f32>(1.0, 0.65, 0.32), vec3<f32>(0.62, 0.78, 1.12), ecl.totality);
    let g3_col = mix(vec3<f32>(1.0, 0.45, 0.65), vec3<f32>(0.85, 0.52, 0.95), ecl.totality);
    let streak_col = mix(vec3<f32>(1.0, 0.80, 0.55), vec3<f32>(0.76, 0.88, 1.18), ecl.totality);

    let g1 = smoothstep(0.09, 0.01, d1) * smoothstep(0.0, 0.03, d1) * g1_col;
    let g2 = smoothstep(0.14, 0.02, d2) * smoothstep(0.03, 0.08, d2) * vec3<f32>(0.35, 0.78, 1.0);
    let g3 = smoothstep(0.06, 0.0, d3) * g3_col;

    // Subtle horizontal anamorphic streak around sun (enhanced silver coronal streak at totality!)
    let streak_dx = abs(uv.x - sun_uv.x) * aspect;
    let streak_dy = abs(uv.y - sun_uv.y);
    let streak = exp(-streak_dx * mix(6.5, 4.2, ecl.totality)) * exp(-streak_dy * 85.0) * streak_col;

    let border_fade = 1.0 - smoothstep(0.55, 1.02, max(abs(ndc_s.x), abs(ndc_s.y)));
    let weather_fade = (1.0 - frame.rain * 0.9) * smoothstep(0.0, 0.18, frame.sun_direction.y);
    let flare_gain = mix(1.0, 1.35, ecl.totality + ecl.diamond_ring * 0.8);

    return (g1 * 0.065 + g2 * 0.045 + g3 * 0.055 + streak * 0.08 * flare_gain) * sun_vis * border_fade * weather_fade;
}

fn post(input: PostInput) -> vec4<f32> {
    // 1. Spatial FXAA anti-aliasing over HDR scene
    var hdr = sample_fxaa(input.uv);

    // 2. Add HDR Bloom + Subtle Optical Sun Flare
    hdr += sample_bloom_tent(input.uv);
    hdr += eval_sun_lens_flare(input.uv);

    // 3. Smooth Eye Adaptation (driven by Horizon's 2s-smoothed eye_light_smooth + solar eclipse) + Manual EV
    let ecl_adapt = eval_solar_eclipse();
    let sun_adapt = smoothstep(-0.12, 0.25, frame.sun_direction.y) * (1.0 - ecl_adapt.obscuration * 0.88);
    let env_light = max(frame.eye_light_smooth.y * sun_adapt, frame.eye_light_smooth.x * 0.75);
    // Gently boost dark caves/nights and gently tame noon glare
    let auto_ev = mix(0.42, -0.14, env_light) * auto_exposure;
    let exposure_gain = exp2(exposure + auto_ev);
    hdr *= exposure_gain;

    // 4. Mid-tone Contrast (log-domain pivot around 18% middle grey = 0.18)
    let grey = 0.18;
    let safe_hdr = max(hdr, vec3<f32>(1e-6));
    hdr = grey * pow(safe_hdr / grey, vec3<f32>(contrast));

    // 5. Intelligent Vibrance & Global Saturation (in linear Rec.709 luminance)
    let y = luma(hdr);
    let max_ch = max(hdr.r, max(hdr.g, hdr.b));
    let min_ch = min(hdr.r, min(hdr.g, hdr.b));
    let cur_sat = (max_ch - min_ch) / max(max_ch, 1e-4);
    let vib_boost = 1.0 + vibrance * (1.0 - cur_sat);
    hdr = mix(vec3<f32>(y), hdr, saturation * vib_boost);

    // 6. Natural Optical Cos^4 Vignette
    if vignette_strength > 0.005 {
        let centered = (input.uv - vec2<f32>(0.5)) * vec2<f32>(1.15, 1.0);
        let r2 = dot(centered, centered);
        let vig = mix(1.0, 1.0 / (1.0 + r2 * 1.45), vignette_strength);
        hdr *= vig;
    }

    return vec4<f32>(max(hdr, vec3<f32>(0.0)), 1.0);
}
