// ============================================================================
// Solis PBR 1.1.5 — Physical Atmospheric Scattering, Sun, Total Solar Eclipse (5800),
//                   Total Lunar Eclipse Blood Supermoon (18000), Stars, Aurora & Fog
// ============================================================================

struct LightEnvironment {
    sun_radiance: vec3<f32>,
    moon_radiance: vec3<f32>,
    active_radiance: vec3<f32>,
    sky_zenith: vec3<f32>,
    sky_horizon: vec3<f32>,
    day_factor: f32,
    twilight_factor: f32,
    night_factor: f32,
    overcast: f32,
    eclipse_obscuration: f32,
    eclipse_totality: f32,
}

fn eval_environment() -> LightEnvironment {
    let sun_y = frame.sun_direction.y;
    let moon_y = frame.moon_direction.y;
    let ecl = eval_solar_eclipse();
    let lun_ecl = eval_lunar_eclipse();
    let sn_str = eval_supernova_strength();
    let g5_str = eval_g5_storm_strength();

    let day_f = smoothstep(-0.06, 0.16, sun_y);
    let night_f = smoothstep(0.04, -0.14, sun_y);
    let twilight_f = smoothstep(-0.14, 0.02, sun_y) * smoothstep(0.34, 0.02, sun_y);
    let overcast = saturate_f(frame.rain * 0.78 + frame.thunder * 0.22);

    // Atmospheric air mass & Rayleigh + Ozone Chappuis transmittance for the sun
    let sun_elev = max(sun_y + 0.08, 0.015);
    let air_mass = min(1.0 / (sun_elev + 0.12 * pow(sun_elev, 0.45)), 14.0);
    const beta_ext = vec3<f32>(0.052, 0.124, 0.258);
    let sun_trans = exp(-beta_ext * air_mass);
    let sun_vis = smoothstep(-0.07, 0.05, sun_y);
    let raw_sun = vec3<f32>(3.45, 3.28, 3.08) * sun_trans * sun_vis;
    let unoccluded_sun = raw_sun * (1.0 - overcast * 0.86);

    // Solar eclipse attenuation (`5800`)
    var sun_rad = unoccluded_sun;
    if ecl.in_window {
        let rem = max(1.0 - ecl.obscuration, 0.0);
        let limb_tint = mix(vec3<f32>(1.0), vec3<f32>(1.06, 0.92, 0.78), smoothstep(0.55, 0.96, ecl.obscuration));
        let coronal_light = vec3<f32>(0.105, 0.148, 0.255) * (1.0 - overcast * 0.85);
        sun_rad = unoccluded_sun * pow(rem, 1.32) * limb_tint + coronal_light * ecl.totality;
    }

    // Crisp silver-cobalt moonlight — shifts to deep refracted copper-crimson during Total Lunar Eclipse (`18000`)!
    let moon_vis = smoothstep(-0.05, 0.11, moon_y) * max(night_f, twilight_f * 0.45) * select(1.0, 0.0, ecl.in_window);
    var moon_rad = vec3<f32>(0.165, 0.225, 0.355) * moon_vis * (1.0 - overcast * 0.82);
    if lun_ecl.in_window {
        let blood_moon_rad = vec3<f32>(0.215, 0.056, 0.024) * moon_vis * (1.0 - overcast * 0.82);
        moon_rad = mix(moon_rad, blood_moon_rad, smoothstep(0.25, 0.95, lun_ecl.immersion));
    }
    // Subtle crisp sapphire-silver starlight boost during the 15500 Galactic Supernova!
    if sn_str > 0.01 {
        moon_rad += vec3<f32>(0.055, 0.075, 0.135) * sn_str * night_f * (1.0 - overcast * 0.85);
    }

    let sun_is_caster = dot(frame.light_direction, frame.sun_direction) > 0.0;
    let active_rad = select(moon_rad, sun_rad, sun_is_caster);

    // Sky hemisphere Zenith & Horizon colors
    const zenith_day = vec3<f32>(0.095, 0.275, 0.76);
    const zenith_twilight = vec3<f32>(0.065, 0.105, 0.30);
    const zenith_night = vec3<f32>(0.008, 0.015, 0.036);
    var zenith = mix(zenith_night, zenith_day, day_f);
    zenith = mix(zenith, zenith_twilight, twilight_f * 0.65);

    const horiz_day = vec3<f32>(0.45, 0.65, 0.92);
    const horiz_twilight = vec3<f32>(0.96, 0.38, 0.14);
    const horiz_night = vec3<f32>(0.020, 0.034, 0.068);
    var horiz = mix(horiz_night, horiz_day, day_f);
    horiz = mix(horiz, horiz_twilight, twilight_f * 0.85);

    // Lingering post-sunset amber-cobalt dusk glow during Great Comet window (`13200`)!
    let comet_dusk = smoothstep(-0.46, -0.14, sun_y) * night_f * eval_great_comet_strength();
    if comet_dusk > 0.01 {
        horiz += vec3<f32>(0.085, 0.036, 0.018) * comet_dusk * (1.0 - overcast);
    }

    // Total Lunar Eclipse (`18000`): deeper darkened night sky with subtle copper horizon cast!
    if lun_ecl.in_window && night_f > 0.2 {
        let l_blend = lun_ecl.totality * night_f * (1.0 - overcast);
        zenith = mix(zenith, vec3<f32>(0.006, 0.008, 0.020), l_blend * 0.75);
        horiz  = mix(horiz,  vec3<f32>(0.036, 0.015, 0.018), l_blend * 0.68);
    }

    // Extreme G5 Geomagnetic Storm (`20500`): subtle auroral sky bounce on terrain while keeping the zenith sky DARK for high-contrast curtains & stars!
    if g5_str > 0.01 && night_f > 0.2 {
        let g_vis = g5_str * night_f * (1.0 - overcast * 0.85);
        zenith += vec3<f32>(0.004, 0.009, 0.007) * g_vis;
        horiz  += vec3<f32>(0.018, 0.042, 0.028) * g_vis;
    }

    // Total Solar Eclipse Umbral Sky (`5800`)
    if ecl.in_window {
        let umbra_curve = pow(ecl.obscuration, 2.4);
        const ecl_zenith = vec3<f32>(0.0055, 0.0115, 0.036);
        const ecl_horiz  = vec3<f32>(0.48, 0.215, 0.095);
        let deep_blend = saturate_f(umbra_curve * 0.82 + ecl.totality * 0.18);
        zenith = mix(zenith, ecl_zenith, deep_blend);
        let partial_horiz = horiz * (1.0 - umbra_curve * 0.72);
        horiz = mix(partial_horiz, ecl_horiz, smoothstep(0.78, 1.0, ecl.obscuration));
    }

    // Overcast storm desaturation & darkening
    let storm_luma = max(luma(zenith) * 0.65 + luma(horiz) * 0.35, 0.016);
    let storm_col = vec3<f32>(0.78, 0.84, 0.92) * storm_luma * (0.65 - frame.thunder * 0.28);
    zenith = mix(zenith, storm_col * 0.85, overcast);
    horiz = mix(horiz, storm_col * 1.05, overcast);

    return LightEnvironment(
        sun_rad,
        moon_rad,
        active_rad,
        zenith,
        horiz,
        day_f * (1.0 - ecl.totality * 0.92),
        max(twilight_f, ecl.totality * 0.65),
        max(night_f, ecl.totality * 0.85),
        overcast,
        ecl.obscuration,
        ecl.totality
    );
}

