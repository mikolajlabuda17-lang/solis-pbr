// ============================================================================
// Solis PBR — Post Pass 1 (`atmo_half` Kept 0.5x): 3D Cumulus Clouds & SSAO
// ============================================================================
// Stored in `atmo_half` (`rgba16float`, `keep = "view"`):
// - Sky pixels (`depth == 0.0`): `vec4(cloud_premult_rgb, cloud_alpha)` with `r >= 0.0`
// - Geometry pixels (`depth > 0.0`): `vec4(-1.0, 0.0, 0.0, ssao)` (`r < 0.0` sentinel prevents cloud ghosting!)

const CLOUD_BASE_Y: f32 = 192.0;
const CLOUD_TOP_Y: f32  = 284.0;

// Smooth, isotropic 3D Cumulus Cloud Density (Macro weather + Perlin-Worley body + soft billow erosion)
fn sample_cloud_density(world_p: vec3<f32>, coverage: f32, h: f32) -> f32 {
    if h <= 0.001 || h >= 0.999 {
        return 0.0;
    }

    // Classic cumulus vertical profile: crisp condensed flat base, rounded billowing crown
    let base_round = smoothstep(0.0, 0.16, h);
    let top_round  = smoothstep(1.0, 0.42, h);
    let height_profile = base_round * top_round;

    let wind = vec2<f32>(frame.time * 0.90, frame.time * 0.36);
    // Subtle altitude anvil lean without high-frequency vertical UV shearing
    let xz = world_p.xz + wind + vec2<f32>(h * 10.0, h * 4.0);

    // Macro weather scale (~1850-block formations) + cumulus cells (~620-block & ~280-block)
    let macro_w = sample_noise(xz * 0.00054 + vec2<f32>(0.17, 0.43)).r;
    let shape_a = sample_noise(xz * 0.00162).r;
    let shape_b = sample_noise(xz * 0.00355 - wind * 0.0005 + vec2<f32>(0.37, 0.61)).g;

    let weather_local = saturate_f(coverage * (0.68 + 0.64 * macro_w));
    let raw_shape = (shape_a * 0.66 + shape_b * 0.34) * height_profile;

    let thresh = saturate_f(1.0 - weather_local * 1.12);
    var base_dens = smoothstep(thresh, thresh + 0.34, raw_shape);
    if base_dens <= 0.001 {
        return 0.0;
    }

    // Smooth 3D billow erosion (gentle height offset `h * 0.19` avoids diagonal/vertical banding!)
    let detail_a = sample_noise(xz * 0.0078 + vec2<f32>(h * 0.19, -h * 0.14)).g;
    let detail_b = sample_noise(xz * 0.0155 - vec2<f32>(h * 0.11, h * 0.17)).r;
    let billow = detail_a * 0.65 + detail_b * 0.35;

    let erode_weight = 0.24 * (1.0 - base_dens * 0.68) * mix(0.55, 1.0, h);
    return saturate_f((base_dens - billow * erode_weight) * 1.38);
}

// Bilinear sky-only fetch from `atmo_half_previous`; returns valid=false if any tap hit geometry last frame
fn sample_previous_cloud(prev_uv: vec2<f32>) -> vec4<f32> {
    let dims_i = vec2<i32>(textureDimensions(atmo_half_previous));
    let dims_f = vec2<f32>(dims_i);
    let coord = prev_uv * dims_f - vec2<f32>(0.5);
    let base = vec2<i32>(floor(coord));
    let f = fract(coord);

    var accum = vec4<f32>(0.0);
    for (var dy = 0; dy <= 1; dy++) {
        for (var dx = 0; dx <= 1; dx++) {
            let tc = clamp(base + vec2<i32>(dx, dy), vec2<i32>(0), dims_i - vec2<i32>(1));
            let s = textureLoad(atmo_half_previous, tc, 0);
            if s.r < -0.25 {
                // Sentinel: this texel belonged to foreground terrain/foliage on the previous frame!
                return vec4<f32>(-1.0, 0.0, 0.0, 0.0);
            }
            let wx = select(1.0 - f.x, f.x, dx == 1);
            let wy = select(1.0 - f.y, f.y, dy == 1);
            accum += s * (wx * wy);
        }
    }
    return accum;
}

