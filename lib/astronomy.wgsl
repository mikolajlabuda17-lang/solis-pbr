// ============================================================================
// Solis PBR 1.1.5 — Hyper-Realistic Atmospheric Optics & Astrophysical Events:
//   - 22° Hexagonal Ice Halo, Sundogs (Parhelia), Parhelic Circle & CZA (1200)
//   - 42°/51° Descartes-Airy Double Rainbow & Alexander's Dark Band (Post-Rain)
//   - Great Comet C/Solis with Curved Mie Dust Tail & CO+ Ion Tail (13200)
//   - Galactic Supernova, V838 Light-Echo Nebula & Perseid Meteors (15500)
//   - Extreme G5 Geomagnetic Storm: SAR Crimson & Emerald Zenith Corona (20500)
// ============================================================================

// Smooth spectral wavelength-to-RGB lobe (`t` in [0 = 700nm red .. 1 = 400nm violet])
fn spectral_rainbow_rgb(t: f32) -> vec3<f32> {
    let x = clamp(t, 0.0, 1.0);
    let r = exp(-sqr((x - 0.13) / 0.19)) + 0.26 * exp(-sqr((x - 0.88) / 0.11));
    let g = exp(-sqr((x - 0.44) / 0.20));
    let b = exp(-sqr((x - 0.77) / 0.19));
    return max(vec3<f32>(r, g, b), vec3<f32>(0.0));
}

// Pure 4-octave rotated Perlin FBM on `.r` channel (100% free of cellular Voronoi ridges!)
fn astro_fbm(p_in: vec2<f32>) -> f32 {
    var p = p_in;
    var sum = 0.0;
    var amp = 0.52;
    for (var i = 0u; i < 4u; i++) {
        sum += amp * sample_noise(p).r;
        p = vec2<f32>(p.x * 1.64 - p.y * 1.22, p.x * 1.22 + p.y * 1.64) + vec2<f32>(0.37, 0.69);
        amp *= 0.50;
    }
    return sum;
}