// Rotate sky direction into celestial coordinates orbiting with the sun & moon
fn to_celestial_sphere(dir: vec3<f32>) -> vec3<f32> {
    let s = normalize(vec2<f32>(-frame.sun_direction.x, frame.sun_direction.y) + vec2<f32>(1e-6, 0.0));
    let cx = s.y * dir.x + s.x * dir.y;
    let cy = -s.x * dir.x + s.y * dir.y;
    return vec3<f32>(cx, cy, dir.z);
}

// Single 3D spherical star layer with blackbody stellar color & gentle scintillation
fn star_layer(cel_dir: vec3<f32>, grid_scale: f32, density_thresh: f32, brightness: f32) -> vec3<f32> {
    let p = cel_dir * grid_scale;
    let cell = floor(p);
    let f = fract(p);

    let rnd = hash31(cell);
    if rnd < density_thresh {
        return vec3<f32>(0.0);
    }

    let jx = hash31(cell + vec3<f32>(17.1, 3.7, 9.2));
    let jy = hash31(cell + vec3<f32>(5.3, 29.4, 13.8));
    let jz = hash31(cell + vec3<f32>(41.9, 11.6, 23.5));
    let center = vec3<f32>(0.24 + 0.52 * jx, 0.24 + 0.52 * jy, 0.24 + 0.52 * jz);

    let d = length(f - center);
    let spot = exp(-d * d * 56.0);

    let temp = jx;
    let cold_star = vec3<f32>(0.68, 0.82, 1.18);
    let warm_star = vec3<f32>(1.18, 0.88, 0.62);
    let star_tint = mix(warm_star, cold_star, smoothstep(0.15, 0.85, temp));

    let twinkle = 0.78 + 0.22 * sin(frame.time * (1.8 + jy * 3.2) + rnd * 47.0);
    let mag = pow(saturate_f((rnd - density_thresh) / max(1.0 - density_thresh, 1e-3)), 1.6);

    return star_tint * spot * mag * twinkle * brightness;
}