fn eval_volumetric_clouds(ray_dir: vec3<f32>, pixel: vec2<f32>) -> vec4<f32> {
    if !volumetric_clouds || frame.dimension != 0 {
        return vec4<f32>(0.0);
    }

    let cam_y = frame.camera_position.y;
    let below_slab = cam_y < CLOUD_BASE_Y;
    let above_slab = cam_y > CLOUD_TOP_Y;

    if below_slab && ray_dir.y <= 0.006 {
        return vec4<f32>(0.0);
    }
    if above_slab && ray_dir.y >= -0.006 {
        return vec4<f32>(0.0);
    }

    // Gentle planetary curvature foreshortening near horizon prevents infinite flat-slab stretching & shelf cutoffs
    let abs_dy = abs(ray_dir.y);
    let curved_dy = abs_dy + 0.042 * (1.0 - saturate_f(abs_dy * 2.5));
    let signed_dy = select(-curved_dy, curved_dy, ray_dir.y >= 0.0);

    let t0 = (CLOUD_BASE_Y - cam_y) / signed_dy;
    let t1 = (CLOUD_TOP_Y - cam_y) / signed_dy;
    let t_enter = max(min(t0, t1), 0.0);
    let t_exit  = min(max(t0, t1), t_enter + 920.0);

    if t_enter > 3800.0 || t_exit <= t_enter + 1.0 {
        return vec4<f32>(0.0);
    }

    let env = eval_environment();
    let cos_sun_c = dot(ray_dir, frame.sun_direction);
    // Natural eclipse pocket clearing directly around the eclipsed sun so clouds frame the corona without hiding it!
    let eclipse_window_clear = mix(1.0, smoothstep(0.994, 0.945, cos_sun_c), env.eclipse_obscuration * 0.90);
    let coverage_eff = clamp(mix(cloud_coverage, 0.84, env.overcast) * eclipse_window_clear, 0.0, 0.92);
    if coverage_eff <= 0.02 {
        return vec4<f32>(0.0);
    }

    let step_count = select(select(10u, 16u, cloud_quality == 1u), 24u, cloud_quality >= 2u);
    let march_len = t_exit - t_enter;
    let dt = march_len / f32(step_count);

    // Mild sub-step temporal jitter (damped near low horizon angles so distant clouds never streak!)
    let jitter_scale = mix(0.28, 0.72, smoothstep(0.05, 0.35, abs_dy));
    let jitter = (interleaved_gradient_noise(pixel) - 0.5) * jitter_scale + 0.5;

    let cos_l = dot(ray_dir, frame.light_direction);
    let phase = 0.52 + 1.75 * dual_hg_phase(cos_l, 0.65, -0.26, 0.72);

    // Physical multi-scattering sky ambient: luminous sky-blue by day, subtle dark slate by night
    let night_dim = mix(1.0, 0.42, env.night_factor);
    let amb_top = (env.sky_zenith * 1.25 + env.sky_horizon * 0.72) * night_dim;
    let amb_bot = (env.sky_horizon * 0.48 + env.sky_zenith * 0.22) * night_dim
                + vec3<f32>(0.42, 0.16, 0.06) * env.twilight_factor * 0.25;
    let direct_col = env.active_radiance * phase * 1.12;

    var transmittance = 1.0;
    var scattered = vec3<f32>(0.0);
    var weighted_t = 0.0;
    var weight_sum = 0.0;

    let slab_inv = 1.0 / (CLOUD_TOP_Y - CLOUD_BASE_Y);

    for (var i = 0u; i < 24u; i++) {
        if i >= step_count || transmittance < 0.015 {
            break;
        }
        let t = t_enter + (f32(i) + jitter) * dt;
        // Match vertical height `h` to our curved atmospheric shell so every ray sweeps h in [0..1] cleanly!
        let shell_y = cam_y + signed_dy * t;
        let h = saturate_f((shell_y - CLOUD_BASE_Y) * slab_inv);
        let world_p = vec3<f32>(
            frame.camera_position.x + ray_dir.x * t,
            shell_y,
            frame.camera_position.z + ray_dir.z * t
        );

        let dens = sample_cloud_density(world_p, coverage_eff, h);
        if dens > 0.002 {
            // Directional light self-shadow tap toward sun/moon
            let shadow_p = world_p + frame.light_direction * 18.0;
            let shadow_h = saturate_f((shadow_p.y - CLOUD_BASE_Y) * slab_inv);
            let d_light = sample_cloud_density(shadow_p, coverage_eff, shadow_h) * 1.65 + (1.0 - h) * 0.32;

            // Dual-octave Beer-Powder multi-scattering approximation (Schneider / Horizon Zero Dawn)
            let beer_primary = exp(-d_light * 1.35);
            let beer_ms      = exp(-d_light * 0.38) * 0.42;
            let powder       = 1.0 - exp(-dens * 3.40);
            let sun_atten    = max(beer_primary, beer_ms) * mix(1.0, 1.55 * powder, saturate_f(-cos_l * 0.5 + 0.5));

            let local_amb = mix(amb_bot, amb_top, h) * (0.58 + 0.42 * exp(-dens * 1.1));
            let step_rad = direct_col * sun_atten + local_amb;

            let sigma_t = dens * 0.052;
            let step_trans = exp(-sigma_t * dt);
            let integral = 1.0 - step_trans;
            let contrib_w = transmittance * integral;

            scattered += contrib_w * step_rad;
            weighted_t += contrib_w * t;
            weight_sum += contrib_w;
            transmittance *= step_trans;
        }
    }

    let raw_alpha = saturate_f(1.0 - transmittance);
    let rep_t = select(0.5 * (t_enter + t_exit), weighted_t / max(weight_sum, 1e-4), weight_sum > 1e-3);

    // Smooth aerial perspective blend into the distant horizon sky
    let horizon_fade = smoothstep(0.008, 0.115, abs_dy) * exp(-t_enter * 0.00042 * fog_density);
    let final_alpha = raw_alpha * horizon_fade;

    var cur_cloud = vec4<f32>(0.0);
    if final_alpha > 0.001 {
        let sky_bg = eval_physical_sky(ray_dir, false);
        let aerial_t = saturate_f(1.0 - exp(-rep_t * 0.00032 * fog_density));
        // Premultiplied cloud color blended toward horizon aerial perspective at far distances
        let cloud_rgb = mix(scattered, sky_bg * raw_alpha, aerial_t * 0.72) * horizon_fade;
        cur_cloud = vec4<f32>(max(cloud_rgb, vec3<f32>(0.0)), final_alpha);
    }

    // Ghost-free Temporal Accumulation using `atmo_half_previous`
    if frame.reset_reasons == 0u {
        let prev_cam_rel = ray_dir * rep_t + frame.camera_motion;
        let prev_clip = frame.previous_view_projection * vec4<f32>(prev_cam_rel, 1.0);
        if prev_clip.w > 0.05 {
            let prev_ndc = prev_clip.xy / prev_clip.w;
            let prev_uv = vec2<f32>(prev_ndc.x * 0.5 + 0.5, 0.5 - prev_ndc.y * 0.5);
            if prev_uv.x > 0.008 && prev_uv.x < 0.992 && prev_uv.y > 0.008 && prev_uv.y < 0.992 {
                let prev_cloud = sample_previous_cloud(prev_uv);
                if prev_cloud.r >= 0.0 {
                    // Reject stale history smoothly if camera panned very fast or coverage shifted
                    let uv_vel = length(prev_uv - (pixel * 2.0 / max(frame.resolution, vec2<f32>(1.0))));
                    let hist_w = clamp(0.76 - uv_vel * 6.0, 0.0, 0.76);
                    cur_cloud = mix(cur_cloud, max(prev_cloud, vec4<f32>(0.0)), hist_w);
                }
            }
        }
    }

    return cur_cloud;
}