// ============================================================================
// 1. 22° Ice-Crystal Halo, Twin Parhelia (Sundogs), Parhelic Circle & CZA (`/time set 1200`)
// ============================================================================
fn eval_ice_crystal_halos(dir: vec3<f32>, sun_rad: vec3<f32>, strength: f32) -> vec3<f32> {
    if strength <= 0.005 || dir.y <= -0.01 || frame.sun_direction.y <= 0.01 {
        return vec3<f32>(0.0);
    }

    let s_dir = normalize(frame.sun_direction);
    let cos_th = clamp(dot(dir, s_dir), -1.0, 1.0);
    let theta_deg = acos(cos_th) * (180.0 / PI);
    let horiz_fade = smoothstep(-0.01, 0.06, dir.y);

    // A. Primary 22° Circular Hexagonal Prism Halo (Red sharp inner rim at 21.7°, blue-white outer tail)
    var halo_rgb = vec3<f32>(0.0);
    if theta_deg > 20.6 && theta_deg < 27.5 {
        let r_lobe = smoothstep(21.35, 21.95, theta_deg) * exp(-max(theta_deg - 21.90, 0.0) * 0.82);
        let g_lobe = smoothstep(21.65, 22.28, theta_deg) * exp(-max(theta_deg - 22.22, 0.0) * 0.78);
        let b_lobe = smoothstep(21.98, 22.68, theta_deg) * exp(-max(theta_deg - 22.60, 0.0) * 0.72);

        let world_up = vec3<f32>(0.0, 1.0, 0.0);
        let s_right = normalize(cross(world_up, s_dir) + vec3<f32>(1e-5));
        let s_up    = cross(s_dir, s_right);
        let ring_up_align = abs(dot(normalize(dir - s_dir * cos_th + vec3<f32>(1e-5)), s_up));
        let tangent_arc = 1.0 + pow(ring_up_align, 6.0) * 0.95;

        halo_rgb += vec3<f32>(r_lobe * 1.18, g_lobe * 1.02, b_lobe * 1.08) * 0.135 * tangent_arc;
    }

    // B. Twin Parhelia (Sundogs) + Parhelic Circle
    let sun_elev = asin(clamp(s_dir.y, -0.99, 0.99));
    let dir_elev = asin(clamp(dir.y, -0.99, 0.99));
    let d_elev_deg = abs(dir_elev - sun_elev) * (180.0 / PI);

    if sun_elev < 0.74 && d_elev_deg < 5.5 {
        let s_az = normalize(vec2<f32>(s_dir.x, s_dir.z) + vec2<f32>(1e-5));
        let d_az = normalize(vec2<f32>(dir.x, dir.z) + vec2<f32>(1e-5));
        let az_deg = acos(clamp(dot(s_az, d_az), -1.0, 1.0)) * (180.0 / PI);

        let dog_az = 22.0 / max(cos(sun_elev * 0.72), 0.75);
        if az_deg > dog_az - 1.4 && az_deg < dog_az + 9.5 {
            let vert_pinch = exp(-sqr(d_elev_deg / 1.18));
            let d_r = smoothstep(dog_az - 0.85, dog_az - 0.05, az_deg) * exp(-max(az_deg - dog_az, 0.0) * 0.62);
            let d_g = smoothstep(dog_az - 0.35, dog_az + 0.45, az_deg) * exp(-max(az_deg - (dog_az + 0.4), 0.0) * 0.54);
            let d_b = smoothstep(dog_az + 0.15, dog_az + 1.05, az_deg) * exp(-max(az_deg - (dog_az + 0.9), 0.0) * 0.46);
            let dog_core = exp(-sqr((az_deg - (dog_az + 0.35)) / 0.85)) * exp(-sqr(d_elev_deg / 0.65)) * 1.45;
            halo_rgb += (vec3<f32>(d_r * 1.35, d_g * 1.05, d_b * 1.02) * vert_pinch * 0.62
                       + vec3<f32>(1.25, 1.08, 0.92) * dog_core * 0.52);
        }

        let parhelic_band = exp(-sqr(d_elev_deg / 0.52)) * smoothstep(4.0, 18.0, az_deg);
        halo_rgb += vec3<f32>(0.95, 0.98, 1.05) * parhelic_band * 0.038;
    }

    // C. Prismatic Circumzenithal Arc ("Upside-Down Zenith Rainbow")
    let sun_elev_deg = sun_elev * (180.0 / PI);
    if sun_elev_deg > 2.0 && sun_elev_deg < 32.0 && dir.y > 0.68 {
        let zenith_ang_deg = acos(clamp(dir.y, -1.0, 1.0)) * (180.0 / PI);
        let cza_radius = 90.0 - 57.8 - sun_elev_deg * 0.45;
        let s_az = normalize(vec2<f32>(s_dir.x, s_dir.z) + vec2<f32>(1e-5));
        let d_az = normalize(vec2<f32>(dir.x, dir.z) + vec2<f32>(1e-5));
        let sunward_arc = smoothstep(0.25, 0.85, dot(s_az, d_az));
        let band_t = (cza_radius + 1.1 - zenith_ang_deg) / 2.2;
        if band_t > 0.0 && band_t < 1.0 && sunward_arc > 0.01 {
            let env_bell = sin(band_t * PI);
            halo_rgb += spectral_rainbow_rgb(band_t) * env_bell * sunward_arc * 0.24;
        }
    }

    let norm_sun = sun_rad / max(luma(sun_rad), 0.85);
    return halo_rgb * norm_sun * strength * horiz_fade * 1.45;
}

// ============================================================================
// 2. Physical 42° Primary + 51° Secondary Double Rainbow & Alexander's Dark Band
// ============================================================================
struct RainbowResult {
    additive_rgb: vec3<f32>,
    sky_mult: f32,
}