fn eval_stars(dir: vec3<f32>, env: LightEnvironment) -> vec3<f32> {
    if !stars_enabled || dir.y <= 0.01 {
        return vec3<f32>(0.0);
    }
    let night_stars = smoothstep(0.08, -0.10, frame.sun_direction.y);
    let eclipse_stars = smoothstep(0.84, 0.995, env.eclipse_obscuration) * smoothstep(0.10, 0.45, dir.y);
    let star_vis = max(night_stars, eclipse_stars * 0.92)
                 * (1.0 - env.overcast * 0.96)
                 * smoothstep(0.01, 0.18, dir.y);
    if star_vis <= 0.005 {
        return vec3<f32>(0.0);
    }

    // Mask stars directly behind the eclipsing Moon silhouette (Solar Eclipse)
    let sun_dir = normalize(frame.sun_direction);
    let r_sun = 0.031 * clamp(celestial_size, 0.5, 2.0);
    let cos_s = dot(dir, sun_dir);
    let theta_s = sqrt(max(2.0 * (1.0 - clamp(cos_s, -1.0, 1.0)), 0.0));
    if env.eclipse_obscuration > 0.5 && theta_s < r_sun * 1.06 {
        return vec3<f32>(0.0);
    }

    // Mask stars directly behind the Lunar Disc!
    let lun_ecl = eval_lunar_eclipse();
    let m_dir = normalize(frame.moon_direction);
    let super_scale = select(1.0, 1.42, lun_ecl.in_window);
    let r_moon = 0.029 * clamp(celestial_size, 0.5, 2.0) * super_scale;
    let cos_m = dot(dir, m_dir);
    let theta_m = sqrt(max(2.0 * (1.0 - clamp(cos_m, -1.0, 1.0)), 0.0));
    if frame.moon_direction.y > -0.02 && theta_m < r_moon * 1.02 {
        return vec3<f32>(0.0);
    }

    let cel = to_celestial_sphere(dir);
    // Stars shine even richer around the darkened Blood Supermoon during Total Lunar Eclipse!
    let lun_star_boost = select(1.0, 1.32, lun_ecl.totality > 0.5);
    var stars = star_layer(cel, 135.0, 0.905, 1.35 * lun_star_boost);
    stars += star_layer(cel + vec3<f32>(0.37, 0.61, 0.19), 235.0, 0.925, 0.65 * lun_star_boost);

    // Add Galactic Supernova (`15500`) + Perseid Shooting Stars!
    stars += eval_supernova_and_meteors(dir, star_vis);

    return stars * star_vis;
}

