// ============================================================================
// Solis PBR — Gerstner Water Waves, Refraction, Beer-Lambert, Foam & Caustics
// ============================================================================

// Animated expanding raindrop ripple normal perturbation (for water & puddles)
fn eval_rain_ripples(world_xz: vec2<f32>, strength: f32) -> vec2<f32> {
    if strength <= 0.01 {
        return vec2<f32>(0.0);
    }
    var grad = vec2<f32>(0.0);
    let t = frame.time * 2.6;
    for (var i = 0u; i < 2u; i++) {
        let scale = select(1.35, 2.15, i == 1u);
        let uv = world_xz * scale + vec2<f32>(f32(i) * 13.7, f32(i) * 7.3);
        let cell = floor(uv);
        let f = fract(uv) - vec2<f32>(0.5);
        let rnd = hash21(cell);
        let center = (vec2<f32>(rnd, fract(rnd * 31.7)) - vec2<f32>(0.5)) * 0.45;
        let d_vec = f - center;
        let d = length(d_vec) + 1e-4;
        let life = fract(t * 0.55 + rnd * 6.13);
        let radius = life * 0.48;
        let ring = sin((d - radius) * 38.0) * exp(-abs(d - radius) * 18.0) * (1.0 - life);
        grad += (d_vec / d) * ring;
    }
    return grad * strength * 0.35;
}

// Multi-directional Gerstner / Trochoidal Wave Normal in World Space
fn eval_water_normal(world_pos: vec3<f32>, geom_normal: vec3<f32>) -> vec3<f32> {
    let is_waterfall = abs(geom_normal.y) < 0.55;
    let t = frame.time;

    if is_waterfall {
        // Sliding vertical glassy streaks on waterfalls
        let flow_uv = vec2<f32>((world_pos.x + world_pos.z) * 0.35, world_pos.y * 0.22 + t * 0.55);
        let n1 = sample_noise(flow_uv).rg - vec2<f32>(0.5);
        let n2 = sample_noise(flow_uv * 2.3 - vec2<f32>(0.0, t * 0.35)).rg - vec2<f32>(0.5);
        let pert = (n1 * 0.65 + n2 * 0.35) * 0.32 * water_wave_height;
        return normalize(geom_normal + vec3<f32>(pert.x, pert.y * 0.35, pert.x));
    }

    let storm_boost = 1.0 + frame.rain * 0.45 + frame.thunder * 0.45;
    let amp = 0.065 * water_wave_height * storm_boost;
    let xz = world_pos.xz;

    // 4 non-collinear gravity-capillary wave trains
    const d0 = vec2<f32>(0.86, 0.51);
    const d1 = vec2<f32>(0.38, -0.92);
    const d2 = vec2<f32>(-0.74, 0.67);
    const d3 = vec2<f32>(-0.24, -0.97);

    let p0 = dot(xz, d0) * 1.45 + t * 1.65;
    let p1 = dot(xz, d1) * 2.65 + t * 2.25;
    let p2 = dot(xz, d2) * 4.80 - t * 2.90;
    let p3 = dot(xz, d3) * 8.40 + t * 3.60;

    var slope = d0 * cos(p0) * 1.00
              + d1 * cos(p1) * 0.62
              + d2 * cos(p2) * 0.34
              + d3 * cos(p3) * 0.18;

    // Fine capillary texture detail
    let cap1 = sample_noise(xz * 0.085 + vec2<f32>(t * 0.018, t * 0.011)).rg - vec2<f32>(0.5);
    let cap2 = sample_noise(xz * 0.230 - vec2<f32>(t * 0.024, -t * 0.016)).rg - vec2<f32>(0.5);
    slope += (cap1 + cap2 * 0.6) * 2.2;

    var grad_xz = slope * amp;

    // Raindrop rings on water surface
    if frame.rain > 0.01 && rain_puddles {
        grad_xz += eval_rain_ripples(xz, frame.rain);
    }

    return normalize(vec3<f32>(-grad_xz.x, 1.0, -grad_xz.y));
}

