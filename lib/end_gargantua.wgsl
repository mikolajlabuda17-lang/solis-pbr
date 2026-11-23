// ============================================================================
// Solis PBR 1.1 — The End: Relativistic "Gargantua" Black Hole, Gravitational
//                 Lensing, Keplerian Accretion Disk & Cosmic Void Atmosphere
// ============================================================================

// Gargantua's position in The End sky (~24 deg above the horizon for monumental framing & water reflections)
const END_BH_DIR: vec3<f32> = vec3<f32>(0.542, 0.408, -0.735);

struct EndBasis {
    forward: vec3<f32>,
    right: vec3<f32>,
    up: vec3<f32>,
    disk_normal: vec3<f32>,
    disk_u: vec3<f32>,
    disk_v: vec3<f32>,
}

fn get_end_bh_basis() -> EndBasis {
    let fwd = normalize(END_BH_DIR);
    let world_up = vec3<f32>(0.0, 1.0, 0.0);
    let base_right = normalize(cross(world_up, fwd));
    let base_up = cross(fwd, base_right);

    // Subtle 11-degree cinematic Dutch roll (classic Interstellar Gargantua framing!)
    let roll = 0.195;
    let cr = cos(roll);
    let sr = sin(roll);
    let right = base_right * cr + base_up * sr;
    let up    = -base_right * sr + base_up * cr;

    // Observer sits ~9.2 deg above the equatorial plane (`prev_h > 0`), so:
    // - Foreground disk (`z < 0`) slices slightly below center across the pitch-black shadow
    // - Far disk (`z > 0`) is gravitationally lensed HIGH OVER the north pole AND UNDER the south pole!
    let tilt = 0.160;
    let disk_normal = normalize(up * cos(tilt) - fwd * sin(tilt));
    let disk_u = right;
    let disk_v = normalize(cross(disk_normal, disk_u));

    return EndBasis(fwd, right, up, disk_normal, disk_u, disk_v);
}

// Deep End Cosmic Background (crisp stars + dark dust lanes & delicate cosmic nebula)
// Evaluated along the gravitationally deflected exit ray `ray_dir`!
fn eval_end_cosmos(ray_dir: vec3<f32>, with_stars: bool) -> vec3<f32> {
    let d = normalize(ray_dir);
    let basis = get_end_bh_basis();
    let eq_lat = dot(d, basis.disk_normal);
    let gal_band = exp(-abs(eq_lat) * 4.6);

    let uv_a = vec2<f32>(dot(d, basis.disk_u), dot(d, basis.forward)) * 0.55 + vec2<f32>(0.31, 0.67);
    let uv_b = vec2<f32>(d.x + d.z * 0.5, d.y - d.x * 0.35) * 0.95;
    let n1_r = sample_noise(uv_a).r;
    let n1_r2 = sample_noise(uv_a * 1.9 + vec2<f32>(0.47, 0.29)).r;
    let n2_r = sample_noise(uv_b * 1.8 + vec2<f32>(0.14, 0.82)).r;
    let n2_r2 = sample_noise(uv_b * 3.1 + vec2<f32>(0.63, 0.41)).r;

    let nebula_wisp = smoothstep(0.42, 0.88, n1_r * 0.62 + n2_r * 0.38);
    let dust_lane   = smoothstep(0.32, 0.74, n2_r2);

    // Deep pitch-black cosmic void so Gargantua's golden accretion disk & Einstein stars pop with maximum contrast!
    var bg = vec3<f32>(0.0014, 0.0012, 0.0032);

    // Subtle cosmic ender-amethyst & warm stardust galactic band (pure Perlin `.r`, zero Voronoi polygons!)
    let violet_neb = vec3<f32>(0.013, 0.006, 0.026) * nebula_wisp * (0.35 + 0.65 * gal_band);
    let gold_dust  = vec3<f32>(0.015, 0.008, 0.004) * gal_band * smoothstep(0.48, 0.88, n1_r2);
    bg += (violet_neb + gold_dust) * (1.0 - dust_lane * 0.58);

    if with_stars && stars_enabled {
        let slow_t = frame.time * 0.0012;
        let cs = cos(slow_t);
        let ss = sin(slow_t);
        let rot_d = vec3<f32>(d.x * cs - d.z * ss, d.y, d.x * ss + d.z * cs);

        var stars = star_layer(rot_d, 140.0, 0.892, 1.65);
        stars += star_layer(rot_d + vec3<f32>(0.41, 0.19, 0.73), 245.0, 0.915, 0.95);
        bg += stars;
    }

    return bg;
}