// Physical HDR Solar Disc + Total Solar Eclipse (`5800`)
fn eval_sun_disc(dir: vec3<f32>, env: LightEnvironment) -> vec3<f32> {
    if frame.sun_direction.y <= -0.06 || dir.y <= -0.03 {
        return vec3<f32>(0.0);
    }
    let sun_dir = normalize(frame.sun_direction);
    let cos_s = clamp(dot(dir, sun_dir), -1.0, 1.0);
    if cos_s < 0.88 {
        return vec3<f32>(0.0);
    }

    let r_sun = 0.031 * clamp(celestial_size, 0.5, 2.0);
    let horizon_clip = smoothstep(-0.025, 0.02, dir.y);
    let weather_atten = 1.0 - env.overcast * 0.95;

    let ecl = eval_solar_eclipse();
    if !ecl.in_window {
        let theta = sqrt(max(2.0 * (1.0 - cos_s), 0.0));
        let disc_aa = smoothstep(r_sun * 1.05, r_sun * 0.93, theta);
        let mu = sqrt(max(1.0 - sqr(min(theta / max(r_sun, 1e-4), 1.0)), 0.0));
        let limb = vec3<f32>(
            0.48 + 0.52 * pow(mu, 0.42),
            0.36 + 0.64 * pow(mu, 0.58),
            0.24 + 0.76 * pow(mu, 0.76)
        );
        let corona = exp(-max(theta - r_sun * 0.75, 0.0) / max(r_sun * 1.15, 1e-3)) * 0.55;
        return env.sun_radiance * (disc_aa * limb * 11.5 + vec3<f32>(corona)) * horizon_clip * weather_atten;
    }

    let ref_z = select(vec3<f32>(0.0, 0.0, 1.0), vec3<f32>(1.0, 0.0, 0.0), abs(sun_dir.z) > 0.9);
    let s_east  = normalize(cross(sun_dir, ref_z));
    let s_north = cross(s_east, sun_dir);

    let local_s = vec2<f32>(dot(dir, s_east), dot(dir, s_north)) / max(r_sun, 1e-4);
    let r_s = length(local_s);
    let unit_s = local_s / max(r_s, 1e-4);

    let rm_scale = 1.036;
    let local_m = (local_s - ecl.offset) / rm_scale;
    let r_m2 = dot(local_m, local_m);
    let r_m = sqrt(r_m2);
    let unit_m = local_m / max(r_m, 1e-4);

    let sun_elev = max(frame.sun_direction.y + 0.08, 0.015);
    let air_mass = min(1.0 / (sun_elev + 0.12 * pow(sun_elev, 0.45)), 14.0);
    let full_solar_rad = vec3<f32>(3.45, 3.28, 3.08) * exp(-vec3<f32>(0.052, 0.124, 0.258) * air_mass);

    let sun_disc_aa = smoothstep(1.045, 0.945, r_s);
    let moon_occ = smoothstep(1.012, 0.986, r_m);
    let mu_s = sqrt(max(1.0 - sqr(min(r_s, 1.0)), 0.0));
    let solar_limb = vec3<f32>(
        0.48 + 0.52 * pow(mu_s, 0.42),
        0.36 + 0.64 * pow(mu_s, 0.58),
        0.24 + 0.76 * pow(mu_s, 0.76)
    );
    var result = full_solar_rad * sun_disc_aa * (1.0 - moon_occ) * solar_limb * 11.5;

    let day_glare = exp(-max(r_s - 0.8, 0.0) * 0.95) * (1.0 - moon_occ) * max(1.0 - ecl.obscuration, 0.0) * 0.55;
    result += full_solar_rad * day_glare;

    let corona_vis = smoothstep(0.68, 0.995, ecl.obscuration);
    if corona_vis > 0.001 && r_m > 0.965 {
        let outside_moon = smoothstep(0.972, 1.006, r_m);
        let dist_limb = max(r_m - 0.99, 0.0);

        let fib1 = sample_noise(unit_s * 1.65 + vec2<f32>(0.23, 0.71)).r;
        let fib2 = sample_noise(unit_s * 3.85 - vec2<f32>(0.51, 0.19)).g;
        let fib3 = sample_noise(unit_s * 7.40 + vec2<f32>(frame.time * 0.002, -frame.time * 0.0015)).r;
        let fine_plumes = 0.58 + 0.42 * fib1 + 0.30 * fib2 + 0.18 * fib3;

        let axis_tilt = vec2<f32>(0.94, -0.34);
        let eq_align = abs(dot(unit_s, axis_tilt));
        let helmet = mix(0.62, 1.68, pow(eq_align, 2.2));

        let inner_k = exp(-dist_limb * 6.8) * 6.4;
        let mid_k   = exp(-dist_limb * 1.75) * fine_plumes * helmet * 1.95;
        let outer_f = exp(-dist_limb * 0.48) * (0.65 + 0.35 * fib1) * helmet * 0.44;

        let corona_col_inner = vec3<f32>(1.02, 1.04, 1.12);
        let corona_col_outer = vec3<f32>(0.76, 0.88, 1.14);
        let corona_hdr = corona_col_inner * inner_k + corona_col_outer * (mid_k + outer_f);

        result += corona_hdr * outside_moon * corona_vis;

        let prom_noise = sample_noise(unit_m * 2.9 + vec2<f32>(0.44, 0.83)).r
                       * sample_noise(unit_m * 5.6 + vec2<f32>(0.12, 0.37)).g;
        let prom_arc = smoothstep(0.18, 0.48, prom_noise);
        let chromo_shell = exp(-dist_limb * 42.0) * (0.45 + 1.85 * prom_arc);
        let h_alpha_col = vec3<f32>(4.8, 0.42, 1.08);
        result += h_alpha_col * chromo_shell * outside_moon * ecl.totality;
    }

    if ecl.diamond_ring > 0.005 {
        let gap_dir = -normalize(ecl.offset + vec2<f32>(1e-5, 0.0));
        let bead_pos = gap_dir * 1.0;
        let d_jewel = length(local_s - bead_pos);
        let jewel_burst = exp(-d_jewel * 5.5) * 14.0 + exp(-d_jewel * 1.6) * 2.2;
        let cross_glint = exp(-abs(local_s.x - bead_pos.x) * 18.0) * exp(-abs(local_s.y - bead_pos.y) * 1.4)
                        + exp(-abs(local_s.y - bead_pos.y) * 18.0) * exp(-abs(local_s.x - bead_pos.x) * 1.4);
        result += vec3<f32>(1.15, 1.06, 0.98) * (jewel_burst + cross_glint * 3.5) * ecl.diamond_ring;
    }

    if r_m < 1.01 && ecl.obscuration > 0.65 {
        let zm = sqrt(max(1.0 - min(r_m2, 1.0), 0.0));
        let m_uv = local_m / (1.0 + zm * 0.55);
        let maria = sample_noise(m_uv * 0.42 + vec2<f32>(0.34, 0.61)).r;
        let craters = sample_noise(m_uv * 1.45 + vec2<f32>(0.73, 0.19)).g;
        let moon_relief = mix(0.45, 1.0, smoothstep(0.35, 0.68, maria)) * (0.85 + 0.30 * craters);
        let rim_glow = pow(saturate_f(1.0 - zm), 4.0) * 0.035;
        let earthshine_rgb = vec3<f32>(0.006, 0.010, 0.020) * moon_relief + vec3<f32>(0.018, 0.024, 0.038) * rim_glow;
        result = mix(result, earthshine_rgb, moon_occ * ecl.totality);
    }

    return result * horizon_clip * weather_atten;
}