// Dual-layer animated Voronoi optical caustics projected along light direction
fn eval_underwater_caustics(world_pos: vec3<f32>, light_dir: vec3<f32>, water_depth: f32) -> vec3<f32> {
    if caustics_strength <= 0.01 || water_depth <= 0.02 {
        return vec3<f32>(0.0);
    }
    let proj_xz = world_pos.xz - light_dir.xz * (world_pos.y / max(abs(light_dir.y), 0.25));
    let t = frame.time * 0.032;

    let uv1 = proj_xz * 0.095 + vec2<f32>(t, t * 0.65);
    let uv2 = proj_xz * 0.125 - vec2<f32>(t * 0.78, -t * 0.52);

    // Slight RGB dispersion offset for realistic refractive caustics
    let c1_r = sample_noise(uv1 + vec2<f32>(0.004, 0.0)).b;
    let c1_g = sample_noise(uv1).b;
    let c1_b = sample_noise(uv1 - vec2<f32>(0.004, 0.0)).b;
    let c2 = sample_noise(uv2).b;

    let pattern = pow(max(vec3<f32>(c1_r, c1_g, c1_b) * c2, vec3<f32>(0.0)), vec3<f32>(1.65)) * 4.2;
    let depth_atten = smoothstep(0.02, 0.65, water_depth) * exp(-water_depth * 0.075);
    return pattern * depth_atten * caustics_strength;
}

// Reconstruct linear view distance from reversed clip depth `d` at `screen_uv`
fn linear_view_dist_at(screen_uv: vec2<f32>, rev_depth: f32) -> f32 {
    let ndc = vec4<f32>(screen_uv.x * 2.0 - 1.0, 1.0 - screen_uv.y * 2.0, rev_depth, 1.0);
    let view_h = frame.projection_inverse * ndc;
    let view_pos = view_h.xyz / max(abs(view_h.w), 1e-6);
    return length(view_pos);
}