fn eval_double_rainbow(dir: vec3<f32>, sun_rad: vec3<f32>, overcast: f32) -> RainbowResult {
    if !rainbow_enabled || frame.dimension != 0 || frame.wetness <= 0.04 || frame.sun_direction.y <= 0.01 || frame.sun_direction.y >= 0.68 || dir.y <= -0.02 {
        return RainbowResult(vec3<f32>(0.0), 1.0);
    }

    let moisture_vis = smoothstep(0.04, 0.32, frame.wetness) * (1.0 - smoothstep(0.45, 0.92, overcast));
    if moisture_vis <= 0.005 {
        return RainbowResult(vec3<f32>(0.0), 1.0);
    }

    let anti_sun = -normalize(frame.sun_direction);
    let cos_anti = clamp(dot(dir, anti_sun), -1.0, 1.0);
    let ang_deg = acos(cos_anti) * (180.0 / PI);
    if ang_deg < 36.0 || ang_deg > 56.0 {
        return RainbowResult(vec3<f32>(0.0), 1.0);
    }

    let above_horizon = smoothstep(-0.02, 0.08, dir.y);
    var bow_rgb = vec3<f32>(0.0);

    if ang_deg >= 39.2 && ang_deg <= 42.65 {
        let t_pri = (42.45 - ang_deg) / 1.95;
        if t_pri >= 0.0 && t_pri <= 1.0 {
            let bell = sin(t_pri * PI);
            bow_rgb += spectral_rainbow_rgb(t_pri) * bell * 0.145;
        }
        if ang_deg < 40.55 {
            let fringe = 0.5 + 0.5 * sin((40.55 - ang_deg) * 14.0);
            let decay  = exp(-(40.55 - ang_deg) * 2.4);
            bow_rgb += mix(vec3<f32>(0.55, 0.25, 0.78), vec3<f32>(0.25, 0.75, 0.68), fringe) * decay * 0.028;
        }
    }

    if ang_deg >= 50.1 && ang_deg <= 53.3 {
        let t_sec = (ang_deg - 50.2) / 2.9;
        if t_sec >= 0.0 && t_sec <= 1.0 {
            let bell_s = sin(t_sec * PI);
            bow_rgb += spectral_rainbow_rgb(t_sec) * bell_s * 0.052;
        }
    }

    let alex_band = smoothstep(42.2, 43.4, ang_deg) * smoothstep(50.6, 49.2, ang_deg);
    let sky_darken = 1.0 - alex_band * 0.13 * moisture_vis * above_horizon;

    let sun_tint = mix(vec3<f32>(1.0), sun_rad / max(luma(sun_rad), 0.4), 0.55);
    return RainbowResult(bow_rgb * sun_tint * moisture_vis * above_horizon, sky_darken);
}