// Physical Textured 3D Lunar Disc + Total Lunar Eclipse ("Copper Blood Supermoon" at `/time set 18000`!)
fn eval_moon_disc(dir: vec3<f32>, env: LightEnvironment) -> vec3<f32> {
    if env.eclipse_obscuration > 0.001 || frame.moon_direction.y <= -0.06 || dir.y <= -0.03 {
        return vec3<f32>(0.0);
    }
    let m_dir = normalize(frame.moon_direction);
    let cos_m = clamp(dot(dir, m_dir), -1.0, 1.0);
    if cos_m < 0.94 {
        return vec3<f32>(0.0);
    }

    let lun_ecl = eval_lunar_eclipse();
    // Perigee Supermoon magnification during the 18000 Lunar Eclipse window so Earth's curved umbra & craters shine!
    let super_scale = mix(1.0, 1.42, smoothstep(0.0, 0.35, lun_ecl.immersion));
    let r_moon = 0.029 * clamp(celestial_size, 0.5, 2.0) * super_scale;

    let ref_z = select(vec3<f32>(0.0, 0.0, 1.0), vec3<f32>(1.0, 0.0, 0.0), abs(m_dir.z) > 0.9);
    let m_right = normalize(cross(m_dir, ref_z));
    let m_up = cross(m_right, m_dir);

    let local_xy = vec2<f32>(dot(dir, m_right), dot(dir, m_up)) / max(r_moon, 1e-4);
    let r2 = dot(local_xy, local_xy);
    let r = sqrt(r2);

    let horizon_clip = smoothstep(-0.025, 0.02, dir.y);
    let weather_atten = 1.0 - env.overcast * 0.94;
    let day_suppress = 1.0 - env.day_factor * 0.80;

    let halo_tint = mix(vec3<f32>(0.24, 0.33, 0.50), vec3<f32>(0.58, 0.14, 0.06), lun_ecl.totality);
    let corona = halo_tint * exp(-max(r - 0.88, 0.0) * 2.5) * 0.36;
    if r >= 1.05 {
        return corona * horizon_clip * weather_atten * day_suppress;
    }

    let disc_aa = smoothstep(1.04, 0.95, r);
    let z_sphere = sqrt(max(1.0 - min(r2, 1.0), 0.0));
    let n_sphere = vec3<f32>(local_xy.x, local_xy.y, z_sphere);

    let sphere_uv = n_sphere.xy / (1.0 + n_sphere.z * 0.55);
    let n_maria = sample_noise(sphere_uv * 0.42 + vec2<f32>(0.34, 0.61));
    let n_crater = sample_noise(sphere_uv * 1.45 + vec2<f32>(0.73, 0.19));
    let n_rays = sample_noise(sphere_uv * 3.80 - vec2<f32>(0.21, 0.54));

    let maria_mask = smoothstep(0.35, 0.66, n_maria.r * 0.72 + n_maria.g * 0.28);
    let crater_detail = 0.82 + 0.32 * n_crater.g - 0.14 * n_crater.b + 0.12 * smoothstep(0.68, 0.95, n_rays.r);
    let basalt_tint = vec3<f32>(0.34, 0.39, 0.48);
    let highland_tint = vec3<f32>(0.90, 0.93, 1.00);
    let moon_albedo = mix(basalt_tint, highland_tint, maria_mask) * crater_detail;

    var lit_moon = vec3<f32>(0.0);

    if !lun_ecl.in_window {
        let phase_cycle = sin(frame.game_time * 0.0022) * 0.55;
        let sun_local = normalize(vec3<f32>(phase_cycle, 0.14, 0.82));
        let lambert = saturate_f(dot(n_sphere, sun_local));
        let oren_limb = mix(lambert, sqrt(lambert), 0.45);
        let earthshine = vec3<f32>(0.08, 0.12, 0.20);
        lit_moon = moon_albedo * (vec3<f32>(1.65, 1.76, 1.98) * oren_limb + earthshine);
    } else {
        // ====================================================================
        // Total Lunar Eclipse Physics (Danjon Copper-Red Umbra + Ozone Fringe!)
        // ====================================================================
        // Lunar eclipses ALWAYS occur at Full Moon opposition (`sun_local ~ (0, 0, 1)`)!
        let full_lambert = mix(n_sphere.z, sqrt(max(n_sphere.z, 0.0)), 0.55);
        let sunlit_full  = vec3<f32>(1.78, 1.86, 2.05) * full_lambert;

        // Normalized radial coordinate inside Earth's spherical shadow cone (`r_u == 1.0` at umbral edge!)
        let r_u = length(local_xy - lun_ecl.umbra_offset) / max(lun_ecl.umbra_radius, 1.0);

        // 1. Penumbral shading outside the umbral edge (`r_u in [1.0 .. 1.55]`)
        let penumbra_atten = mix(0.48, 1.0, smoothstep(1.0, 1.55, r_u));

        // 2. Stratospheric Chappuis-Band Ozone Turquoise Fringe right inside Earth's umbral rim (`r_u ~ 0.90..1.02`)!
        // Ozone at 20-40km absorbs 600nm orange-red while letting 470nm blue-turquoise refract onto the umbral border!
        let ozone_band = exp(-sqr((r_u - 0.965) / 0.055));
        let ozone_col  = vec3<f32>(0.18, 0.62, 1.05) * ozone_band * 0.85;

        // 3. Refracted Rayleigh Sunset Glow inside Earth's Deep Umbra (`r_u < 0.98`):
        // Deep brick-crimson near umbral center (`r_u -> 0`), luminous copper-amber near closest umbral edge (`r_u -> 0.92`)!
        let umbral_grad = smoothstep(0.10, 0.92, r_u);
        let col_umbra_core = vec3<f32>(0.36, 0.036, 0.012);
        let col_umbra_edge = vec3<f32>(1.52, 0.34, 0.068);
        let refracted_earth_sunset = mix(col_umbra_core, col_umbra_edge, pow(umbral_grad, 1.45)) + ozone_col;

        // Smooth physical blurred solar-disc shadow edge (`~0.045` umbral penumbra width)
        let in_umbra = smoothstep(1.028, 0.962, r_u);
        let limb_scatter = pow(saturate_f(1.0 - z_sphere), 2.6) * vec3<f32>(0.55, 0.14, 0.04) * in_umbra;

        let total_irrad = mix(sunlit_full * penumbra_atten, refracted_earth_sunset * (0.72 + 0.42 * full_lambert), in_umbra);
        lit_moon = moon_albedo * total_irrad + limb_scatter;
    }

    return (lit_moon * disc_aa + corona * (1.0 - disc_aa * 0.65)) * horizon_clip * weather_atten * day_suppress;
}