// Relativistic Keplerian Accretion Disk Radiance & Optical Opacity at equatorial plane crossing `hit_pos`
fn sample_accretion_disk(
    hit_pos: vec3<f32>,
    ray_vel: vec3<f32>,
    basis: EndBasis,
    crossing_order: u32
) -> vec4<f32> {
    let r = length(hit_pos);
    let r_in  = 1.78;
    let r_out = 9.40;

    if r <= 1.42 || r >= r_out {
        return vec4<f32>(0.0);
    }

    // Crisp hot ISCO inner edge + wide feathery outer plasma/dust taper
    let inner_taper = smoothstep(1.48, r_in + 0.38, r);
    let outer_taper = 1.0 - smoothstep(4.2, r_out, r);
    let radial_env  = inner_taper * outer_taper;
    if radial_env <= 0.001 {
        return vec4<f32>(0.0);
    }

    let u = dot(hit_pos, basis.disk_u);
    let v = dot(hit_pos, basis.disk_v);
    let disk_xy = vec2<f32>(u, v);
    let unit_xy = disk_xy / max(r, 1e-4);

    // Seamless differential Keplerian orbital shear (zero atan2 branch discontinuity!)
    let omega = 1.85 / pow(max(r, 1.4), 1.35);
    let phase_a = fract(frame.time * 0.036);
    let phase_b = fract(frame.time * 0.036 + 0.5);
    let blend_b = abs(phase_a * 2.0 - 1.0);

    let ang_a = (phase_a - 0.5) * 3.8 * omega - log(max(r, 1.0)) * 2.65;
    let ang_b = (phase_b - 0.5) * 3.8 * omega - log(max(r, 1.0)) * 2.65;

    let ca = cos(ang_a); let sa = sin(ang_a);
    let cb = cos(ang_b); let sb = sin(ang_b);

    let rot_a = vec2<f32>(disk_xy.x * ca - disk_xy.y * sa, disk_xy.x * sa + disk_xy.y * ca);
    let rot_b = vec2<f32>(disk_xy.x * cb - disk_xy.y * sb, disk_xy.x * sb + disk_xy.y * cb);

    // Concentric Keplerian plasma lanes + sheared MRI turbulence filaments
    let ring_n1 = sample_noise(vec2<f32>(r * 0.68, r * 0.29) + unit_xy * 0.07).r;
    let ring_n2 = sample_noise(vec2<f32>(r * 1.65 + 0.31, r * 0.94) - unit_xy * 0.05).g;
    let fil_a1  = sample_noise(rot_a * 0.155 + vec2<f32>(0.21, 0.57)).r;
    let fil_b1  = sample_noise(rot_b * 0.155 + vec2<f32>(0.21, 0.57)).r;
    let fil_a2  = sample_noise(rot_a * 0.360 - vec2<f32>(0.63, 0.19)).g;
    let fil_b2  = sample_noise(rot_b * 0.360 - vec2<f32>(0.63, 0.19)).g;

    let spiral_coarse = mix(fil_a1, fil_b1, blend_b);
    let spiral_fine   = mix(fil_a2, fil_b2, blend_b);

    // Multi-frequency bright plasma ringlets & dark dust gaps (signature Interstellar Gargantua detail!)
    let fine_rings = 0.54 + 0.46 * (0.5 + 0.5 * sin(r * 10.5 + ring_n1 * 4.0))
                          * (0.62 + 0.38 * sin(r * 24.0 - ring_n2 * 3.2));
    let filaments = saturate_f(ring_n1 * 0.38 + spiral_coarse * 0.38 + spiral_fine * 0.24);
    let structure = clamp((0.32 + 0.95 * filaments) * fine_rings, 0.04, 1.75);

    // Blackbody Temperature Gradient: searing cream-white inner ISCO -> rich Interstellar gold-amber -> deep burnt copper-orange
    let temp_norm = saturate_f((r - r_in) / (r_out - r_in));
    let col_isco  = vec3<f32>(1.72, 1.46, 1.08);
    let col_inner = vec3<f32>(1.58, 0.94, 0.36);
    let col_mid   = vec3<f32>(1.36, 0.52, 0.11);
    let col_outer = vec3<f32>(0.62, 0.15, 0.03);

    var bb_col = mix(col_isco, col_inner, smoothstep(0.0, 0.20, temp_norm));
    bb_col = mix(bb_col, col_mid, smoothstep(0.16, 0.54, temp_norm));
    bb_col = mix(bb_col, col_outer, smoothstep(0.48, 0.94, temp_norm));

    // Relativistic Doppler Beaming + Gravitational Redshift
    let orb_tan = normalize(cross(basis.disk_normal, hit_pos));
    let photon_travel = normalize(ray_vel);
    let beta = min(0.50 / sqrt(max(r - 0.75, 0.65)), 0.60) * clamp(end_doppler_shift, 0.0, 1.6);
    let cos_emit = dot(orb_tan, -photon_travel);
    let gamma_rel = 1.0 / sqrt(max(1.0 - beta * beta, 0.25));
    let grav_red  = sqrt(max(1.0 - 1.0 / max(r, 1.08), 0.12));
    let doppler_g = clamp(grav_red / max(gamma_rel * (1.0 - beta * cos_emit), 0.30), 0.34, 1.82);

    let beam_gain = pow(doppler_g, 2.75);
    let shift_t = clamp((doppler_g - 1.0) * 0.82, -0.62, 0.72);
    let blue_shifted = vec3<f32>(bb_col.r * 0.98, bb_col.g * 1.12, bb_col.b * 1.38 + 0.10);
    let red_shifted  = vec3<f32>(bb_col.r * 1.08, bb_col.g * 0.66, bb_col.b * 0.35);
    let relativistic_col = select(
        mix(bb_col, red_shifted, -shift_t),
        mix(bb_col, blue_shifted, shift_t),
        shift_t >= 0.0
    );

    let radial_glow = exp(-max(r - r_in, 0.0) * 0.44) * 1.85 + 0.30 * (1.0 - temp_norm);
    let order_atten = select(1.0, 0.78, crossing_order >= 1u);

    let hdr_emission = relativistic_col * structure * radial_env * radial_glow * beam_gain * order_atten * 3.35 * end_disk_intensity;
    // Dense inner/mid Keplerian plasma naturally occludes the lower photon ring passing behind the foreground disk!
    let opacity = saturate_f(radial_env * (0.74 + 0.26 * filaments) * mix(1.0, 0.52, temp_norm));

    return vec4<f32>(max(hdr_emission, vec3<f32>(0.0)), opacity);
}