// ============================================================================
// 3. Great Comet C/Solis (Nucleus, C2 Coma, Curved Dust Tail & CO+ Ion Tail) (`/time set 13200`)
// ============================================================================
fn eval_great_comet(dir: vec3<f32>) -> vec3<f32> {
    let strength = eval_great_comet_strength();
    if strength <= 0.005 || dir.y <= 0.002 {
        return vec3<f32>(0.0);
    }

    let c_head = normalize(GREAT_COMET_DIR);
    let cos_head = clamp(dot(dir, c_head), -1.0, 1.0);
    if cos_head < 0.58 {
        return vec3<f32>(0.0);
    }

    let anti_solar_hint = normalize(vec3<f32>(0.38, 0.86, 0.33));
    let tail_axis = normalize(anti_solar_hint - c_head * dot(anti_solar_hint, c_head));
    let perp_axis = normalize(cross(c_head, tail_axis));

    let denom = max(cos_head, 0.35);
    let u = dot(dir, tail_axis) / denom;
    let v = dot(dir, perp_axis) / denom;
    let r_head = length(vec2<f32>(u, v));

    var comet_rgb = vec3<f32>(0.0);

    // A. Blazing Sublimating Nucleus + Swan-Band C2 Emerald-Cyan Coma
    let nucleus = exp(-sqr(r_head / 0.0028)) * 16.0 + exp(-sqr(r_head / 0.0075)) * 3.4;
    let inner_coma = exp(-r_head * 78.0) * 1.45;
    let outer_coma = exp(-r_head * 24.0) * 0.28;
    let hood_mask = smoothstep(-0.022, 0.015, u + 0.018 - v * v * 14.0);
    comet_rgb += vec3<f32>(1.35, 1.26, 1.12) * nucleus;
    comet_rgb += vec3<f32>(0.42, 1.18, 0.96) * inner_coma * mix(0.65, 1.0, hood_mask);
    comet_rgb += vec3<f32>(0.28, 0.88, 0.82) * outer_coma;

    // B. Sweeping Curved Golden-Champagne Mie-Scattering Dust Tail
    if u > -0.012 && u < 0.72 {
        let u_pos = max(u + 0.006, 0.0);
        let dust_center_v = 0.34 * u_pos * u_pos + 0.045 * u_pos;
        let dust_width    = 0.0065 + 0.115 * u_pos + 0.085 * u_pos * u_pos;
        let dv_dust       = (v - dust_center_v) / dust_width;

        let cross_prof = select(
            exp(-sqr(dv_dust * 1.85)),
            exp(-sqr(dv_dust * 0.92)),
            dv_dust >= 0.0
        );

        let stria_uv = vec2<f32>(u_pos * 1.8 - frame.time * 0.0004, dv_dust * 0.85 + 0.37);
        let stria_n1 = sample_noise(stria_uv).r;
        let stria_n2 = sample_noise(stria_uv * 2.7 + vec2<f32>(0.19, 0.63)).r;
        let striations = 0.72 + 0.30 * stria_n1 + 0.22 * stria_n2;

        let length_fade = smoothstep(-0.008, 0.018, u) * exp(-u_pos * 3.85) * (1.0 - smoothstep(0.52, 0.72, u_pos));
        let dust_col = mix(vec3<f32>(1.28, 1.08, 0.82), vec3<f32>(1.08, 0.76, 0.46), saturate_f(u_pos * 1.8));
        comet_rgb += dust_col * cross_prof * striations * length_fade * 0.78;
    }

    // C. Razor-Straight Electric Cobalt-Blue CO+ Ion Tail
    if u > -0.004 && u < 0.68 {
        let u_ion = max(u, 0.0);
        let ion_width = 0.0032 + 0.018 * u_ion;
        let dv_ion = v / ion_width;
        let ion_core = exp(-sqr(dv_ion * 1.35));

        let ray_n = sample_noise(vec2<f32>(u_ion * 2.6 - frame.time * 0.0045, dv_ion * 0.35 + 0.51)).r;
        let fine_rays = 0.66 + 0.52 * sin(dv_ion * 5.2 + ray_n * 3.0) * 0.5 + 0.32 * ray_n;
        let ion_fade = smoothstep(-0.004, 0.015, u) * exp(-u_ion * 3.35) * (1.0 - smoothstep(0.48, 0.68, u_ion));

        comet_rgb += vec3<f32>(0.28, 0.64, 1.48) * ion_core * fine_rays * ion_fade * 0.62;
    }

    // D. Subtle Sunward Orbital Anti-Tail Spike
    if u < 0.004 && u > -0.085 {
        let anti_u = max(-u, 0.0);
        let anti_prof = exp(-sqr(v / (0.0035 + anti_u * 0.05))) * exp(-anti_u * 38.0);
        comet_rgb += vec3<f32>(1.12, 0.96, 0.74) * anti_prof * 0.24;
    }

    let horiz_clip = smoothstep(0.002, 0.075, dir.y);
    return max(comet_rgb * strength * horiz_clip, vec3<f32>(0.0));
}