// High-altitude wispy cirrus clouds
fn eval_cirrus(dir: vec3<f32>, env: LightEnvironment) -> vec3<f32> {
    if !cirrus_clouds || dir.y <= 0.02 {
        return vec3<f32>(0.0);
    }
    let plane_uv = dir.xz / (dir.y + 0.18) * 0.075;
    let wind = vec2<f32>(frame.time * 0.0012, frame.time * 0.0005);
    let n1 = sample_noise(plane_uv + wind);
    let stretch_uv = vec2<f32>(plane_uv.x * 2.2 + n1.g * 0.16, plane_uv.y * 0.55 - n1.r * 0.10);
    let n2 = sample_noise(stretch_uv - wind * 0.6);

    let halo_cirrus_boost = eval_ice_halo_strength() * 0.25;
    let density = smoothstep(0.56 - halo_cirrus_boost, 0.88, n1.r * 0.55 + n2.g * 0.45) * (1.0 - env.overcast * 0.85);
    let horizon_fade = smoothstep(0.02, 0.24, dir.y);
    let cos_sun = dot(dir, frame.sun_direction);
    let phase = 0.65 + 2.0 * hg_phase(cos_sun, 0.60);

    let lit_col = env.sun_radiance * 0.34 * phase + env.sky_horizon * 0.40 + env.moon_radiance * 0.45;
    return lit_col * density * horizon_fade * 0.46;
}

// Cold-biome Night Aurora Borealis + Extreme G5 Geomagnetic Corona Storm (`/time set 20500`)
fn eval_aurora(dir: vec3<f32>, env: LightEnvironment) -> vec3<f32> {
    let real_night = smoothstep(0.04, -0.14, frame.sun_direction.y);
    if real_night <= 0.05 || dir.y <= 0.015 {
        return vec3<f32>(0.0);
    }

    var out_aur = vec3<f32>(0.0);
    let g5_str = eval_g5_storm_strength();
    if g5_str > 0.005 {
        out_aur += eval_g5_corona_aurora(dir, g5_str * real_night, env.overcast);
    }

    if aurora_enabled && dir.y > 0.03 {
        let cold_boost = mix(0.26, 1.0, smoothstep(0.55, 0.05, frame.temperature));
        // Fade normal subtle green ribbon down when the full G5 Corona Storm takes over!
        let vis = real_night * (1.0 - env.overcast * 0.92) * cold_boost * (1.0 - g5_str * 0.85);
        if vis > 0.01 {
            let proj = dir.xz / (dir.y + 0.22);
            let t = frame.time * 0.018;
            let wave = sin(proj.x * 2.1 + t) * 0.25 + cos(proj.y * 1.6 - t * 0.7) * 0.18;
            let ribbon_uv = vec2<f32>(proj.x * 0.14 + wave * 0.12, proj.y * 0.14 + t * 0.08);
            let n_base = sample_noise(ribbon_uv);
            let n_fine = sample_noise(ribbon_uv * 2.7 - vec2<f32>(t * 0.15, 0.0));

            let curtain = smoothstep(0.56, 0.82, n_base.r * 0.65 + n_fine.g * 0.35);
            let alt_band = smoothstep(0.04, 0.28, dir.y) * smoothstep(0.92, 0.32, dir.y);
            let height_grad = saturate_f((dir.y - 0.06) * 1.9);

            const col_low = vec3<f32>(0.05, 0.88, 0.42);
            const col_high = vec3<f32>(0.38, 0.14, 0.85);
            out_aur += mix(col_low, col_high, height_grad) * curtain * alt_band * vis * 0.34;
        }
    }

    return out_aur;
}