// Full Relativistic Geodesic Sky Evaluator for The End (`frame.dimension == 1`)
fn eval_end_sky(dir: vec3<f32>, with_fine_detail: bool) -> vec3<f32> {
    if !end_black_hole {
        return eval_end_cosmos(dir, with_fine_detail);
    }

    let basis = get_end_bh_basis();
    let cos_bh = clamp(dot(dir, basis.forward), -1.0, 1.0);

    // Fast diffuse/ambient hemisphere approximation when fine disk detail isn't needed
    if !with_fine_detail {
        let base_cosmos = eval_end_cosmos(dir, false);
        let disk_glow = pow(max(cos_bh, 0.0), 6.0) * vec3<f32>(0.42, 0.22, 0.08) * end_disk_intensity;
        return base_cosmos + disk_glow;
    }

    let scale = clamp(end_bh_size, 0.5, 2.0);
    // Monumental Gargantua camera distance in Schwarzschild radii `r_s = 1.0`!
    let cam_dist = 11.8 / scale;

    // Analytic weak-field Einstein deflection using monotonic chord `sqrt(2*(1 - cos_bh))` (ZERO antipode pinch at 180 deg!)
    let chord_far = sqrt(max(2.0 * (1.0 - cos_bh), 1e-5));
    let b_approx  = cam_dist * chord_far;
    let alpha_weak = (2.0 / max(b_approx, 2.6)) * smoothstep(-0.35, 0.35, cos_bh);
    let weak_lensed_dir = normalize(dir + basis.forward * min(alpha_weak, 0.28));

    if cos_bh < 0.34 {
        return eval_end_cosmos(weak_lensed_dir, true);
    }

    // ========================================================================
    // Full General-Relativistic Schwarzschild Null-Geodesic Integration:
    //   d^2 x / d lambda^2 = -(3/2) * r_s * |x cross v|^2 / r^5 * x
    // ========================================================================
    var pos = -basis.forward * cam_dist;
    var vel = dir;

    let l_vec = cross(pos, vel);
    let l2 = dot(l_vec, l_vec);

    var accum_rgb = vec3<f32>(0.0);
    var transmittance = 1.0;
    var captured = false;
    var min_r = 1000.0;
    var crossings = 0u;

    var prev_h = dot(pos, basis.disk_normal);

    for (var step = 0u; step < 56u; step++) {
        let r2 = dot(pos, pos);
        let r = sqrt(r2);
        min_r = min(min_r, r);

        // Exact Schwarzschild Photon-Sphere Capture Theorem:
        // Our ISCO disk ends at r = 1.48; any null geodesic from outside that plunges inside r <= 1.46
        // has passed the r = 1.50 photon sphere peak and MUST fall into the Event Horizon!
        if r <= 1.46 {
            captured = true;
            break;
        }

        if step > 8u && r > max(cam_dist * 1.25, 13.5) && dot(pos, vel) > 0.0 {
            break;
        }

        // Adaptive step size scales smoothly even when `end_bh_size = 0.5` (`cam_dist = 23.6`) so rays never starve of steps!
        let dt = clamp(0.045 + 0.115 * max(r - 1.35, 0.0) + 0.22 * max(r - 9.8, 0.0), 0.044, 2.40);

        let inv_r5 = 1.0 / max(r2 * r2 * r, 1e-4);
        let acc0 = -1.5 * l2 * inv_r5 * pos;
        let mid_pos = pos + vel * (0.5 * dt) + acc0 * (0.125 * dt * dt);
        let mid_r2 = dot(mid_pos, mid_pos);
        let mid_r = sqrt(mid_r2);
        if mid_r <= 1.46 {
            captured = true;
            min_r = min(min_r, mid_r);
            break;
        }
        let mid_inv_r5 = 1.0 / max(mid_r2 * mid_r2 * mid_r, 1e-4);
        let acc_mid = -1.5 * l2 * mid_inv_r5 * mid_pos;

        let next_pos = pos + vel * dt + acc_mid * (0.5 * dt * dt);
        let next_vel = normalize(vel + acc_mid * dt);

        let cur_h = dot(next_pos, basis.disk_normal);

        // Exact Equatorial Accretion Disk Plane Crossing (`prev_h * cur_h <= 0.0`)
        if prev_h * cur_h <= 0.0 && crossings < 3u {
            let denom = abs(prev_h - cur_h);
            let frac_t = select(0.5, abs(prev_h) / denom, denom > 1e-6);
            let hit_p = mix(pos, next_pos, frac_t);
            let hit_v = normalize(mix(vel, next_vel, frac_t));

            let disk_sample = sample_accretion_disk(hit_p, hit_v, basis, crossings);
            if disk_sample.a > 0.001 || luma(disk_sample.rgb) > 0.001 {
                accum_rgb += transmittance * disk_sample.rgb;
                transmittance *= (1.0 - disk_sample.a * 0.96);
            }
            crossings += 1u;
            if transmittance < 0.012 {
                break;
            }
        }

        pos = next_pos;
        vel = next_vel;
        prev_h = cur_h;
    }

    // Safety guard: any ray still plunging inward (`dot(pos, vel) <= 0`) or orbiting near the photon sphere (`r < 1.62`) at max steps is captured!
    if dot(pos, vel) <= 0.0 || dot(pos, pos) < (1.62 * 1.62) {
        captured = true;
    }

    // Razor-sharp Relativistic Photon Ring ONLY for genuinely escaping rays (`!captured && min_r >= 1.46`)!
    if !captured && min_r < 2.25 {
        let ring_dist = abs(min_r - 1.50);
        let side_doppler = 1.0 + 0.45 * clamp(end_doppler_shift, 0.0, 1.6) * dot(dir, -basis.disk_u);
        let photon_ring = exp(-ring_dist * 24.0) * 5.2 + exp(-ring_dist * 6.5) * 0.42;
        accum_rgb += transmittance * vec3<f32>(1.68, 1.24, 0.76) * photon_ring * max(side_doppler, 0.45) * end_disk_intensity;
    }

    // Gravitationally lensed background stars & cosmic dust (ONLY for rays that escaped the Event Horizon!)
    if !captured && transmittance > 0.005 {
        let geodesic_blend = smoothstep(0.34, 0.52, cos_bh);
        let seamless_vel = normalize(mix(weak_lensed_dir, vel, geodesic_blend));
        let lensed_bg = eval_end_cosmos(seamless_vel, true);
        let einstein_mag = 1.0 + exp(-max(min_r - 1.52, 0.0) * 2.0) * 0.95 * geodesic_blend;
        accum_rgb += transmittance * lensed_bg * einstein_mag;
    }

    return max(accum_rgb, vec3<f32>(0.0));
}