// Normal- & Depth-Aware Screen-Space Ambient Occlusion (SSAO)
fn eval_ssao(uv: vec2<f32>, rev_depth: f32, pixel: vec2<f32>) -> f32 {
    if !ssao_enabled || ssao_strength <= 0.01 {
        return 1.0;
    }

    let full_px = clamp(vec2<i32>(uv * frame.resolution), vec2<i32>(0), vec2<i32>(frame.resolution) - vec2<i32>(1));
    let surf = surface_at(full_px);
    if !surf.present {
        return 1.0;
    }

    let center_pos = view_position(uv, rev_depth);
    let center_dist = length(center_pos);
    if center_dist > 96.0 || center_dist < 0.15 {
        return 1.0;
    }

    let n = surf.normal;
    let view_dir = -center_pos / center_dist;
    let radius_world = 0.85;
    let uv_radius = clamp(radius_world / max(center_dist * 0.95, 0.6), 0.003, 0.045);
    let aspect = frame.resolution.x / max(frame.resolution.y, 1.0);
    let rot = spatial_ign(pixel) * TAU;

    var occ = 0.0;
    for (var i = 0u; i < 8u; i++) {
        let r = sqrt((f32(i) + 0.5) / 8.0) * uv_radius;
        let ang = f32(i) * GOLDEN_ANGLE + rot;
        let offset = vec2<f32>(cos(ang) / aspect, sin(ang)) * r;
        let sample_uv = clamp(uv + offset, vec2<f32>(0.001), vec2<f32>(0.999));
        let sd = depth_at(sample_uv);
        if sd > 0.0 {
            let sample_pos = view_position(sample_uv, sd);
            let diff = sample_pos - center_pos;
            let diff_len = length(diff) + 1e-4;
            let dir = diff / diff_len;

            let n_bias = max(dot(n, dir) - 0.12, 0.0);
            let range_check = smoothstep(radius_world * 2.2, radius_world * 0.35, diff_len);
            let view_guard = saturate_f(dot(view_dir, dir) + 0.65);
            occ += n_bias * range_check * view_guard;
        }
    }

    let distance_fade = 1.0 - smoothstep(56.0, 96.0, center_dist);
    let ao = 1.0 - saturate_f((occ / 8.0) * 2.35 * ssao_strength * distance_fade);
    return clamp(ao, 0.18, 1.0);
}

fn post(input: PostInput) -> vec4<f32> {
    let d = depth_at(input.uv);
    if d == 0.0 {
        let p_near = view_position(input.uv, 0.5);
        let p_far  = view_position(input.uv, 0.01);
        let ray_dir = normalize(p_far - p_near);
        return eval_volumetric_clouds(ray_dir, input.pixel);
    }

    let ao = eval_ssao(input.uv, d, input.pixel);
    // Negative R sentinel marks geometry texels so temporal cloud reprojection never bleeds SSAO texels!
    return vec4<f32>(-1.0, 0.0, 0.0, ao);
}