// Full Physical Sky Dome along unit world direction `dir`
fn eval_physical_sky(dir: vec3<f32>, with_upper_layers: bool) -> vec3<f32> {
    if frame.dimension == 1 {
        return eval_end_sky(dir, with_upper_layers);
    }
    if frame.dimension == -1 {
        return eval_nether_sky(dir);
    }
    if frame.dimension != 0 {
        return frame.fog_color;
    }

    let env = eval_environment();
    let up = clamp(dir.y, -1.0, 1.0);
    let abs_up = max(up, 0.0);

    let horizon_exp = mix(3.0, 4.6, env.eclipse_totality);
    let horizon_t = pow(max(1.0 - abs_up, 0.0), horizon_exp);
    var sky = mix(env.sky_zenith, env.sky_horizon, horizon_t);

    if env.eclipse_totality > 0.01 {
        let mid_band = smoothstep(0.02, 0.22, abs_up) * smoothstep(0.68, 0.20, abs_up);
        sky += vec3<f32>(0.018, 0.038, 0.095) * mid_band * env.eclipse_totality * (1.0 - env.overcast);
    }

    let cos_sun = dot(dir, frame.sun_direction);
    let rayleigh_mod = 0.84 + 0.34 * cos_sun * cos_sun;
    sky *= mix(rayleigh_mod, 1.0, max(env.overcast, env.eclipse_totality * 0.65));

    let real_twilight = smoothstep(-0.14, 0.02, frame.sun_direction.y) * smoothstep(0.34, 0.02, frame.sun_direction.y);
    let sun_az_glow = pow(max(cos_sun, 0.0), 3.5) * pow(max(1.0 - abs_up, 0.0), 2.2);
    sky += vec3<f32>(1.18, 0.48, 0.15) * sun_az_glow * real_twilight * (1.0 - env.overcast * 0.85);

    let anti_sun = pow(max(-cos_sun, 0.0), 2.0) * smoothstep(0.0, 0.18, abs_up) * smoothstep(0.45, 0.12, abs_up);
    sky += vec3<f32>(0.32, 0.14, 0.30) * anti_sun * real_twilight * (1.0 - env.overcast);

    // Solar Mie Aureole
    let mie_sun = dual_hg_phase(cos_sun, 0.78, -0.25, 0.85);
    let sun_above = smoothstep(-0.08, 0.04, up);
    sky += env.sun_radiance * min(mie_sun * 0.068, 1.55) * sun_above * (1.0 - env.overcast * 0.65);

    if env.eclipse_totality > 0.01 {
        let coronal_sky_glow = hg_phase(cos_sun, 0.82);
        sky += vec3<f32>(0.055, 0.082, 0.155) * min(coronal_sky_glow * 0.35, 1.2) * env.eclipse_totality * sun_above * (1.0 - env.overcast * 0.8);
    }

    // Lunar Mie Aureole (copper-tinted during 18000 Total Lunar Eclipse!)
    let cos_moon = dot(dir, frame.moon_direction);
    let mie_moon = hg_phase(cos_moon, 0.74);
    sky += env.moon_radiance * min(mie_moon * 0.095, 0.48) * sun_above;

    // Night & Total-Eclipse Milky Way Dust Band
    if env.night_factor > 0.05 && up > 0.0 {
        let cel = to_celestial_sphere(dir);
        let gal_plane = abs(cel.x * 0.58 + cel.z * 0.54 - cel.y * 0.32);
        let band = exp(-gal_plane * 5.2) * smoothstep(0.05, 0.45, up);
        let dust = sample_noise(cel.xz * 0.85 + vec2<f32>(0.31, 0.77)).r;
        sky += vec3<f32>(0.012, 0.018, 0.035) * band * (0.45 + 0.85 * dust) * env.night_factor * (1.0 - env.overcast);
    }

    // Physical 42°/51° Post-Rain Double Rainbow & Alexander's Dark Band!
    let rainbow = eval_double_rainbow(dir, env.sun_radiance, env.overcast);
    sky = sky * rainbow.sky_mult + rainbow.additive_rgb;

    if with_upper_layers {
        // 22° Hexagonal Ice Halo, Sundogs, Parhelic Circle & CZA (`/time set 1200`)!
        let halo_str = eval_ice_halo_strength();
        if halo_str > 0.005 {
            sky += eval_ice_crystal_halos(dir, env.sun_radiance, halo_str);
        }

        sky += eval_stars(dir, env);
        // Great Comet C/Solis (`/time set 13200`)!
        sky += eval_great_comet(dir);
        sky += eval_sun_disc(dir, env);
        sky += eval_moon_disc(dir, env);
        sky += eval_aurora(dir, env);
        sky += eval_cirrus(dir, env);
    }

    if up < 0.0 {
        let ground_bounce = env.sky_horizon * 0.48 + env.sun_radiance * 0.04;
        sky = mix(sky, ground_bounce, smoothstep(0.0, -0.28, up));
    }

    if frame.night_vision > 0.0 {
        sky = mix(sky, max(sky, frame.sky_color * 0.65), frame.night_vision * 0.5);
    }

    return max(sky, vec3<f32>(0.0));
}