// Full Physically-Based Water Shading (Refraction + Beer-Lambert + Caustics + Foam + Planar/Sky Reflection)
fn shade_water_surface(
    cam_pos: vec3<f32>,
    geom_normal: vec3<f32>,
    screen_uv: vec2<f32>,
    biome_tint: vec3<f32>,
    sky_light: f32,
    block_light: f32,
    lightmap_col: vec3<f32>,
    dynamic_col: vec3<f32>
) -> vec4<f32> {
    let world_pos = cam_pos + frame.camera_position;
    let view_dist = length(cam_pos);
    let v = -cam_pos / max(view_dist, 1e-4);
    let n = eval_water_normal(world_pos, geom_normal);
    let env = eval_environment();

    // Shadowing on the water surface itself (sun glint & surface scatter)
    let sun_shadow = eval_sun_shadow(cam_pos, geom_normal, screen_uv, 0.0);
    let sky_exposure = smoothstep(0.05, 0.92, sky_light);

    // Measure water depth behind this fragment from opaque_depth
    let res = frame.resolution;
    let base_px = clamp(vec2<i32>(screen_uv * res), vec2<i32>(0), vec2<i32>(res) - vec2<i32>(1));
    let bg_rev_depth = textureLoad(opaque_depth, base_px, 0);
    let bg_dist_unrefracted = select(frame.far, linear_view_dist_at(screen_uv, bg_rev_depth), bg_rev_depth > 0.0);
    var water_thickness = max(bg_dist_unrefracted - view_dist, 0.0);

    // Wave-driven screen-space refraction offset, clamped if target pixel lies in front of water!
    let refr_scale = 0.032 * water_refraction / max(1.0 + view_dist * 0.065, 1.0);
    let refr_offset = (n.xz - geom_normal.xz) * refr_scale * min(water_thickness, 3.0);
    let refr_uv = clamp(screen_uv + refr_offset, vec2<f32>(0.001), vec2<f32>(0.999));
    let refr_px = clamp(vec2<i32>(refr_uv * res), vec2<i32>(0), vec2<i32>(res) - vec2<i32>(1));
    let refr_depth = textureLoad(opaque_depth, refr_px, 0);
    let refr_dist = select(frame.far, linear_view_dist_at(refr_uv, refr_depth), refr_depth > 0.0);

    let use_refr = refr_dist > view_dist - 0.05;
    let final_px = select(base_px, refr_px, use_refr);
    if use_refr {
        water_thickness = max(refr_dist - view_dist, 0.0);
    }
    let seabed_rgb = textureLoad(opaque_color, final_px, 0).rgb;

    // Beer-Lambert spectral absorption (red attenuates fastest, turquoise-blue slowest)
    let clarity = max(water_clarity, 0.25);
    let tint_norm = mix(vec3<f32>(1.0), biome_tint / max(luma(biome_tint), 0.15), 0.35);
    let sigma_abs = vec3<f32>(0.42, 0.115, 0.058) / (clarity * max(tint_norm, vec3<f32>(0.35)));
    let transmittance = exp(-sigma_abs * min(water_thickness, 48.0));

    // Underwater caustics added onto the refracted seabed before absorption!
    var lit_seabed = seabed_rgb;
    if bg_rev_depth > 0.0 && water_thickness < 28.0 {
        let seabed_world = world_pos - v * water_thickness;
        let caust = eval_underwater_caustics(seabed_world, frame.light_direction, water_thickness);
        lit_seabed += seabed_rgb * caust * env.active_radiance * sun_shadow * sky_exposure * 0.55;
    }

    // Multiple-scattering water volume color (shallows turquoise glow + deep ocean navy)
    let block_rad = eval_block_illumination(cam_pos, block_light, lightmap_col, dynamic_col);
    let vol_light = env.active_radiance * (0.14 + 0.18 * sun_shadow) * sky_exposure
                  + env.sky_zenith * 0.55 * sky_exposure
                  + block_rad * 0.45;
    let water_scatter_albedo = vec3<f32>(0.045, 0.28, 0.34) * tint_norm;
    let inscatter = water_scatter_albedo * vol_light * (vec3<f32>(1.0) - transmittance);

    var underwater_col = lit_seabed * transmittance + inscatter;

    // Soft Shore Foam where water meets blocks in shallow areas
    if shore_foam && abs(geom_normal.y) > 0.7 && water_thickness > 0.005 && water_thickness < 0.58 {
        let foam_n = sample_noise(world_pos.xz * 0.42 + vec2<f32>(frame.time * 0.02, -frame.time * 0.015));
        let edge_band = 1.0 - smoothstep(0.04, 0.55, water_thickness);
        let foam_mask = smoothstep(0.32, 0.72, edge_band + (foam_n.r - 0.45) * 0.45) * edge_band;
        let foam_light = env.active_radiance * sun_shadow * 0.28 + env.sky_horizon * 0.55 + block_rad * 0.5;
        underwater_col = mix(underwater_col, foam_light * 0.85, saturate_f(foam_mask * 0.72));
    }

    // Dielectric Fresnel (IOR 1.333 -> F0 = 0.02)
    let n_dot_v = saturate_f(dot(n, v));
    let fresnel = 0.02 + 0.98 * pow5(1.0 - n_dot_v);

    // Reflection: Horizon planar water mirror (`reflection`) + Physical Sky fallback
    let refl_dir = reflect(-v, n);
    var refl_col = eval_physical_sky(vec3<f32>(refl_dir.x, abs(refl_dir.y), refl_dir.z), true) * sky_exposure;

    if water_reflections && frame.has_reflection == 1u && abs(geom_normal.y) > 0.75 {
        let on_mirror_plane = smoothstep(2.2, 0.45, abs(world_pos.y - frame.water_plane));
        let mirror_distort = (n.xz - geom_normal.xz) * 0.045;
        let mirror_uv = clamp(screen_uv + mirror_distort, vec2<f32>(0.002), vec2<f32>(0.998));
        let mirror_sample = textureSampleLevel(reflection, reflection_sampler, mirror_uv, 0.0);
        let edge_guard = smoothstep(0.0, 0.06, mirror_uv.x) * smoothstep(1.0, 0.94, mirror_uv.x)
                       * smoothstep(0.0, 0.06, mirror_uv.y) * smoothstep(1.0, 0.94, mirror_uv.y);
        // Horizon's planar mirror holds solid terrain over sky; blend smoothly on the active water plane
        let mirror_weight = saturate_f(mirror_sample.a) * edge_guard * on_mirror_plane * 0.88;
        refl_col = mix(refl_col, mirror_sample.rgb, mirror_weight);
    }

    // Crisp GGX Solar & Lunar Sun-Glint Path on ripples
    let glint = eval_ggx_specular(n, v, frame.light_direction, 0.055, vec3<f32>(0.025))
              * env.active_radiance * sun_shadow * sky_exposure;

    // Combine underwater refracted radiance + Fresnel reflection + solar glint
    let refl_Factor = select(fresnel * 0.35, fresnel, frame.eye_in == 0u);
    var final_water = mix(underwater_col, refl_col, refl_Factor) + glint;
    final_water = apply_aerial_fog(final_water, cam_pos);

    // When opaque_color is valid (post chain active), return full composite at alpha 0.99;
    // if user disabled refraction, allow smooth optical blending
    let has_refr_buf = luma(seabed_rgb) > 1e-6 || bg_rev_depth == 0.0;
    let alpha_out = select(
        clamp(0.28 + fresnel * 0.70 + (1.0 - luma(transmittance)) * 0.55, 0.25, 0.96),
        0.99,
        has_refr_buf && water_refraction > 0.01
    );

    return vec4<f32>(max(final_water, vec3<f32>(0.0)), alpha_out);
}