// ============================================================================
// 4. Galactic Supernova + Hubble V838 / SN 1987A Light-Echo Nebula (`/time set 15500`) & Meteors
// ============================================================================
fn eval_supernova_and_meteors(dir: vec3<f32>, star_vis: f32) -> vec3<f32> {
    if dir.y <= 0.01 {
        return vec3<f32>(0.0);
    }

    var out_rgb = vec3<f32>(0.0);
    let horiz_fade = smoothstep(0.01, 0.12, dir.y);

    // --- Part A: Hyper-Realistic Galactic Supernova + Domain-Warped Hubble Light-Echo Nebula ---
    let sn_str = eval_supernova_strength();
    if sn_str > 0.005 {
        let sn_dir = normalize(SUPERNOVA_DIR);
        let cos_sn = clamp(dot(dir, sn_dir), -1.0, 1.0);
        if cos_sn > 0.90 {
            let world_up = vec3<f32>(0.0, 1.0, 0.0);
            let sn_right = normalize(cross(world_up, sn_dir));
            let sn_up    = cross(sn_dir, sn_right);
            let p = vec2<f32>(dot(dir, sn_right), dot(dir, sn_up)) / max(cos_sn, 0.5);
            let r = length(p);

            // 1. Blinding 22,000K Blue-White Progenitor Flash + atmospheric scintillation
            let scint = 0.90 + 0.10 * sin(frame.time * 7.5) * cos(frame.time * 11.3);
            let core_hdr = (exp(-sqr(r / 0.0020)) * 30.0 + exp(-sqr(r / 0.0062)) * 4.5 + exp(-r * 72.0) * 0.85) * scint;
            out_rgb += vec3<f32>(0.84, 0.97, 1.48) * core_hdr;

            // 2. Crisp 4-Vane + Secondary 45° Fraunhofer Diffraction Spikes with Spectral Dispersion
            let rot = vec2<f32>(p.x * 0.966 - p.y * 0.259, p.x * 0.259 + p.y * 0.966);
            let spike_h = exp(-abs(rot.y) * 1050.0) * exp(-abs(rot.x) * 26.0);
            let spike_v = exp(-abs(rot.x) * 1050.0) * exp(-abs(rot.y) * 26.0);
            let diag    = (rot.x + rot.y) * 0.70710678;
            let adiag   = (rot.x - rot.y) * 0.70710678;
            let spike_d = (exp(-abs(diag) * 1350.0) * exp(-abs(adiag) * 46.0)
                         + exp(-abs(adiag) * 1350.0) * exp(-abs(diag) * 46.0)) * 0.32;

            let disp_phase = fract(r * 28.0);
            let disp_col = mix(vec3<f32>(0.88, 0.96, 1.32), spectral_rainbow_rgb(disp_phase) * 1.35, smoothstep(0.012, 0.055, r) * 0.60);
            out_rgb += disp_col * (spike_h + spike_v + spike_d) * 3.6 * scint;

            // 3. Organic Domain-Warped Hubble V838 Monocerotis / SN 1987A Multi-Shell Dust Light Echo!
            // Uses pure rotated Perlin `.r` FBM — ZERO cellular Voronoi grid artifacts!
            if r < 0.155 {
                let q = vec2<f32>(
                    astro_fbm(p * 11.5 + vec2<f32>(0.21, 0.74)),
                    astro_fbm(p * 11.5 + vec2<f32>(0.83, 0.39))
                ) - vec2<f32>(0.5);
                let w_uv = p * 14.5 + q * 0.95;
                let billow_a = astro_fbm(w_uv);
                let billow_b = astro_fbm(w_uv * 1.85 + vec2<f32>(0.47, 0.18));

                // Tilted SN 1987A shocked equatorial circumstellar ring with glowing pearl hot-spots!
                let tilt_p = vec2<f32>(rot.x, rot.y * 1.72);
                let r_eq = length(tilt_p);
                let pearl_ang = atan2(tilt_p.y, tilt_p.x);
                let pearls = 0.62 + 0.38 * pow(0.5 + 0.5 * sin(pearl_ang * 19.0 + billow_a * 2.5), 3.0);
                let eq_ring = exp(-sqr((r_eq - 0.019) / 0.0028)) * pearls * 1.35;

                // Inner Ionized [O III] & H-alpha Ejecta Cavity (`r ~ 0.008..0.045`)
                let warp_r = r + (billow_a - 0.5) * 0.022 + (billow_b - 0.5) * 0.010;
                let inner_ejecta = exp(-sqr((warp_r - 0.028) / 0.015)) * smoothstep(0.30, 0.76, billow_b);

                // Mid V838 Scattered Blue-Cyan Dust Sheet (`r ~ 0.035..0.075`)
                let mid_echo = exp(-sqr((warp_r - 0.052) / 0.022)) * smoothstep(0.34, 0.80, billow_a * 0.65 + billow_b * 0.35);

                // Outer Swirling Cinnamon-Gold & Crimson Interstellar Dust Cloud (`r ~ 0.055..0.115`)
                let outer_dust = exp(-sqr((warp_r - 0.078) / 0.028)) * smoothstep(0.38, 0.84, billow_a)
                               * (1.0 - smoothstep(0.105, 0.150, r));

                // Dark absorbing Bok-globule dust lanes silhouetted in front of the glowing cavity!
                let dark_lanes = mix(0.28, 1.18, smoothstep(0.34, 0.68, billow_b));

                let nebula_rgb = vec3<f32>(1.65, 0.52, 0.78) * eq_ring
                               + vec3<f32>(1.38, 0.24, 0.46) * inner_ejecta * 0.75 * dark_lanes
                               + vec3<f32>(0.30, 0.82, 1.38) * mid_echo * 0.82 * dark_lanes
                               + vec3<f32>(1.12, 0.56, 0.28) * outer_dust * 0.62 * dark_lanes;
                out_rgb += nebula_rgb;
            }
        }
        out_rgb *= sn_str;
    }

    // --- Part B: Hyper-Realistic Shooting Stars / Perseid Meteors (Forbidden O-I 557.7nm Green Ionization Wake!) ---
    if meteors_enabled && star_vis > 0.15 && dir.y > 0.08 {
        let shower_boost = sn_str;
        let num_tracks = select(2u, 5u, shower_boost > 0.25);
        let sky_dome = vec2<f32>(dir.x, dir.z) / (dir.y + 0.35);

        for (var m = 0u; m < 5u; m++) {
            if m >= num_tracks {
                break;
            }
            let fm = f32(m);
            let period = select(5.8 + fm * 2.3, 2.4 + fm * 0.75, shower_boost > 0.25);
            let t_raw = frame.time / period + fm * 0.37;
            let cycle = floor(t_raw);
            let phase = fract(t_raw);

            let active_frac = select(0.16, 0.34, shower_boost > 0.25);
            if phase < active_frac {
                let life = phase / active_frac;
                let rnd_a = hash21(vec2<f32>(cycle * 1.73 + fm * 13.1, fm * 7.9));
                let rnd_b = hash21(vec2<f32>(fm * 29.3, cycle * 3.19 + 5.7));

                let start_pos = (vec2<f32>(rnd_a, rnd_b) - vec2<f32>(0.5)) * 1.65;
                let ang = 0.65 + (rnd_a - 0.5) * 0.55;
                let m_dir = vec2<f32>(cos(ang), sin(ang));
                let m_perp = vec2<f32>(-m_dir.y, m_dir.x);

                let speed_len = 0.68 + 0.42 * rnd_b;
                let head_pos = start_pos + m_dir * (life * speed_len);
                let tail_len = 0.22 + 0.14 * rnd_b;

                let rel = sky_dome - head_pos;
                let along = -dot(rel, m_dir);
                let perp  = abs(dot(rel, m_perp));

                if along >= -0.008 && along < tail_len && perp < 0.014 {
                    let env_life = sin(life * PI);
                    let width = exp(-sqr(perp / 0.0022));
                    let head_burst = exp(-sqr(along / 0.008)) * width * 8.5;
                    let wake_trail = smoothstep(-0.002, 0.006, along) * (1.0 - along / tail_len) * exp(-along * 11.0) * width;

                    let meteor_col = vec3<f32>(1.45, 1.28, 0.95) * head_burst
                                   + mix(vec3<f32>(0.35, 1.35, 0.78), vec3<f32>(0.95, 0.62, 0.32), saturate_f(along / tail_len)) * wake_trail * 2.4;
                    out_rgb += meteor_col * env_life * star_vis;
                }
            }
        }
    }

    return out_rgb * horiz_fade;
}