// Physical Aerial Perspective + Dimension-Specific Volumetric Fog (Overworld, End & Nether!)
fn apply_aerial_fog(surface_color: vec3<f32>, camera_rel_pos: vec3<f32>) -> vec3<f32> {
    let dist = length(camera_rel_pos);
    let view_dir = camera_rel_pos / max(dist, 1e-4);
    let v_fog = vanilla_fog(camera_rel_pos);

    // Submerged in molten lava (`eye_in == 2u`): liquid rock is opaque incandescent magma (even in Creative mode!)
    if frame.eye_in == 2u {
        let magma_glow = vec3<f32>(0.88, 0.145, 0.014);
        let magma_opaq = saturate_f(max(1.0 - exp(-dist * 4.8), smoothstep(0.05, 0.50, dist)));
        return mix(surface_color, magma_glow, magma_opaq);
    }

    if frame.eye_in >= 3u || frame.blindness > 0.01 || frame.darkness > 0.01 {
        return mix(surface_color, frame.fog_color, v_fog);
    }

    if frame.dimension == 1 {
        let world_y = frame.camera_position.y + camera_rel_pos.y;
        let void_abyss = smoothstep(46.0, 4.0, world_y) * 0.55;
        let far_fade = smoothstep(0.62, 1.0, dist / max(frame.far, 64.0));
        let end_sigma = 0.00085 * fog_density * (1.0 + void_abyss * 2.4);
        let scatter_end = 1.0 - exp(-dist * end_sigma);

        let cos_bh = dot(view_dir, normalize(END_BH_DIR));
        let bh_rim = pow(max(cos_bh, 0.0), 5.0) * vec3<f32>(0.055, 0.030, 0.012) * end_disk_intensity * select(0.0, 1.0, end_black_hole);
        let void_haze = vec3<f32>(0.005, 0.004, 0.011) + bh_rim;
        let end_fog_t = saturate_f(max(scatter_end * 0.65, far_fade * 0.92));
        return mix(surface_color, void_haze, end_fog_t);
    }

    if frame.dimension == -1 {
        return apply_nether_volumetric_fog(surface_color, camera_rel_pos);
    }

    if frame.dimension != 0 {
        return mix(surface_color, frame.fog_color, v_fog);
    }

    let env = eval_environment();

    if frame.eye_in == 1u || frame.in_water > 0.01 {
        let cos_l = dot(view_dir, frame.light_direction);
        let water_phase = 0.75 + 1.45 * hg_phase(cos_l, 0.55);
        let deep_scatter = vec3<f32>(0.018, 0.145, 0.235) * (env.day_factor * 0.85 + 0.15) * water_phase
                         + frame.fog_color * 0.35 * (1.0 - env.eclipse_totality * 0.85);
        let uw_sigma = 0.048 / max(water_clarity, 0.25);
        let uw_fog = saturate_f(max(1.0 - exp(-dist * uw_sigma), v_fog * 0.85));
        return mix(surface_color, deep_scatter, uw_fog * max(frame.in_water, f32(frame.eye_in == 1u)));
    }

    let rain_mist = frame.rain * 0.0085 + frame.thunder * 0.005;
    let twilight_mist = env.twilight_factor * 0.0020;
    let base_sigma = (0.0014 + twilight_mist + rain_mist) * fog_density;

    let world_y = frame.camera_position.y + camera_rel_pos.y;
    let valley_factor = mix(1.35, 0.65, smoothstep(58.0, 145.0, world_y));
    let scatter_t = 1.0 - exp(-dist * base_sigma * valley_factor);

    let horizon_ray = normalize(vec3<f32>(view_dir.x, max(view_dir.y * 0.35, 0.02), view_dir.z));
    var inscatter = eval_physical_sky(horizon_ray, false);
    let cos_sun = dot(view_dir, frame.sun_direction);
    inscatter += env.sun_radiance * hg_phase(cos_sun, 0.68) * 0.08 * (1.0 - env.overcast * 0.5);

    let combined_fog = saturate_f(max(scatter_t * 0.82, smoothstep(0.15, 1.0, v_fog)));
    return mix(surface_color, inscatter, combined_fog);
}