// ============================================================================
// 5. Extreme G5 Geomagnetic Storm — High-Contrast SAR Crimson & Emerald Corona (`/time set 20500`)
// ============================================================================
fn eval_g5_corona_aurora(dir: vec3<f32>, storm_strength: f32, overcast: f32) -> vec3<f32> {
    if storm_strength <= 0.005 || dir.y <= 0.015 {
        return vec3<f32>(0.0);
    }
    let vis = storm_strength * (1.0 - overcast * 0.88) * smoothstep(0.015, 0.16, dir.y);
    if vis <= 0.005 {
        return vec3<f32>(0.0);
    }

    // Magnetic Dipole Zenith (~62° inclination — curtains & rays physically converge overhead!)
    let mag_zenith = normalize(vec3<f32>(0.14, 0.88, -0.45));
    let t_anim = frame.time * 0.020;

    // Tangent coordinates around Magnetic Zenith for authentic radial magnetic-field ray striations!
    let world_x = vec3<f32>(1.0, 0.0, 0.0);
    let m_east  = normalize(cross(mag_zenith, world_x));
    let m_north = cross(m_east, mag_zenith);
    let m_xy    = vec2<f32>(dot(dir, m_east), dot(dir, m_north));
    let m_rad   = length(m_xy);
    let m_ang   = atan2(m_xy.y, m_xy.x);

    // Fine magnetic-field-aligned vertical ray Pillars (sharp luminous needles converging at corona!)
    let ray_wave = 0.5 + 0.5 * sin(m_ang * 26.0 + sin(m_ang * 7.0 - t_anim * 1.4) * 2.2);
    let ray_fine = 0.5 + 0.5 * sin(m_ang * 58.0 - t_anim * 2.1);
    let pillar_striation = mix(0.42, 1.45, pow(ray_wave * 0.68 + ray_fine * 0.32, 2.2));
    // Pinch right at the exact magnetic zenith pinhole so rays radiate cleanly outward
    let zenith_pinhole = smoothstep(0.015, 0.14, m_rad);

    // Raymarch 6 stratified ionospheric shells (105 km N2+ magenta -> 150 km O-I emerald -> 340 km O-I crimson!)
    var accum = vec3<f32>(0.0);

    for (var i = 0u; i < 6u; i++) {
        let h_frac = f32(i) / 5.0;
        let field_ray = normalize(dir + mag_zenith * (h_frac * 0.48));
        let proj = field_ray.xz / (max(field_ray.y, 0.05) + 0.20);

        // Domain-warped meandering S-folds with DEEP DARK STARRY VALLEYS between glowing ribbons!
        let warp = sample_noise(proj * 0.09 + vec2<f32>(t_anim * 0.06, -t_anim * 0.04)).r - 0.5;
        let uv1 = vec2<f32>(proj.x * 0.14 + warp * 0.55, proj.y * 0.11 + t_anim * 0.08);
        let uv2 = vec2<f32>(proj.x * 0.29 - t_anim * 0.11, proj.y * 0.24 + warp * 0.35);

        let n1 = sample_noise(uv1).r;
        let n2 = sample_noise(uv2).r;

        // Narrow folded ribbon (`abs(...) < 0.26`) leaves ~60% of the night sky crisp & dark so stars blaze through!
        let ridge_a = exp(-sqr((n1 - 0.52) / 0.095));
        let ridge_b = exp(-sqr((n2 - 0.48) / 0.115)) * 0.65;
        let curtain = saturate_f(ridge_a + ridge_b * ridge_a);

        // Altitude-stratified atomic emission lines:
        // - Lower border (100 km): N2+ 427.8nm / 670nm electric violet-magenta fringe
        // - Main drapery (130-200 km): O-I 557.7nm saturated neon emerald-green
        // - Upper canopy (260-400 km): O-I 630.0nm deep blood-crimson / ruby SAR streamers!
        let col_n2_low = vec3<f32>(0.92, 0.06, 0.85);
        let col_oi_grn = vec3<f32>(0.02, 1.18, 0.38);
        let col_oi_red = vec3<f32>(1.28, 0.04, 0.14);

        var layer_col = mix(col_n2_low, col_oi_grn, smoothstep(0.0, 0.24, h_frac));
        layer_col = mix(layer_col, col_oi_red, smoothstep(0.44, 0.84, h_frac));

        let weight = mix(0.115, 0.075, h_frac);
        accum += layer_col * curtain * pillar_striation * weight;
    }

    // Subtle deep-crimson SAR band in the mid-sky (kept dark enough that stars & green curtains pop!)
    let sar_band = exp(-sqr((dir.y - 0.42) / 0.26)) * smoothstep(0.35, 0.78, sample_noise(dir.xz * 0.28 + vec2<f32>(t_anim * 0.04, 0.0)).r);
    let sar_glow = vec3<f32>(0.26, 0.015, 0.042) * sar_band;

    return (accum * zenith_pinhole + sar_glow) * vis;
}
